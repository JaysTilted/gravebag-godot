import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
test('playable entry shows New character after death and Reconnect after offline/failed', () => {
  const result = spawnSync(godot, ['--headless', '--path', root, '--quit-after', '1', '-s', 'res://src/game/fsod_entry_selftest.gd'], { encoding: 'utf8', timeout: 30000 });
  assert.ifError(result.error);
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /SCRIPT ERROR|Parse Error|Assertion failed/i);
  assert.match(output, /FSOD ENTRY SELFTEST PASS/);
  // Recovery paths must never log auth material; dummy GUID/Password stay in-process only.
  assert.doesNotMatch(output, /GUID|Password|configure_login/i);
});
