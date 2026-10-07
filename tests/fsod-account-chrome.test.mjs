// SPDX-License-Identifier: AGPL-3.0-only
// Account chrome: isolated Godot selftest + real frames. No network or main-scene import.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const establishedBinary = '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const godot = process.env.GODOT_BIN || (existsSync(establishedBinary) ? establishedBinary : 'godot');

test('FSoD account chrome: states, latch, diagnostics, and rendered frames', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'fsod-account-chrome-'));
  const home = join(scratch, 'home');
  const project = join(scratch, 'project');
  const env = {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_DATA_HOME: join(home, '.local/share'),
  };
  try {
    mkdirSync(home);
    for (const path of ['src/client/fsod/account_chrome.gd', 'src/client/fsod/account_chrome_selftest.gd']) {
      const destination = join(project, path);
      mkdirSync(resolve(destination, '..'), { recursive: true });
      copyFileSync(join(root, path), destination);
    }
    const source = readFileSync(join(root, 'src/client/fsod/account_chrome.gd'), 'utf8');
    assert.doesNotMatch(source, /FileAccess|password|login_file|fsod_session|fsod_entry|world_view|return_to_nexus/i);
    assert.match(source, /signal reconnect_requested/);
    assert.match(source, /signal new_character_requested/);
    assert.match(source, /character_name/);
    assert.match(source, /class_name/);
    writeFileSync(join(project, 'project.godot'), projectFile(1280, 720));
    const args = ['--path', project, '-s', 'src/client/fsod/account_chrome_selftest.gd'];
    const selftest = run(godot, ['--headless', ...args], /FSOD ACCOUNT CHROME PASS: \d+ checks, 0 failures/, env, project);
    console.log(selftest.trim().split('\n').slice(-1)[0]);
    const frames = join(scratch, 'frames');
    mkdirSync(frames);
    const rendering = run('xvfb-run', ['-a', godot, ...args, '--', `--capture-dir=${frames}`], /FSOD ACCOUNT CHROME FRAME: 1280x720 offline/, env, project);
    for (const [file, width, height] of [
      ['sequence-2.png', 1280, 720],
      ['state-dead.png', 1280, 720],
      ['state-busy.png', 1280, 720],
      ['state-ready.png', 1280, 720],
    ]) {
      const png = readFileSync(join(frames, file));
      assert.equal(png.subarray(1, 4).toString(), 'PNG');
      assert.equal(png.readUInt32BE(16), width, file);
      assert.equal(png.readUInt32BE(20), height, file);
      assert.ok(png.length > 8000, `${file} must be a rendered frame`);
    }
    assert.match(rendering, /FSOD ACCOUNT CHROME FRAME: \d+x\d+ small/);
    assert.match(rendering, /FSOD ACCOUNT CHROME LETTERBOX:/);
    assert.doesNotMatch(rendering, /GUID|Password|configure_login/i);
    const themeDir = join(project, 'src/client/fsod');
    writeFileSync(join(themeDir, 'ui_theme.gd'), `extends RefCounted
static func tokens() -> Dictionary:
	return {"void": "#112233", "charcoal": "#223344", "muted": "#8899aa", "silver": "#ddeeff", "gold": "#efcf7a", "hp": "#fc3436"}
`);
    const themed = run(godot, ['--headless', ...args], /FSOD ACCOUNT CHROME THEME: 112233/, env, project);
    assert.match(themed, /FSOD ACCOUNT CHROME PASS: \d+ checks, 0 failures/);
    if (process.env.FSOD_ACCOUNT_CHROME_PROOF_DIR) {
      const proof = resolve(process.env.FSOD_ACCOUNT_CHROME_PROOF_DIR);
      mkdirSync(proof, { recursive: true });
      for (const file of ['sequence-0.png', 'sequence-1.png', 'sequence-2.png', 'state-dead.png', 'state-busy.png', 'state-ready.png', 'state-small.png', 'state-letterbox.png']) {
        const from = join(frames, file);
        if (existsSync(from)) copyFileSync(from, join(proof, file));
      }
    }
    console.log(rendering.trim().split('\n').filter((line) => line.includes('FSOD ACCOUNT CHROME')).slice(-8).join('\n'));
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});

function projectFile(width, height) {
  return `config_version=5
[application]
config/name="Account chrome isolated"
[display]
window/size/viewport_width=${width}
window/size/viewport_height=${height}
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
[rendering]
renderer/rendering_method="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
`;
}

function run(bin, args, expected, env, cwd) {
  const result = spawnSync(bin, args, { cwd, env, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024 });
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  assert.ifError(result.error);
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /(?:SCRIPT ERROR|Parse Error|ERROR:|FAIL:)/i, output);
  assert.match(output, expected, output);
  return output;
}
