# AKS Configurator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-file HTML wizard that lets ops teams configure AKS deployments and generate `.bicepparam` files + deployment guides.

**Architecture:** Single `tools/aks-configurator.html` file. Schema-driven: a central data object defines all fields, defaults, validations. `state` tracks values + edit flags. `render()` dispatches to per-step renderers. Generators produce `.bicepparam` and markdown output. All HTML content is generated from user's own local input (internal tool, opened as local file).

**Tech Stack:** Vanilla JavaScript, Tailwind CSS (CDN), HTML5

**Spec:** `docs/superpowers/specs/2026-04-10-aks-configurator-design.md`

**Reference files for output format:**
- `infra/main.dev.bicepparam` -- dev parameter structure
- `infra/main.prod.bicepparam` -- prod parameter structure
- `infra/main.bicep` -- parameter names and types
- `infra/types.bicep` -- UDT definitions

**Security note:** This is a local-only internal tool opened as a file in the browser. All rendered content originates from the user's own input -- no external/untrusted data is rendered. The `escapeHtml()` utility is used for code preview sections.

---

## Critical Rules (from GPT review)

1. **Generator scope:** Only emit params that exist in `infra/main.bicep`. The params are: `customerName`, `environment`, `location`, `tags`, `features`, `networkConfig`, `aksConfig`, `adminGroupObjectIds`, `acrSku`, `keyVaultSku`, `logRetentionDays`, `additionalRoleAssignments`. Guide-only fields (authorized IPs, availability zones, upgrade channel, max pods) go in the deployment guide markdown, NOT in the `.bicepparam` file.

2. **Generator format:** Use a fixed template approach (ordered string concatenation), not dynamic object iteration. Add `bicepString(value)` helper that escapes single quotes for Bicep (`O'Brien` → `O''Brien`).

3. **State mutation rule:** All array/object updates must clone before modifying. Never mutate `state[key].value` in place. Always `setVal(key, [...oldArray])` or `setVal(key, {...oldObj})`.

4. **Validation per-step:** Each task implements validation ONLY for its own step. Task 1 validates Step 1 only. Task 2 adds Step 2 validation. Etc.

5. **Step navigation:** `goToStep()` is intentionally unrestricted — users can jump to any step to review or fix. Only `nextStep()` gates on validation.

6. **Subnet capacity before compute:** Task 3's subnet capacity calculation uses current state values (which are env defaults until Task 4 is filled). This is correct behavior.

7. **File sections:** Structure the JS with clear comment section headers as table of contents: CONSTANTS, ENV_DEFAULTS, ECOSYSTEM_TOOLS, STATE, VALIDATION, CIDR_UTILS, RENDER, STEP_RENDERERS, GENERATORS, PERSISTENCE, INIT.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `tools/aks-configurator.html` | CREATE | The entire configurator tool |

This is a single-file project. All HTML, CSS, and JS live in one file.

---

## Task 1: Scaffold + Core Architecture + Step 1 (Cluster Basics)

**Files:**
- Create: `tools/aks-configurator.html`

This is the foundation task. It establishes ALL architectural patterns.

- [ ] **Step 1: Create the complete HTML file with all architecture code**

