# ENTIRE FSoD backend / Godot frontend acceptance

**Direction:** original C# server and database stay authoritative and intact; replace presentation/input with Godot. This is not a selected-mechanic port. Prototype commit `42c616a6067d3cda0f70ed88049fff17f2107653` is preserved **in history only**, and not evidence of a working backend replacement. Separate reversion `d672fd7` restored all three XP/records files from `5ace1f3`; only acceptance fixtures/checklists and the parent-authorized identical combat radius assertion repair remain active in this lane.

**Pinned upstream:** https://github.com/ossimc82/fabiano-swagger-of-doom @ `6fd20aad4a7905b13f25389c68368a942a2b68cb` (AGPL-3.0; parent owns license/credits packaging). Read-only source checkout `/home/jay/fsod-ref`; intended retained dependency `references/fsod` gitlink. Generated fixtures date: 2026-10-06.

## Proof boundary

**1,367 tracked upstream entries retained in the reference inventory. 91 concrete packet schemas: 44 client → server, 47 server → client. 20 backend acceptance families: ALL runtime-pending.**

`tests/fsod/source-inventory.json` captures every upstream tracked path, mode and Git blob/object ID, not just XP files. Includes 461 wServer, 371 HTTP server, 33 db, 42 DungeonGen, 20 terrain and 82 map entries; the remaining tracked entries include original client/tools/dependencies. AI behavior/state/transition/loot databases, all dungeon templates/worlds/maps, accounts, trade, guilds, SQL and both service trees must remain in the pinned source dependency. Do not copy selected source files and claim this gate preserved the whole backend.

Static checks compare the ENTIRE inventory to the exact upstream commit, reject tracked source edits, validate all concrete packet Read/Write bodies against the source, re-export all fourteen XML class stat profiles, assert XP/fame source expressions and spot checks, decode/re-encode plaintext NEW_TICK and MAPINFO fixtures. They never boot C#, execute AI, open sockets, write accounts/SQL, exercise trades, prove client gameplay, or test vendor payments.

When the gitlink is absent in this lane, source checks use the explicitly assigned pinned `/home/jay/fsod-ref` fallback and report **one packaging skip**, not backend-ready. Parent release gate must run `--require-gitlink`; a fallback-only run is not source attachment proof.

## Run / export

- `python3 -B tests/fsod/export_fixtures.py --source /home/jay/fsod-ref` regenerates only `tests/fsod/*.json`; review and commit fixture changes.
- `python3 -B tests/fsod/test_source_fidelity.py --source /home/jay/fsod-ref` runs source-only checks.
- `node --test tests/fsod-source.test.mjs` is the receipt-compatible bounded adapter; same Python checks, no shell wrapper or provider mutation.
- Release attachment gate: `python3 -B tests/fsod/test_source_fidelity.py --source references/fsod --require-gitlink`.
- Parent must run the adapter at the delivered commit in a fresh clone with isolated HOME. Source fallback is explicit task input, not operator HOME state. All other backend runtime acceptance below remains pending.

## Reusable fixture contracts

- `stats-golden.json`: all 20 goals/thresholds, lifetime-XP fame cases, class milestones, damage share/clamps, attack factors, all fourteen class base/caps/inclusive gains, sequential death-fame examples, token rewards. Source-derived expectations, NOT executed C# output; compare them with parent C# oracle before claiming runtime parity.
- `binary-stats.json`: exact stat IDs/UTF set, packet IDs, full plaintext NEW_TICK frame/body with 18 stats including all five UTF types, negative empty item/high-bit flags, account bank vs character fame, and MAPINFO body with XML32 lengths. Body encryption is absent by design; live protocol uses persistent directional RC4 state and BE int32 frame length including five-byte header, unencrypted byte packet ID.
- `protocol-catalog.json`: full Read/Write method bodies for EVERY concrete client/server packet, not a shortlist. Actual outbound client encoding follows **server Read**; inbound decoding follows **server Write**.
- `client-responsibilities.json`: every declared outbound packet, handler path/body, registered TODO handlers, absent handlers, and collision/ACK responsibilities. Source coverage is not implementation coverage of another worker's client branch.
- `acceptance-matrix.json`: machine-readable source/packet/checklist mapping for the 20 families below. Every case intentionally says `pending_runtime`.

