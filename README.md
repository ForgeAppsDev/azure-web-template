# Azure Web Template and Provisioning Platform

One repository with two roles:

1. a GitHub Template Repository for independent client sites;
2. the central Azure control plane that provisions each client's isolated deployment boundary.

The design targets 20–30 sites without sharing credentials or a subscription-wide
deployment identity between clients.

## Architecture

```text
azure-web-template (central provisioner)
  └─ Provision site
       ├─ rg-{project}-{environment}
       ├─ id-github-{project}-{environment}
       ├─ GitHub main-branch OIDC federation
       └─ Contributor + RBAC Administrator scoped only to that client RG

client repository
  └─ deploy.yml (thin wrapper)
       └─ reusable-deploy.yml from azure-web-template@main
            ├─ OIDC login as the client's identity
            ├─ Bicep infrastructure deployment
            ├─ frontend deployment to Static Web Apps
            └─ optional .NET 8 isolated Functions deployment
```

No client secret, publish profile, PAT, or permanent Static Web Apps deployment
token is committed. The SWA token is obtained dynamically after Azure OIDC login,
masked, used once, and discarded with the runner.

## Infrastructure profiles

All profiles use the single `infra/main.bicep` orchestrator and conditional modules.

| Profile | Resources |
| --- | --- |
| `static` | Azure Static Web App only |
| `serverless` | Free Static Web App, separate .NET 8 isolated Azure Functions on Flex Consumption, runtime identity, Functions Storage, Log Analytics and Application Insights |
| `advanced` | Everything in `serverless`, plus a separate application-data Storage Account |

`serverless` keeps the browser frontend and API on separate HTTPS origins. The
deployment workflow does **not** link Functions into Static Web Apps, because that
integration requires the paid Standard tier. Configure API CORS for the exact SWA
origin; CORS is not authentication, so every non-public API operation must validate
the caller's access token and authorization role.

For document data, consider the platform-owned shared Cosmos DB Free account only
when a project benefits from document queries. It is an opt-in data mode and is not
created in a client resource group. Create one container per project/environment in
the platform's shared-throughput database, use the project's own partition key, and
grant that app's runtime identity a data-plane role scoped only to its container.
Never give a client deployment identity the Cosmos account key or broad account
access. The one-account free allowance is 1,000 RU/s and 25 GB total, shared by all
projects; a shared database supports at most 25 containers. Cosmos Free is provisioned
throughput, not Cosmos Serverless, and the allowance is not a hard spending cap.
Choose isolated Table Storage for simple key lookups or whenever shared throughput,
administration, or recovery boundaries are unacceptable.

Functions uses the current `FC1` Flex Consumption plan, managed identity access to
Storage, and a dedicated blob container for deployment packages. Linux Consumption
`Y1` is not used.

## 1. Initial platform bootstrap (one time)

This connects only the central repository to the Azure subscription:

```text
ForgeAppsDev/azure-web-template
  → GitHub OIDC
  → id-github-azure-web-provisioner
  → Azure subscription provisioning permissions
```

Run as a subscription Owner:

```bash
az login
az account set --subscription <subscription-id>
az deployment sub create \
  --name azure-web-platform-bootstrap \
  --location westeurope \
  --template-file bootstrap/bootstrap.bicep
```

Add the returned values as Actions variables in **this central repository**:

- `AZURE_PROVISIONER_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

See [`bootstrap/README.md`](bootstrap/README.md) for the exact boundary and required
permissions. This is the only Azure bootstrap requiring an interactive privileged
Azure identity.

## 2. Add a new client

Example client:

```text
repository:  client-wisniowy-piec
projectName: wisniowy-piec
profile:     static
environment: prod
location:    westeurope
```

### Step A — create the client repository

On GitHub select **Use this template**, then create:

```text
ForgeAppsDev/client-wisniowy-piec
```

### Step B — provision its isolated Azure boundary

In this central repository run **Actions → Provision site → Run workflow** and enter
the values above.

The workflow creates:

```text
rg-wisniowy-piec-prod
└─ id-github-wisniowy-piec-prod
   └─ federated subject:
      repo:ForgeAppsDev/client-wisniowy-piec:ref:refs/heads/main
```

The identity receives `Contributor` and `Role Based Access Control Administrator`
only on `rg-wisniowy-piec-prod`. The second role is required because the application
Bicep grants the Functions runtime identity narrow Storage data roles. It has no
access to other clients or subscription scope.

### Step C — set client repository variables

GitHub deliberately scopes the built-in `GITHUB_TOKEN` to the repository running the
workflow. It cannot write Actions variables in another repository. `Provision site`
therefore prints eight ready-to-run `gh variable set` commands in its job summary:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_LOCATION`
- `PROJECT_NAME`
- `SITE_PROFILE`
- `ENVIRONMENT_NAME`

Run those commands once while GitHub CLI is authenticated as the repository owner.
This is the smallest manual GitHub step and does not store a PAT in either repo.

