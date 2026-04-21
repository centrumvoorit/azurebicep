# Enterprise AKS Infrastructure

Bicep Infrastructure-as-Code voor het uitrollen van enterprise Azure Kubernetes Service (AKS) clusters met ondersteunende resources. Ships mee met een browser-based wizard die hetzelfde hardened pakket genereert op basis van klant-specifieke inputs.

Twee paden, één baseline:

1. **`infra/`** — de reference deployment. `main.bicep` + `main.<env>.bicepparam`. Clone, pas parameters aan, `az deployment sub create`.
2. **`tools/aks-configurator.html`** — zelfstandige HTML-wizard. Open in een browser, loop 7 stappen door, download een complete `.zip` met alle templates en een deployment guide. Beide paden genereren Bicep met dezelfde Well-Architected baseline — wijzigingen in infra/ en de configurator blijven in sync via de CI in dit repo.

## Architectuurprincipes

| Principe | Implementatie |
|---|---|
| Declaratieve orchestratie | Enkele `main.bicep` met feature flags |
| Typed configuratie | `.bicepparam` met User-Defined Types (UDTs) in `types.bicep` |
| Modulair & versioneerbaar | Onafhankelijke modules, ACR registry-ready |
| Shift-left validatie | PSRule (blocking) + Checkov (soft-fail) op elke PR |
| Hardened by default | AKS 2025-10-01 API, Cilium + Overlay, managed NAT gateway, Defender, Image Cleaner, CSI Secret Store, Azure Policy, auto-upgrade + maintenance windows, cost analysis, AzureLinux + Ephemeral disks |
| Self-documenting | UDTs met `@description`, typed parameters, wizard + auto-generated deployment guide |

## Wat wordt er uitgerold?

Resources zijn optioneel via **feature flags** — schakel building blocks aan/uit per klant.

| Resource | Feature Flag | Beschrijving |
|---|---|---|
| Resource Group | altijd | Dedicated resource group per omgeving |
| Virtual Network | altijd | VNet met subnets voor AKS, services en private endpoints; NSGs met default-deny en outbound lateral-traversal guard |
| AKS Cluster | altijd | Managed Kubernetes (API 2025-10-01). Cilium dataplane + Azure CNI Overlay, managed NAT gateway outbound, system + user node pools, auto-upgrade + twee maintenance windows, Defender for Containers, Image Cleaner, OIDC + Workload Identity, cost analysis |
| Maintenance Configurations | altijd | `aksManagedAutoUpgradeSchedule` (Sun 03:00 UTC) + `aksManagedNodeOSUpgradeSchedule` (Sat 03:00 UTC) |
| Managed Identity | altijd | User-assigned identity voor AKS |
| Azure Container Registry | `features.deployAcr` | Premium registry met private endpoint, geo-replication voor acc/prod, export policy disabled |
| Azure Key Vault | `features.deployKeyVault` | RBAC + purge protection + private endpoint; `azureKeyvaultSecretsProvider` CSI addon aan AKS-kant voor secret mounting |
| Log Analytics | `features.deployMonitoring` | Workspace met replication in acc/prod |
| Data Collection Rule | `features.deployMonitoring` | `azureMonitorProfile.containerInsights` + DCR association — moderne Container Insights pad, vervangt legacy `omsagent` addon |
| Azure Policy addon | altijd (AKS) | Gatekeeper-based policy enforcement |
| Role Assignments | conditioneel | Least-privilege RBAC, alleen voor gedeployde resources |

## Structuur

```
azurebicep/
├── bicepconfig.json                       # Root linter regels + module registry alias
├── ps-rule.yaml                            # Legacy root config (PSRule prefereert .ps-rule/)
│
├── .ps-rule/
│   ├── ps-rule.yaml                        # PSRule config — expansion + pathIgnore + suppressions
│   └── suppression-groups.Rule.yaml        # SuppressionGroup voor hash-suffixed ACR namen
│
├── infra/
│   ├── bicepconfig.json                    # Downgrade use-recent-api-versions voor diagnosticSettings
│   ├── main.bicep                          # Orchestrator met feature flags
│   ├── types.bicep                         # User-Defined Types (aksConfigType etc.)
│   ├── main.dev.bicepparam                 # Dev parameters
│   ├── main.acc.bicepparam                 # Acceptatie parameters
│   ├── main.prod.bicepparam                # Productie parameters
│   └── modules/
│       ├── network/vnet.bicep
│       ├── identity/managedIdentity.bicep
│       ├── monitoring/logAnalytics.bicep
│       ├── monitoring/dcr.bicep            # Data Collection Rule + association
│       ├── acr/containerRegistry.bicep
│       ├── keyvault/keyVault.bicep
│       ├── aks/aksCluster.bicep
│       ├── privateEndpoint/privateEndpoint.bicep
│       └── roleAssignment/roleAssignment.bicep
│
├── tools/
│   ├── aks-configurator.html               # Browser wizard — 7 steps → downloadable .zip
│   └── test/
│       ├── package.json                    # jsdom dep voor CI generator
│       └── generate-package.mjs            # Headless extractor for generate + bicep build CI
│
├── .github/workflows/
│   ├── validate.yml                        # PR op infra/: Bicep build + PSRule (blocking) + Checkov (soft-fail)
│   └── configurator-test.yml               # PR op tools/: JS syntax + generate + Bicep build + PSRule
│
├── .azuredevops/                           # ADO pipeline variants (referenced but not primary)
│   ├── validate.yml
│   ├── deploy.yml
│   └── templates/deploy-stage.yml
│
└── scripts/
    └── validate.sh                         # Lokale lint/build helper
```

