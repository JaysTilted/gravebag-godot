// SPDX-License-Identifier: AGPL-3.0-only
// Guard only: the live backend proof is a separate isolated run, not this test.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');

test('QA orchestrator refuses Jay state and stays in this worktree', () => {
  const result = spawnSync('python3', ['scripts/fsod_qa/run_isolated.py', '--check-isolation'], { cwd: root, encoding: 'utf8', timeout: 20000 });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.ok, true);
  assert.equal(payload.jay_refused, true);
  assert.equal(payload.state, join(root, 'scripts/fsod_backend/.state'));
  assert.doesNotMatch(payload.state, /\/gravebag-godot\/scripts\/fsod_backend\/\.state$/);
  const driver = readFileSync(join(root, 'scripts/fsod_qa/live_driver.gd'), 'utf8');
  assert.doesNotMatch(driver, /interact_requested\.emit|send_fields\(|predict_motion\(/);
  assert.match(driver, /Input\.parse_input_event/);
  assert.match(driver, /RealmGuide/);
});
