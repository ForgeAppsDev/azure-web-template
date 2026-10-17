targetScope = 'resourceGroup'

@description('Azure region for the shared platform Cosmos account.')
param location string = resourceGroup().location

@description('A single Cosmos DB Free Tier account is allowed per subscription. This name is deterministic within the subscription.')
param accountName string = 'forgeapps-${uniqueString(subscription().id)}'

@description('Common platform ownership tags.')
param tags object = {
  purpose: 'shared-platform-nosql'
  managedBy: 'azure-web-template'
}

resource sharedAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  tags: tags
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: true
    disableLocalAuth: true
    disableKeyBasedMetadataWriteAccess: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableNoSQL'
      }
    ]
  }
}

resource sharedDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: sharedAccount
  name: 'forgeapps'
  properties: {
    resource: {
      id: 'forgeapps'
    }
    options: {
      throughput: 1000
    }
  }
}

output accountName string = sharedAccount.name
output endpoint string = sharedAccount.properties.documentEndpoint
output databaseName string = sharedDatabase.name
