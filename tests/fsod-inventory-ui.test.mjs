// SPDX-License-Identifier: AGPL-3.0-only
// Stage only owned UI + full source metadata. No network, services, or main game import.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const establishedBinary = '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const godot = process.env.GODOT_BIN || (existsSync(establishedBinary) ? establishedBinary : 'godot');

test('FSoD inventory: real SceneTree authority, callbacks, complete layout and rendered frame', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'fsod-inventory-ui-'));
  const home = join(scratch, 'home');
  const project = join(scratch, 'project');
  const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, '.config'), XDG_CACHE_HOME: join(home, '.cache'), XDG_DATA_HOME: join(home, '.local/share') };
  try {
    mkdirSync(home);
    for (const path of ['src/client/fsod/inventory_panel.gd', 'src/client/fsod/item_icon.gd', 'src/client/fsod/item_tooltip.gd', 'src/client/fsod/inventory_ui_selftest.gd', 'src/data/fsod/items.json', 'src/data/fsod/objects.json']) {
      const destination = join(project, path);
      mkdirSync(resolve(destination, '..'), { recursive: true });
      copyFileSync(join(root, path), destination);
    }
    // v1 rollback fixture. The panel must ignore it and keep the frozen v2 sample.
    writeFileSync(join(project, 'src/client/fsod/ui_theme.gd'), "extends RefCounted\nstatic func tokens():\n\treturn {\"ink\": \"#171717\", \"slate\": \"#343434\"}\n");
    writeFileSync(join(project, 'project.godot'), `config_version=5
[application]
config/name="Inventory isolated acceptance"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
`);
    function run(argv, expected) {
      const result = spawnSync(argv[0], argv.slice(1), { cwd: project, env, encoding: 'utf8', timeout: 120000, maxBuffer: 4 * 1024 * 1024 });
      const output = `${result.stdout || ''}\n${result.stderr || ''}`;
      assert.ifError(result.error);
      assert.equal(result.status, 0, output);
      assert.doesNotMatch(output, /(?:SCRIPT ERROR|Parse Error|ERROR:|FAIL:)/i, output);
      assert.match(output, expected);
      return output;
    }
    const args = ['--path', project, '-s', 'src/client/fsod/inventory_ui_selftest.gd'];
    const selftest = run([godot, '--headless', ...args], /FSOD INVENTORY PASS: \d+ checks, 0 failures/);
    const frame = join(scratch, 'inventory-frame.png');
    run(['xvfb-run', '-a', godot, ...args, '--', `--capture=${frame}`], /FSOD INVENTORY RENDER PASS/);
    const png = readFileSync(frame);
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    assert.equal(png.readUInt32BE(16), 1280);
    assert.equal(png.readUInt32BE(20), 720);
    assert.ok(png.length > 10000, 'real frame must contain rendered inventory, not a marker');
    if (process.env.FSOD_INVENTORY_PROOF_DIR) {
      copyFileSync(frame, join(resolve(process.env.FSOD_INVENTORY_PROOF_DIR), 'inventory-frame.png'));
    }
    console.log(selftest.trim());
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
