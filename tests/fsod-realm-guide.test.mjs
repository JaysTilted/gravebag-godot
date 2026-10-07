// SPDX-License-Identifier: AGPL-3.0-only
// Realm guide overlay: real Godot selftest + real 1280x720 render + existing
// entry/frontend fixtures (walkingwriter collision check). Isolated HOME.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, copyFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const scratch = mkdtempSync(join(tmpdir(), 'fsod-realm-guide-'));
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

test('realm guide overlay: fixtures, render, and entry/frontend collision check', () => {
  try {
    run([godot, '--headless', '--path', root, '--import']);
    const guide = run([godot, '--headless', '--path', root, '-s', 'src/client/fsod/realm_guide_selftest.gd'], /FSOD REALM GUIDE PASS: \d+ checks, 0 failures/);
    console.log(guide.trim().split('\n').slice(-2).join('\n'));
    const frames = join(scratch, 'frames');
    mkdirSync(frames);
    const rendering = run(['xvfb-run', '-a', godot, '--path', root, '-s', 'src/client/fsod/realm_guide_selftest.gd', '--', `--capture-dir=${frames}`], /FSOD REALM GUIDE FRAME: 1280x720/);
    const frame = join(frames, 'realm-guide-frame-0.png');
    assert.ok(existsSync(frame), 'rendered realm guide frame must exist');
    const png = readFileSync(frame);
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    assert.equal(png.readUInt32BE(16), 1280, 'rendered frame width is the real 1280 viewport');
    assert.equal(png.readUInt32BE(20), 720, 'rendered frame height is the real 720 viewport');
    assert.ok(png.length > 10000, 'real rendered frame must not be a blank marker');
    assert.match(rendering, /FSOD REALM GUIDE REALM FRAME: 1280x720 map=NexusPortal\.Sprite explore_absent=true/);
    const realmFrame = join(frames, 'realm-guide-realm-frame-0.png');
    assert.ok(existsSync(realmFrame), 'rendered original-realm frame must exist');
    const realmPng = readFileSync(realmFrame);
    assert.equal(realmPng.subarray(1, 4).toString(), 'PNG');
    assert.equal(realmPng.readUInt32BE(16), 1280, 'original-realm frame width is the real 1280 viewport');
    assert.equal(realmPng.readUInt32BE(20), 720, 'original-realm frame height is the real 720 viewport');
    assert.ok(realmPng.length > 10000, 'original-realm frame must not be a blank marker');
    if (process.env.FSOD_PROOF_DIR) {
      const proof = resolve(process.env.FSOD_PROOF_DIR);
      copyFileSync(frame, join(proof, 'realm-guide-frame-0.png'));
      copyFileSync(realmFrame, join(proof, 'realm-guide-realm-frame-0.png'));
    }
    console.log(rendering.trim().split('\n').slice(-3).join('\n'));
    // Walkingwriter collision: existing entry + frontend fixtures still pass untouched.
    const entry = run([godot, '--headless', '--path', root, '--quit-after', '1', '-s', 'res://src/game/fsod_entry_selftest.gd'], /FSOD ENTRY SELFTEST PASS/);
    assert.doesNotMatch(entry, /GUID|Password|configure_login/i);
    run([godot, '--headless', '--path', root, '-s', 'src/client/fsod/selftest.gd'], /FSOD FRONTEND PASS: \d+ checks, 0 failures/);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
