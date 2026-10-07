# RotMG UI target-geometry proof

Status: binding integrated fixture gate, not final reference/live approval.
The original proof lane's baseline-only ownership restrictions are historical;
the sole integration coordinator owns the merged UI and proof repairs.

## Production composition, isolated IO
`tests/layout.test.mjs` stages the actual source dependencies into a temporary
Godot project with isolated HOME and Xvfb. `ui_acceptance_selftest.gd` subclasses
production `fsod_entry.gd`, disabling only startup/account/profile IO. Production
Entry state/READY/refresh handlers attach the actual World, account chrome,
feedback and guide, and connect the actual recovery signals. Session commands
are local counters: this does not prove original-backend packets or saves.
No current player profile, backend STATE, display or window is used.

## Binding checks
Every target gate asserts immediately; later states cannot overwrite an earlier
failure. Core 4 equipment + 8 inventory slots must be visible and unclipped by
any ancestor. Real HP/MP/XP/stat region rectangles and measured caption font,
line height and width must fit, including at 640x360. The compact layout reserves
header/bars/stats above a height-budgeted grid; there is no core scrolling.
Main host and potion strip match the primary v2 contract via real controls.
Identity/Fame rectangles and rendered text must not overlap. The existing guide
uses shared charcoal tokens and shrinks unused label rows. Potions show authored
icons plus known wire 69/70 counts and existing F/V actions. Unknown maxima have
empty fills, not a level-20 full Fame bar; known values remain readable.

All eight states (Nexus, realm, combat, inventory, loot, tooltip, offline, death)
are captured at 1280x720, 640x360, 800x600 and 1920x1080, plus letterbox, tile-change
and temporal samples. Offline/death captures use actual production Entry action
handlers and prove a latched press routes once to the fixture session. Chrome
and legibility tooltip frames settle fully; separate tooltip fade frames remain
transitional evidence. Temporal HP/MP/XP values jump to source, fills ease between
source and previous samples, and Space passes focused inventory slots unchanged.
The 1/60 algorithm samples are harness steps, not a measured production FPS claim.

## Provenance and limits
The manifest hashes every staged source dependency (including Entry/theme/guide)
and every PNG. The gate compares each rendered source hash with the declared
commit before capture, then checks sources remain unchanged. Dirty source cannot
produce an accepted exact-HEAD manifest. The inspected RotMG references are real
classic/Exalt stills; full video/motion remains unwatched. The terrain fixture is
12x8 known cells, not live Nexus's initial terrain population. No quests, chat,
party, gameplay rules or original Flash artwork are invented to fill gaps.

Run `node --test tests/layout.test.mjs` from a fresh clone with isolated HOME.
The headless run_all path deliberately skips render proof. Independent frame
review and separately authorized fresh-account live QA remain acceptance gates.
