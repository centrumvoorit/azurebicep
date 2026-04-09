# Enterprise AKS Infrastructure

Bicep Infrastructure-as-Code voor het uitrollen van enterprise Azure Kubernetes Service (AKS) clusters met ondersteunende resources.

## Wat wordt er uitgerold?

| Resource | Beschrijving |
|---|---|
| **Resource Group** | Dedicated resource group per omgeving |
| **Virtual Network** | VNet met subnets voor AKS, services en private endpoints |
| **Network Security Groups** | NSGs met default-deny op elk subnet |
| **AKS Cluster** | Managed Kubernetes met system + user node pools |
| **Azure Container Registry** | Container registry met optionele private endpoint |
| **Azure Key Vault** | Secret management met private endpoint |
| **Log Analytics** | Centraal logging + Container Insights |
| **Managed Identity** | User-assigned identity voor AKS |
| **Role Assignments** | Least-privilege RBAC (AcrPull, Network Contributor, KV Secrets User) |

## Structuur

```
infra/
├── main.bicep                    # Orchestrator
├── main.dev.bicepparam           # Dev parameters
├── main.acc.bicepparam           # Acceptatie parameters
├── main.prod.bicepparam          # Productie parameters
└── modules/
    ├── network/vnet.bicep        # VNet + subnets + NSGs
    ├── identity/managedIdentity.bicep
    ├── monitoring/logAnalytics.bicep
    ├── acr/containerRegistry.bicep
    ├── keyvault/keyVault.bicep
    ├── aks/aksCluster.bicep
    ├── privateEndpoint/privateEndpoint.bicep
    └── roleAssignment/roleAssignment.bicep
```

## Snelstart

### 1. Klant-specifieke configuratie

Pas de `.bicepparam` bestanden aan per omgeving:

```bicep
// infra/main.dev.bicepparam
using 'main.bicep'

param customerName = 'mijnklant'        // Klantnaam (kort, lowercase)
param environment = 'dev'
param location = 'westeurope'
param adminGroupObjectIds = [
  'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'  // Azure AD groep voor cluster admins
]
// ... overige parameters
```

**Minimaal aan te passen per klant:**
- `customerName` — unieke klantnaam
- `adminGroupObjectIds` — Azure AD groep Object ID's
- `tags` — kostenplaats, eigenaar, etc.
- VNet address prefixes (als de klant een specifiek IP-bereik nodig heeft)

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
| `validate.yml` | Pull Request | Bicep build + what-if per omgeving |
| `deploy.yml` | Push naar main | Deploy dev → acc → prod (met approval gates) |

**Setup vereist:**
1. Maak een Azure AD App Registration met federated credential voor je GitHub repo
2. Stel de volgende GitHub secrets in:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
3. Maak GitHub Environments aan: `dev`, `acc`, `prod` (met protection rules voor acc/prod)

### Azure DevOps

| Pipeline | Trigger | Actie |
|---|---|---|
| `validate.yml` | Pull Request | What-if per omgeving |
| `deploy.yml` | Push naar main | Deploy met stages + approval gates |

**Setup vereist:**
1. Maak een Azure DevOps service connection (workload identity federation)
2. Stel de pipeline variabele `azureServiceConnection` in
3. Maak ADO Environments aan: `aks-dev`, `aks-acc`, `aks-prod` (met approvals voor acc/prod)

## Security

- **Private cluster**: standaard aan voor acc/prod (`enablePrivateCluster: true`)
- **Private endpoints**: ACR en Key Vault (Premium SKU vereist voor ACR)
- **Azure RBAC**: op AKS cluster, lokale accounts uitgeschakeld
- **Key Vault**: RBAC autorisatie, soft delete, purge protection
- **Workload Identity**: OIDC enabled op AKS
- **CI/CD**: OIDC/workload identity federation (geen opgeslagen secrets)
- **Diagnostics**: alle resources loggen naar Log Analytics

## Aandachtspunten

### Private cluster en CI/CD
Wanneer `enablePrivateCluster: true` is, kan een publieke GitHub-hosted runner de AKS API server niet bereiken. Opties:
- Self-hosted runner in het VNet
- `enablePrivateClusterPublicFQDN: true` instellen in de AKS module
- API server authorized IP ranges gebruiken in plaats van volledig private

### ACR Private Endpoints
Private endpoints op ACR vereisen de **Premium** SKU. Dev kan Standard gebruiken zonder PE om kosten te besparen.

### Hub-spoke DNS
Als je organisatie centraal DNS beheert, pas dan de `privateEndpoint` module aan om bestaande DNS zones te refereren in plaats van nieuwe aan te maken.

### Benodigde permissions
De deploying identity heeft minimaal **Contributor** op subscription scope nodig voor het aanmaken van resource groups.