For future zero-touch variable configuration, install a narrowly scoped GitHub App
with **Actions variables: write** on selected client repositories and mint short-lived
installation tokens. Do not use a classic PAT or commit an App private key.

### Step D — deploy

Push site code to the client's `main` branch or run **Deploy site** manually.
The thin `.github/workflows/deploy.yml` calls the central reusable workflow:

```yaml
uses: ForgeAppsDev/azure-web-template/.github/workflows/reusable-deploy.yml@main
```

Infrastructure is created or updated idempotently, then the frontend and optional
Functions backend are deployed. Changes to the central deployment pipeline apply to
all clients on their next run without editing 30 repositories.

## Expected client layout

The reusable deployment supports either a Node frontend or plain static HTML:

```text
package.json          # optional; runs npm ci and npm run build
dist/                 # default Node build output
index.html            # plain static alternative
api/*.csproj          # optional for serverless/advanced
infra/main.bicep
```

Paths can be changed through reusable-workflow inputs if a client needs a different
layout.

## Direct infrastructure deployment

For local diagnostics or one-off deployment:

```bash
az group create --name rg-my-site-dev --location westeurope
az deployment group create \
  --resource-group rg-my-site-dev \
  --template-file infra/main.bicep \
  --parameters infra/profiles/static.bicepparam \
  --parameters projectName=my-site environmentName=dev
```

Replace the parameter file with `serverless.bicepparam` or
`advanced.bicepparam` as required.

## Repository structure

```text
.github/workflows/
  deploy.yml             thin workflow copied to client repos
  reusable-deploy.yml    central deployment implementation
  provision-site.yml     central-only client provisioner
  validate-infra.yml     Bicep and workflow validation
bootstrap/
  bootstrap.bicep        one-time central OIDC bootstrap
  README.md
provision/
  provision-site.bicep   RG, client identity, federation and RBAC
infra/
  main.bicep             single profile orchestrator
  modules/
  profiles/
```

`provision-site.yml` has a hard repository guard and cannot execute after being
copied into a client repository. Conversely, `deploy.yml` skips the central repo.

## Security model

- GitHub OIDC only; no `AZURE_CLIENT_SECRET`.
- One User Assigned Managed Identity per client repository and environment.
- Client deployment identity is scoped only to its own Resource Group.
- Separate Functions runtime identity with Storage data-plane roles only.
- No committed tenant, subscription, client IDs, PATs, publish profiles, or SWA tokens.
- Central provisioner identity is never exposed to client repositories.
- Federated credentials trust the exact repository and `refs/heads/main` subject.
- The central provisioner uses a custom provisioning role rather than subscription
  `Contributor`. Its conditioned RBAC role can assign only the two client-boundary
  roles. Bootstrap it once and use it only from the guarded central workflow.

## Validation

Pull requests and pushes affecting infrastructure run:

- Bicep build for `infra/main.bicep`;
- Bicep parameter builds for all three profiles;
- Bicep builds for bootstrap and provisioning templates;
- `actionlint` for every GitHub Actions workflow.


## Shared Cosmos DB for serverless projects

For small serverless projects that need durable NoSQL data, first check whether the
platform-owned Cosmos DB for NoSQL account can host a separate project/environment
container. Avoid creating a database account per template project during early
development when tenant-level cost consolidation is the requirement.

The account is created once in `rg-azure-web-platform` from
`bootstrap/shared-cosmos.bicep`. The template opts into Free Tier on account
creation, disables local key authentication, uses one region, and creates the
`forgeapps` database with a single manually provisioned shared throughput cap of
1000 RU/s. Free Tier covers up to 25 GB and 1000 RU/s on one account per subscription.
Containers in the shared-throughput database share that RU pool; a container is an
isolation boundary for names/data, while Cosmos SQL RBAC is scoped separately to
that exact container.

For each non-static project/environment, the central provisioning workflow creates a
container named `products-{project}-{environment}`, partitioned by `/project`, and
grants the app runtime managed identity Cosmos DB Built-in Data Contributor only on
that container. The client GitHub deployment identity receives no Cosmos data-plane
role and has no access to the platform resource group. The application uses managed
identity and never reads account keys. Monitoring is enabled for serverless projects
with a 0.1 GB/day Log Analytics ingestion cap to bound unexpected telemetry charges.
Keep containers, storage, and throughput within the account's free limits. At the
25-container limit or when one workload needs independent throughput, region, or
availability controls, move that workload to its own account/database after reviewing cost.

To create the shared account once, use an Azure Owner identity:

```sh
az deployment group create \
  --name shared-cosmos-bootstrap \
  --resource-group rg-azure-web-platform \
  --template-file bootstrap/shared-cosmos.bicep \
  --parameters location=westeurope
```

Copy the output account name to the central repository Actions variable
`SHARED_COSMOS_ACCOUNT_NAME`. Then provision the app with the `serverless` profile;
the central workflow prints the endpoint, database, container, and partition value for
the client's Actions variables. Never enable Cosmos Serverless, per-container
throughput, autoscale, or additional regions on this shared free-tier account.
