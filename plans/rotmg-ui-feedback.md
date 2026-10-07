# RotMG combat feedback — display-only overlay

Status: render lane. Host attaches. This lane does not edit entry, world, session, or theme.

Owner files:
- NEW `src/client/fsod/combat_feedback.gd` (+uid)
- NEW `src/client/fsod/combat_feedback_selftest.gd` (+uid)
- NEW `tests/fsod-combat-feedback.test.mjs`
- THIS PLAN `plans/rotmg-ui-feedback.md`

Forbidden: every existing production script, `project.godot`, private profiles, live windows, full CI.

## What is observed vs inferred

Observed (researcher stills, not watched motion): right-rail dock stays off the fight; enemy names are small and red when the server has a name; a tiny bar only when HP metadata exists; loot/death text is a thin line, not a modal; bullets stay crisp in the open center. No still showed hit-stop, shake, blur, or a measured floater timing. Those are omitted.

Inferred, and labeled as such: a small HP-delta number at the entity's displayed pose, rising and fading from render delta. Parent accepted that inference. It is not a video measurement.

`src/ui/hud.gd` is the wrong surface for this client. It is not read as the contract.

## Bind

`Control`, mouse ignore, focus none. No signals.

- `initialize()` idempotent. Installs CanvasLayer 80 if missing. Does not attach to entry.
- `refresh(session, frontend)` once per frame from the host. Readonly.
- `clear()` drops cues and baselines, keeps the node.
- `ui_diagnostics()` schema `gravebag.ui_diagnostics.v1`: viewport `{w,h}`, regions from `get_global_rect`, motion from actual `_process` delta and label alpha/position (no fps), `supported_actions: []`, `focus: {owner, traps_gameplay: false}`, state.

Theme: `ResourceLoader.exists("res://src/client/fsod/ui_theme.gd")` then static `tokens()`. Else the frozen fsod-ui-theme/2 map (charcoal `#333333`, slot `#515151`, slot_edge `#2a2a2a`, silver `#d4d4d4`, muted `#9a9a9a`, gold `#efcf7a`, hp `#fc3436`, mp `#648dff`, xp `#5b832b`, fame `#ff8a1a`, player `#ffe500`, enemy `#ff3b4a`, portal `#3d8bff`, void `#1a1a1a`; ink=void, slate=charcoal, steel=muted, paper=silver, danger=hp). No `set_theme_tokens`.

## Cues

HP text only for a verified integer stat-1 change on a player or enemy, and only at `display_position()` converted by the parent `Node2D.to_global`. No authoritative-tile screen guess. First snapshot, missing stat, non-integer stat, map change, player-id change, teleport over 4 tiles, death, offline, and any non-playing state do not queue a hit. Updates before the next `_process` coalesce to one net number. Identical snapshots do not repeat. Fade and rise are functions of summed delta, so step size does not change the result.

Status text only for named bits: paralysis (stat 29 bit 13) and NinjaSpeedy (stat 96 bit 15). The first time a condition word is seen is a baseline, not an edge from a fake 0. Level text only when stat 7 increases after a baseline. Enemy name and 22×3 bar only when the descriptor name and both HP stats exist. Labels are clamped inside the playfield (8px margin, rail excluded) and sit above the display origin so they do not cover the contact point. Cap 3 per entity, 12 total.

## Verify

`node --test tests/fsod-combat-feedback.test.mjs` with an isolated `HOME`. Headless fixtures plus one xvfb 1280×720 sequence. No live backend.
