const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// Each run gets separate synthetic fixtures; the following batches share them.
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const output = path.resolve(process.env.E2E_OUTPUT_DIR || path.join(__dirname, '../../.test-results/note1-e2e', stamp));
fs.mkdirSync(output, { recursive: true });

const ids = (prefix, first, last) => Array.from({ length: last - first + 1 }, (_, offset) => `${prefix}${String(first + offset).padStart(2, '0')}`);
const batches = [
  { script: 'web-audit.cjs', result: 'web-results.json', ids: ids('W', 1, 16) },
  { script: 'supplemental.cjs', result: 'supplemental-results.json', ids: ids('W', 17, 27) },
  { script: 'boundaries.cjs', result: 'boundary-results.json', ids: ids('W', 28, 34) },
  { script: 'backup-deletion.cjs', result: 'deletion-results.json', ids: ids('W', 35, 37) },
  { script: 'fix-regressions.cjs', result: 'fix-regression-results.json', ids: ids('E', 1, 8) },
];
const checks = [];
const failures = [];

console.log(`NOTE1 E2E artifacts: ${output}`);
for (const batch of batches) {
  console.log(`\nRunning ${batch.script}`);
  const resultFile = path.join(output, batch.result);
  // An explicit output directory can be reused without stale result files.
  fs.rmSync(resultFile, { force: true });
  const child = spawnSync(process.execPath, [path.join(__dirname, batch.script)], {
    env: { ...process.env, E2E_OUTPUT_DIR: output },
    stdio: 'inherit',
    timeout: 240_000,
  });
  if (child.status !== 0 || child.error) failures.push({ script: batch.script, error: String(child.error || `Exit status ${child.status}`) });
  try {
    const data = JSON.parse(fs.readFileSync(resultFile, 'utf8'));
    const rows = Array.isArray(data) ? data : data.results;
    if (!Array.isArray(rows)) throw new Error('Result file has no checks array.');
    if (data.errors?.length) failures.push({ script: batch.script, browserErrors: data.errors });
    const expected = new Set(batch.ids);
    const found = new Set();
    for (const row of rows) {
      const id = row.id.split('-')[0];
      if (!expected.has(id) || found.has(id)) throw new Error(`Unexpected or duplicate check ${row.id}`);
      found.add(id);
      checks.push({ id: row.id, status: row.status, ...(row.error ? { error: row.error } : {}) });
    }
    for (const id of expected) if (!found.has(id)) checks.push({ id, status: 'missing' });
  } catch (error) {
    failures.push({ script: batch.script, error: String(error) });
    const collected = new Set(checks.map(row => row.id.split('-')[0]));
    for (const id of batch.ids) if (!collected.has(id)) checks.push({ id, status: 'missing' });
  }
}

const passed = checks.filter(row => row.status === 'passed').length;
const summary = { total: 45, passed, failed: checks.filter(row => row.status === 'failed').length, missing: checks.filter(row => row.status === 'missing').length, checks, failures };
fs.writeFileSync(path.join(output, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(`\nNOTE1 E2E: ${passed}/45 passed; ${summary.failed} failed; ${summary.missing} missing.`);
if (passed !== 45 || failures.length) process.exitCode = 1;
