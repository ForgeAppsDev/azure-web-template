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

resource sharedCosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: sharedCosmosAccountName
  scope: platformResourceGroup
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' existing = {
  parent: sharedCosmos
  name: 'forgeapps'
}

var containerName = 'products-${projectName}-${environmentName}'
var projectKey = '${projectName}-${environmentName}'

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = if (profile != 'static') {
  parent: cosmosDatabase
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [ '/project' ]
        kind: 'Hash'
        version: 2
      }
    }
  }
}

resource cosmosContainerDataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = if (profile != 'static') {
  parent: sharedCosmos
  name: guid(sharedCosmos.id, clientBoundary.outputs.runtimePrincipalId, containerName)
  properties: {
    principalId: clientBoundary.outputs.runtimePrincipalId
    roleDefinitionId: '${sharedCosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: '${sharedCosmos.id}/dbs/forgeapps/colls/${containerName}'
  }
  dependsOn: [ cosmosContainer ]
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
output cosmosEndpoint string = profile != 'static' ? sharedCosmos.properties.documentEndpoint : ''
output cosmosDatabaseName string = profile != 'static' ? 'forgeapps' : ''
output cosmosContainerName string = profile != 'static' ? containerName : ''
output cosmosProjectKey string = profile != 'static' ? projectKey : ''
output runtimePrincipalId string = profile != 'static' ? clientBoundary.outputs.runtimePrincipalId : ''