Create `tools/aks-configurator.html` containing:
1. HTML skeleton with Tailwind CDN, header with version banner, wizard sidebar + main content layout, bottom navigation (prev/next/save/load/reset buttons), environment change banner, save status indicator
2. `STEPS` array (7 step labels), `VM_SIZES` array (D2s-D16s, E4s-E16s with vCPU/RAM), `REGIONS` array, `K8S_VERSIONS` array, `UPGRADE_CHANNELS` array
3. `ENV_DEFAULTS` object -- per-environment defaults for all fields (dev/acc/prod) matching the existing `.bicepparam` files
4. `ECOSYSTEM_TOOLS` object -- all 15 tools across 5 categories with: id, label, description, deployType badge, requirements function, guidance data (helm repo/chart/namespace/commands/verify)
5. State management: `initState(env)`, `getVal(key)`, `setVal(key, value)`, `setValNoRender(key, value)`, `switchEnvironment(newEnv)` with edit tracking, `getFlatState()`, `getVmVcpu(vmSize)`
6. Validation framework: `validateStep(stepNum)` returning `{errors, warnings, infos}` — implement only Step 1 validation in this task. Each subsequent task adds its own step's validation. `validateAllSteps()` aggregator calls validateStep for each step (returns empty for unimplemented steps)
7. CIDR utilities: `parseCIDR()`, `cidrCapacity()`, `cidrRange()`, `isWithinCIDR()`, `cidrsOverlap()`, `isIPInCIDR()`, `suggestSubnets()`
8. Render system: `render()`, `renderStepNav()`, `renderCurrentStep()`, `updateNavButtons()`, `nextStep()` (with validation gating), `prevStep()`, `goToStep()`
9. UI helpers: `badge(level)` (params/guide/info pills), `deployBadge(type)`, `fieldRow(label, inputHtml, badgeLevel, helpText)`, `errorsHtml()`, `warningsHtml()`, `infoPanel()`, `escapeHtml()`
10. `renderStep1()` -- Cluster Basics with: customer name input with resource name preview (rg-/aks-/acr- names shown live), environment select triggering `switchEnvironment()`, region select, public/private toggle with implications text, K8s version select
11. Placeholder renderers for Steps 2-7 ("Coming in next build...")
12. `autoSave()` to localStorage, `autoRestore()`, `resetState()`, stub `saveConfig()`/`loadConfig()`
13. Initialization: try autoRestore, fallback to initState('dev'), call render()

**Key architectural patterns to follow:**
- All DOM updates go through `render()` -- no direct DOM manipulation outside render functions
- `setVal()` marks fields as `_edited: true`, calls `autoSave()` and `render()`
- `switchEnvironment()` only updates fields where `_edited === false`
- State shape: `{ fieldName: { value: any, _edited: boolean } }`
- Validation functions are pure: `(stepNum) => { errors: string[], warnings: string[], infos: string[] }`
- CIDR functions work on 32-bit unsigned integer representations of IPv4

**Reference for .bicepparam output format -- match exactly:**
```
using 'main.bicep'

param customerName = 'contoso'
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
  kubernetesVersion: '1.30'
  systemNodeCount: 1
  systemNodeVmSize: 'Standard_D2s_v5'
  userNodeCount: 1
  userNodeVmSize: 'Standard_D4s_v5'
  enablePrivateCluster: false
}

param adminGroupObjectIds = [
  '00000000-0000-0000-0000-000000000000'
]

param acrSku = 'Standard'
param keyVaultSku = 'standard'
param logRetentionDays = 30
```

- [ ] **Step 2: Open in browser and verify**

Open `tools/aks-configurator.html` in a browser.

Verify:
- Wizard shows 7 step labels in sidebar with step numbers
- Step 1 form is interactive: type customer name, see resource name preview update live
- Switch environment dev to prod: banner shows, untouched fields update
- Try to advance with empty customer name: validation error, blocked
- Public/Private toggle shows different implications text
- Steps 2-7 show placeholder text
- Previous/Next navigation works

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: scaffold AKS Configurator with core architecture and Step 1"
```

---

## Task 2: Step 2 -- Access & Governance

**Files:**
- Modify: `tools/aks-configurator.html` (replace `renderStep2` placeholder)

- [ ] **Step 1: Implement renderStep2() and helper functions**

Replace the placeholder `renderStep2()` with full implementation containing:
1. Admin Group Object IDs: multi-input with add/remove, GUID format validation
2. Required tags: CostCenter, Owner, Project text inputs
3. Advanced section (collapsible `<details>`): custom tags (dynamic key-value rows with add/remove), additional role assignments (dynamic rows: principalId, roleDefinitionId, principalType select)
4. Info panel about Azure RBAC, disabled local accounts, Workload Identity
5. Support-level badges on all fields

Add these helper functions: `updateArrayItem()`, `addArrayItem()`, `removeArrayItem()`, `updateCustomTag()`, `addCustomTag()`, `removeCustomTag()`, `updateRoleAssignment()`, `addRoleAssignment()`, `removeRoleAssignment()`

- [ ] **Step 2: Verify in browser**

Navigate to Step 2. Add/remove admin GUIDs, fill tags, add custom tags and role assignments. Try advancing with empty required fields -- blocked.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add Step 2 - Access & Governance"
```

---

## Task 3: Step 3 -- Networking

**Files:**
- Modify: `tools/aks-configurator.html` (replace `renderStep3` placeholder)

- [ ] **Step 1: Implement renderStep3() and helper functions**