## Snelstart

### 1. Klant-specifieke configuratie

Pas de `.bicepparam` bestanden aan per omgeving. Alle parameters zijn getypeerd via UDTs — je IDE geeft direct fouten bij ongeldige configuratie.

```bicep
// infra/main.dev.bicepparam
using 'main.bicep'

param customerName = 'mijnklant'
param environment = 'dev'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

// Feature flags
param features = {
  deployAcr: true
  deployKeyVault: true
  deployMonitoring: true
}

// Typed network configuratie
param networkConfig = {
  vnetAddressPrefix: '10.1.0.0/16'
  aksSubnetPrefix: '10.1.0.0/20'
  servicesSubnetPrefix: '10.1.16.0/24'
  privateEndpointSubnetPrefix: '10.1.17.0/24'
}

// Typed AKS configuratie — alle velden zijn verplicht (compile-time gecontroleerd)
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
  skuTier: 'Free'               // 'Standard' verplicht voor SLA op acc/prod
  upgradeChannel: 'patch'
  nodeOSUpgradeChannel: 'NodeImage'
  osDiskType: 'Ephemeral'
  osDiskSizeGB: 30
  maxPodsPerNode: 50
}

param adminGroupObjectIds = [
  // REQUIRED: vervang met Azure AD groep Object ID's.
  // Gecombineerd met disableLocalAccounts: true op het cluster
  // veroorzaakt de placeholder hieronder een silent cluster lockout.
  '00000000-0000-0000-0000-000000000000'
]

param acrSku = 'Standard'
param keyVaultSku = 'standard'
param logRetentionDays = 30
```

**Minimaal aan te passen per klant:**
- `customerName` — korte, lowercase, alfanumeriek
- `adminGroupObjectIds` — Azure AD groep Object ID's (**niet** de all-zeros placeholder; anders is het cluster na deploy onbereikbaar)
- `tags.CostCenter` / `.Owner` / `.Project`
- `networkConfig` — VNet en subnet ranges
- `features` — welke resources nodig zijn

### 2. Lokale validatie

```bash
# Vereist: Azure CLI met Bicep extensie
./scripts/validate.sh
```

Of handmatig:

```bash
az bicep build --file infra/main.bicep
```

### 3. Deployment

```bash
az deployment sub create \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam \
  --name "deploy-dev-001"
```

## Configurator wizard

`tools/aks-configurator.html` is een zelfstandige browser-tool die het `infra/` pakket genereert op basis van UI-inputs. Geen build step, geen server — open het HTML bestand in een moderne browser.

De wizard is **in sync** met `infra/`:
- Emits exact dezelfde Bicep templates (API versions, Cilium + overlay, managed NAT gateway, securityProfile, addons, DCR module, etc.)
- Bundelt een `BREAKING.md`-stijl waarschuwing in de gegenereerde deployment guide voor users die migreren vanaf pre-Cilium / pre-NAT Gateway clusters
- Runtime-validator weigert de all-zeros admin GUID placeholder (de reference `.bicepparam` in `infra/` heeft een manuele commentaar waarschuwing)

De CI in `.github/workflows/configurator-test.yml` genereert op elke PR een pakket voor dev/acc/prod, draait `az bicep build` en scant met PSRule. Drift tussen wizard en `infra/` wordt zo afgevangen.

## CI/CD

### GitHub Actions

| Workflow | Trigger | Actie |
|---|---|---|
| `validate.yml` | Pull Request op `infra/**` of `bicepconfig.json` | Bicep build + PSRule (blocking) + Checkov (soft-fail) op elke `.bicepparam` omgeving |
| `configurator-test.yml` | Pull Request op `tools/aks-configurator.html` of `tools/test/**` | JS syntax check + generate complete pakket voor dev/acc/prod via jsdom + `az bicep build` + PSRule |

