# Account chrome — connect, death, reconnect

Status: new component. HUD writer owns entry host integration.
Design inference: classic 2012 stills show a flat bottom text bar and yellow
death lines. Exalt's play menu was not watched. The shop splash is not copied.
Full video was not watched.

## Owner files
- NEW `src/client/fsod/account_chrome.gd` (+uid)
- NEW `src/client/fsod/account_chrome_selftest.gd` (+uid)
- NEW `tests/fsod-account-chrome.test.mjs`
- THIS PLAN `plans/rotmg-ui-account.md`

Forbidden: `fsod_entry.gd`, `fsod_session.gd`, `world_view.gd`, `entity_view.gd`,
`inventory_panel.gd`, `ui_theme.gd`, `project.godot`. No login-file reads.

## Contract
`refresh(snapshot: Dictionary)` is a full readonly snapshot. It emits nothing
and does not write the dictionary.

Signals, no arguments: `reconnect_requested`, `new_character_requested`.
No `return_to_nexus_requested`. Nexus escape stays R / packet 47 in session.

Snapshot keys, exact:
- `state`: `offline|connecting|authenticating|loading_character|playing|reconnecting|dead|failed`
- `ready`: bool, entry's FSOD CLIENT READY only. Any other type is not ready.
- `status`: entry's computed string, shown verbatim. No countdown, no invented success.
- `error`: failure text. Omitted from the panel when it duplicates `status`.
- `character_name`, `class_name`, `map_name`: strings only. Generic `name` / `class` are ignored. Non-strings are not coerced.

Buttons: `dead` → `New character`; `offline|failed` → `Reconnect`. Every other
state hides and disables the button, including `reconnecting` and `playing`.
Press sets real `Button.disabled` and latches until `state` changes. The same
snapshot does not re-enable and does not emit again.

`playing` + `ready` hides the blocking strip immediately (fade is visual only)
and leaves a mouse-ignore chip with `character_name` / `class_name` when those
strings exist, otherwise `status`. Commands are not delayed by the fade.
Clicks outside the strip pass through. Gameplay keys are not handled.

`ui_diagnostics() -> Dictionary` is a pure read, schema
`gravebag.ui_diagnostics.v1`: `viewport {w,h}`, `regions[{id,rect{x,y,w,h},visible,clipped,text,focusable,focused}]`,
`actions`, `focus {owner,traps_gameplay}`, `state`, `mouse_ignore`.
`diagnostics()` is the same dictionary.

Theme: `ResourceLoader.exists("res://src/client/fsod/ui_theme.gd")` then static
`tokens()`. Alias pairs: ink=void, slate=charcoal, steel=muted, paper=silver,
danger=hp. Missing file uses the same sampled palette: void `#1a1a1a`,
charcoal `#333333`, slot `#515151`, slot_edge `#2a2a2a`, silver `#d4d4d4`,
muted `#9a9a9a`, gold `#efcf7a`, hp `#fc3436`, mp `#648dff`, xp `#5b832b`,
fame `#ff8a1a`. Corners 0. No painted splash, no rounded card.

Placement inference: bottom-left flat strip, clear of the 256px rail, so it
does not cover the realm guide at `(16, 80)`. The ready chip stays at the
top-left and ends above y=72.

## Verify
`node --test tests/fsod-account-chrome.test.mjs`

Isolated HOME, targeted Godot only. Fixtures: 1280x720 offline/dead/busy/ready
plus a fade sequence, a 640x360 clamp, and a letterboxed large window whose
logical strip stays 360px.

## Limits
Entry must hide its old status/button when this node exists, or both show.
A refused command that stays in the same state stays latched until entry
refreshes a different state. This file does not call `retry_connection` or
`restart_as_new_character`.