## Source asymmetries — mandatory bridge semantics

1. `wServer/Structures.cs:ObjectStats.Write` uses `StatsType.IsUTF()` for Name(31), AccountId(38), OwnerAccountId(54), Guild(62), PetSkin(82). Its Read recognizes only Name/Guild. Follow SERVER WRITE for all five; do not copy the incomplete reader.
2. `wServer/networking/svrPackets/MapInfoPacket.cs:Write` uses **BE int32 byte lengths** for each ClientXML/ExtraXML element; array counts remain i16. Its Read uses i16 strings incorrectly. Follow SERVER WRITE, including unsigned seed and UTF-8 byte (not character) lengths.
3. `wServer/networking/cliPackets/HelloPacket.cs:Read` expects build UTF, world i32, RSA-encrypted GUID UTF, ignored i32, RSA-encrypted password UTF, randomint1 i32, secret UTF, keytime i32, i16 key length/bytes, i32 map length/bytes, then five UTF obfuscation fields. Its Write emits a different order. Follow SERVER READ for client HELLO. Source HelloHandler requires build `27.3.2`.

Parent reported original C# writer oracle verification of the first two asymmetries at `5777822`; this lane does not claim to have run that oracle.

## Exact client collision / hit / ACK responsibilities

Passive rendering alone will not reproduce original combat: `Projectile.TickCore` advances/expires/blocks projectile movement but does **not** detect entity contacts. The Godot client must implement presentation-side projectile trajectories and actual collision-report inputs while server computes damage, XP, loot and persistence.

- **PLAYERSHOOT(13):** Time i32, BulletId u8, ContainerType i16, Position 2×f32, Angle f32. Preserve XML projectile trajectories and IDs/generations. `PlayerShootHandler` creates damage/projectile, validates slot type, broadcasts ALLYSHOOT and calls FameCounter.Shoot. No client-computed damage value is sent.
- **ENEMYHIT(42):** Time i32, BulletId u8, TargetId i32, Killed bool. On own-shot enemy contact, send one report per target/generation with original MultiHit/PassesCover/lifetime semantics. `EnemyHitHandler` resolves the player's projectile and ForceHit; **Killed is ignored**. `Enemy.HitByProjectile` applies defense/effects, damage tally, death and loot. The server does not provide a reliable duplicate-contact suppression guarantee; do not emit duplicate collision callbacks.
- **PLAYERHIT(17):** BulletId u8, shooter ObjectId i32. On enemy-shot self contact, identify by owner+bullet+generation, not byte bullet ID globally. `PlayerHitHander` looks up that projectile, applies effects and Damage; it does not destroy/deduplicate a reported hit. Duplicate reports can double damage. Client must avoid duplicate reports; parent runtime tests should demonstrate the exact preserved behavior.
- **GROUNDDAMAGE(59):** Time i32 plus Position 2×f32 for damaging ground. Server checks tile/ground protection and paused/invincible state, rolls damage and applies death; Time is ignored. Original-client reporting cadence is still **pending oracle verification**, not invented here.
- **MOVE(87):** tick ID i32, time i32, position 2×f32, i16 record count then TimedPosition(time i32, position 2×f32). Server flushes/moves, handles paralysis and Lab tile effects. Player.ClientTick timing/speed validation is commented out.
- **UPDATEACK(45):** empty packet after UPDATE application. Handler increments UpdatesReceived. Player.cs ACK-enforcement check is commented out; do not claim enforced timeout protection.
- **PONG(52):** serial i32 plus client time i32. Source Player.Pong updates last-seen every 60 pongs and contains rare gift-code behavior; no active RTT/timeout validation is in that method.
- **AOEACK(95), GOTOACK(12), SHOOTACK(36), OTHERHIT(14), SQUAREHIT(86):** preserve wire schemas/compatibility, but all five HandlePacket bodies are TODO-only in pinned source. Do not invent effects, validation or ACK guarantees to call them supported mechanics.
- **SETCONDITION(91), client FAILURE(0):** packet classes exist but no registered server handler. Catalog them as source gaps, not required working gameplay features.

