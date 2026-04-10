# AKS Configurator — Design Specification

## Context

The azurebicep repo contains production-ready Bicep modules for deploying AKS clusters with networking, ACR, Key Vault, monitoring, identity, private endpoints, and RBAC. Operations teams currently need to understand the full parameter space by reading Bicep source files and manually editing `.bicepparam` files — error-prone and not discoverable.

This tool gives ops teams a visual, guided way to configure AKS deployments and generate correct Bicep parameter files without needing to understand the module internals.

## What We're Building

A **single static HTML file** (`tools/aks-configurator.html`) — a wizard-based configurator that:
- Walks ops teams through all AKS deployment parameters in 7 guided steps
- Shows ecosystem tools (Prometheus, Grafana, Istio, etc.) with deployment guidance
- Validates configurations and warns about conflicts
- Generates a downloadable `.bicepparam` file and deployment guide
- Supports save/load of configurations via JSON export/import

## Target Users

Internal operations team members who deploy and manage AKS clusters.

## Technical Approach

- **Single `.html` file** — no build step, no npm, no framework
- **Tailwind CSS via CDN** for styling (with inline fallback note for restricted networks)
- **Vanilla JavaScript** for wizard logic, validation, and code generation
- All parameter definitions and ecosystem tool data in a central JS schema object
- Estimated ~3000-4000 lines

### JS Architecture

```
schema = {}         // Single source: field definitions, defaults, validations, help text
state = {}          // All user selections + "edited" flags per field
generators = {}     // Functions: state -> .bicepparam code + deployment guide
validators = {}     // Functions: state -> warning/error messages
render()            // Updates DOM from state (step navigation, forms, review)
```

**Key design rule:** The `schema` object is the single source of truth for all fields. The UI renders from it. This makes updates easier — change schema, UI follows.

### Smart Defaults — Edit Tracking

Each field tracks whether it was user-edited or still at its default. When the user changes environment (e.g., dev → prod):
- **Untouched fields** update to the new environment's defaults
- **User-edited fields** are preserved
- A banner shows: "Environment changed to prod. X fields updated to recommended defaults."

### Support Level Badges

Every field and ecosystem tool displays a badge indicating its output target:
- **`In params`** (green) — Value written to the generated `.bicepparam` file
- **`Guide only`** (blue) — Included in deployment guide as post-deploy commands
- **`Info only`** (gray) — Informational, not in any generated output

This prevents users from assuming everything in the wizard lands in the Bicep parameter file.

### Subnet Capacity Calculation

The tool calculates required AKS subnet IP capacity based on:
- `(maxNodes × maxPodsPerNode) + maxNodes` for Azure CNI
- Compares against selected AKS subnet CIDR capacity
- Shows warning if subnet is too small (e.g., "/20 provides 4094 IPs, your config needs ~5500")

## Wizard Steps (7 steps)

### Step 1: Cluster Basics
| Field | Tier | Type | Validation | Notes |
|-------|------|------|-----------|-------|
| Customer name | Required | text | required, alphanumeric + hyphens, max 15 chars | Used in resource naming |
| Environment | Required | select: dev/acc/prod | required | Drives smart defaults |
| Azure region | Required | select | required | westeurope, northeurope, eastus, eastus2, westus2, etc. |
| Cluster type | Required | toggle: Public / Private | — | Shows implications inline |
| Kubernetes version | Required | select | required | 1.29, 1.30, 1.31 |

**Resource name preview:** As the user types customer name and selects environment/region, show a live preview of generated resource names:
- `rg-{customer}-{env}-{region}` (resource group)
- `aks-{customer}-{env}` (AKS cluster)
- `acr{customer}{env}` (ACR, if enabled)
- Warns if names exceed Azure length limits

**Cluster type implications shown inline:**
- **Public:** API server accessible from internet. Use authorized IP ranges (Step 3) to restrict.
- **Private:** API server only accessible within VNet. Requires Premium ACR for private endpoints. Needs VPN/jump box for management.

**Smart defaults on environment change:**
- `dev` → public cluster, 1 system node, 1 user node, Standard ACR, 30-day logs
- `acc` → private cluster, 2 system nodes, 2 user nodes, Premium ACR, 90-day logs
- `prod` → private cluster, 3 system nodes, 3 user nodes, Premium ACR, 365-day logs