**Beide workflows zijn volledig offline** — geen Azure OIDC, geen secrets. De tidigare `deploy.yml`, `deploy-environment.yml`, `publish-modules.yml` en de `what-if` matrix in `validate.yml` zijn verwijderd omdat op deze tenant geen Entra app registration aangemaakt kan worden voor federated credentials. `git log -- .github/workflows/` toont de history; herstellen vereist de drie secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` plus een tenant admin met App Registration rechten.

### Azure DevOps

Pipeline definities staan in `.azuredevops/` — zelfde validate-then-deploy pattern, maar niet de primaire CI voor dit repo. Zelfde Entra vereiste geldt voor ADO deployments.

## PSRule policy

Blocking op `validate.yml` Lint & Security Scan. `.ps-rule/ps-rule.yaml` bevat:
- Bicep expansion config + 30s timeout (defaulted van 5s)
- `pathIgnore` voor `modules/**` + `main.bicep` (alleen entry point via `.bicepparam`)
- Suppressions voor stale rules die de 2025-10-01 AKS schema niet begrijpen (Azure.AKS.NetworkPolicy / UseRBAC / ContainerInsights / StandardLB / PoolScaleSet / AuditLogs / PlatformLogs), plus environment-gated suppressions voor dev-only gaps (UptimeSLA, AuthorizedIPs, Log.Replication).
- `suppression-groups.Rule.yaml` — name-pattern matcher voor hash-suffixed ACR namen (`acrcitestdev*` + `acrcontosodev*`).

Als een nieuwe finding opduikt: fix de finding in de Bicep, niet de suppressions. `continue-on-error: true` is bewust verwijderd.

## Security highlights

- **Hardened AKS baseline by default** — `sku.tier: Standard` voor acc/prod, autoUpgradeProfile + maintenanceConfigurations, securityProfile.defender + imageCleaner, Cilium + Overlay, managedNATGateway, azureMonitorProfile + DCR (niet de legacy omsagent addon), metricsProfile.costAnalysis, osSKU AzureLinux, osDiskType Ephemeral.
- **Admin access** — `disableLocalAccounts: true`, `aadProfile.managed` + `enableAzureRBAC`, Azure AD groep via `adminGroupObjectIds`. Placeholder GUID is een bewuste lockout guard — moet vervangen worden vóór deploy.
- **Workloads → secrets** — OIDC + Workload Identity + `azureKeyvaultSecretsProvider` CSI addon. Kubelet identity krijgt `Key Vault Secrets User` RBAC via `main.bicep`.
- **Network** — private endpoints voor ACR/KV, managed NAT gateway outbound, NSG outbound deny voor management ports (lateral-traversal guard).
- **Policy** — `azurepolicy` addon (Gatekeeper) always on.

## Breaking change notice

`networkPluginMode`, `networkDataplane`, `networkPolicy`, `outboundType`, `osSKU`, en `osDiskType` zijn **create-time** properties op `managedClusters`. Redeploy van deze Bicep tegen een bestaand cluster dat op Azure CNI classic / loadBalancer outbound / Ubuntu / Managed disk draaide zal falen. Opties:
- Blue/green replace (aanbevolen)
- Edit `infra/modules/aks/aksCluster.bicep` lokaal om het bestaande cluster-profile te matchen vóór de deploy
- Volg de deployment guide die de configurator wizard genereert — daar staat een rollback-sectie die exact aangeeft welke properties terug te draaien

## Extensibility

### Extra role assignments

```bicep
param additionalRoleAssignments = [
  {
    principalId: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    principalType: 'Group'
  }
]
```

## Aandachtspunten

### Private cluster en CI/CD
Wanneer `aksConfig.enablePrivateCluster: true`, kan een publieke GitHub-hosted runner de AKS API server niet bereiken. Opties:
- Self-hosted runner in het VNet
- `apiServerAuthorizedIPRanges` populeren met de runner's uitgaande IPs
- Geen CI-based deploys maar handmatig via een jumpbox / bastion

### ACR Private Endpoints
Vereisen de **Premium** SKU. Dev gebruikt Standard zonder PE om kosten te besparen.

### Ephemeral OS disk grootte vs VM cache
`osDiskSizeGB: 30` is de veilige default (Azure minimum) en past binnen de cache van elke VM size in de wizard's lijst. Upgrade bewust: D2s_v5 cache = 50 GB, D4s_v5 = 100 GB, D8s_v5 = 200 GB. Zet `osDiskSizeGB` hoger dan de cache size van je gekozen VM en de deploy faalt.

### Benodigde permissions
Deploying identity heeft minimaal **Contributor** op subscription scope nodig voor resource group creatie. Voor `azureKeyvaultSecretsProvider` + Defender is ook read access op de Log Analytics workspace ID nodig.

## AKS + Bicep review skill

Voor diepgaande reviews van AKS Bicep is er een Claude Code skill op `~/.claude/skills/azure-aks-bicep-expert/`. Triggert op elke PR die AKS bicep raakt; produceert gestructureerde findings (operational/network/security/cost) met `@file:line` links en live Microsoft Learn references.
