// SPDX-License-Identifier: AGPL-3.0-only
// Bounded, isolated-HOME test for FSoD entity edge polish + remote presentation
// smoothing. Runs the real Godot selftest headless; no network/game seats.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const scratch = mkdtempSync(join(tmpdir(), 'fsod-smoothing-'));
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

test('FSoD entity smoothing real Godot selftest passes', () => {
  try {
    run([godot, '--headless', '--path', root, '--import']);
    const selftest = run([godot, '--headless', '--path', root, '-s', 'src/client/fsod/entity_smoothing_selftest.gd'], /FSOD SMOOTHING PASS: \d+ checks, 0 failures/);
    console.log(selftest.trim().split('\n').at(-1));
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});

test('FSoD entity smoothing keeps scope and aesthetic', () => {
  const entity = readFileSync(join(root, 'src/client/fsod/entity_view.gd'), 'utf8');
  assert.match(entity, /func advance_presentation\(delta: float\)/, 'optional render-rate pass exists');
  assert.match(entity, /func display_position\(\)/, 'camera worker display getter exists');
  assert.match(entity, /antialiased/, 'vector decorations antialiased');
  assert.match(entity, /draw_set_transform\(_render_offset/, 'draw shifts origin only, never contact position');
  assert.match(entity, /position = _from\.lerp\(_to, clampf\(_elapsed \/ _duration/, 'baseline linear contact evolution kept');
  assert.doesNotMatch(entity, /CanvasItemMaterial|ShaderMaterial|TextureFilter/, 'no blanket blur/material/filter nodes');
  const project = readFileSync(join(root, 'project.godot'), 'utf8');
  assert.match(project, /default_texture_filter=0/, 'Nearest crisp pixel filter preserved');
  const world = readFileSync(join(root, 'src/client/fsod/world_view.gd'), 'utf8');
  assert.doesNotMatch(world, /advance_presentation/, 'world camera cadence untouched by this change');
});