## Missing outbound client packet coverage checklist

This lane contains no committed FSoD client bridge. Thus **none of these 44 declarations has proven Godot client implementation/round-trip coverage here**. This is not a claim that another writer's unseen branch lacks them. Parent must fill a per-packet status/evidence field using the complete catalog, rather than declaring entire backend readiness from HELLO/MOVE alone.

- Session/world/heartbeat: HELLO, CREATE, LOAD, ESCAPE, USEPORTAL, MOVE, UPDATEACK, PONG, GOTOACK.
- Combat/input: PLAYERSHOOT, ENEMYHIT, PLAYERHIT, GROUNDDAMAGE, AOEACK, SHOOTACK, OTHERHIT, SQUAREHIT, USEITEM, TELEPORT.
- Inventory/shop/name: INVSWAP, INVDROP, BUY, CHECKCREDITS, CHOOSENAME.
- Social/trade/guild: PLAYERTEXT, EDITACCOUNTLIST, REQUESTTRADE, CHANGETRADE, ACCEPTTRADE, CANCELTRADE, CREATEGUILD, GUILDINVITE, JOINGUILD, GUILDREMOVE, CHANGEGUILDRANK.
- Pets/quests/arena/appearance: PETCOMMAND, PETYARDCOMMAND, VIEWQUESTS, TINKERQUEST, ENTER_ARENA, LEAVEARENA, RESKIN.
- Declared but no handler: SETCONDITION, FAILURE.

Likewise all **47 inbound** packet schemas need client decode/dispatch evidence, including optional SHOOT suffix, MAPINFO XML32, UPDATE object/tile/remove arrays, NEW_TICK typed stats, RECONNECT, DAMAGE/DEATH, trade/guild/pet/quest/arena responses and effect/media/error packets. Plaintext fixture decoding proves only the selected NEW_TICK/MAPINFO sample layouts.

## Entire-backend runtime acceptance matrix — parent owned, all pending

Each entry links exact source files/handlers and packet names in `acceptance-matrix.json`. Evidence must include original C# execution, Godot client inputs/output, and DB/world results; static file presence is not completion.

