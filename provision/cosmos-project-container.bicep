targetScope = 'resourceGroup'

param accountName string
param projectName string
param environmentName string
param runtimePrincipalId string

resource sharedAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: accountName
}

resource sharedDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' existing = {
  parent: sharedAccount
  name: 'forgeapps'
}

var containerName = 'products-${projectName}-${environmentName}'
var projectKey = '${projectName}-${environmentName}'

resource projectContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: sharedDatabase
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

resource runtimeDataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: sharedAccount
  name: guid(sharedAccount.id, runtimePrincipalId, containerName)
  properties: {
    principalId: runtimePrincipalId
    roleDefinitionId: '${sharedAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: '${sharedAccount.id}/dbs/forgeapps/colls/${containerName}'
  }
  dependsOn: [ projectContainer ]
}

output endpoint string = sharedAccount.properties.documentEndpoint
output databaseName string = sharedDatabase.name
output containerName string = projectContainer.name
output projectKey string = projectKey
