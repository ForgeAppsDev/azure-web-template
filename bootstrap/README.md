# One-time Azure platform bootstrap

This deployment creates the central GitHub OIDC identity used only by
`ForgeAppsDev/azure-web-template` to provision isolated client resource groups.

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

For repositories using GitHub immutable-ID OIDC subjects, pass the exact emitted subject as `--parameters githubSubject="repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main"`. The provisioner resolves IDs for client repositories automatically.


The bootstrap also assigns **Azure Web Shared Cosmos Provisioner** to the central identity at `rg-azure-web-platform` only. It can create project containers and container-scoped Cosmos SQL role assignments there; client deployment identities receive neither this role nor access to the platform resource group. The bootstrap does not create the Cosmos account.

After the bootstrap, create the account once with an interactive Azure Owner identity using `bootstrap/shared-cosmos.bicep`. This is intentionally separate because opting into Free Tier and changing account-level billing/network settings are platform-owner actions. The template opts in to Free Tier at initial account creation, disables local key authentication, and creates one 1000 RU/s shared-throughput database.
