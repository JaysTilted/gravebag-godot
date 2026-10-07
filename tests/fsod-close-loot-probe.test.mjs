// SPDX-License-Identifier: AGPL-3.0-only
// The acceptance loot driver may only tighten the shipped approach radius.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');

test('close loot probe extends the shipped bot and requests inside 0.55 tiles', () => {
  const close = readFileSync(join(root, 'src/game/fsod_close_loot_probe.gd'), 'utf8');
  const shipped = readFileSync(join(root, 'src/game/fsod_live_probe.gd'), 'utf8');
  assert.match(close, /extends "res:\/\/src\/game\/fsod_live_probe\.gd"/);
  assert.match(close, /nearest_distance >= 0\.55/);
  assert.doesNotMatch(close, /nearest_distance >= 1\.0/);
  assert.match(shipped, /nearest_distance >= 1\.0/);
  assert.match(close, /APPROACH bag=%d distance=%.2f/);
  assert.match(close, /WAIT bag=%d distance=%.2f/);
  assert.match(close, /player_stats\.get\(wire/);
});
