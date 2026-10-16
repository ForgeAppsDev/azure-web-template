targetScope = 'resourceGroup'

param location string
param githubSubject string = ''
param githubOwner string
param repository string
param identityName string

resource provisionerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    purpose: 'github-oidc-site-provisioning'
  }
}

resource githubCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: provisionerIdentity
  name: 'github-main'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: empty(githubSubject) ? 'repo:${githubOwner}/${repository}:ref:refs/heads/main' : githubSubject
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output clientId string = provisionerIdentity.properties.clientId
output principalId string = provisionerIdentity.properties.principalId
output federatedSubject string = githubCredential.properties.subject

