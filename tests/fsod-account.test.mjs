// SPDX-License-Identifier: AGPL-3.0-only
// Verifier entrypoint: real Python stdlib fixtures, no live backend dependency.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = fileURLToPath(new URL('../', import.meta.url));
test('FSoD account parsing, loopback HTTP, safe CLI, public RSA and private profiles', { timeout: 60000 }, (t) => {
  const home = mkdtempSync(join(tmpdir(), 'fsod-account-home-'));
  try {
    const result = spawnSync('python3', ['-B', 'scripts/fsod_account/test_bridge.py'], {
      cwd: repo,
      env: { ...process.env, HOME: home, PYTHONDONTWRITEBYTECODE: '1' },
      encoding: 'utf8', timeout: 45000, maxBuffer: 1024 * 1024,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr, /Ran \d+ tests/);
    assert.match(result.stderr, /\nOK\s*$/);
    t.diagnostic(result.stderr.match(/Ran \d+ tests[^\n]*/)[0]);
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});
