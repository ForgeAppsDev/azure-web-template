# One-time Azure platform bootstrap

This deployment creates the central GitHub OIDC identity used only by
`MPiwowarski/azure-web-template` to provision isolated client resource groups.

Run once as an Azure subscription Owner (or an identity able to create resource
groups, managed identities, federated credentials, and role assignments):

```bash
az login
az account set --subscription <subscription-id>
az deployment sub create \
  --name azure-web-platform-bootstrap \
  --location westeurope \
  --template-file bootstrap/bootstrap.bicep
```

Copy the deployment outputs into repository variables on the central repository:

- `AZURE_PROVISIONER_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

No client secret is created. The federated subject trusts only the central
repository's `main` branch.

The provisioner receives a subscription-scoped custom role limited to Resource
Groups, ARM deployments, managed identities and federated credentials. It also
receives Role Based Access Control Administrator with a condition that permits
assigning only the client `Contributor` and conditioned `RBAC Administrator`
roles. It is intentionally never shared with client repos.
