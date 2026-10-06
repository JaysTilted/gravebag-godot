# Partial FSoD combat port — superseded, NOT integrated

Operator pivot: preserve original C# server; Godot is a presentation/client bridge.
These standalone files are reference/test progress, NOT the selected backend.
No existing combat/game/player/world/stats/cache files changed. No adapter was
completed, no game restarted, no merge claimed. Parent should NOT cherry-pick
this partial-port commit into the authoritative-server integration.

## Provenance

AGPL-3.0-only, FSoD `/home/jay/fsod-ref` at
`6fd20aad4a7905b13f25389c68368a942a2b68cb`. Original source contains no author
headers; retained region/source identity in per-file attribution comments.
`src/combat/fsod/LICENSE` is upstream LICENSE verbatim. No art, SWF, DLL,
or network code copied. Roster specs: `wServer/logic/db/BehaviorDb.Lowland.cs`.
Stats: `db/data/dat1.xml:14584-14664,14753-14835`.

## Reusable standalone API

- `roster.gd`: `IDS`, `get_enemy(source_id) -> Dictionary`; five concrete enemies:
  Hobbit Mage (HP200/DEF2), Archer (22/0), Rogue (26/0), Sumo Master (340/5),
  Lil Sumo (55/4). Projectile damage/speed/lifetime copied as DATA from XML.
- `interpreter.gd`: `configure(tree, seed=1)`, `tick(milliseconds, context)`,
  `reset()`, `current_state`, `spread(spec,bearing_radians)`, `source_speed(s)`.
  Context contains value snapshots only, no Nodes/references. `has_target=false`
  or `dead=true` suppresses all work; reset clears state/transition timers and RNG.
  This does NOT establish null/freed-target safety or respawn behavior for a
  CombatEnemy node; there is no `enemy.gd` adapter.
- Result `{position, shots, events}` uses source tiles. Caller owns projection,
  collision, spawning, portals, loot and generated visuals. Never attach to dive
  as a parallel authority when connecting the C# server.

## Exact semantics preserved in tested subset

`Entity.cs:125-191`: first deepest child, transitions before OLD state's behaviors,
leaf before parent, new-state entry next tick. Shoot coolDownOffset on entry;
checks <=0 before subtracting integer milliseconds; default cooldown1000;
aimed shots acquire within radius; fixedAngle shoots even outside radius.
Degrees become radians exactly once; shootAngle is ADJACENT spacing, not total
fan width; first shot = center - spacing*(count-1)/2. Aim recomputed per volley.
Timers retain storage on state reentry (TimedTransition lacks an entry reset).
Prioritize locks one child until Completed/NotStarted, not a per-frame selector.
Seeded RNG is deliberate adaptation, NOT upstream thread-local random identity.
Movement uses `Utils.cs:188-193`: 5.55*behaviorSpeed+0.74 tiles/sec (unconditioned).
Projectile speed uses `Projectile.cs:57`: XML Speed/10 tiles/sec, NOT /100.
All interpreter positions/ranges are tiles; integration projection should use
one explicit scale (current `src/world/realm.gd:17` is64 pixels/tile). No pixel
conversion or fixed server tick rate is implemented in this superseded port.

## Explicit gaps

No CombatEnemy adapter/configure(source_id)/signal wiring/canned-cycle disabling.
No copied terrain, status effects, collision validation, spawning world, portals,
loot tables or generated-art changes. Spawn emits exact max/initial/cooldown
requests only; world has no consumer. StayAbove needs elevation/map_center.
Protect/Orbit need ally snapshots; peer exclusion belongs to caller. Selected
roster has no predictive shots; generic predictive/Charge support is unproven.
Projectile MultiHit/PassesCover/size retained as metadata, not simulated.
XML has no XpMult for Archer/Rogue: remains null in data; baseline XP uses actual
DamageCounter.cs:88 fallback1: HP/10*(XpMult??1). Baselines32,2.2,2.6,56.1,11
are NOT final awarded XP (damage shares, caps, boost/int conversion excluded).
No source base movement Speed was invented: speeds come from BehaviorDb.

## Checks

Godot4.6 headless import + `-s src/combat/fsod/selftest.gd`: zero failures.
`bash scripts/verify.sh --fast`: VERIFY PASS, all16 selftests passed.
Bubblewrap isolated /tmp, HOME and .godot into this worktree's ignored
`src/combat/fsod/.test-output/`; no shared /tmp/gravebag logs/cache writes.
Test log paths: `.test-output/selftest.log`, `.test-output/verify-fast.log`,
`.test-output/tmp/gravebag-verify-tests.log` (relative to owned combat dir).

## Client protocol findings for the original-backend pivot

`wServer/PacketIds.cs`: UPDATE7, NEW_TICK80, SHOOT96 (enemy volley).
`networking/Packet.cs:41-50`: big-endian int32 total length INCLUDING5-byte
header, then byte packet ID, then encrypted body. Stateful stream handling must
assemble entire frames and preserve directional cipher state.
`networking/svrPackets/ShootPacket.cs:24-53`: byte BulletId, int32 OwnerId,
byte BulletType, two float32 tile coordinates, float32 Angle in RADIANS,
int16 Damage; optional byte NumShots + float32 AngleInc only when multishot
and nonzero increment. Missing tail means single shot (not0 shots). Volley
angles already start at centered fan's first shot; do not recenter again.
`db/NReader.cs:21-50`, `NWriter.cs:22-51`: network-endian integers/floats.
`NewTickPacket.cs:22-43`: int32 TickId/TickTime(ms), uint16 status count.
`UpdatePacket.cs:25-77`: uint16 tile/object/removal counts; tiles int16 x/y
+ uint16 type, objects ObjectDef, removals int32 entity ids.
`wServer/Structures.cs:197-278`: positions float32 x/y; ObjectDef uint16
ObjectType+ObjectStats; ObjectStats int32 Id+Position+uint16 stat count,
byte stat ID then UTF string for Name/Guild, otherwise int32.
`realm/LogicTicker.cs:32-33,71-75`: MsPT=1000/TPS; lag combines ticks into
thisTickTimes. Honor server TickTime; do not assume Godot physics tick identity.
`realm/entities/Projectile.cs:52-97`: render projection must retain projectile
ID parity, descriptor speed/10, lifetime, wavy/parametric/boomerang/amplitude
paths; straight-only bullet pool is not a complete frontend for that backend.
