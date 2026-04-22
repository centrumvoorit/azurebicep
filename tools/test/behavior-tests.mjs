#!/usr/bin/env node
// Behavior tests for the AKS configurator wizard logic.
// Runs state transitions in jsdom and verifies validation, generation,
// and cross-field interactions that have historically broken.

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { JSDOM, VirtualConsole } from 'jsdom';

const here = dirname(fileURLToPath(import.meta.url));
const htmlPath = resolve(here, '..', 'aks-configurator.html');
const html = readFileSync(htmlPath, 'utf8');

let passed = 0;
let failed = 0;
const failures = [];

function assert(condition, msg) {
  if (condition) {
    passed++;
  } else {
    failed++;
    failures.push(msg);
    console.error(`  FAIL: ${msg}`);
  }
}

function assertIncludes(arr, substring, msg) {
  const found = arr.some(m => m.includes(substring));
  assert(found, msg + ` (expected string containing "${substring}" in [${arr.map(s => s.substring(0, 60)).join(', ')}])`);
}

function assertNotIncludes(arr, substring, msg) {
  const found = arr.some(m => m.includes(substring));
  assert(!found, msg + ` (unexpected string containing "${substring}" found)`);
}

function createDom() {
  const vc = new VirtualConsole();
  vc.on('error', () => {});
  vc.on('jsdomError', () => {});
  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    resources: undefined,
    virtualConsole: vc,
    pretendToBeVisual: true,
  });
  return dom;
}

// ============================================================
// Test suite
// ============================================================

console.log('Behavior tests for aks-configurator.html\n');

// ----------------------------------------------------------
// 1. Private cluster clears authorizedIPRanges
// ----------------------------------------------------------
console.log('1. Private cluster clears authorizedIPRanges');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('enablePrivateCluster', false);
  T.setValNow('apiServerAuthorizedIPs', ['203.0.113.0/24', '198.51.100.0/24']);

  // Verify IPs are set
  const ipsBefore = T.getVal('apiServerAuthorizedIPs');
  assert(ipsBefore.length === 2, 'IPs should be set before toggle');

  // Toggle to private
  T.setValNow('enablePrivateCluster', true);
  const ipsAfter = T.getVal('apiServerAuthorizedIPs');
  assert(ipsAfter.length === 0, 'IPs should be cleared after switching to private');

  // Verify bicepparam also emits empty array for private
  const state = T.getFlatState();
  state.enablePrivateCluster = true;
  state.apiServerAuthorizedIPs = ['leftover-ip']; // simulate stale state
  const param = T.generateBicepParam(state);
  assert(param.includes("apiServerAuthorizedIPRanges: []"), 'bicepparam should force empty IPs for private cluster');

  dom.window.close();
}

// ----------------------------------------------------------
// 2. Public cluster preserves authorizedIPRanges
// ----------------------------------------------------------
console.log('2. Public cluster preserves authorizedIPRanges');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('enablePrivateCluster', false);
  T.setValNow('apiServerAuthorizedIPs', ['203.0.113.0/24']);

  // Toggle to public again (no-op)
  T.setValNow('enablePrivateCluster', false);
  const ips = T.getVal('apiServerAuthorizedIPs');
  assert(ips.length === 1, 'IPs should be preserved when staying public');
  assert(ips[0] === '203.0.113.0/24', 'IP value should be unchanged');

  dom.window.close();
}

// ----------------------------------------------------------
// 3. Environment switching applies defaults
// ----------------------------------------------------------
console.log('3. Environment switching applies defaults');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  assert(T.getVal('skuTier') === 'Free', 'Dev should default to Free tier');
  assert(T.getVal('enablePrivateCluster') === false, 'Dev should default to public');

  T.initState('prod');
  assert(T.getVal('skuTier') === 'Standard', 'Prod should default to Standard tier');
  assert(T.getVal('enablePrivateCluster') === true, 'Prod should default to private');

  const zones = T.getVal('availabilityZones');
  assert(Array.isArray(zones) && zones.length === 3, 'Prod should default to 3 availability zones');

  dom.window.close();
}