### Step 2: Access & Governance
| Field | Tier | Type | Validation | Notes |
|-------|------|------|-----------|-------|
| Admin group Object IDs | Required | multi-input | at least 1 | Azure AD/Entra ID group GUIDs |
| Tags: CostCenter | Required | text | required | |
| Tags: Owner | Required | text | required | |
| Tags: Project | Required | text | required | |
| Custom tags | Advanced | key-value pairs | optional | Add/remove rows |
| Additional role assignments | Advanced | dynamic rows | optional | principalId + role + type |

**Info panel:** "Azure RBAC is enabled. Local accounts are disabled. Workload Identity and OIDC issuer are enabled by default."

### Step 3: Networking
| Field | Tier | Type | Validation | Notes |
|-------|------|------|-----------|-------|
| VNet address prefix | Required | text | valid CIDR, /16 recommended | e.g., 10.1.0.0/16 |
| AKS subnet prefix | Required | text | auto-suggested, within VNet, no overlap | /20 recommended for CNI |
| Services subnet prefix | Required | text | auto-suggested, within VNet, no overlap | /24 |
| PE subnet prefix | Required | text | auto-suggested, within VNet, no overlap | /24 |
| Service CIDR | Recommended | text | valid CIDR, no overlap with VNet | default 10.0.0.0/16 |
| DNS service IP | Recommended | text | must be within Service CIDR | default 10.0.0.10 |
| API server authorized IPs | Recommended | multi-input | valid CIDRs | Only for public clusters. Note: not in current modules — included in deployment guide as post-deploy `az aks update` command |

**Auto-suggestion:** When VNet prefix is entered (e.g., `10.1.0.0/16`), auto-populate:
- AKS: `10.1.0.0/20`
- Services: `10.1.16.0/24`
- PE: `10.1.17.0/24`

**Validation rules:**
- All subnets must be within VNet CIDR
- No subnet overlap
- Service CIDR must not overlap with VNet CIDR
- DNS service IP must be within Service CIDR
- API server authorized IPs only shown for public clusters

**Visual:** Styled HTML boxes showing subnet layout and address space allocation with used/free space indicators.

### Step 4: Compute / Node Pools
| Field | Tier | Type | Validation | Notes |
|-------|------|------|-----------|-------|
| **System Pool** | | | | |
| System VM size | Required | select (with vCPU/RAM) | required | D-series, E-series |
| Autoscaling enabled | Required | toggle | — | default: on |
| Min nodes | Required | number | min 1 | shown if autoscale on |
| Max nodes | Required | number | >= min | shown if autoscale on |
| Node count | Required | number | min 1 | shown if autoscale off |
| **User Pool** | | | | |
| User VM size | Required | select (with vCPU/RAM) | required | |
| Autoscaling enabled | Required | toggle | — | default: on |
| Min nodes | Required | number | min 1 | |
| Max nodes | Required | number | >= min | |
| Node count | Required | number | min 1 | if autoscale off |
| **Shared Settings** | | | | |
| OS disk size (GB) | Recommended | slider | 30-1024 | default 128 |
| Availability zones | Recommended | multi-select: 1, 2, 3 | — | default: all 3 for prod. Note: not in current modules — generates guidance for module extension |
| Upgrade channel | Advanced | select | — | none/patch/stable/rapid/node-image. Note: not in current modules — included in deployment guide as post-deploy config |
| Max pods per node | Advanced | number | 10-250 | default 110 (Azure CNI). Note: not in current modules — included in deployment guide |

**VM size options:** Standard_D2s_v5 (2 vCPU/8GB), D4s_v5 (4/16), D8s_v5 (8/32), D16s_v5 (16/64), E4s_v5 (4/32), E8s_v5 (8/64), E16s_v5 (16/128).

**Ecosystem dependency warnings:** If Istio is later selected (Step 6) and user VM has < 4 vCPU, show warning on review.

### Step 5: Azure Platform Services
| Field | Tier | Type | Validation | Notes |
|-------|------|------|-----------|-------|
| Deploy ACR | Recommended | toggle | — | |
| ACR SKU | Recommended | select: Basic/Standard/Premium | if ACR on | |
| Deploy Key Vault | Recommended | toggle | — | |
| Key Vault SKU | Recommended | select: standard/premium | if KV on | |
| Deploy Monitoring | Recommended | toggle | — | |
| Log retention (days) | Recommended | slider: 30-730 | if monitoring on | |

