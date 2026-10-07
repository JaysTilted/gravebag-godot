// SPDX-License-Identifier: AGPL-3.0-only
// Bounded, isolated-HOME adapter for real Godot camera-smoothing tests.
// No network/game seats. Proves display-only follow: deterministic easing,
// map/teleport snap, displayed-transform mouse mapping, untouched authority.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const scratch = mkdtempSync(join(tmpdir(), 'fsod-camera-'));
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

test('FSoD camera smoothing real Godot logic plus two rendered frames', () => {
  try {
    run([godot, '--headless', '--path', root, '--import']);
    const selftest = run([godot, '--headless', '--path', root, '-s', 'src/client/fsod/camera_smoothing_selftest.gd'], /FSOD CAMERA SMOOTHING PASS: \d+ checks, 0 failures/);
    const frames = join(scratch, 'frames');
    mkdirSync(frames);
    const rendering = run(['xvfb-run', '-a', godot, '--path', root, '-s', 'src/client/fsod/camera_smoothing_selftest.gd', '--', `--capture-dir=${frames}`], /FSOD CAMERA RENDER PASS/);
    const first = readFileSync(join(frames, 'camera-frame-0.png'));
    const second = readFileSync(join(frames, 'camera-frame-1.png'));
    for (const png of [first, second]) {
      assert.equal(png.subarray(1, 4).toString(), 'PNG');
      assert.equal(png.readUInt32BE(16), 1280);
      assert.equal(png.readUInt32BE(20), 720);
      assert.ok(png.length > 10000, 'real rendered frame must not be a blank marker');
    }
    assert.notDeepEqual(first, second, 'smoothed mid-flight frame must differ from converged frame');
    if (process.env.FSOD_PROOF_DIR) {
      const proof = resolve(process.env.FSOD_PROOF_DIR);
      for (const name of ['camera-frame-0.png', 'camera-frame-1.png']) copyFileSync(join(frames, name), join(proof, name));
    }
    console.log(selftest.trim());
    console.log(rendering.trim());
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