// ----------------------------------------------------------
// 4. SLA tier warning for acc/prod with Free
// ----------------------------------------------------------
console.log('4. SLA tier warning for acc/prod with Free');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('prod');
  T.setValNow('skuTier', 'Free');
  const v = T.validateStep(1);
  assertIncludes(v.warnings, 'Free tier has no SLA', 'Prod + Free should warn about SLA');

  T.initState('dev');
  T.setValNow('skuTier', 'Free');
  const vDev = T.validateStep(1);
  assertNotIncludes(vDev.warnings, 'Free tier', 'Dev + Free should NOT warn about SLA');

  dom.window.close();
}

// ----------------------------------------------------------
// 5. Availability zone warning is region-aware
// ----------------------------------------------------------
console.log('5. Availability zone warning is region-aware');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  // Prod + westeurope (has zones) + no zones selected
  T.initState('prod');
  T.setValNow('location', 'westeurope');
  T.setValNow('availabilityZones', []);
  const v1 = T.validateStep(1);
  assertIncludes(v1.warnings, 'availability zones', 'westeurope prod without zones should warn');

  // Prod + ukwest (no zones) + no zones selected
  T.initState('prod');
  T.setValNow('location', 'ukwest');
  T.setValNow('availabilityZones', []);
  const v2 = T.validateStep(1);
  assertNotIncludes(v2.warnings, 'availability zones', 'ukwest prod should NOT warn about zones');
  assertIncludes(v2.infos, 'does not support availability zones', 'ukwest prod should info about no zone support');

  dom.window.close();
}

// ----------------------------------------------------------
// 6. DNS service IP validation
// ----------------------------------------------------------
console.log('6. DNS service IP validation');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('serviceCidr', '10.0.0.0/16');

  // .0 is network address — error
  T.setValNow('dnsServiceIP', '10.0.0.0');
  const v1 = T.validateStep(3);
  assertIncludes(v1.errors, 'network address', 'DNS IP at .0 should error');

  // .1 is reserved — warning
  T.setValNow('dnsServiceIP', '10.0.0.1');
  const v2 = T.validateStep(3);
  assertIncludes(v2.warnings, '.1 of the Service CIDR', 'DNS IP at .1 should warn');

  // .10 is fine — no errors about DNS
  T.setValNow('dnsServiceIP', '10.0.0.10');
  const v3 = T.validateStep(3);
  const dnsErrors = v3.errors.filter(e => e.includes('DNS'));
  const dnsWarnings = v3.warnings.filter(w => w.includes('DNS'));
  assert(dnsErrors.length === 0, 'DNS IP .10 should have no DNS errors');
  assert(dnsWarnings.length === 0, 'DNS IP .10 should have no DNS warnings');

  dom.window.close();
}

// ----------------------------------------------------------
// 7. Public acc/prod without authorized IPs warns
// ----------------------------------------------------------
console.log('7. Public acc/prod without authorized IPs warns');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('prod');
  T.setValNow('enablePrivateCluster', false);
  T.setValNow('apiServerAuthorizedIPs', []);
  const v1 = T.validateStep(3);
  assertIncludes(v1.warnings, 'API server IP restrictions', 'Public prod with no IPs should warn');

  // Dev should not warn
  T.initState('dev');
  T.setValNow('enablePrivateCluster', false);
  T.setValNow('apiServerAuthorizedIPs', []);
  const v2 = T.validateStep(3);
  assertNotIncludes(v2.warnings, 'API server IP restrictions', 'Public dev with no IPs should NOT warn');

  dom.window.close();
}

// ----------------------------------------------------------
// 8. Whitespace-only tags are rejected
// ----------------------------------------------------------
console.log('8. Whitespace-only tags are rejected');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('tagCostCenter', '   ');
  T.setValNow('tagOwner', '');
  T.setValNow('tagProject', '\t');
  const v = T.validateStep(2);
  assertIncludes(v.errors, 'CostCenter is required', 'Whitespace CostCenter should error');
  assertIncludes(v.errors, 'Owner is required', 'Empty Owner should error');
  assertIncludes(v.errors, 'Project is required', 'Tab-only Project should error');

  dom.window.close();
}