Replace the placeholder with:
1. VNet address prefix input triggering `onVnetChange()` -- auto-suggests subnets for non-edited fields using `suggestSubnets()`
2. 3-column grid: AKS subnet, Services subnet, PE subnet inputs
3. Service CIDR and DNS service IP inputs with defaults
4. API server authorized IPs: multi-input, only visible when `enablePrivateCluster === false`
5. Info panel about hardcoded network settings (Azure CNI, Azure policy, LB outbound)
6. Subnet layout visual: colored horizontal bar chart showing address space allocation with legend (AKS=blue, Services=green, PE=purple, Free=gray) and IP counts
7. All CIDR validation inline (overlap, containment, capacity)
8. Subnet capacity warning: calculates `(maxNodes * maxPodsPerNode) + maxNodes` vs AKS subnet capacity

Add: `onVnetChange(value)`, `renderMultiInput(key, values, placeholder)`, `renderSubnetVisual(s)`

- [ ] **Step 2: Verify in browser**

Enter VNet `10.1.0.0/16` -- subnets auto-populate. Edit AKS subnet, change VNet -- AKS preserved, others update. Enter overlapping subnets -- error. Public cluster shows authorized IPs. Subnet visual renders.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add Step 3 - Networking with CIDR validation and subnet visual"
```

---

## Task 4: Step 4 -- Compute / Node Pools

**Files:**
- Modify: `tools/aks-configurator.html` (replace `renderStep4` placeholder)

- [ ] **Step 1: Implement renderStep4()**

Replace the placeholder with:
1. System Pool section (bordered card): VM size select showing vCPU/RAM, autoscaling toggle (enabled: min/max inputs, disabled: fixed count input)
2. User Pool section: same pattern
3. Shared Settings section: OS disk slider (30-1024, default 128), availability zones multi-select checkboxes (1/2/3) with `Guide only` badge
4. Advanced subsection (collapsible): upgrade channel select, max pods per node input -- both with `Guide only` badges
5. Validation: min >= 1, max >= min

Add: `toggleZone(zone)` function, reusable `nodePoolSection(prefix, label)` helper

- [ ] **Step 2: Verify in browser**

Toggle autoscaling on/off. Select VMs. Slider works. Change max nodes to large value, go to Step 3 -- subnet capacity warning.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add Step 4 - Compute / Node Pools"
```

---

## Task 5: Step 5 -- Azure Platform Services

**Files:**
- Modify: `tools/aks-configurator.html` (replace `renderStep5` placeholder)

- [ ] **Step 1: Implement renderStep5()**

Replace the placeholder with:
1. ACR card: enable/disable toggle button, SKU select (Basic/Standard/Premium) shown when enabled, info panel about Premium features
2. Key Vault card: enable/disable toggle, SKU select, info panel about RBAC/soft-delete/purge-protection
3. Monitoring card: enable/disable toggle, log retention slider (30-730), info panel about Container Insights
4. Cross-field warning: private cluster + non-Premium ACR
5. Info note when ACR enabled: "AcrPull role will be assigned to AKS managed identity"

- [ ] **Step 2: Verify in browser**

Toggle services on/off. Set private cluster + Standard ACR -- warning appears. Slider shows live value.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add Step 5 - Azure Platform Services"
```

---

## Task 6: Step 6 -- Ecosystem Tools

**Files:**
- Modify: `tools/aks-configurator.html` (replace `renderStep6` placeholder)

- [ ] **Step 1: Implement renderStep6() and helpers**

Replace the placeholder with:
1. Iterate `ECOSYSTEM_TOOLS` categories, render each as a section with category heading
2. Per tool: ON/OFF toggle button, tool label, `deployBadge(type)`, description, requirements check (calls tool.requirements with flat state), guidance preview (collapsible `<details>` showing Helm/az commands with resource names substituted)
3. Conflict warnings rendered from category `conflicts` arrays
4. `toggleEcoTool(toolId)` function
5. `renderToolGuidancePreview(tool, s)` function -- shows helm repo add/install or az commands, verify command, notes, "Starter commands" disclaimer

- [ ] **Step 2: Verify in browser**

Browse 5 categories. Toggle tools. Enable Istio with D2s_v5 -- warning. Enable Flux+ArgoCD -- conflict warning. Enable cert-manager without ingress -- requirement warning. Expand guidance preview.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add Step 6 - Ecosystem Tools with 15 tools across 5 categories"
```