- [ ] **source-retention:** attach full pinned gitlink + URL; compile/boot original TCP and HTTP services with original dependencies/config/schema in isolated fixtures. No selectively ported GDScript backend.
- [ ] **protocol-all:** all 91 directional schemas, framing/chunking/coalescing, persistent RC4, RSA HELLO, counts/signed values/UTF widths, optional fields, reconnect/key/error behavior. Compare original writer/reader oracles.
- [ ] **accounts-http:** EVERY registered IRequestHandler, not only account verify; registration/auth/recovery/email/guest/gifts/name/locks/unlocks/purchases and all original routes, isolated test accounts only.
- [ ] **create-load:** HelloHandler → CreateHandler/LoadHandler → Database.CreateCharacter/LoadCharacter; all fourteen classes/owned skins, slot limits, live and dead/missing chars, saved stats/items, build/key errors.
- [ ] **nexus-realm:** UsePortalHandler/EscapeHander → Client.Reconnect → target world; actual Nexus/realm entry, seeds, full/invalid portal errors, exit and reload.
- [ ] **movement-acks:** MoveHandler/UpdateAckHandler/PongHandler and TODO ACK stubs; entity/tile updates, moves and timestamps, ground/paralysis effects, preserve active vs commented validation.
- [ ] **dungeons-all:** EVERY original world/map and DungeonGen template via real portals, instance/seed/capacity/exit behavior; the four listed sample paths are anchors, not the entire list.
- [ ] **ai-boss-all:** EVERY BehaviorDb registration/state/transition, boss phase, minion, timer/projectile, summon/drop/portal and death behavior; server runs original logic, client renders it.
- [ ] **combat-damage:** PlayerShoot/EnemyHit/PlayerHit/GroundDamage handler paths, ForceHit/defense/conditions, collision report responsibility, all projectile shapes and duplicate report behavior.
- [ ] **loot-equip:** original loot tables/private bag ownership, damage participation, InvSwap/InvDrop, class slots/distance/soulbound/capacity/boosts; re-login checks DB item preservation/no duplication.
- [ ] **potions-abilities:** UseItemHandler and Player.UseItem activation paths, quick slots 254/255, stacks, health/mana/stat consumables, effects/cost/cooldowns and fame counters; XML-derived outcomes, failed use and reload.
- [ ] **xp-level-fame:** Player.Leveling/DamageCounter/FameCounter/FameStats and all classes; fixture numbers, inclusive random stat gains/caps, XP shares/quest/boost/nearby copy, source one-level-per-event timing, death bonus floors and bank.
- [ ] **death-save-reload:** Player.Death/SaveToCharacter → Database.SaveCharacter/Death, dead flag, graves/fame stats/class best and account bank, dead-load rejection, disconnect/reconnect/restart and no repeated banking.
- [ ] **trading:** TradeHandler → Player.Trade, two isolated accounts, request/change/accept/cancel, changed offers/capacity/distance/soulbound/disconnect, both persisted inventories exactly once.
- [ ] **guilds-chat-social:** guild packet handlers, Player.Guild/Chat/List, Database.Guilds and HTTP guild endpoints; ranks/invites/removal/board/hall, chat/commands/whispers/ignore/lock/authorization and persistence.
- [ ] **vault-gifts-commerce:** original vault ownership/gifts/chests, Buy/CheckCredits, shops/currencies/name/slots/packages/skins/gift redemption/fortune/mystery boxes; no real provider mutation in these tests.
- [ ] **pets-all:** PetCommand/PetYard handlers, hatch/equip/feed/fuse/release/evolve/yard/caps and every pet behavior/effect/save; original currencies/items/account ownership.
- [ ] **arena-quests-reskins:** original arena waves/death/exit/records, daily quest item redemption and 1/1/2/2 Fortune Token rewards, owned reskins, endpoint/state persistence.
- [ ] **admin-config-operations:** original SQL/config/build/dependencies/logs/service errors and rank-gated command/admin surfaces; unprivileged rejection and isolated fixture lifecycle.
- [ ] **frontend-only-contract:** Godot renders and sends source-defined inputs, including collision reports; no local replacement AI/XP/fame/loot/trade/guild/pet/account/persistence. Compare reference client/server and Godot on EVERY interface catalog entry.

## Stats protocol semantics (do not invent display-model authority)

Player.ExportStats sends Experience(6) = lifetime Experience − GetLevelExp(Level); ExperienceGoal(5) = current goal (1950 at 20); Level(7). Reconstruct lifetime only for inspection as stat6 + 50×(stat7−1)². Level 20 threshold is 18050, not 19950. Fame is floor(lifetime XP/1000) even below 20; source CalculateFame timing can lag during a level-up event.

CurrentFame(39) is ACCOUNT bank, Fame(57) is CHARACTER base fame, FameGoal(58) is class milestone. The db Char.CurrentFame name maps to Player.Fame, while account Stats.Fame maps to Player.CurrentFame. Account bank is not the character's live tally and 200/2000 are not fame currency caps. FameStats.CalculateTotal computes death bonuses with intermediate floors. Daily quests award tokens, not spend fame in these constants.

MaximumHP/MP and exported attack/defense/speed/vitality/wisdom/dexterity already include equipment Boost. Bonus stat fields separately describe the component; never add them twice. Use server maxima/resources, not prototype fixed 100 caps or local level-up gains.