// ----------------------------------------------------------
// 9. vCPU quota estimate is visible (infos populated)
// ----------------------------------------------------------
console.log('9. vCPU quota estimate is visible');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  const v = T.validateStep(4);
  assert(v.infos.length > 0, 'Step 4 should produce info messages');
  assertIncludes(v.infos, 'vCPU', 'Step 4 infos should contain vCPU estimate');
  assertIncludes(v.infos, 'az vm list-usage', 'Step 4 infos should contain quota check command');

  dom.window.close();
}

// ----------------------------------------------------------
// 10. Ecosystem tool conflicts
// ----------------------------------------------------------
console.log('10. Ecosystem tool conflicts');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('ecosystemTools', { istio: true, linkerd: true });
  const v = T.validateStep(6);
  assertIncludes(v.warnings, 'cannot be used together', 'Istio + Linkerd should warn conflict');

  // No conflict when only one is selected
  T.setValNow('ecosystemTools', { istio: true });
  const v2 = T.validateStep(6);
  assertNotIncludes(v2.warnings, 'cannot be used together', 'Single tool should not warn conflict');

  dom.window.close();
}

// ----------------------------------------------------------
// 11. Ephemeral OS disk enforcement
// ----------------------------------------------------------
console.log('11. Ephemeral OS disk enforcement');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  // Dsv5 does NOT support ephemeral
  assert(T.vmSupportsEphemeral('Standard_D4s_v5') === false, 'D4s_v5 should not support ephemeral');
  // Ddsv5 DOES support ephemeral
  assert(T.vmSupportsEphemeral('Standard_D4ds_v5') === true, 'D4ds_v5 should support ephemeral');

  dom.window.close();
}

// ----------------------------------------------------------
// 12. Placeholder admin GUID is rejected
// ----------------------------------------------------------
console.log('12. Placeholder admin GUID is rejected');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('adminGroupObjectIds', ['00000000-0000-0000-0000-000000000000']);
  const v = T.validateStep(2);
  assertIncludes(v.errors, 'placeholder', 'All-zeros GUID should be rejected as placeholder');

  dom.window.close();
}

// ----------------------------------------------------------
// 13. Deploy script has subscription verification
// ----------------------------------------------------------
console.log('13. Deploy script has subscription verification');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const script = T.generateDeployScript({
    customerName: 'testco',
    environment: 'dev',
    location: 'westeurope',
    deployAcr: true,
    deployKeyVault: true,
  });
  assert(script.includes('az account show'), 'Deploy script should verify subscription');
  assert(script.includes('Correct subscription'), 'Deploy script should ask for confirmation');
  assert(script.includes('az deployment sub create'), 'Deploy script should deploy');

  dom.window.close();
}

// ----------------------------------------------------------
// 14. Deploy script includes conditional providers
// ----------------------------------------------------------
console.log('14. Deploy script includes conditional providers');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  // With ACR + KV
  const s1 = T.generateDeployScript({
    customerName: 'test', environment: 'dev', location: 'westeurope',
    deployAcr: true, deployKeyVault: true,
  });
  assert(s1.includes('Microsoft.ContainerRegistry'), 'Script with ACR should register ContainerRegistry');
  assert(s1.includes('Microsoft.KeyVault'), 'Script with KV should register KeyVault');

  // Without ACR + KV
  const s2 = T.generateDeployScript({
    customerName: 'test', environment: 'dev', location: 'westeurope',
    deployAcr: false, deployKeyVault: false,
  });
  assert(!s2.includes('Microsoft.ContainerRegistry'), 'Script without ACR should not register ContainerRegistry');
  assert(!s2.includes('Microsoft.KeyVault'), 'Script without KV should not register KeyVault');

  dom.window.close();
}