---

## Task 7: Step 7 -- Review & Generate

**Files:**
- Modify: `tools/aks-configurator.html` (replace `renderStep7` placeholder)

- [ ] **Step 1: Implement renderStep7(), generators, and helpers**

Replace the placeholder with:
1. Architecture visual: `renderArchitectureVisual(s)` -- styled card showing resource group tree with VNet/subnets/AKS/pools/services/ecosystem tools, color-coded green (enabled) vs gray (disabled)
2. Validation panel: `validateAllSteps()` results grouped by severity (errors=red, warnings=yellow, success=green)
3. Security posture summary (collapsible): RBAC, local accounts, workload identity, OIDC, private cluster, private endpoints, network policy, key vault status
4. `.bicepparam` preview: `generateBicepParam(s)` output in dark code block with Copy and Download buttons
5. Deployment guide preview: `generateDeploymentGuide(s)` output in light code block with Copy and Download buttons

Add `generateBicepParam(s)` -- produces exact `.bicepparam` format matching reference files:
- `using 'main.bicep'` header
- Uses fixed template (ordered string concatenation), NOT dynamic object iteration
- All params with correct Bicep object syntax (curly braces, no quotes on keys, colon separator)
- `systemNodeCount` uses minCount when autoscaling, nodeCount when not
- `additionalRoleAssignments` only emitted if non-empty
- Only emits params that exist in `infra/main.bicep` (see Critical Rules above)
- Add `bicepString(value)` helper that escapes single quotes for Bicep syntax

Add `generateDeploymentGuide(s)` -- produces markdown with:
- Prerequisites, deploy command, get-credentials command
- Post-deploy sections for authorized IPs, availability zones, upgrade channel (if configured)
- Per-selected-ecosystem-tool sections with Helm/az commands, verify steps
- Validation checklist

Add helpers: `renderArchitectureVisual(s)`, `downloadFile(filename, content)`, `copyToClipboard(text)`, `escapeHtml(text)`

- [ ] **Step 2: Verify in browser**

Complete Steps 1-6, go to Step 7. Architecture visual renders. Validation shows remaining warnings. Download `.bicepparam` -- compare with `infra/main.prod.bicepparam`. Download guide -- verify Helm commands. Copy works.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add Step 7 - Review, code generation, and architecture visual"
```

---

## Task 8: Save/Load + Polish

**Files:**
- Modify: `tools/aks-configurator.html` (replace `saveConfig`/`loadConfig` stubs)

- [ ] **Step 1: Implement save/load and download all**

Replace stub functions with:
1. `saveConfig()` -- serializes `{ schemaVersion, toolVersion, exportedAt, currentStep, state }` as JSON, downloads as `aks-config-{customer}-{env}.json`
2. `loadConfig(event)` -- reads JSON file, checks schemaVersion compatibility (warns if mismatch), populates state, re-renders
3. `downloadAll()` -- downloads 3 files sequentially (.bicepparam, deployment-guide.md, README.md) with 500ms delays
4. Add "Download All" button to Step 7's output section

- [ ] **Step 2: Verify in browser**

Fill wizard, close tab, reopen -- state restored. Save config, start over, load config -- fields restored. Download All produces 3 files.

- [ ] **Step 3: Commit**

```bash
git add tools/aks-configurator.html
git commit -m "feat: add save/load config and download all"
```

---

## Verification Checklist

After all 8 tasks:

1. Open `tools/aks-configurator.html` in a browser
2. Walk through all 7 steps with prod config: contoso, prod, westeurope, private, K8s 1.30
3. Admin group: `00000000-0000-0000-0000-000000000000`, tags: IT/platform-team/aks-platform
4. Network defaults (10.3.0.0/16), Compute: D4s_v5 sys, D8s_v5 user, 3 nodes, autoscaling
5. ACR Premium, KV standard, Monitoring 365d
6. Ecosystem: kube-prometheus-stack, Istio, NGINX, cert-manager, Flux
7. Verify resource name preview, smart defaults, subnet capacity, conflict warnings
8. Download .bicepparam -- compare with `infra/main.prod.bicepparam`
9. Download deployment guide -- verify all tool commands
10. Save/load config JSON round-trip
11. localStorage persistence (close/reopen tab)
