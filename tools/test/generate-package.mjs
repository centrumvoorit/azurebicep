#!/usr/bin/env node
// Loads aks-configurator.html in jsdom, picks an ENV_DEFAULTS preset, calls
// generateBicepParam(), extracts BICEP_TEMPLATES, and writes a complete
// deployment package to disk. CI then runs `az bicep build` on main.bicep
// inside that directory to prove the emitted templates compile end-to-end.

import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { JSDOM, VirtualConsole } from 'jsdom';

const { values } = parseArgs({
  options: {
    env: { type: 'string', short: 'e', default: 'dev' },
    out: { type: 'string', short: 'o', default: 'generated' },
    html: { type: 'string', default: '' },
  },
});

const env = values.env;
if (!['dev', 'acc', 'prod'].includes(env)) {
  console.error(`error: --env must be one of dev|acc|prod, got "${env}"`);
  process.exit(2);
}

const here = dirname(fileURLToPath(import.meta.url));
const htmlPath = values.html || resolve(here, '..', 'aks-configurator.html');
const outDir = resolve(values.out);

const html = readFileSync(htmlPath, 'utf8');

// Route jsdom's console to ours but swallow the noisy Tailwind CDN warning.
const virtualConsole = new VirtualConsole();
virtualConsole.on('error', (msg) => {
  if (typeof msg === 'string' && msg.includes('cdn.tailwindcss.com')) return;
  console.error('[jsdom]', msg);
});
virtualConsole.on('jsdomError', () => {}); // external CDN scripts are blocked in CI; ignore

const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  resources: undefined, // do not fetch external scripts (Tailwind, JSZip)
  virtualConsole,
  pretendToBeVisual: true,
});
const { window } = dom;

const hook = window.__TEST__;
if (!hook) {
  throw new Error('window.__TEST__ not found — configurator did not expose test hook');
}
if (typeof hook.generateBicepParam !== 'function') {
  throw new Error('__TEST__.generateBicepParam missing');
}
if (typeof hook.BICEP_TEMPLATES !== 'object' || hook.BICEP_TEMPLATES === null) {
  throw new Error('__TEST__.BICEP_TEMPLATES missing');
}
if (typeof hook.ENV_DEFAULTS !== 'object' || !hook.ENV_DEFAULTS[env]) {
  throw new Error(`__TEST__.ENV_DEFAULTS[${env}] missing`);
}

// Build a flat state object from the env preset plus required ID fields so
// validation doesn't trip on empty required inputs. Admin group uses a real
// GUID (not the placeholder the validator rejects).
const preset = hook.ENV_DEFAULTS[env];
const state = {
  ...preset,
  customerName: 'citest',
  adminGroupObjectIds: ['11111111-2222-3333-4444-555555555555'],
  customTags: [],
  additionalRoleAssignments: [],
  ecosystemTools: {},
};

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

// Write every embedded Bicep template.
for (const [relPath, content] of Object.entries(hook.BICEP_TEMPLATES)) {
  const full = join(outDir, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, content, 'utf8');
}

// Write the generated .bicepparam.
const bicepparam = hook.generateBicepParam(state);
writeFileSync(join(outDir, `main.${env}.bicepparam`), bicepparam, 'utf8');

// Sanity: list what was written.
const files = Object.keys(hook.BICEP_TEMPLATES).concat([`main.${env}.bicepparam`]);
console.log(`Wrote ${files.length} files to ${outDir}:`);
for (const f of files) console.log('  ' + f);

dom.window.close();