**Cross-field warnings:**
- Private cluster + ACR Standard/Basic → "Private endpoints require Premium ACR SKU"
- No monitoring + ecosystem tools selected → "Monitoring recommended for observability tools"
- ACR deployed → "AcrPull role will be assigned to AKS managed identity"

**Info panels for each service:**
- ACR: "Premium SKU enables geo-replication, private endpoints, and zone redundancy"
- Key Vault: "RBAC authorization, soft delete (90d), and purge protection enabled by default"
- Monitoring: "Log Analytics workspace with Container Insights integration"

### Step 6: Ecosystem Tools

Five categories. Each tool has a toggle, description, requirements check, and guidance preview. Tools that overlap or conflict show warnings.

**Each tool displays a deployment type badge:**
- **`AKS add-on`** — Native AKS feature, enabled via az CLI or Bicep
- **`Helm install`** — Deployed via Helm chart post-cluster creation
- **`Advanced`** — Requires production hardening beyond starter guidance

#### Monitoring
| Tool | Description | Requirements | Guidance |
|------|------------|-------------|----------|
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager bundle. Metrics, dashboards, alerting | Min 2 vCPU user nodes, monitoring enabled | Helm install with recommended values |
| **Azure Monitor / Container Insights** | Native Azure monitoring via Log Analytics | Monitoring feature flag enabled | Already configured via Bicep |

**Note:** kube-prometheus-stack includes Prometheus, Grafana, and Alertmanager as one package.

#### Service Mesh
| Tool | Description | Requirements | Guidance |
|------|------------|-------------|----------|
| **Istio** (AKS managed add-on) | mTLS, traffic management, canary deploys | Min 4 vCPU user nodes, ~2GB RAM/node | az aks mesh enable command |
| **Linkerd** | Lightweight mTLS, observability | Min 2 vCPU user nodes | Helm install |

**Warning if both selected:** "Selecting multiple service meshes is not recommended."

#### Ingress
| Tool | Description | Requirements | Guidance |
|------|------------|-------------|----------|
| **NGINX Ingress Controller** | Most popular K8s ingress, flexible routing | Services subnet | Helm install |
| **Azure App Gateway (AGIC)** | Azure-native L7 LB with WAF | Separate subnet recommended | AKS add-on or Helm |
| **Traefik** | Dynamic routing, auto TLS, middleware | Services subnet | Helm install |

