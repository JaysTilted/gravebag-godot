# Full FSoD cutover: actual runtime evidence (2026-10-06)

The pinned original C# backend, maps, AI, descriptors, loot, XP and persistence remain authoritative. Godot is a protocol/presentation/input client, not a second backend simulation. The previous toy build remains the default until frontend acceptance is complete.

## Proved through the real isolated backend

- Account registration/encrypted HELLO, character creation/load and live Nexus tiles/entities/stats.
- Original Nexus movement/obstacles, bound0x0712 portal, reconnect and real generated realm. Recovered original half-grid clipping fixed a navigation stall; no fake teleports or local map generation.
- Shooting/contact reports, enemy kill and server XP25. Successful replay: `.state/exec-fee1f7aa62944979b5e9e7b5d49bb57c.{json,log}`; exit0/not timed out;625 server ticks and four real1280×720 frames.
- Subsequent reload retained XP25. Real enemy contact changed server HP100→93: `.state/exec-a677ba98b12641d1bada93fca5a658c1.{json,log}`; exit0/not timed out.
- Further live play produced original level-up/resource maxima changes and more XP. These were not applied by Godot.
- Source-authoritative inventory/nearby loot UI:55 actual component checks;61 integrated world checks; UI callback→original command serializer tests. A request never changes local inventory, and full inventories leave loot intact. Real loot pickup is now proved: source bag304321, Iron Shield2569 → inventory slot4, confirmed only by the server's subsequent snapshot. Replay `.state/exec-b86c36cbd3b9488c867c9cfab13f2061.{json,log}` exited0/not timed out; actual frame06-original-loot.png inspected.

Host log prefix: `scripts/fsod_backend/`. Runtime frames are under `.state/live-frames/`; these files are ignored development evidence, not committed account profiles. The isolated namespace has only loopback listeners/no outbound routes and its own MariaDB, with no existing database or email/payment provider access.

## Owning fixes, not gameplay replacements

The real first portal reconnect exposed an original async disconnect/account-null race that terminated wServer. `scripts/fsod_backend/lifecycle.patch` fixes session/save/dispose ownership, compare-and-remove registration, and the reconnect persistence barrier. Eleven compiled regression interleavings plus full original project builds pass. After applying through the normal backend build pipeline, the actual portal/combat replay succeeded and all three services remained alive. Content/AI/loot/XP/death-fame code is not replaced; overlay hashes are recorded by the builder.

Protocol tests copy only their source module into disposable projects; they no longer attempt to clone live UNIX sockets or private runtime profiles. Current combined static/protocol/account/UI/lifecycle adapters:16 passed; Godot fast gate:13 selftests passed and VERIFY PASS.

## Not yet complete

Live equip/use readbacks, permadeath/new-character UI, all dungeon/boss routes, trading, guild/social, vault/gifts/shop, pets, quests/arena/reskins and corresponding frontend controls still require acceptance. `plans/fsod-acceptance.md` retains the whole20-family contract; these core loop proofs do not complete every family. Original TODO-only packet handlers and missing upstream dependency source remain documented source limitations.

Do not infer full gameplay delivery from compilation, mock tests, source retention or the old slice's verification.
