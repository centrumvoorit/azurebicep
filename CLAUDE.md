# CLAUDE.md

Project memory loaded into every Claude Code session opened in this repo.

## What this repo is

Enterprise AKS deployment as two parallel code paths that ship the same Well-Architected-baseline Bicep:

1. **`infra/`** — reference deployment. `main.bicep` (subscription-scope) + one `main.<env>.bicepparam` per environment (dev/acc/prod) + `modules/**`. Consumers clone, set params, run `az deployment sub create`.
2. **`tools/aks-configurator.html`** — single-file browser wizard that generates the same package as `infra/` based on UI inputs. Has its own CI that exercises generate-then-build-then-PSRule on every PR.

The two paths are kept in sync by CI — any drift between `infra/modules/**` and the configurator's embedded `BICEP_TEMPLATES` will be caught.

## Hard rules

- **PSRule on `validate.yml` is blocking, not advisory.** If a finding surfaces, fix the underlying Bicep rather than flipping `continue-on-error: true`. The previous "advisory" flag was a temporary workaround while `infra/` lagged behind the configurator; that gap is closed (commit `2f82045`).
- **Admin group placeholder `'00000000-0000-0000-0000-000000000000'`** in every `main.*.bicepparam` is intentional. Combined with `disableLocalAccounts: true` on the cluster it causes a silent lockout — the comment above it is the guardrail. Do not "helpfully" replace it with a real GUID; deployers must do that.
- **Do not re-add Azure-auth-dependent workflows** (`deploy.yml`, `deploy-environment.yml`, `publish-modules.yml`, or the `what-if` matrix on `validate.yml`) unless the owner has explicitly confirmed that (a) a tenant admin has created an Entra app registration with federated credentials for this repo, and (b) `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` are set as GitHub secrets. Current constraint: no Entra admin access → zero secrets set → those workflows can't run. Restoration source: `git log -- .github/workflows/`.
- **AKS cluster network profile, outbound type, osSKU, and osDiskType are create-time.** Any change to `networkPluginMode` / `networkDataplane` / `networkPolicy` / `outboundType` / `osSKU` / `osDiskType` breaks existing clusters — requires blue/green replace. Document and escalate before touching.

## Conventions

- **Language:** README + inline comments in `.bicepparam` are in Dutch; Bicep code comments and commit messages are in English. Keep that split when editing.
- **Types first:** any new AKS config knob must land as a field in `types.bicep → aksConfigType` before it's referenced anywhere else. Untyped `object` params are a code smell here.
- **Feature flags:** optional building blocks gate on `features.deployAcr` / `deployKeyVault` / `deployMonitoring`. If adding a new resource family, add a flag rather than making it unconditional.
- **Customer name:** stays `'contoso'` in the reference repo. The configurator's test fixture uses `'citest'`. PSRule suppressions list both prefixes (see `.ps-rule/ps-rule.yaml`).
- **API versions:** AKS is on `2025-10-01` (2026-01-01 not yet available in all regions). Network types on `2025-05-01`. ACR on `2025-11-01`. DCR + DCR association on `2024-03-11`. `diagnosticSettings@2021-05-01-preview` is kept with `#disable-next-line use-recent-api-versions` because the only stable alternative (`2016-09-01`) predates `categoryGroup: 'allLogs'`.

## CI map

| Workflow | Triggers on | What it does |
|---|---|---|
| `.github/workflows/validate.yml` | PRs touching `infra/**` or `bicepconfig.json` | Bicep build + PSRule (blocking) + Checkov (soft-fail) + comment scan results |
| `.github/workflows/configurator-test.yml` | PRs touching `tools/aks-configurator.html` or `tools/test/**` | JS syntax check + jsdom-based generate-package + `az bicep build` on dev/acc/prod + PSRule on each generated package |

Both are fully offline. No Azure auth. Expect green on a clean PR.

## Where the diagnostic skill lives

For any AKS + Bicep review question, trigger the `azure-aks-bicep-expert` skill (installed at `~/.claude/skills/azure-aks-bicep-expert/`). It's report-only — does not edit files unless asked. Use it before proposing Bicep changes; the findings format is what review PRs in this repo use.

## Recent history worth knowing

- **PR #2** (`2e2ad67`): configurator Batches A+B+C landed; emitted Bicep now matches the baseline.
- **PR #3** (`9454809`): infra/ partial fixes (ACR/KV uniqueString, K8s 1.35, autoscaler kebab-case, NSG outbound deny, ACR policies, Log Analytics replication, resourceGroups API bump, `infra/bicepconfig.json`). Also deleted Azure-auth workflows.
- **PR #4** (`2f82045`): full port of the configurator's hardening into `infra/`. PSRule flipped back to blocking.

See `git log` for detail. Anything referenced above predates this file and the exact commit SHAs are the source of truth.
