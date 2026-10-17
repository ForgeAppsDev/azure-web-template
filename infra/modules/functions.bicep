param namePrefix string
param location string
param storageAccountName string
param storageAccountId string
param deploymentContainerName string
param deploymentContainerUrl string
param applicationInsightsConnectionString string
@description('Explicit HTTPS origins allowed to call this API from browsers.')
param allowedOrigins array = []
param tags object = {}

@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 100

@allowed([
  2048
  4096
])
param instanceMemoryMB int = 2048

var functionAppName = '${namePrefix}-api'
var runtimeIdentityName = '${namePrefix}-api-runtime'

resource functionStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: runtimeIdentityName
  location: location
  tags: tags
}

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${namePrefix}-functions-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource storageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, runtimeIdentity.id, 'storage-blob-data-owner')
  scope: functionStorage
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  }
}

resource storageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, runtimeIdentity.id, 'storage-queue-data-contributor')
  scope: functionStorage
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  }
}

resource storageTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, runtimeIdentity.id, 'storage-table-data-contributor')
  scope: functionStorage
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  }
}

resource monitoringMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, runtimeIdentity.id, 'monitoring-metrics-publisher')
  scope: resourceGroup()
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: deploymentContainerUrl
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: runtimeIdentity.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
    }
  }
  dependsOn: [
    storageBlobOwner
    storageQueueContributor
    storageTableContributor
    monitoringMetricsPublisher
  ]
}

resource appSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage__accountName: storageAccountName
    AzureWebJobsStorage__credential: 'managedidentity'
    AzureWebJobsStorage__clientId: runtimeIdentity.properties.clientId
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${runtimeIdentity.properties.clientId};Authorization=AAD'
    DEPLOYMENT_STORAGE_CONTAINER: deploymentContainerName
  }
}

resource webConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    cors: {
      allowedOrigins: allowedOrigins
      supportCredentials: false
    }
  }
}

output id string = functionApp.id
output name string = functionApp.name
output defaultHostname string = functionApp.properties.defaultHostName
output runtimeIdentityName string = runtimeIdentity.name
