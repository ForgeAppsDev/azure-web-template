targetScope = 'subscription'

param location string = 'westeurope'
param githubOwner string = 'ForgeAppsDev'

@description('Exact GitHub OIDC subject, including immutable IDs when enabled by GitHub.')
param githubSubject string = ''
param repository string = 'azure-web-template'
param resourceGroupName string = 'rg-azure-web-platform'
param identityName string = 'id-github-azure-web-provisioner'

var rbacAdminRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
var provisionerIdentityResourceId = resourceId(subscription().subscriptionId, resourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', identityName)
var provisioningRoleCondition = '''
((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {b24988ac-6180-42a0-ab88-20f7382dd24c, f58310d9-a9f6-439a-9e8d-f62e7b41a168})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {b24988ac-6180-42a0-ab88-20f7382dd24c, f58310d9-a9f6-439a-9e8d-f62e7b41a168}))
'''

resource platformResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    purpose: 'azure-web-platform-control-plane'
    managedBy: 'bicep'
  }
}

resource provisionerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'azure-web-site-provisioner')
  properties: {
    roleName: 'Azure Web Site Provisioner'
    description: 'Creates client resource groups, ARM deployments, managed identities and GitHub federation without general subscription Contributor access.'
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/read'
          'Microsoft.Resources/subscriptions/locations/read'
          'Microsoft.Resources/subscriptions/resourceGroups/read'
          'Microsoft.Resources/subscriptions/resourceGroups/write'
          'Microsoft.Resources/deployments/*'
          'Microsoft.ManagedIdentity/userAssignedIdentities/read'
          'Microsoft.ManagedIdentity/userAssignedIdentities/write'
          'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/*'
          'Microsoft.Authorization/roleAssignments/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

module platformIdentity 'platform-identity.bicep' = {
  name: 'platform-provisioner-identity'
  scope: platformResourceGroup
  params: {
    location: location
    githubOwner: githubOwner
    githubSubject: githubSubject
    repository: repository
    identityName: identityName
  }
}

resource subscriptionProvisioner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, provisionerIdentityResourceId, provisionerRole.id)
  properties: {
    principalId: platformIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: provisionerRole.id
  }
}

// Required for creating the isolated, RG-scoped role assignments used by each
// client. This identity is trusted only from the central repo's main branch.
resource subscriptionRbacAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, provisionerIdentityResourceId, rbacAdminRoleId)
  properties: {
    principalId: platformIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: rbacAdminRoleId
    conditionVersion: '2.0'
    condition: provisioningRoleCondition
  }
}


// Dedicated control-plane role: it can create project containers and scoped
// Cosmos SQL role assignments only inside the platform resource group.
resource sharedCosmosProvisioningRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'azure-web-shared-cosmos-provisioner')
  properties: {
    roleName: 'Azure Web Shared Cosmos Provisioner'
    description: 'Creates shared database containers and container-scoped Cosmos SQL role assignments in the platform resource group.'
    type: 'CustomRole'
    assignableScopes: [ subscription().id ]
    permissions: [
      {
        actions: [
          'Microsoft.DocumentDB/databaseAccounts/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/write'
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/write'
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/delete'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

resource platformCosmosProvisioner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(platformResourceGroup.id, provisionerIdentityResourceId, sharedCosmosProvisioningRole.id)
  scope: platformResourceGroup
  properties: {
    principalId: platformIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: sharedCosmosProvisioningRole.id
  }
}

output azureProvisionerClientId string = platformIdentity.outputs.clientId
output azureTenantId string = tenant().tenantId
output azureSubscriptionId string = subscription().subscriptionId
output platformResourceGroup string = platformResourceGroup.name
output federatedSubject string = platformIdentity.outputs.federatedSubject
