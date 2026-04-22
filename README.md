# Enterprise AKS Infrastructure

Bicep Infrastructure-as-Code for deploying enterprise Azure Kubernetes Service (AKS) clusters with supporting resources. Ships with a browser-based wizard that generates the same hardened package based on customer-specific inputs.

Two paths, one baseline:

1. **`infra/`** — reference deployment. `main.bicep` + `main.<env>.bicepparam`. Clone, adjust parameters, `az deployment sub create`.
2. **`tools/aks-configurator.html`** — standalone HTML wizard. Open in a browser, walk through 7 steps, download a complete `.zip` with all templates, a deploy script, and a deployment guide. Both paths generate Bicep with the same Well-Architected baseline — changes in `infra/` and the configurator stay in sync via CI.

## Architecture Principles

| Principle | Implementation |
|---|---|
| Declarative orchestration | Single `main.bicep` with feature flags |
| Typed configuration | `.bicepparam` with User-Defined Types (UDTs) in `types.bicep` |
| Modular & versionable | Independent modules, ACR registry-ready |
| Shift-left validation | PSRule (blocking) + Checkov (soft-fail) on every PR |
| Hardened by default | AKS 2025-10-01 API, Cilium + Overlay, user-assigned NAT Gateway, Defender, Image Cleaner, CSI Secret Store, Azure Policy, auto-upgrade + maintenance windows, cost analysis, AzureLinux + Managed disks |
| Self-documenting | UDTs with `@description`, typed parameters, wizard + auto-generated deployment guide |

## What Gets Deployed?

Resources are optional via **feature flags** — toggle building blocks per customer.

| Resource | Feature Flag | Description |
|---|---|---|
| Resource Group | always | Dedicated resource group per environment |
| NAT Gateway | always | User-assigned NAT gateway with zone-redundant public IPs for AKS outbound traffic |
| Virtual Network | always | VNet with subnets for AKS, services, and private endpoints; NSGs with default-deny and outbound lateral-traversal guard |
| AKS Cluster | always | Managed Kubernetes (API 2025-10-01). Cilium dataplane + Azure CNI Overlay, user-assigned NAT Gateway outbound, system + user node pools, auto-upgrade + two maintenance windows, Defender for Containers, Image Cleaner, OIDC + Workload Identity, cost analysis |
| Maintenance Configurations | always | `aksManagedAutoUpgradeSchedule` (Sun 03:00 UTC) + `aksManagedNodeOSUpgradeSchedule` (Sat 03:00 UTC) |
| Managed Identity | always | User-assigned identity for AKS |
| Azure Container Registry | `features.deployAcr` | Premium registry with private endpoint, geo-replication for acc/prod, export policy disabled |
| Azure Key Vault | `features.deployKeyVault` | RBAC + purge protection + private endpoint; `azureKeyvaultSecretsProvider` CSI addon on the AKS side for secret mounting |
| Log Analytics | `features.deployMonitoring` | Workspace with replication in acc/prod |
| Data Collection Rule | `features.deployMonitoring` | Container Insights via DCR + DCR association — modern monitoring path |
| Azure Policy addon | always (AKS) | Gatekeeper-based policy enforcement |
| Role Assignments | conditional | Least-privilege RBAC, only for deployed resources |

## Structure

```
azurebicep/
├── bicepconfig.json
├── .ps-rule/
│   ├── ps-rule.yaml
│   └── suppression-groups.Rule.yaml
│
├── infra/
│   ├── bicepconfig.json
│   ├── main.bicep                          # Orchestrator with feature flags
│   ├── types.bicep                         # User-Defined Types (aksConfigType etc.)
│   ├── main.dev.bicepparam
│   ├── main.acc.bicepparam
│   ├── main.prod.bicepparam
│   └── modules/
│       ├── aks/aksCluster.bicep
│       ├── network/vnet.bicep
│       ├── network/natGateway.bicep
│       ├── identity/managedIdentity.bicep
│       ├── monitoring/logAnalytics.bicep
│       ├── monitoring/dcr.bicep
│       ├── acr/containerRegistry.bicep
│       ├── keyvault/keyVault.bicep
│       ├── privateEndpoint/privateEndpoint.bicep
│       └── roleAssignment/roleAssignment.bicep
│
├── tools/
│   ├── aks-configurator.html               # Browser wizard — 7 steps → downloadable .zip
│   └── test/
│       ├── package.json
│       └── generate-package.mjs
│
└── .github/workflows/
    ├── validate.yml                        # PR on infra/: Bicep build + PSRule + Checkov
    └── configurator-test.yml               # PR on tools/: JS syntax + generate + build + PSRule
```