#### Certificates & DNS
| Tool | Description | Requirements | Guidance |
|------|------------|-------------|----------|
| **cert-manager** | Automatic TLS certificate management (Let's Encrypt) | Ingress controller selected | Helm install |
| **external-dns** | Automatic DNS record management | Azure DNS zone access | Helm install |

#### GitOps & Security
| Tool | Description | Requirements | Guidance |
|------|------------|-------------|----------|
| **Flux** | GitOps operator, syncs K8s state from git | AKS extension | az k8s-extension create |
| **ArgoCD** | GitOps with UI dashboard | Min 2 vCPU for server | Helm install |
| **OPA/Gatekeeper** | Policy enforcement, admission control | — | Helm install |
| **Azure Policy** | Azure-native policy for AKS | No extra resources | AKS add-on |
| **Falco** | Runtime security monitoring | ~0.5 vCPU/node overhead | Helm install |
| **KEDA** | Event-driven pod autoscaling | — | AKS add-on or Helm |
| **CSI Secret Store + Key Vault provider** | Mount Key Vault secrets as volumes | Key Vault deployed | AKS add-on |

**Conflict warnings:**
- Flux + ArgoCD → "Both GitOps tools selected. Most teams use one or the other."
- Gatekeeper + Azure Policy → "These overlap in functionality. Consider which fits your governance model."

**Per-category recommendations:**
Each category shows: "Recommended for production", "Best for", "Can combine with" labels.

### Step 7: Review & Generate

**Architecture Visual** — Styled HTML card layout:
- Resource Group with all child resources
- VNet with subnet diagram
- AKS cluster with node pools
- Connected services (ACR, KV, Log Analytics)
- Ecosystem tools grouped by category
- Color-coded: green = enabled, gray = disabled

**Validation panel:**
- Errors (must fix): blocking issues like missing required fields
- Warnings (should fix): conflicts like private cluster + Standard ACR
- Info: suggestions and best practices

**Security posture summary:** Quick overview of enabled security features (RBAC, private cluster, private endpoints, workload identity, etc.)

**Download options:**
- "Download .bicepparam" — the parameter file for the selected environment
- "Download Deployment Guide" — markdown with all commands
- "Download All (.zip)" — both files plus a README
- "Copy to clipboard" buttons per file
- "Save Configuration" — export current wizard state as JSON
- "Load Configuration" — import previously saved JSON

**Version banner:** Shows tool version and compatible Bicep module version.

## Generated Output

### Primary: `.bicepparam` file
Generate only `main.{env}.bicepparam` — the parameter file that targets the existing `main.bicep` in the repo. This avoids drift from the repo's source of truth.

```bicep
using 'main.bicep'

param customerName = 'contoso'
param environment = 'prod'
param location = 'westeurope'
// ... all parameters filled from wizard state
```

The tool does NOT regenerate `main.bicep`, `types.bicep`, or modules — those are the repo's source of truth.

### Deployment Guide (Markdown)
Generated as `deployment-guide.md`:

1. **Prerequisites** — Azure CLI, Bicep, Helm, kubectl, required permissions
2. **Deploy Infrastructure**
   ```
   az deployment sub create --location {region} --template-file infra/main.bicep --parameters infra/main.{env}.bicepparam
   ```
3. **Connect to Cluster** — `az aks get-credentials` command
4. **Ecosystem Tools** — for each selected tool:
   - What it does (1-2 sentences)
   - Helm repo add + install commands with recommended values
   - Key configuration notes
   - Post-install verification (`kubectl get pods -n ...`)
   - Label: "Starter commands — review values for production use."
5. **Validation checklist** — commands to verify the full deployment

## Save / Load Configuration

- **Export:** Serializes wizard state to JSON with a `schemaVersion` field, downloads as `aks-config-{customer}-{env}.json`. Schema version enables import compatibility checks as the tool evolves.
- **Import:** Loads JSON, populates all wizard fields, respects edit tracking
- **Auto-save:** localStorage saves state on every field change, restores on page load
- **Reset:** "Start over" button clears state and localStorage

## v1 Scope Boundaries

**In scope:**
- 1 system pool + 1 user pool
- Azure CNI network plugin (hardcoded, matches current modules)
- Azure network policy (hardcoded, matches current modules)
- Load balancer outbound type (hardcoded)
- All ecosystem tools listed above

**Deferred to v2:**
- Multiple user node pools
- Network plugin choices (CNI Overlay, Kubenet)
- Network policy choices (Calico, Cilium)
- Outbound type choices (UDR, NAT Gateway)
- Spot node pools
- Node labels and taints
- Microsoft Defender for Containers
- FIPS / host encryption
- Cost estimation
- Managed Prometheus / Azure Managed Grafana
- Velero backup
- Kubecost

## Key Files

| File | Purpose |
|------|---------|
| `tools/aks-configurator.html` | The configurator tool (new) |
| `infra/main.bicep` | Source of truth for orchestration |
| `infra/types.bicep` | Source of truth for UDT definitions |
| `infra/main.dev.bicepparam` | Reference for parameter structure |
| `infra/main.acc.bicepparam` | Reference for parameter structure |
| `infra/main.prod.bicepparam` | Reference for parameter structure |
| `infra/modules/aks/aksCluster.bicep` | Reference for AKS parameters |

## Verification

1. Open `tools/aks-configurator.html` in a browser
2. Walk through all 7 wizard steps with a test configuration
3. Verify smart defaults apply when switching environments (only untouched fields update)
4. Verify validation warnings for conflicting configs (private + Standard ACR, Istio + small VMs)
5. Verify ecosystem tool conflict warnings (Flux + ArgoCD, Gatekeeper + Azure Policy)
6. Download generated `.bicepparam` file
7. Run `az bicep build -f infra/main.bicep --parameters <generated-file>` to verify valid Bicep
8. Compare generated `.bicepparam` with existing repo examples for structural correctness
9. Verify deployment guide contains correct Helm/az commands for selected ecosystem tools
10. Test save/load configuration (export JSON, reload page, import JSON, verify all fields restored)
11. Test auto-save (fill wizard, close tab, reopen — state should restore from localStorage)
