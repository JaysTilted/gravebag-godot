// SPDX-License-Identifier: AGPL-3.0-only
// Binding Godot UI target geometry, motion and input gates on the integrated source.
// Fixtures are not original-backend live proof or independent visual approval.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync, rmSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
// Preserved guide/inventory render regressions from the initial baseline gate.
import './fsod-realm-guide.test.mjs';
import './fsod-inventory-ui.test.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const STATES = ['nexus', 'realm', 'combat', 'inventory', 'loot', 'tooltip', 'offline', 'death'];
const LIVE = [
  'src/client/fsod/world_view.gd',
  'src/client/fsod/entity_view.gd',
  'src/client/fsod/inventory_panel.gd',
  'src/client/fsod/realm_guide.gd',
  'src/client/fsod/ui_acceptance_selftest.gd',
];
const OPTIONAL = [
  'src/client/fsod/ui_theme.gd',
  'src/client/fsod/account_chrome.gd',
  'src/client/fsod/combat_feedback.gd',
  'src/client/fsod/item_tooltip.gd',
];

function sha256(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

function pngSize(buf) {
  assert.equal(buf.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', 'png signature');
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

function copyRel(project, rel) {
  const from = join(root, rel);
  if (!existsSync(from)) return false;
  const dest = join(project, rel);
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(from, dest);
  return true;
}

function stage(project) {
  const copied = new Set();
  const queue = [...LIVE, ...OPTIONAL.filter((rel) => existsSync(join(root, rel)))];
  while (queue.length) {
    const rel = queue.pop();
    if (copied.has(rel) || !copyRel(project, rel)) continue;
    copied.add(rel);
    const text = readFileSync(join(project, rel), 'utf8');
    for (const match of text.matchAll(/res:\/\/([A-Za-z0-9_./-]+\.gd)/g)) {
      if (!copied.has(match[1])) queue.push(match[1]);
    }
  }
  writeFileSync(join(project, 'project.godot'), `; Isolated UI acceptance fixture. Not the live game.\nconfig_version=5\n\n[application]\nconfig/name="UI acceptance baseline"\nconfig/features=PackedStringArray("4.6", "GL Compatibility")\n\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\nwindow/stretch/mode="canvas_items"\nwindow/stretch/aspect="keep"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\ntextures/canvas_textures/default_texture_filter=0\n`);
  return [...copied];
}

test('integrated UI meets target geometry and input gates without claiming live parity', { timeout: 240000 }, () => {
  assert.equal(existsSync(godot), true, `godot binary missing: ${godot}`);
  const contract = JSON.parse(readFileSync(join(root, 'scripts/fsod_ui_proof/contract.json'), 'utf8'));
  assert.equal(contract.schema, 'gravebag.ui_diagnostics.v1');
  const scratch = mkdtempSync(join(tmpdir(), 'fsod-ui-proof-'));
  const home = join(scratch, 'home');
  const project = join(scratch, 'project');
  const capture = join(scratch, 'capture');
  mkdirSync(home, { recursive: true });
  mkdirSync(project, { recursive: true });
  mkdirSync(capture, { recursive: true });
  const env = {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_DATA_HOME: join(home, '.local/share'),
  };
  delete env.FSOD_PROFILE;
  try {
    const copied = stage(project);
    assert.equal(copied.includes('src/client/fsod/world_view.gd'), true);
    const head = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
    assert.match(head, /^[0-9a-f]{40}$/);
    const version = spawnSync(godot, ['--version'], { encoding: 'utf8', timeout: 30000 });
    assert.equal(version.status, 0, version.stderr || version.stdout);
    const runtimeVersion = String(version.stdout).trim();
    const sourceBefore = Object.fromEntries([...copied, 'src/game/fsod_entry.gd', 'tests/layout.test.mjs'].filter((rel) => existsSync(join(root, rel))).map((rel) => [rel, sha256(readFileSync(join(root, rel)))]));
    for (const [rel, hash] of Object.entries(sourceBefore)) {
      const committed = execFileSync('git', ['show', `${head}:${rel}`], { cwd: root, timeout: 30000, maxBuffer: 8 * 1024 * 1024 });
      assert.equal(sha256(committed), hash, `rendered source differs from declared HEAD: ${rel}`);
    }
    const reportPath = join(capture, 'geometry.json');
    const run = spawnSync('xvfb-run', ['-a', godot, '--path', project, '-s', 'res://src/client/fsod/ui_acceptance_selftest.gd', '--', `--capture-dir=${capture}`, `--report=${reportPath}`], {
      cwd: project,
      env,
      encoding: 'utf8',
      timeout: 180000,
      maxBuffer: 8 * 1024 * 1024,
    });
    const log = `${run.stdout || ''}\n${run.stderr || ''}`;
    if (run.status !== 0) {
      writeFileSync(join(capture, 'godot.log'), log);
      assert.fail(`godot baseline failed status=${run.status} signal=${run.signal}\n${log.slice(-4000)}`);
    }
    assert.match(log, /FSOD UI ACCEPTANCE TARGET: checks=\d+ failures=0 target_claimed=false/);
    assert.doesNotMatch(log, /SCRIPT ERROR|Parse Error|FSOD UI ACCEPTANCE FAIL/);
    for (const [rel, hash] of Object.entries(sourceBefore)) {
      assert.equal(sha256(readFileSync(join(root, rel))), hash, `${rel} was rewritten by the fixture`);
    }
    const geometry = JSON.parse(readFileSync(reportPath, 'utf8'));
    assert.equal(geometry.acceptance, 'target_geometry');
    assert.equal(geometry.target_quality_claimed, false);
    assert.equal(geometry.final_acceptance, false);
    assert.equal(geometry.reference_motion_matched, false);
    assert.equal(geometry.reference_comparison, 'not_applied');
    assert.equal(geometry.research_video_watched, false);
    assert.equal(geometry.slice_hud_used_as_acceptance, false);
    assert.equal(geometry.live_subject, 'world_view');
    assert.equal(geometry.backend_live, false);
    assert.equal(geometry.failures, 0);
    assert.equal(geometry.modules.world_view, 'present');
    assert.equal(geometry.modules.slice_hud, 'excluded');
    assert.ok(Array.isArray(geometry.unmet));
    for (const id of geometry.unmet) assert.equal(geometry.gates[id].met, false, id);
    // Target acceptance, not observed baseline: every measured gate must be met.
    assert.deepEqual(geometry.unmet, [], `unmet target gates: ${geometry.unmet.join(', ')}`);
    for (const id of ['rail_nexus', 'core_4_plus_8_nexus', 'core_4_plus_8_640x360', 'core_4_plus_8_800x600', 'core_4_plus_8_1920x1080',
      'essential_inner_2px_1280', 'potions_69_70_displayed', 'bars_readable_unclipped', 'six_stats_rows', 'minimap_readable',
      'space_passthrough_while_slot_focused', 'minimap_cache_skips_unchanged_physics', 'inventory_host_rect', 'theme_tokens',
      'chrome_ready_hides', 'chrome_actions_once', 'feedback_no_false_first_damage', 'feedback_map_reset_clean', 'identity_fame_nonoverlap', 'guide_charcoal_compact']) {
      assert.equal(geometry.gates[id]?.met, true, `target gate ${id}`);
    }
    assert.ok(geometry.gates.rail_nexus.measured.rect.x + geometry.gates.rail_nexus.measured.rect.w <= 1280.5, 'rail ends inside 1280');
    for (const fit of Object.values(geometry.gates.bars_readable_unclipped.measured.fits)) {
      assert.ok(fit.font_size >= 12 && fit.text_w <= fit.label_w && fit.line_height <= fit.label_h, `bar caption fits ${JSON.stringify(fit)}`);
    }
    assert.equal(typeof geometry.gates.rail_nexus.measured.rect.w, 'number');
    assert.equal(geometry.gates.rail_nexus.measured.width, geometry.gates.rail_nexus.measured.rect.w);
    assert.equal(geometry.gates.rail_offset_256.met, true);
    assert.equal(geometry.gates.missing_stat_emdash.met, true);
    assert.equal(geometry.gates.input_authority.met, true);
    assert.equal(geometry.gates.minimap_invalidates_on_tile_change.met, true);
    assert.equal(geometry.gates.render_rate_samples.met, true);
    assert.equal(geometry.gates.render_rate_samples.measured.sample_hz, 60);
    assert.equal(geometry.gates.letterbox_not_larger_hud.met, true);
    const frames = geometry.frames.filter((frame) => frame.file && frame.file.endsWith('.png'));
    const byFile = new Map(frames.map((frame) => [frame.file, frame]));
    for (const state of STATES) {
      const file = `1280x720-${state}.png`;
      assert.equal(byFile.has(file), true, file);
      const frame = byFile.get(file);
      assert.equal(frame.state, state);
      assert.equal(frame.logical_w, 1280);
      assert.equal(frame.logical_h, 720);
      assert.ok(String(frame.state_source).length > 12, file);
      if (state === 'combat') assert.match(frame.state_source, /projectile/);
      if (state === 'death' || state === 'offline') assert.match(frame.state_source, /session\.state/);
      if (state === 'tooltip') assert.match(frame.state_source, /tooltip_text/);
    }
    const manifestFrames = [];
    for (const file of readdirSync(capture).filter((name) => name.endsWith('.png'))) {
      const buf = readFileSync(join(capture, file));
      const size = pngSize(buf);
      const minBytes = file.startsWith('minimap-') ? 80 : 1500;
      assert.ok(buf.length > minBytes, `${file} is too small to be a render (${buf.length})`);
      if (byFile.has(file)) {
        assert.equal(size.w, byFile.get(file).png_w, file);
        assert.equal(size.h, byFile.get(file).png_h, file);
        if (!file.startsWith('letterbox')) {
          assert.equal(size.w, byFile.get(file).logical_w, `${file} pixel size is not the logical viewport`);
          assert.equal(size.h, byFile.get(file).logical_h);
        }
        assert.ok(byFile.get(file).sample_colors >= 4, file);
        assert.equal(byFile.get(file).transform.coordinate_space, 'viewport');
      }
      manifestFrames.push({ file, sha256: sha256(buf), bytes: buf.length, png_w: size.w, png_h: size.h });
    }
    const temporal = manifestFrames.filter((frame) => frame.file.startsWith('temporal-'));
    assert.equal(temporal.length, 4);
    assert.ok(new Set(temporal.map((frame) => frame.sha256)).size >= 2, 'temporal samples are not distinct renders');
    const before = manifestFrames.find((frame) => frame.file === 'minimap-before.png');
    const after = manifestFrames.find((frame) => frame.file === 'minimap-after.png');
    assert.notEqual(before.sha256, after.sha256);
    const letterbox = byFile.get('letterbox-1920x1080.png');
    assert.equal(letterbox.logical_w, 1280);
    assert.equal(letterbox.logical_h, 720);
    assert.ok(letterbox.transform);
    for (const size of ['800x600', '640x360', '1920x1080']) {
      for (const state of STATES) {
        const name = `${size}-${state}.png`;
        assert.equal(byFile.has(name), true, name);
        const frame = byFile.get(name);
        assert.ok(frame.diagnostics?.world?.bars?.hp, `${name} source diagnostics`);
        for (const region of frame.diagnostics.world.regions.filter(r => r.visible)) assert.equal(region.clipped, false, `${name} ${region.id}`);
        if (state === 'death' || state === 'offline') {
          assert.equal(frame.diagnostics.chrome.state, state === 'death' ? 'dead' : 'offline', `${name} real composed chrome state`);
          assert.deepEqual(frame.diagnostics.entry.actions, [state === 'death' ? 'new_character' : 'reconnect'], `${name} production Entry action`);
          assert.ok(frame.diagnostics.chrome.regions.some(r => r.visible && !r.clipped && r.focusable), `${name} actual recovery control`);
        }
      }
    }
    const manifest = {
      kind: 'gravebag.ui_review_manifest.v1',
      acceptance: 'target_geometry',
      fixture_composition: 'production Entry handlers; only startup/profile IO disabled',
      target_quality_claimed: false,
      final_acceptance: false,
      reference_motion_matched: false,
      reference_comparison: 'not_applied',
      head,
      runtime: { godot: runtimeVersion, sha256: sha256(readFileSync(godot)) },
      source_sha256: sourceBefore,
      frames: manifestFrames,
      geometry_sha256: sha256(readFileSync(reportPath)),
      unmet: geometry.unmet,
      modules: geometry.modules,
      diagnostics_contract: geometry.diagnostics.length ? 'partial' : 'absent',
      reason: geometry.reason,
    };
    const manifestPath = join(capture, 'review-manifest.json');
    writeFileSync(manifestPath, JSON.stringify(manifest));
    const parsed = JSON.parse(readFileSync(manifestPath, 'utf8'));
    assert.equal(parsed.head, head);
    assert.equal(parsed.target_quality_claimed, false);
    assert.equal(parsed.frames.length, manifestFrames.length);
    const proof = process.env.FSOD_UI_PROOF_DIR;
    if (proof) {
      mkdirSync(proof, { recursive: true });
      for (const name of ['review-manifest.json', 'geometry.json', ...manifestFrames.map((frame) => frame.file)]) {
        copyFileSync(join(capture, name), join(proof, name));
      }
    }
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
