targetScope = 'subscription'

param githubOwner string = 'MPiwowarski'
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
    repository: repository
    projectName: projectName
    environmentName: environmentName
    location: location
    tags: commonTags
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

