# FSoD Realm Guide — original-frontend realm entry overlay

Status: scoped fix, walkingwriter-collision-free.
Owner files (this branch only):
- NEW `src/client/fsod/realm_guide.gd` (+uid) — overlay, no gameplay writes.
- NEW `src/client/fsod/realm_guide_selftest.gd` (+uid) — fixtures + render.
- NEW `tests/fsod-realm-guide.test.mjs` — runs new + existing entry/frontend fixtures.
- EDIT `src/game/fsod_entry.gd` — attach overlay via `_process` readonly poll.
- THIS PLAN `plans/fsod-realm-guide.md`.

Forbidden (walkingwriter owns ALL 3): `world_view.gd`, `entity_view.gd`,
`fsod_session.gd`. Also forbidden: `project.godot`, private `.state`,
backend/account. Jay is actively playing: no focus/input/restart/live-window
touch; headless + xvfb fixture only.

## Source facts (scout `scout-muy3taly1/evidence/report.md`)
- Realm portal type `0x0712` = 1810 = `Nexus Portal`, class `Portal`
  (`src/data/fsod/objects.json:1810`, `indices.json` nexus portal → 1810).
- Bound-realm use: server `RealmPortalMonitor` spawns one `Portal(0x0712)`
  per bound realm at a Nexus tile with `Region == Realm_Portals`.
- Travel: client `UsePortal` id 9 with `ObjectId`; server uses existing
  `WorldInstance` or falls back to Nexus for `0x0712`.
- Today: all portals render as identical teal/cyan swirl (`entity_view.gd:189`),
  no floating name, no E prompt (`world_view.gd:654`, rail `659-676`).
- Session picks nearest `Portal`/`Container` within `1.0` tile and sets
  `view.interaction_target_id` (`fsod_session.gd:346-358`); `E` sends id 9
  only when that id is `>= 0` (`world_view.gd:514-515`).
- Wire stat 31 is UTF (`codec.gd:9`) and carries the portal `Name`/WorldName
  (e.g. realm instance name); type name stays `Nexus Portal`.
  Dragon/Cube-style world names arrive here, not in the type id.

## What the overlay does
Pure display read, zero gameplay writes:
- Reads ONLY session snapshots (`state`, `player_id`, `pending_position`,
  `entity_states`, `object_types`, `metadata`) and frontend display reads
  from named existing world fields/get methods (`entities`,
  `interaction_target_id`, `map_name`, `get_global_position()`,
  `display_position()`, `position`, `get_viewport().get_visible_rect()`).
  Optional helper layout only (rail width 256, clamp, palette).
- Labels SOURCE visible nearby portals (floating name above each on-screen
  portal). Realm `0x0712` prefers cleaned WorldName (stat 31); other portals
  show their source type name. WorldName localization braces
  (`{ns.Name}` → `Name`, `_` → space) are cleaned; typeName is never altered.
- Actionable prompt reflects the ACTUAL E target (`interaction_target_id`),
  never a different portal than E will use:
  - E target is a realm portal → `E · Enter realm <WorldName>`.
  - E target is another portal → `E · Enter <TypeName>`.
  - E target is a bag/unknown (Container closer) → no E realm prompt;
    show `Stand closer…` hint so Jay steps to the realm swirl.
  - Out of range (`interaction_target_id < 0`) → `Stand closer…` hint.
- Direction + distance to the nearest streamed REALM (`0x0712`) portal while
  in Nexus: `<RealmLabel> · <compass> <N> tiles`. Compass uses the rendered
  avatar tile pose (`display_position()/32`, else node position) so "here"
  matches the sprite. Session `pending_position` can lead the sprite; it is
  not the direction anchor. The E line still follows `interaction_target_id`
  only, including when a nearer bag owns E. WorldName cleanup also strips
  source ids `NexusPortal.Dragon` → `Dragon` (stat 31). No guessed coordinates:
  - Portal streamed but off-screen → direction line only, no floating label.
  - No portal streamed → `Explore Nexus to find a realm portal`.
  - Never emits `Realm portals are north of spawn` unless a source-verified
    direction exists (none pinned, so the generic explore line is used).
- Stand-closer hint, no auto `UsePortal`, no fabricated portals, no local
  teleport. Emits NO signals, touches NO transport.
- Visible only when `session.state == "playing"` AND `map_name` contains
  `nexus` (case-insensitive) AND `player_id >= 0`. Hidden offline/failed/
  connecting/reconnecting/loading/dead and after leaving Nexus (e.g. `Realm`).
  No coupling to learning/original-position state.
- Dark readable pixel HUD in current palette only:
  bg `111829`, direction `efcf7a`, prompt `64cbd3`, hint `8996af`,
  portal names `f9de86` with `111829` shadow. Top-left at `(16, 80)` (below
  entry status/button), space-clamped to `viewport.x - 256 (rail)`, portal
  labels clamped to viewport minus rail. All controls `MOUSE_FILTER_IGNORE`,
  `FOCUS_NONE` — never steals focus/input.

## Entry wiring (`fsod_entry.gd` only)
- `preload` guide, `var _realm_guide`, create after successful
  `session.bind` in `_ready`, `add_child`.
- `_process` polls `guide.refresh(session, _frontend)` once per frame when all
  three are valid; guide itself hides when conditions fail. Readonly, light
  single pass, no signals. Early-`_fail` paths leave guide null and `_process`
  no-ops, so existing entry selftests are unaffected.

## Fixtures (`realm_guide_selftest.gd`, real Godot, no live server)
Headless logic + xvfb render, all with real `world_view` + mock session:
1. Nexus far — direction east + distance, stand-closer, no E, label shown.
2. Nexus near — `interaction_target == portal` → `E · Enter realm Dragon`.
3. Unknown WorldName — falls back to `Nexus Portal`, no fabrication.
4. Bag-closer — E target is bag → no E realm prompt, stand-closer stays.
5. Non-realm portal nearer — labels both, direction still targets `0x0712`.
6. Realm map — hidden.
7. Removed portal — labels cleared → explore line.
8. Busy/offline — hidden, zero outbound requests (all frontend signals quiet).
9. Viewport small (640×360) / large (1920×1080) clamp stays left of rail.
10. Localization cleanup `{objects.Dragon}` → `Dragon`, typeName untouched.
11. Render (xvfb `--capture-dir`): real 1280×720 frame with source name +
    E prompt, saved as `realm-guide-frame-0.png`. Avatar is synced onto the
    session pose first. The original fixture left the sprite at tile 10 while
    pending sat at tile 20 next to a portal at 20.5: (20.5-10)*32 = 336px,
    which is why that frame said "here 1 tile" beside a distant ring.
12. Smoothed-camera label: `_world.position` lagged by (120, -70); floating
    label equals the portal global display pose, not raw tile*32.

## Verification
- `tests/fsod-realm-guide.test.mjs` runs: guide selftest (headless),
  guide render (xvfb, asserts 1280×720 PNG + `E ·` prompt in tree),
  existing `fsod_entry_selftest.gd` + `src/client/fsod/selftest.gd`
  (walkingwriter collision check). Isolated `HOME`, `SCRIPT ERROR` fail.
- Commit artifacts + scope; parent sole push/CI/merger; do NOT retire tree
  until native acceptance. Return commit SHA, tests, frame path/limits.
