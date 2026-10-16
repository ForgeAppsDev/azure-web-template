targetScope = 'resourceGroup'

param githubSubject string = ''
param githubOwner string
param repository string
param projectName string
param environmentName string
param location string
param tags object = {}
param enableRuntimeRoleAssignments bool = true

var identityName = 'id-github-${projectName}-${environmentName}'
var contributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var rbacAdminRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
var runtimeRoleCondition = '''
((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {b7e6dc6d-f1e8-4753-8033-0f276bb0955b, 974c5e8b-45b9-4653-ba55-5f855dd0fb88, 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3, 3913510d-42f4-4e42-8a64-420c390055eb})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {b7e6dc6d-f1e8-4753-8033-0f276bb0955b, 974c5e8b-45b9-4653-ba55-5f855dd0fb88, 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3, 3913510d-42f4-4e42-8a64-420c390055eb}))
'''

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: union(tags, {
    purpose: 'github-oidc-deployment'
  })
}

resource mainBranchCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deploymentIdentity
  name: 'github-main'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: empty(githubSubject) ? 'repo:${githubOwner}/${repository}:ref:refs/heads/main' : githubSubject
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource resourceGroupContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentity.id, contributorRoleId)
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRoleId
  }
}

// The application Bicep grants its Functions runtime identity narrow Storage
// data roles. This role never escapes the client's Resource Group.
resource resourceGroupRbacAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRuntimeRoleAssignments) {
  name: guid(resourceGroup().id, deploymentIdentity.id, rbacAdminRoleId)
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: rbacAdminRoleId
    conditionVersion: '2.0'
    condition: runtimeRoleCondition
  }
}

output clientId string = deploymentIdentity.properties.clientId
output principalId string = deploymentIdentity.properties.principalId
output identityName string = deploymentIdentity.name
output federatedSubject string = mainBranchCredential.properties.subject
