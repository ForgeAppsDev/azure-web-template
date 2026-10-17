targetScope = 'subscription'

param githubOwner string = 'ForgeAppsDev'

@description('Exact GitHub OIDC subject, including immutable IDs when enabled by GitHub.')
param githubSubject string = ''
param repository string

@minLength(2)
@maxLength(40)
param projectName string

@allowed([
  'static'
  'serverless'
  'advanced'
])
param profile string

@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environmentName string

param location string = 'westeurope'

@description('Existing platform-owned Free Tier Cosmos DB for NoSQL account. Required for serverless/advanced profiles.')
param sharedCosmosAccountName string = 'forgeapps-${uniqueString(subscription().id)}'

var resourceGroupName = 'rg-${projectName}-${environmentName}'
var commonTags = {
  project: projectName
  environment: environmentName
  profile: profile
  repository: '${githubOwner}/${repository}'
  managedBy: 'azure-web-template'
}

resource clientResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

module clientBoundary 'client-boundary.bicep' = {
  name: 'client-deployment-boundary'
  scope: clientResourceGroup
  params: {
    githubOwner: githubOwner
    githubSubject: githubSubject
    repository: repository
    projectName: projectName
    environmentName: environmentName
    location: location
    tags: commonTags
    enableRuntimeRoleAssignments: profile != 'static'
  }
}

resource platformResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: 'rg-azure-web-platform'
}

module projectCosmos 'cosmos-project-container.bicep' = if (profile != 'static') {
  name: 'project-cosmos-container'
  scope: platformResourceGroup
  params: {
    accountName: sharedCosmosAccountName
    projectName: projectName
    environmentName: environmentName
    runtimePrincipalId: clientBoundary.outputs.runtimePrincipalId
  }
}

output azureClientId string = clientBoundary.outputs.clientId
output azureTenantId string = tenant().tenantId
output azureSubscriptionId string = subscription().subscriptionId
output azureResourceGroup string = clientResourceGroup.name
output azureLocation string = location
output projectNameValue string = projectName
output siteProfile string = profile
output environmentNameValue string = environmentName
output deploymentIdentityName string = clientBoundary.outputs.identityName
output federatedSubject string = clientBoundary.outputs.federatedSubject
output cosmosEndpoint string = profile != 'static' ? projectCosmos!.outputs.endpoint : ''
output cosmosDatabaseName string = profile != 'static' ? projectCosmos!.outputs.databaseName : ''
output cosmosContainerName string = profile != 'static' ? projectCosmos!.outputs.containerName : ''
output cosmosProjectKey string = profile != 'static' ? projectCosmos!.outputs.projectKey : ''
output runtimePrincipalId string = profile != 'static' ? clientBoundary.outputs.runtimePrincipalId : ''
