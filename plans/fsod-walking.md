# FSoD walking stutter — real cause, repro, fix (fix/fsod-walking)

## 1 hypothesis at a time (systematic debugging record)

- H1: NEW_TICK rebases prediction to the delayed auth snapshot, discarding
  unacked MOVE input each 100ms (world_view `apply_tick`: `_prediction =
  auth`; display follower `lerp(... delta*20)`). Local avatars bypass the
  follower so the displayed player and camera target pop. GOTO works because
  it is a one-off snap, not a rebase every tick.
- Baseline real-Godot fixture BEFORE fix (walking_selftest held RIGHT 1.0s
  @60Hz, 100ms delayed+quantized server echoes, 20Hz MOVE batching):
  `rewinds=1 rewind_total=0.400 backward_steps=2 total_disp=3.444 moves=20`.
  Motion check failures 5/16. H1 CONFIRMED by the quoted fixture; no H2
  needed (max 3 hypotheses allowed, stayed at 1). Baseline path shows the
  100ms sawtooth: prediction chopped to the one-tick-behind echo, display
  stepped backward twice, total distance 0.49 tiles short of speed*time
  (speed pause).
- GOTO working path vs NEW_TICK broken path: bare `world_view.apply_tick`
  tick_id>=0 landed on old MOVE echoes mid-path every 100ms (rewind),
  while tick_id -1 / tick_time 0 lands far away once (correct hard snap).
  Same code identity check, two different causal behaviors: rebase-always
  vs reconcile-against-unacked-input. The fix preserves GOTO snapping
  while NEW_TICK only snaps on genuine corrections.

## Root cause (exact)

`world_view.apply_tick` set `_prediction = auth` on every NEW_TICK for the
local player, before the session even sent the next MOVE batch; the semantic
follower (`lerp(_prediction*px, delta*20)`) in `predict_motion` then amplified
the step into a visible pop, while `entity_view.apply_status` rewound the
local baseline contact track onto the stale echo. 20Hz MOVE cadence and
collision sampling were unchanged (moves=20 both runs) — purely the
display/rebase path.

## Fix (integration tree, after scout review of a5a3c24)

- `src/client/fsod/world_view.gd`: `_reconcile_prediction()` snaps on first
  spawn, hard GOTO, >4-tile teleport, condition bit 13 (including a 0.2 or
  0.6 tile freeze), and auth that is not a sent MOVE sample and not within
  0.20 of the current pose. A delayed echo matches sent MOVE samples in
  order (0.02 epsilon), not every physics sample within 0.35. An occupied
  cell alone does not rewind. Render follows the lead; contact does not.
- `src/client/fsod/entity_view.gd`: `present_prediction` moves only the
  render pose. Node.position stays on the server echo so PLAYERHIT sampling
  is unchanged. Hard snaps still land contact and render together.
- `src/game/fsod_session.gd`: MOVE-record trail clears only on our own GOTO.
  A foreign GOTO leaves the unsent local samples.
- NEW `src/client/fsod/walking_selftest.gd` (+uid): deterministic held-WASD
  fixture (delayed+quantized server, ack timings) asserting zero rewinds,
  monotonic display, full speed*time, 20Hz cadence, release hold, GOTO snap,
  60/144Hz agreement, mouse mapping, NoWalk blocking, untouched HP.
- NEW `tests/fsod-walking.test.mjs`: real Godot run (imports, asserts PASS
  line) + scope guard (no follower, reconcile present, teleport clears
  stale MOVE).
- Baseline vs fixed (same fixture, quoted):
  - BEFORE: `rewinds=1 rewind_total=0.400 backward_steps=2 total_disp=3.444 moves=20`
  - AFTER: `rewinds=0 rewind_total=0.000 backward_steps=0 total_disp=3.933 moves=20` (expected 3.933), 16/16 PASS.
- GOTO still wins (hard snap verified), NoWalk walls still clip prediction,
  condition-speed is the only motion authority (no lowpass hiding big
  corrections), HP/server positions never rewritten by display.

## Checked

- `walking_selftest.gd` real Godot: reverse, perpendicular, 0.20 dead zone, 0.30 off-trail non-echo snap, 0.50 same rule
  threshold, paralysis 0.2 and 0.6, OccupySquare echo, aged 144Hz ring,
  echo-vs-prediction PLAYERHIT. Contact stays on the echo.
- `tests/fsod-walking.test.mjs` (isolated HOME): 2/2 pass.
- Existing: frontend, session, camera-smoothing, entity-smoothing suites
  re-run (entity-smoothing self-check text needed one comment reword;
  "snapped" tripped its source-text lint — logic untouched).
- Jay's live runtime never touched; no input driving, no restarts.

## Open / limits

- Local QA hold-to-walk feel (hand/gamepad curve) is verified only by the
  deterministic fixture; parent runs the separate QA client after merge.
- Portal/entry/current realm guide integration stays with the portal
  worker; no edits to fsod_entry.gd, guide files or shared selftests here.