// ----------------------------------------------------------
// 15. CIDR overlap detection
// ----------------------------------------------------------
console.log('15. CIDR overlap detection');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  assert(T.cidrsOverlap('10.1.0.0/20', '10.1.8.0/24') === true, 'Nested subnets should overlap');
  assert(T.cidrsOverlap('10.1.0.0/24', '10.2.0.0/24') === false, 'Separate subnets should not overlap');
  assert(T.isWithinCIDR('10.1.0.0/20', '10.1.0.0/16') === true, '/20 should be within /16');
  assert(T.isWithinCIDR('10.2.0.0/20', '10.1.0.0/16') === false, '10.2 not within 10.1/16');

  dom.window.close();
}

// ----------------------------------------------------------
// 16. validateAllSteps aggregates all steps
// ----------------------------------------------------------
console.log('16. validateAllSteps aggregates all steps');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  T.initState('dev');
  T.setValNow('customerName', ''); // force Step 1 error
  const all = T.validateAllSteps();
  assertIncludes(all.errors, 'Customer name is required', 'validateAllSteps should include Step 1 errors');
  assert(all.infos.length > 0, 'validateAllSteps should include infos from all steps');

  dom.window.close();
}

// ----------------------------------------------------------
// 17. manualOnly tools excluded from post-deploy automation
// ----------------------------------------------------------
console.log('17. manualOnly tools excluded from post-deploy automation');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  // AGIC and Flux are manualOnly — should not appear as executable commands
  const script = T.generatePostDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { agic: true, flux: true, nginx: true },
  });

  // nginx is automatable — should have its install commands
  assert(script.includes('ingress-nginx'), 'Post-deploy should install nginx');

  // AGIC and Flux should NOT be executed — only printed via echo
  const execLines = script.split('\n').filter(l => !l.startsWith('echo ') && !l.startsWith('#'));
  const execBlock = execLines.join('\n');
  assert(!execBlock.includes('ingress-appgw'), 'Post-deploy should NOT execute AGIC command');
  assert(!execBlock.includes('flux create'), 'Post-deploy should NOT execute Flux command');

  // But they should be mentioned as manual steps
  assert(script.includes('AGIC'), 'Post-deploy should mention AGIC as manual');
  assert(script.includes('Flux'), 'Post-deploy should mention Flux as manual');
  assert(script.includes('manual configuration'), 'Post-deploy should explain manual tools');

  dom.window.close();
}

// ----------------------------------------------------------
// 18. Post-deploy script empty when only Bicep-native tools selected
// ----------------------------------------------------------
console.log('18. Post-deploy script empty for Bicep-native tools only');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const script = T.generatePostDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { 'azure-monitor': true, 'azure-policy': true, 'csi-secret-store': true },
  });
  assert(script === '', 'Post-deploy should be empty when only Bicep-native tools selected');

  dom.window.close();
}

// ----------------------------------------------------------
// 19. Deploy script always uses --no-wait
// ----------------------------------------------------------
console.log('19. Deploy script always uses --no-wait');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  // With ecosystem tools
  const s1 = T.generateDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { nginx: true, 'kube-prometheus-stack': true },
  });
  assert(s1.includes('--no-wait'), 'Deploy script should use --no-wait even with ecosystem tools');
  assert(!s1.includes('get-credentials'), 'Deploy script should NOT get kubeconfig');

  // Without ecosystem tools
  const s2 = T.generateDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: {},
  });
  assert(s2.includes('--no-wait'), 'Deploy script should use --no-wait without ecosystem tools');

  dom.window.close();
}

// ----------------------------------------------------------
// 20. Linkerd is manualOnly
// ----------------------------------------------------------
console.log('20. Linkerd is manualOnly');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const script = T.generatePostDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { linkerd: true, nginx: true },
  });
  const execLines = script.split('\n').filter(l => !l.startsWith('echo ') && !l.startsWith('#'));
  const execBlock = execLines.join('\n');
  assert(!execBlock.includes('linkerd install'), 'Post-deploy should NOT execute linkerd install');
  assert(script.includes('Linkerd'), 'Post-deploy should mention Linkerd as manual');

  dom.window.close();
}

