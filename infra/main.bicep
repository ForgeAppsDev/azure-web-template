targetScope = 'resourceGroup'

@description('Short, lowercase project identifier used in resource names.')
@minLength(2)
@maxLength(20)
param projectName string

@description('Deployment environment, for example dev, test, staging, or prod.')
@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environmentName string = 'dev'

@description('Infrastructure profile controlling which optional resources are deployed.')
@allowed([
  'static'
  'serverless'
  'advanced'
])
param profile string = 'static'

@description('Primary Azure region. Static Web Apps uses its own supported location parameter.')
param location string = resourceGroup().location

@description('Azure Static Web Apps location.')
param staticWebAppLocation string = 'westeurope'

@description('Static Web Apps SKU.')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('Common tags applied to all resources.')
param tags object = {}

var deployBackend = contains([
  'serverless'
  'advanced'
], profile)
var deployDataStorage = profile == 'advanced'
var normalizedProject = toLower(replace(projectName, '-', ''))
var suffix = uniqueString(subscription().subscriptionId, resourceGroup().id, projectName, environmentName)
var namePrefix = '${projectName}-${environmentName}'
var commonTags = union(tags, {
  project: projectName
  environment: environmentName
  profile: profile
  managedBy: 'bicep'
})

module staticWebApp 'modules/static-web-app.bicep' = {
  name: 'static-web-app'
  params: {
    name: '${namePrefix}-web'
    location: staticWebAppLocation
    sku: staticWebAppSku
    tags: commonTags
  }
}

module monitoring 'modules/monitoring.bicep' = if (deployBackend) {
  name: 'monitoring'
  params: {
    namePrefix: namePrefix
    location: location
    tags: commonTags
  }
}

module functionStorage 'modules/storage.bicep' = if (deployBackend) {
  name: 'function-storage'
  params: {
    name: take('st${normalizedProject}${environmentName}${suffix}', 24)
    location: location
    tags: commonTags
    allowBlobPublicAccess: false
    deploymentContainerName: 'function-releases'
  }
}

module functions 'modules/functions.bicep' = if (deployBackend) {
  name: 'functions'
  params: {
    namePrefix: namePrefix
    location: location
    storageAccountName: functionStorage!.outputs.name
    storageAccountId: functionStorage!.outputs.id
    deploymentContainerName: functionStorage!.outputs.deploymentContainerName
    deploymentContainerUrl: functionStorage!.outputs.deploymentContainerUrl
    applicationInsightsConnectionString: monitoring!.outputs.applicationInsightsConnectionString
    tags: commonTags
  }
}

module dataStorage 'modules/storage.bicep' = if (deployDataStorage) {
  name: 'data-storage'
  params: {
    name: take('data${normalizedProject}${environmentName}${suffix}', 24)
    location: location
    tags: union(commonTags, {
      purpose: 'application-data'
    })
    allowBlobPublicAccess: false
  }
}

output profile string = profile
output staticWebAppName string = staticWebApp.outputs.name
output staticWebAppHostname string = staticWebApp.outputs.defaultHostname
output functionAppName string = deployBackend ? functions!.outputs.name : ''
output functionAppHostname string = deployBackend ? functions!.outputs.defaultHostname : ''
output dataStorageAccountName string = deployDataStorage ? dataStorage!.outputs.name : ''
