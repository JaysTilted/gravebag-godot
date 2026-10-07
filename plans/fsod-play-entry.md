# FSoD playable-entry UX repair (bounded)

## Scope

Owns ONLY:

- `src/game/fsod_entry.gd`
- `src/game/fsod_session.gd`
- NEW `src/game/fsod_entry_selftest.gd` (+uid)
- NEW `tests/fsod-entry.test.mjs`
- This plan `plans/fsod-play-entry.md`

Do NOT touch `src/client/fsod/` (world/entity owned by other workers),
existing `src/game/fsod_session_selftest.gd`, private `.state`/accounts,
or live processes. Read-only reference to pinned C# (`6fd20aad`) only.
Main source current `7e393b7`.

## Problem

Death only labels `YOU DIED` and writes profile `character_id = -1`; no
playable restart exists. Offline (`disconnected`) and `failed`
(`FAILURE`/protocol error) leave Jay stranded on a status label with no
usable action.

## Fix

Real `Button` nodes on the same `CanvasLayer 100` entry layer, same 18pt
aesthetic, wired to real session recovery (no delay guesses, no fake world):

- `dead` → `New character` → `session.restart_as_new_character()` →
  Nexus HELLO, `character_id = -1`, MAPINFO then sends `CREATE` (78).
  Never `LOAD`s the dead id.
- `offline` / `failed` → `Reconnect` → `session.retry_connection()` →
  Nexus HELLO, saved `character_id` preserved, MAPINFO then sends `LOAD`
  (8) when a character is saved, else `CREATE` (78).
- Hidden during `connecting` / `authenticating` / `loading_character` /
  `playing`, and during normal portal `reconnecting` (no failure button
  on a healthy portal hop). Press disables the button at once; session
  guards return `ERR_BUSY` without a second transport connect.

Session recovery (`fsod_session.gd`):

```gdscript
retry_connection() -> Error            # offline/failed only, else ERR_*
restart_as_new_character() -> Error    # dead only, else ERR_*
_reset_to_nexus_hello()                # GameId -2, KeyTime 0, Key empty
```

Both restore the original Nexus HELLO (`GameId -2`, `KeyTime 0`, empty
`Key`), reuse the stored encrypted `GUID`/`Password`, and connect once
to the stored Nexus `_host`/`_port`. View/map clearing happens only on
real `MAPINFO` (65). No HP/XP/inventory mutation, no fame award, no
resurrection, no credential logging. `_on_disconnected` already preserves
`dead`/`failed`/`reconnecting` (no silent flip to `offline`).

Entry (`fsod_entry.gd`):

- `_action: Button` created beside `_status` in `_ready`, initially
  hidden+disabled, `pressed` → `_on_action`.
- `_on_state` keeps existing playing/dead profile saves and status text,
  then `_refresh_action()`.
- `_fail` keeps its generic message (never logs auth) and refreshes the
  button so `failed`/`offline` stay usable.
- `_refresh_action()` shows `New character` for `dead`, `Reconnect` for
  `offline`/`failed`, hides otherwise.
- `_on_action()` disables at press, calls exactly one session method,
  refreshes on the synchronous `state_changed` (`connecting` or `failed`).

## Proof

- `src/game/fsod_entry_selftest.gd` drives actual Godot signals
  (`connected`, `disconnected`, `packet_received`, `Button.pressed`)
  against a mock transport + `Codec.encode_client` validation:
  CREATE-not-LOAD after death, LOAD saved char on reconnect, one
  connect per button press (`ERR_BUSY` on duplicates), dead preserved
  across socket close, failed preserved with usable retry (never faked
  to `playing`), Nexus HELLO restore with credentials reused, view
  cleared only by real MAPINFO, portal `reconnecting` shows no button.
- `node --test tests/fsod-entry.test.mjs` runs the selftest headless on
  Godot 4.6, asserts exit 0, `FSOD ENTRY SELFTEST PASS`, no
  `SCRIPT ERROR`/`Assertion failed`, and no `GUID`/`Password` in output.
- Existing `tests/fsod-session.test.mjs` must still pass (no behavior
  change to playing/portal paths).

## Limits / not done

- No live original-server connect/auth/create/load proof here; parent
  integrates and proves against the real backend.
- No auto-retry timers, no portal resume-to-realm on unexpected drops:
  retry re-enters Nexus; the server authorizes placement.
- No merge/push; commit scoped to the files above for parent review.