// ----------------------------------------------------------
// 21. Helm prerequisite check in post-deploy script
// ----------------------------------------------------------
console.log('21. Helm prerequisite check in post-deploy script');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  // nginx uses Helm
  const s1 = T.generatePostDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { nginx: true },
  });
  assert(s1.includes('command -v helm'), 'Post-deploy with Helm tools should check for helm');

  // keda is AKS add-on (no Helm)
  const s2 = T.generatePostDeployScript({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { keda: true },
  });
  assert(!s2.includes('command -v helm'), 'Post-deploy with only AKS add-ons should not check for helm');

  dom.window.close();
}

// ----------------------------------------------------------
// 22. Helm listed in deployment guide prerequisites when needed
// ----------------------------------------------------------
console.log('22. Helm in deployment guide prerequisites');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const g1 = T.generateDeploymentGuide({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { nginx: true },
  });
  assert(g1.includes('Helm 3 installed'), 'Guide should list Helm when Helm tools selected');

  const g2 = T.generateDeploymentGuide({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: {},
  });
  assert(!g2.includes('Helm'), 'Guide should NOT list Helm when no tools selected');

  dom.window.close();
}

// ----------------------------------------------------------
// 23. Bicep-native tools excluded from guide install commands
// ----------------------------------------------------------
console.log('23. Bicep-native tools excluded from guide install commands');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const guide = T.generateDeploymentGuide({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    deployMonitoring: true,
    ecosystemTools: { 'azure-monitor': true, 'azure-policy': true, 'csi-secret-store': true, nginx: true },
  });

  // Should NOT have fenced install commands for Bicep-native tools
  assert(!guide.includes('az aks enable-addons -g rg-testco-dev-westeurope -n aks-testco-dev --addons azure-policy'), 'Guide should NOT show azure-policy install command');
  assert(!guide.includes('az aks enable-addons -g rg-testco-dev-westeurope -n aks-testco-dev --addons azure-keyvault'), 'Guide should NOT show CSI install command');

  // Should have a "deployed via Bicep" note
  assert(guide.includes('Already deployed via Bicep'), 'Guide should have Bicep-native section');
  assert(guide.includes('Azure Monitor'), 'Guide should list Azure Monitor as Bicep-native');
  assert(guide.includes('Azure Policy'), 'Guide should list Azure Policy as Bicep-native');

  // nginx should still be shown
  assert(guide.includes('NGINX'), 'Guide should still show nginx install commands');

  dom.window.close();
}

// ----------------------------------------------------------
// 24. Linkerd-only does not add Helm prerequisite to guide
// ----------------------------------------------------------
console.log('24. Linkerd-only does not add Helm prerequisite to guide');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const guide = T.generateDeploymentGuide({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { linkerd: true },
  });
  assert(!guide.includes('Helm 3'), 'Guide should NOT list Helm for Linkerd-only (manualOnly tool)');
  dom.window.close();
}

// ----------------------------------------------------------
// 25. Manual-only tools adapt guide language
// ----------------------------------------------------------
console.log('25. Manual-only tools adapt guide language');
{
  const dom = createDom();
  const T = dom.window.__TEST__;

  const guide = T.generateDeploymentGuide({
    customerName: 'testco', environment: 'dev', location: 'westeurope',
    ecosystemTools: { linkerd: true },
  });
  assert(!guide.includes('installs each tool automatically'), 'Guide should NOT say "installs automatically" for manual-only');
  assert(!guide.includes('install automatable tools'), 'Guide should NOT say "install automatable tools" for manual-only');
  assert(guide.includes('starter commands'), 'Guide should mention starter commands for manual-only');
  dom.window.close();
}

// ----------------------------------------------------------
// Summary
// ----------------------------------------------------------
console.log('\n' + '='.repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failures.length > 0) {
  console.log('\nFailures:');
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
} else {
  console.log('All tests passed.');
}
