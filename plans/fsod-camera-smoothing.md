# FSoD camera/world rendering smoothing (display-only)

Date (UTC): 2026-10-07 · Branch: `polish/fsod-camera` · Worktree: `/tmp/wt-fsod-camera`
Scope: original-FSoD Godot client only. Owned files: `src/client/fsod/world_view.gd`,
`src/client/fsod/camera_smoothing_selftest.gd` (+uid), `tests/fsod-camera-smoothing.test.mjs`,
this plan. Explicitly NOT touched: `entity_view.gd`, `project.godot`, existing
`selftest.gd`/`render_fixture.gd`, session/entry, backend, accounts, `.state`.

## Problem (scout-muxh42390)

Jay: pixel-art client "feels jagged". Two confirmed sources: (1) camera hard-snaps
`_world.position` every physics frame (60 Hz) while the display refreshes faster —
every server correction steps the whole world; (2) fractional canvas scale +
Nearest filter shimmer (out of scope here; no `project.godot` edits allowed).

## Design: smooth the display, freeze the simulation

- Physics (`_physics_process`) keeps its exact cadence and order: `advance_visuals`
  (entity interp + projectile age + hit sampling), input/prediction, aim, held-fire,
  ground contact, MOVE batching. Hit sampling reads semantic Node positions, so it
  must NOT move to render rate — otherwise contact semantics change.
- Physics only *records* the desired framing (`_camera_target`); `_process` eases
  the visible `_world.position` toward it with framerate-independent exponential
  smoothing (`smooth_camera_step`, rate 14/s, clamped delta 0.25 s). No rounding of
  the camera — fractional offsets are preserved so the follow never reintroduces
  pixel judder.
- Camera target follows the *displayed* player center: the parallel entity worker's
  optional `display_position()` render pose when present, else the semantic
  `position` fallback (`has_method` guard — works with or without that interface).
  `advance_presentation(delta)` is called from `_process` the same optional way.
- Mouse aim + ability cursor map through the *displayed* transform
  (`screen_to_world_tiles`), measuring the angle from the displayed player center,
  so the cursor stays aligned with rendered pixels. Outbound packet trajectory
  origins still use `_prediction` (server-authored semantics, untouched).
- Hard snap (no slew) on: map load (`apply_map` invalidates), player identity
  change (`set_player_id`), and any authoritative jump > 4 tiles (`apply_update` /
  `apply_tick` discontinuity → snap to the authoritative landing + hold there until
  the render pose lands within 1 tile). Local prediction stays responsive: the pose
  reconciles via the unchanged `delta*20` prediction lerp at physics cadence.
- Decoration-only softening in the owned file: tile grid line now antialiased.
  Collision, trajectories, radii, damage: untouched.

## Coordination (parallel workers)

- Entity worker owns `entity_view.gd` (may add `advance_presentation` / render-pose
  interface). This change needs no coordination beyond the optional-method guards:
  camera degrades to the `position` fallback if the interface never lands.
- `advance_visuals` deliberately NOT moved to `_process` (parent-confirmed): hit
  requests would resample at render rate and change contact semantics.
- Entry worker owns session/entry — untouched here.

## Verification

- New deterministic Godot selftest (`camera_smoothing_selftest.gd`, 30 checks):
  framing math, spawn snap, sub-teleport ease (no snap), convergence, 60 Hz vs
  120 Hz time invariance (<1 px over 1 s), 30 Hz vs 120 Hz convergence, degenerate
  input guards, teleport snap + authoritative hold + release, map reset snap,
  displayed-transform mouse mapping, authority/stats/prediction/tiles/trajectory
  preservation, zero request emissions from presentation, fractional (unrounded)
  easing, pure-function step equality, semantic fallback.
- New `tests/fsod-camera-smoothing.test.mjs`: isolated-HOME `--import`, headless
  selftest, xvfb real-GL render capture (`camera-frame-0.png` mid-smoothing vs
  `camera-frame-1.png` converged; 1280x720, >10 KB, pixel-different).
- Existing `tests/fsod-frontend.test.mjs` re-run for regression (NOT modified).

## Limits

- Remote-entity interpolation stepping (entity worker's lane) and texture-filter
  shimmer (`project.godot`, forbidden here) are separate jaggedness sources.
- Headless selftest cannot drive real mouse/physics timing; live aim feel needs
  Jay's playtest after playable. Reopen only after playable per Jay.
