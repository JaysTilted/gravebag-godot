# FSoD entity edge polish + remote presentation smoothing

Scope: original-FSoD Godot frontend only. Owns `src/client/fsod/entity_view.gd`,
`src/client/fsod/entity_smoothing_selftest.gd`, `tests/fsod-entity-smoothing.test.mjs`.
Does NOT touch `world_view.gd` (camera worker), `project.godot`, existing
`selftest.gd`, session/entry, or services. Recon basis: scout report
`/home/jay/.pi/agent/runs/scout-muxh42390/evidence/report.md`.

## Constraints kept

- Crisp pixel look Jay calls beautiful: `PIXEL=3.0`, 8x8 sprite frames, palette,
  silhouettes, `default_texture_filter=0` (Nearest), and `_visual_size` from
  descriptor `MinSize`/wire stat 2 (clamped 0.5–3.0) are all unchanged. No integer
  scale forcing, no blur node/filter.
- Gameplay/semantic positions and targets unchanged: `stats`,
  `authoritative_position`, and `Node2D.position` evolution are bit-identical to
  baseline (linear `_from.lerp(_to, elapsed/duration)`, reset every tick at
  physics 60 Hz). `world_view.gd:401+` hit sampling reads
  `target.position/TILE_PIXELS`, so easing `position` was explicitly rejected per
  parent instruction — contact interpolation is untouched.
- No `_process`/`_physics_process` added to the entity (would double-step under
  the world camera owner).

## What changed (all in `entity_view.gd`)

1. **Edge polish in `_draw` only.** Sprite texel `draw_rect`s are byte-identical.
   Portal arcs raised 16→48 and 8→24 segments with `antialiased=true`; portal disc,
   aim line/dot use `antialiased=true`; shadow keeps the exact 22x4 core footprint
   at source alpha with two 1px feather bands softening the hard rect edge.
2. **Render pose separated from contact pose.** New cosmetic-only
   `_render_pos`/`_render_target`/`_render_offset`/`_render_ready` plus constants
   `SNAP_PIXELS=256` (8 tiles), `INSTANT_DURATION=0.002`, `PRESENT_RATE=20`.
   `_draw` origin becomes `draw_set_transform(_render_offset, …)`; without the new
   pass the offset stays ZERO and visuals are baseline-identical.
3. **`advance_presentation(delta)` (optional).** Render-rate cosmetic pass for the
   camera worker to call from `_process`. Damps the render pose toward the latest
   authoritative target with `1 - exp(-RATE*delta)`, which converges identically
   under any FPS subdivision. Local player snaps tight (no input lag). Large
   jumps / GOTO zero-tick snap the render pose instantly (never slides).
   `display_position()` exposes the render pose if the camera worker wants it.

## Interface contract (camera worker / parent)

- Keep calling `advance_visual(physics_delta)` from `_physics_process` exactly as
  today. Optionally also call `advance_presentation(render_delta)` from `_process`.
- If `advance_presentation` is never called, nothing changes visually.
- A distinct render pose exists if needed: `display_position()`. Coordinate any
  camera use of it through the parent.

## Proof

- `src/client/fsod/entity_smoothing_selftest.gd`: real Godot headless checks for
  contact linearity (halfway/endpoint), render easing + monotonic convergence,
  FPS stability (10x20ms == 1x200ms), teleport/GOTO render snap with unchanged
  contact, sourceSize fidelity (incl. fractional 1.33), no authority mutation
  from predict/visual/presentation, local tightness, before/after frame bounds,
  no entity `_process`, and source-audit (AA present, no blur, no int snap).
- `tests/fsod-entity-smoothing.test.mjs`: isolated-HOME Godot import + selftest
  run, plus scope/aesthetic file assertions (Nearest kept, world camera untouched).
- Existing `src/client/fsod/selftest.gd` expectations (halfway `Vector2(160,96)`,
  endpoint `Vector2(192,96)`) still hold because contact evolution is untouched.
