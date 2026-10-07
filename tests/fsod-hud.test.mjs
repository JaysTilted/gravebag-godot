import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';

test('FSoD HUD theme, bars, and rail diagnostics', () => {
  const home = mkdtempSync(join(tmpdir(), 'fsod-hud-home-'));
  try {
    const result = spawnSync(godot, ['--headless', '--path', root, '--quit-after', '8', '-s', 'res://src/client/fsod/hud_selftest.gd'], {
      encoding: 'utf8',
      timeout: 90000,
      env: { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, '.config'), XDG_CACHE_HOME: join(home, '.cache'), XDG_DATA_HOME: join(home, '.local/share') },
    });
    assert.ifError(result.error);
    const output = `${result.stdout}\n${result.stderr}`;
    assert.equal(result.status, 0, output);
    assert.match(output, /FSOD HUD SELFTEST PASS/);
    assert.doesNotMatch(output, /SCRIPT ERROR|Parse Error|FSOD HUD FAIL/i);
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});