## Quick Start

### 1. Customer-Specific Configuration

Edit the `.bicepparam` files per environment. All parameters are typed via UDTs — your IDE shows errors immediately for invalid configuration.

```bicep
// infra/main.dev.bicepparam
using 'main.bicep'

param customerName = 'mycustomer'
param environment = 'dev'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

param features = {
  deployAcr: true
  deployKeyVault: true
  deployMonitoring: true
}

param networkConfig = {
  vnetAddressPrefix: '10.1.0.0/16'
  aksSubnetPrefix: '10.1.0.0/20'
  servicesSubnetPrefix: '10.1.16.0/24'
  privateEndpointSubnetPrefix: '10.1.17.0/24'
}

param aksConfig = {
  kubernetesVersion: '1.35'
  systemNodeCount: 3
  systemNodeVmSize: 'Standard_D2s_v5'
  systemNodeMinCount: 3
  systemNodeMaxCount: 5
  userNodeCount: 3
  userNodeVmSize: 'Standard_D4s_v5'
  userNodeMinCount: 3
  userNodeMaxCount: 5
  enablePrivateCluster: false
  availabilityZones: []
  apiServerAuthorizedIPRanges: []
  skuTier: 'Free'               // 'Standard' required for SLA on acc/prod
  upgradeChannel: 'patch'
  nodeOSUpgradeChannel: 'NodeImage'
  osDiskType: 'Managed'
  osDiskSizeGB: 30
  maxPodsPerNode: 50
}

param adminGroupObjectIds = [
  // REQUIRED: replace with real Entra ID group or user Object ID.
  // Combined with disableLocalAccounts: true on the cluster,
  // the placeholder below causes a silent cluster lockout.
  // Get your user ID: az ad signed-in-user show --query id -o tsv
  '00000000-0000-0000-0000-000000000000'
]

param acrSku = 'Standard'
param keyVaultSku = 'standard'
param logRetentionDays = 30
```

**Minimum changes per customer:**
- `customerName` — short, lowercase, alphanumeric
- `adminGroupObjectIds` — real Entra ID group or user Object IDs (**not** the all-zeros placeholder; otherwise the cluster is unreachable after deploy). Get your ID: `az ad signed-in-user show --query id -o tsv`
- `tags.CostCenter` / `.Owner` / `.Project`
- `networkConfig` — VNet and subnet ranges
- `features` — which resources to deploy

### 2. Local Validation

```bash
# Requires: Azure CLI with Bicep extension
./scripts/validate.sh
```

Or manually:

```bash
az bicep build --file infra/main.bicep
```

### 3. Deployment

The generated zip includes a `deploy.sh` script that handles everything:

```bash
cd infra
chmod +x deploy.sh
./deploy.sh
```

The script runs 4 steps:
1. Registers required Azure resource providers
2. Creates the resource group (needed for what-if validation)
3. Runs `az deployment sub what-if` to preview changes and catch errors
4. Asks for confirmation, then deploys with `--no-wait`

Or deploy manually:

```bash
az deployment sub create \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam \
  --name "deploy-dev-001"
```

## Configurator Wizard

`tools/aks-configurator.html` is a standalone browser tool that generates the `infra/` package from UI inputs. No build step, no server — open the HTML file in any modern browser.

The wizard is **in sync** with `infra/`:
- Emits the exact same Bicep templates (API versions, Cilium + Overlay, user-assigned NAT Gateway, securityProfile, addons, DCR module, etc.)
- Includes a breaking-change warning in the generated deployment guide for users migrating from pre-Cilium / pre-NAT Gateway clusters
- Blocks placeholder admin GUIDs at generation time
- Validates VM size vs OS disk type compatibility (Ephemeral only available on VMs with local storage)
- Generates a `deploy.sh` with provider registration, resource group creation, what-if validation, and deploy

CI in `.github/workflows/configurator-test.yml` generates a package for dev/acc/prod on every PR, runs `az bicep build`, and scans with PSRule. Drift between wizard and `infra/` is caught automatically.

## CI/CD

### GitHub Actions

