// SPDX-License-Identifier: AGPL-3.0-only
// Combat feedback overlay: isolated HOME, headless fixtures, xvfb frame sequence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, copyFileSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';

const root = resolve(import.meta.dirname, '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const scratch = mkdtempSync(join(tmpdir(), 'fsod-combat-feedback-'));
const home = join(scratch, 'home');
mkdirSync(home);
const env = {
  ...process.env,
  HOME: home,
  XDG_CONFIG_HOME: join(home, '.config'),
  XDG_CACHE_HOME: join(home, '.cache'),
  XDG_DATA_HOME: join(home, '.local/share'),
};

function run(argv, expected) {
  const result = spawnSync(argv[0], argv.slice(1), {
    cwd: root,
    env,
    encoding: 'utf8',
    timeout: 180000,
    maxBuffer: 8 * 1024 * 1024,
  });
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  assert.ifError(result.error);
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /(?:SCRIPT ERROR|Parse Error|ERROR:|FAIL:)/i, output);
  if (expected) assert.match(output, expected);
  return output;
}

test('combat feedback overlay: source contract, fixtures, and rendered fade sequence', () => {
  try {
    const source = readFileSync(join(root, 'src/client/fsod/combat_feedback.gd'), 'utf8');
    assert.match(source, /func initialize\(/);
    assert.match(source, /func clear\(/);
    assert.match(source, /func refresh\(/);
    assert.match(source, /func ui_diagnostics\(/);
    assert.match(source, /gravebag\.ui_diagnostics\.v1/);
    assert.match(source, /display_position/);
    assert.match(source, /MOUSE_FILTER_IGNORE/);
    assert.match(source, /#fc3436/);
    assert.match(source, /#ff3b4a/);
    assert.match(source, /#efcf7a/);
    assert.doesNotMatch(source, /shoot_requested|move_requested|send_fields|advance_visuals|predict_motion|projectile_hit|set_theme_tokens|ground_damage_requested/);
    run([godot, '--headless', '--path', root, '--import']);
    const logic = run(
      [godot, '--headless', '--path', root, '-s', 'src/client/fsod/combat_feedback_selftest.gd'],
      /FSOD COMBAT FEEDBACK PASS: \d+ checks, 0 failures/,
    );
    console.log(logic.trim().split('\n').slice(-2).join('\n'));
    const frames = join(scratch, 'frames');
    mkdirSync(frames);
    const rendering = run(
      ['xvfb-run', '-a', godot, '--path', root, '-s', 'src/client/fsod/combat_feedback_selftest.gd', '--', `--capture-dir=${frames}`],
      /FSOD COMBAT FEEDBACK FRAME: 1280x720/,
    );
    const names = ['combat-feedback-frame-0.png', 'combat-feedback-frame-1.png', 'combat-feedback-frame-2.png', 'combat-feedback-frame-3.png'];
    const hashes = names.map((name) => {
      const path = join(frames, name);
      assert.ok(existsSync(path), `${name} must exist`);
      const png = readFileSync(path);
      assert.equal(png.subarray(1, 4).toString(), 'PNG');
      assert.equal(png.readUInt32BE(16), 1280);
      assert.equal(png.readUInt32BE(20), 720);
      assert.ok(png.length > 8000, `${name} must be a real viewport frame`);
      return createHash('sha256').update(png).digest('hex');
    });
    assert.notEqual(hashes[0], hashes[3], 'fade sequence must change pixels');
    assert.match(rendering, /alpha=1\.000/);
    assert.match(rendering, /red=true/);
    const motionPath = join(frames, 'combat-feedback-motion.json');
    assert.ok(existsSync(motionPath), 'motion log must exist');
    const motion = JSON.parse(readFileSync(motionPath, 'utf8'));
    assert.equal(motion.schema, 'gravebag.ui_diagnostics.v1');
    assert.equal(motion.frames.length, 4);
    assert.equal(motion.frames[0].diagnostics.schema, 'gravebag.ui_diagnostics.v1');
    assert.deepEqual(motion.frames[0].diagnostics.supported_actions, []);
    assert.equal(motion.frames[0].diagnostics.focus.traps_gameplay, false);
    assert.ok(motion.frames[0].alpha > motion.frames[2].alpha, 'logged alpha must fall');
    assert.equal(JSON.stringify(motion).includes('"fps"'), false);
    if (process.env.FSOD_PROOF_DIR) {
      const proof = resolve(process.env.FSOD_PROOF_DIR);
      mkdirSync(proof, { recursive: true });
      for (const name of readdirSync(frames)) {
        copyFileSync(join(frames, name), join(proof, name));
      }
    }
    console.log(rendering.trim().split('\n').filter((line) => line.includes('FSOD COMBAT FEEDBACK FRAME')).join('\n'));
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
