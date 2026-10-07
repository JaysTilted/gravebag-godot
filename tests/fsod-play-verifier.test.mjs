import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
test('runtime acceptance verifier rejects stale, timed out, failed and nonrendered synthetic proofs', () => {
  const result = spawnSync('python3', ['-B', resolve(root, 'scripts/fsod_play/test_verify.py')], { encoding: 'utf8', timeout: 30000 });
  assert.ifError(result.error);
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 0, output);
  assert.match(output, /Ran 14 tests/);
  assert.match(output, /\bOK\b/);
});
