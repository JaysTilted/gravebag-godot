import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
test('live probe compiles and refuses missing private profile without fake success', () => {
  const result = spawnSync(godot, ['--headless', '--path', root, '--quit-after', '2', '-s', 'res://src/game/fsod_live_probe.gd'], { encoding: 'utf8', timeout: 30000 });
  assert.ifError(result.error);
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 1, output);
  assert.doesNotMatch(output, /Parse Error|SCRIPT ERROR|Failed to load script/i);
  assert.match(output, /FSOD LIVE FAIL: profile missing/);
  assert.doesNotMatch(output, /FSOD LIVE PASS/);
});
test('real Godot bot input thresholds cannot idle before waypoint arrival', () => {
  const result = spawnSync(godot, ['--headless', '--path', root, '-s', 'res://src/game/fsod_probe_navigation_selftest.gd'], { encoding: 'utf8', timeout: 30000 });
  assert.ifError(result.error);
  const output = `${result.stdout}\n${result.stderr}`;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /Parse Error|SCRIPT ERROR|Assertion failed/i);
  assert.match(output, /FSOD PROBE NAVIGATION PASS: 1802 checks/);
});
