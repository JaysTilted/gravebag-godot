import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// Source-fidelity adapter only: no server boot, DB/provider mutation or gameplay claim.
// Fixtures use the pinned references/fsod checkout, with the assigned read-only
// /home/jay/fsod-ref fallback when the parent has not attached the gitlink yet.
const root = fileURLToPath(new URL('../', import.meta.url));

test('entire pinned FSoD source, packet catalogs and golden fixture contracts', { timeout: 180_000 }, () => {
  const result = spawnSync('python3', ['-B', 'tests/fsod/test_source_fidelity.py'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 120_000,
    maxBuffer: 1024 * 1024,
  });
  assert.ifError(result.error);
  console.log(result.stdout);
  console.log(result.stderr);
  assert.equal(result.signal, null, 'Python fixture checks must finish before their deadline');
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /SOURCE FIDELITY PASS/);
});