| Workflow | Trigger | Action |
|---|---|---|
| `validate.yml` | PR on `infra/**` or `bicepconfig.json` | Bicep build + PSRule (blocking) + Checkov (soft-fail) per `.bicepparam` environment |
| `configurator-test.yml` | PR on `tools/aks-configurator.html` or `tools/test/**` | JS syntax check + generate complete package for dev/acc/prod via jsdom + `az bicep build` + PSRule |

**Both workflows are fully offline** — no Azure OIDC, no secrets. The previous `deploy.yml`, `deploy-environment.yml`, `publish-modules.yml`, and the `what-if` matrix in `validate.yml` were removed because no Entra app registration can be created on this tenant for federated credentials. `git log -- .github/workflows/` shows the history; restoring requires three secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) plus a tenant admin with App Registration permissions.

### Azure DevOps

Pipeline definitions in `.azuredevops/` — same validate-then-deploy pattern, but not the primary CI for this repo. Same Entra requirement applies for ADO deployments.

## PSRule Policy

Blocking on `validate.yml` Lint & Security Scan. `.ps-rule/ps-rule.yaml` contains:
- Bicep expansion config + 30s timeout
- `pathIgnore` for `modules/**` + `main.bicep` (only entry point via `.bicepparam`)
- Suppressions for rules that don't understand the 2025-10-01 AKS schema, plus environment-gated suppressions for dev-only gaps (UptimeSLA, AuthorizedIPs, Log.Replication)
- `suppression-groups.Rule.yaml` — name-pattern matcher for hash-suffixed ACR names

If a new finding surfaces: fix the Bicep, not the suppressions. `continue-on-error: true` has been intentionally removed.

## Security Highlights

- **Hardened AKS baseline by default** — `sku.tier: Standard` for acc/prod, autoUpgradeProfile + maintenanceConfigurations, securityProfile.defender + imageCleaner, Cilium + Overlay, user-assigned NAT Gateway, azureMonitorProfile + DCR, metricsProfile.costAnalysis, osSKU AzureLinux
- **Admin access** — `disableLocalAccounts: true`, `aadProfile.managed` + `enableAzureRBAC`, Entra ID group via `adminGroupObjectIds`. Placeholder GUID is an intentional lockout guard — must be replaced before deploy
- **Workloads → secrets** — OIDC + Workload Identity + `azureKeyvaultSecretsProvider` CSI addon. Kubelet identity gets `Key Vault Secrets User` RBAC via `main.bicep`
- **Network** — private endpoints for ACR/KV, user-assigned NAT Gateway outbound, NSG outbound deny for management ports (lateral-traversal guard)
- **Policy** — `azurepolicy` addon (Gatekeeper) always on

## Breaking Change Notice

`networkPluginMode`, `networkDataplane`, `networkPolicy`, `outboundType`, `osSKU`, and `osDiskType` are **create-time** properties on `managedClusters`. Redeploying this Bicep against an existing cluster that used Azure CNI classic / Load Balancer outbound / Ubuntu / different disk type will fail. Options:
- Blue/green replace (recommended)
- Edit `infra/modules/aks/aksCluster.bicep` locally to match the existing cluster profile before deploy
- Follow the deployment guide generated by the configurator wizard — it has a rollback section listing which properties to revert

## Extensibility

### Additional Role Assignments

```bicep
param additionalRoleAssignments = [
  {
    principalId: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    principalType: 'Group'
  }
]
```

## Important Notes

### Ephemeral vs Managed OS Disks
Dsv5 and Esv5 series VMs do **not** support Ephemeral OS disks (no local cache/temp disk). Use Managed disk type for these VMs, or switch to Ddsv5/Edsv5 series (with local storage) for Ephemeral. The configurator enforces this automatically.

### Private Cluster and CI/CD
When `aksConfig.enablePrivateCluster: true`, a public GitHub-hosted runner cannot reach the AKS API server. Options:
- Self-hosted runner in the VNet
- Populate `apiServerAuthorizedIPRanges` with the runner's outbound IPs
- Manual deploy via a jumpbox / bastion instead of CI-based deploys

### ACR Private Endpoints
Require the **Premium** SKU. Dev uses Standard without PE to save costs.

### Required Permissions
The deploying identity needs at minimum **Contributor** at subscription scope for resource group creation. For `azureKeyvaultSecretsProvider` + Defender, read access on the Log Analytics workspace ID is also required.
