// SPDX-License-Identifier: AGPL-3.0-only
// Bounded, isolated-HOME adapter for real Godot walking-stutter tests.
// No network/game seats. Proves the NEW_TICK reconcile: steady held motion
// with delayed server snapshots, release hold, GOTO snap, FPS agreement,
// mouse mapping and authority preservation.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const scratch = mkdtempSync(join(tmpdir(), 'fsod-walking-'));
const home = join(scratch, 'home');
mkdirSync(home);
const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, '.config'), XDG_CACHE_HOME: join(home, '.cache'), XDG_DATA_HOME: join(home, '.local/share') };

function run(argv, expected) {
  const result = spawnSync(argv[0], argv.slice(1), { cwd: root, env, encoding: 'utf8', timeout: 120000, maxBuffer: 4 * 1024 * 1024 });
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  assert.ifError(result.error);
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /(?:SCRIPT ERROR|Parse Error|ERROR:|FAIL:)/i, output);
  if (expected) assert.match(output, expected);
  return output;
}

test('FSoD walking stutter real Godot selftest passes', () => {
  try {
    run([godot, '--headless', '--path', root, '--import']);
    const selftest = run([godot, '--headless', '--path', root, '-s', 'src/client/fsod/walking_selftest.gd'], /FSOD WALKING PASS: \d+ checks, 0 failures/);
    console.log(selftest.trim().split('\n').filter((l) => l.includes('WALKING')).join('\n'));
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});

test('FSoD walking fix keeps scope: prediction/display only', () => {
  const world = readFileSync(join(root, 'src/client/fsod/world_view.gd'), 'utf8');
  assert.match(world, /func _reconcile_prediction\(/, 'tick reconciles against unacked input instead of discarding it');
  assert.match(world, /func predicted_position\(\)/, 'prediction accessor present');
  assert.match(world, /player\.present_prediction\(_prediction\)/, 'render pose follows prediction without moving the contact box');
  assert.doesNotMatch(world, /player\.position\.lerp\(_prediction/, 'delta*20 semantic follower removed');
  assert.doesNotMatch(world, /if not _can_walk\(_prediction\)/, 'occupied cell alone must not rewind prediction');
  assert.doesNotMatch(world, /OFFPATH_SNAP_TILES|_off_sent_trail/, 'unused off-trail threshold must not return');
  const entity = readFileSync(join(root, 'src/client/fsod/entity_view.gd'), 'utf8');
  assert.match(entity, /Contact stays on the server echo/, 'projectile contact is not the unacked lead');
  const session = readFileSync(join(root, 'src/game/fsod_session.gd'), 'utf8');
  assert.match(session, /Only our own teleport invalidates the unsent local trail/, 'foreign GOTO does not clear the local MOVE trail');
});
