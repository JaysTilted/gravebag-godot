# RotMG UI acceptance proof

Status: baseline harness. Not final visual-parity acceptance.
Owner files (this branch only):
- NEW `src/client/fsod/ui_acceptance_selftest.gd` (+uid) — isolated fixture runner.
- NEW `scripts/fsod_ui_proof/contract.json` — frozen diagnostics schema the runner consumes.
- NEW `tests/layout.test.mjs` — xvfb render, geometry, motion, input gate.
- THIS PLAN `plans/rotmg-ui-proof.md`.

Forbidden: `world_view.gd`, `entity_view.gd`, `fsod_session.gd`, `inventory_panel.gd`,
`fsod_entry.gd`, `project.godot`, `src/ui/hud.gd`, theme, and every other
production UI file. Those writers own the modules. This lane does not invent a
stand-in HUD or a `ui_diagnostics()` implementation on their files.

## What this proves
A real GL frame of the live `world_view` rail at logical 1280×720, 800×600,
640×360 and 1920×1080, plus a 1920×1080 window whose logical viewport stays
1280×720 (letterbox). States are Nexus, realm, combat (enemy + projectile, not
map name alone), inventory, loot, tooltip text, offline and death. Review
manifests carry runtime, frame and source hashes. `target_quality_claimed` stays
false until production modules, reference comparison and the binding gates are
all actually met.

## What this does not prove
RotMG parity, watched-video motion, original-backend live play, or a pass of
unchanged source. Slice `src/ui/hud.gd` is not the live client and is not
instantiated. Account chrome and combat feedback are exercised only when their
scripts exist in the tree.

## Verification
`node --test tests/layout.test.mjs` with isolated HOME and xvfb. No `verify.sh`,
no live window, no profile, no network. `tests/run_all.sh` launches this script
headless with no capture args; that path prints SKIP and is not render proof.

## Limits
Parent owns integration and CI. Geometry targets are measured from production
controls and `Theme.inventory_host_rect` when that method exists. Positions are
not hardcoded pass flags.
