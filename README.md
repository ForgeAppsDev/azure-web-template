# Azure Web Template

Reusable Azure infrastructure template for static sites and serverless web applications.

## Profiles

| Profile | Resources |
| --- | --- |
| `static` | Azure Static Web App |
| `serverless` | Static Web App, Linux Consumption plan, Azure Functions, Storage, Application Insights |
| `advanced` | Everything in `serverless`, plus a separate data Storage Account prepared for application data |

## Deploy

```bash
az group create --name rg-my-site-dev --location westeurope
az deployment group create \  --resource-group rg-my-site-dev \  --template-file infra/main.bicep \  --parameters infra/profiles/static.bicepparam \  --parameters projectName=my-site environmentName=dev
```

Replace `static.bicepparam` with `serverless.bicepparam` or `advanced.bicepparam` as needed.

## Structure

- `infra/main.bicep` - single entry point for all profiles
- `infra/modules/` - focused, reusable resource modules
- `infra/profiles/` - profile parameter files
- `.github/workflows/validate-infra.yml` - Bicep build validation for pull requests and pushes

## Design notes

- Resource names are derived from `projectName`, `environmentName`, and a deterministic Azure suffix.
- The Functions backend is optional and enabled by profile.
- Secrets are not stored in the template. Function configuration uses managed Azure resource references.
- The template outputs deployed resource names and the Static Web App hostname.
