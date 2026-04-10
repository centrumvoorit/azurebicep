# Enterprise AKS Infrastructure

Bicep Infrastructure-as-Code voor het uitrollen van enterprise Azure Kubernetes Service (AKS) clusters met ondersteunende resources. Gebouwd volgens de principes uit de *Modern Bicep Delivery* architectuur.

## Architectuurprincipes

| Principe | Implementatie |
|---|---|
| Declaratieve orchestratie | Enkele `main.bicep` met feature flags |
| Typed configuratie | `.bicepparam` met User-Defined Types (UDTs) |
| Modulair & versioneerbaar | Onafhankelijke modules, ACR registry-ready |
| Shift-left validatie | PSRule + Checkov + what-if op elke PR |
| Generieke workflows | Reusable workflows (GH Actions + ADO templates) |
| Self-documenting | UDTs met `@description`, typed parameters |

## Wat wordt er uitgerold?

Alle resources zijn optioneel via **feature flags** — schakel building blocks aan/uit per klant.

| Resource | Feature Flag | Beschrijving |
|---|---|---|
| **Resource Group** | altijd | Dedicated resource group per omgeving |
| **Virtual Network** | altijd | VNet met subnets voor AKS, services en private endpoints |
| **Network Security Groups** | altijd | NSGs met default-deny op elk subnet |
| **AKS Cluster** | altijd | Managed Kubernetes met system + user node pools |
| **Managed Identity** | altijd | User-assigned identity voor AKS |
| **Azure Container Registry** | `features.deployAcr` | Container registry met optionele private endpoint |
| **Azure Key Vault** | `features.deployKeyVault` | Secret management met private endpoint |
| **Log Analytics** | `features.deployMonitoring` | Centraal logging + Container Insights |
| **Role Assignments** | conditioneel | Least-privilege RBAC, alleen voor gedeployde resources |

## Structuur

```
azurebicep/
├── bicepconfig.json                       # Linter regels + module registry alias
├── ps-rule.yaml                           # PSRule configuratie
├── .checkov.yaml                          # Checkov configuratie
│
├── infra/
│   ├── main.bicep                         # Orchestrator met feature flags
│   ├── types.bicep                        # User-Defined Types (UDTs)
│   ├── main.dev.bicepparam                # Dev parameters
│   ├── main.acc.bicepparam                # Acceptatie parameters
│   ├── main.prod.bicepparam               # Productie parameters
│   └── modules/
│       ├── network/vnet.bicep
│       ├── identity/managedIdentity.bicep
│       ├── monitoring/logAnalytics.bicep
│       ├── acr/containerRegistry.bicep
│       ├── keyvault/keyVault.bicep
│       ├── aks/aksCluster.bicep
│       ├── privateEndpoint/privateEndpoint.bicep
│       └── roleAssignment/roleAssignment.bicep
│
├── .github/workflows/
│   ├── validate.yml                       # PR: lint + PSRule + Checkov + what-if
│   ├── deploy.yml                         # Main: staged deploy via reusable workflow
│   ├── deploy-environment.yml             # Reusable workflow per omgeving
│   └── publish-modules.yml                # Tag: publiceer modules naar ACR registry
│
├── .azuredevops/
│   ├── validate.yml                       # PR: lint + PSRule + Checkov + what-if
│   ├── deploy.yml                         # Main: staged deploy via template
│   └── templates/
│       └── deploy-stage.yml               # Herbruikbaar deploy template
│
└── scripts/
    └── validate.sh                        # Lokale lint/build helper
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

// Feature flags — schakel building blocks aan/uit
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

// Typed AKS configuratie
param aksConfig = {
  kubernetesVersion: '1.30'
  systemNodeCount: 1
  systemNodeVmSize: 'Standard_D2s_v5'
  userNodeCount: 1
  userNodeVmSize: 'Standard_D4s_v5'
  enablePrivateCluster: false
}

param adminGroupObjectIds = [
  'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
]
```

