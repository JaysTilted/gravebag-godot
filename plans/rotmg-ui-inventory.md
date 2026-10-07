# RotMG inventory, loot, and tooltips

Status: active. Owner: inventory lane. Do not treat this as a live play proof.

## What was observed

Classic still `mmohuts-classic-2012-maxresdefault.jpg` (researcher-muyf6k0g6): dark charcoal rail, four equipment slots then eight inventory slots, flat lighter-gray wells, large pixel icons, no item-name captions. Exalt stills show dense icons with a tiny tier numeral. No tooltip and no backpack page were in those frames. Hover motion was not watched.

Potion counts (stats 69/70) and the potion strip sit outside this panel. The HUD writer owns that strip and `ui_theme.gd`.

## This panel

- Equipment 4 + inventory 8, no internal scroll. Optional backpack only when source stat 79 is 1. Nearby loot only when a container id is present.
- Slots are square and sized from the live control width (36–48). Icons are the existing 8×8 silhouettes, integer-scaled. No clipped item-name text. A tier digit is drawn only when source `Tier` is >= 0.
- Tooltips are a design inference. They show source name, tier, slot role, projectile min/max, MP, cooldown, documented stat boosts, heal/magic amount, and the decoded `{equip.*}` instruction. Missing or unknown values are `—`. They do not invent a stat name or a zero damage.
- Theme: `ResourceLoader.exists("res://src/client/fsod/ui_theme.gd")` then `tokens()` / zero-arg `panel_style()` / `slot_style()`, and only if the dict is frozen v2 (`slot` `#515151` or `charcoal` `#333333`). A v1 rollback is ignored. Standalone fallback uses that same v2 sample, not a second palette. Host x/y/height are not pinned here.
- `ui_diagnostics()` returns `gravebag.ui_diagnostics.v1` from `get_global_rect()` and source names. Region ids are `gear`, `inventory`, `loot`, `tooltip`. `focus.traps_gameplay` is false. Space is not accepted, so ability still reaches `_unhandled_input`. Enter still activates the focused slot.
- Swap and use signals fire immediately. Pending is not authority. The next snapshot is the readback; the panel does not draw success.

## Forbidden

No writes to world, entity, session, entry, realm guide, `project.godot`, `ui_theme.gd`, HUD, or layout tests. No source textures, no video-sprite copies, no potion-count strip, no backpack page, no shared theme API invented here.

## Verification

`node --test tests/fsod-inventory-ui.test.mjs` in an isolated HOME. The PNG is a 1280×720 fixture, not a live session. Baseline before this change: `evidence/baseline-inventory-960x760.png` at `ab8b8f8568a15d080beb2f6ce8dfb2cf5c519d44`.
