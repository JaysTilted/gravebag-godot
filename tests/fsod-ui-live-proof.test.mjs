// SPDX-License-Identifier: AGPL-3.0-only
// Owned live-UI acceptance contract: fail-closed. Intermediate HEAD asserts
// prep readiness + final wiring presence; final live capture asserts only
// with FSOD_UI_LIVE_FINAL=1 on the parent frozen HEAD after frame approval.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const owned = [
  'scripts/fsod_ui_live.py',
  'src/game/fsod_ui_live_probe.gd',
  'src/game/fsod_ui_live_probe.gd.uid',
  'tests/fsod-ui-live-proof.test.mjs',
  'plans/fsod-ui-live-proof.md',
];

test('owned helpers exist and production entry/probes untouched by this seat', () => {
  for (const file of owned) {
    assert.equal(existsSync(join(root, file)), true, `missing owned helper ${file}`);
  }
  // This seat never edits existing UI files, primary/play, STATE, or master.
  const status = spawnSync('git', ['status', '--short'], { cwd: root, encoding: 'utf8' }).stdout ?? '';
  for (const line of status.split('\n')) {
    if (!line.trim()) continue;
    const file = line.slice(3).trim();
    if (owned.includes(file)) continue;
    assert.fail(`this seat must own only NEW helpers, found unrelated change: ${line}`);
  }
});

test('probe uses production entry + real input, genuine frame deltas, no fakes', () => {
  const probe = readFileSync(join(root, 'src/game/fsod_ui_live_probe.gd'), 'utf8');
  assert.match(probe, /preload\("res:\/\/src\/game\/fsod_entry\.gd"\)/);
  assert.match(probe, /Input\.parse_input_event/);
  assert.match(probe, /InputEventMouseButton/);
  assert.match(probe, /Time\.get_ticks_msec/);
  assert.match(probe, /frame-delta|frame_delta|avg_delta/);
  assert.match(probe, /frame-deltas\.json/);
  assert.match(probe, /ui-diagnostics\.jsonl/);
  assert.match(probe, /ui_diagnostics/);
  assert.match(probe, /get_texture\(\)\.get_image\(\)/);
  assert.match(probe, /FSOD UI LIVE PASS/);
  assert.match(probe, /new_character/);
  assert.match(probe, /reconnect/);
  assert.doesNotMatch(probe, /send_fields\(|predict_motion\(|interact_requested\.emit/);
  assert.doesNotMatch(probe, /1\/60/);
  const orch = readFileSync(join(root, 'scripts/fsod_ui_live.py'), 'utf8').toLowerCase();
  assert.match(orch, /fail-closed/);
  assert.match(orch, /ui_diagnostics/);
});

test('orchestrator wires the real final pipeline (4 probes, frames, provenance, cleanup)', () => {
  const orch = readFileSync(join(root, 'scripts/fsod_ui_live.py'), 'utf8');
  assert.match(orch, /os\.getuid\(\) == 1000/);
  assert.match(orch, /xvfb-run/);
  assert.match(orch, /LP_NUM_THREADS/);
  assert.match(orch, /run_isolated/);
  assert.match(orch, /verify\.py/);
  assert.match(orch, /--fsod-bot-realm/);
  assert.match(orch, /--fsod-bot-injury/);
  assert.match(orch, /--fsod-bot-loot/);
  assert.match(orch, /--fsod-bot-death-cycle/);
  assert.match(orch, /runtime_hashes/);
  assert.match(orch, /netns/);
  assert.match(orch, /bootstrap_account/);
  assert.match(orch, /"stop"/);
  assert.match(orch, /1280, 720/);
  assert.match(orch, /640, 360/);
});

test('orchestrator prep is fail-closed and pending final freeze without gate', () => {
  const result = spawnSync('python3', ['scripts/fsod_ui_live.py', '--check-prep'], { cwd: root, encoding: 'utf8', timeout: 20000 });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.ok, true);
  assert.equal(payload.problems.length, 0);
  assert.equal(payload.final_capture, 'pending-parent-frozen-head-and-frame-approval');
  assert.equal(payload.backend_pin, '6fd20aad4a7905b13f25389c68368a942a2b68cb');
  assert.equal(payload.uid, 1000);
});

test('final live capture refuses without explicit final gate', () => {
  const env = { ...process.env };
  delete env.FSOD_UI_LIVE_FINAL;
  const result = spawnSync('python3', ['scripts/fsod_ui_live.py', '--run-final'], { cwd: root, encoding: 'utf8', timeout: 20000, env });
  assert.notEqual(result.status, 0);
  assert.match((result.stderr || result.stdout).toLowerCase(), /refusing live capture/);
});