**Minimaal aan te passen per klant:**
- `customerName` — unieke klantnaam
- `adminGroupObjectIds` — Azure AD groep Object ID's
- `tags` — kostenplaats, eigenaar, etc.
- `networkConfig` — VNet en subnet ranges
- `features` — welke resources nodig zijn

### 2. Lokale validatie

```bash
# Vereist: Azure CLI met Bicep extensie
./scripts/validate.sh
```

### 3. Deployment

**Handmatig (Azure CLI):**

```bash
az deployment sub create \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam \
  --name "deploy-dev-001"
```

**Via CI/CD:** Zie de pipelines hieronder.

## CI/CD

### GitHub Actions

| Workflow | Trigger | Actie |
|---|---|---|
| `validate.yml` | Pull Request | Bicep build + PSRule + Checkov + what-if per omgeving |
| `deploy.yml` | Push naar main | Deploy dev → acc → prod via reusable workflow |
| `deploy-environment.yml` | Reusable | Generiek deploy workflow per omgeving |
| `publish-modules.yml` | Git tag `v*` | Publiceer modules naar ACR registry |

**Setup vereist:**
1. Maak een Azure AD App Registration met federated credential voor je GitHub repo
2. Stel de volgende GitHub secrets in:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `ACR_REGISTRY_NAME` (optioneel, voor module publicatie)
3. Maak GitHub Environments aan: `dev`, `acc`, `prod` (met protection rules voor acc/prod)

### Azure DevOps

| Pipeline | Trigger | Actie |
|---|---|---|
| `validate.yml` | Pull Request | Lint + PSRule + Checkov + what-if |
| `deploy.yml` | Push naar main | Deploy via herbruikbaar template |
| `templates/deploy-stage.yml` | Template | Generiek deploy stage |

**Setup vereist:**
1. Maak een Azure DevOps service connection (workload identity federation)
2. Stel de pipeline variabele `azureServiceConnection` in
3. Maak ADO Environments aan: `aks-dev`, `aks-acc`, `aks-prod` (met approvals voor acc/prod)

## Module Registry

Modules kunnen gepubliceerd worden naar een Azure Container Registry voor versiebeheer:

```bash
# Handmatig publiceren
az bicep publish \
  --file infra/modules/aks/aksCluster.bicep \
  --target br:myregistry.azurecr.io/bicep/modules/aks/aksCluster:1.0.0

# Consumeren vanuit registry
module aks 'br/modules:aks/aksCluster:1.0.0' = { ... }
```

Automatisch publiceren via `publish-modules.yml` bij het aanmaken van een Git tag (`v1.0.0`).

## Security

- **Private cluster**: standaard aan voor acc/prod (`aksConfig.enablePrivateCluster`)
- **Private endpoints**: ACR en Key Vault (Premium SKU vereist voor ACR)
- **Azure RBAC**: op AKS cluster, lokale accounts uitgeschakeld
- **Key Vault**: RBAC autorisatie, soft delete, purge protection
- **Workload Identity**: OIDC enabled op AKS
- **CI/CD**: OIDC/workload identity federation (geen opgeslagen secrets)
- **Diagnostics**: alle resources loggen naar Log Analytics
- **PSRule**: Azure best practices validatie op elke PR
- **Checkov**: IaC security scanning op elke PR

## Extensibility

### Extra role assignments

Voeg extra role assignments toe zonder `main.bicep` aan te passen:

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
Wanneer `aksConfig.enablePrivateCluster` is `true`, kan een publieke GitHub-hosted runner de AKS API server niet bereiken. Opties:
- Self-hosted runner in het VNet
- `enablePrivateClusterPublicFQDN: true` instellen in de AKS module
- API server authorized IP ranges gebruiken in plaats van volledig private

### ACR Private Endpoints
Private endpoints op ACR vereisen de **Premium** SKU. Dev kan Standard gebruiken zonder PE om kosten te besparen.

### Hub-spoke DNS
Als je organisatie centraal DNS beheert, pas dan de `privateEndpoint` module aan om bestaande DNS zones te refereren in plaats van nieuwe aan te maken.

### Benodigde permissions
De deploying identity heeft minimaal **Contributor** op subscription scope nodig voor het aanmaken van resource groups.
