# FSoD Warden research — backend-retention pivot

## Delivered (not a boss replacement)

Latest operator guidance supersedes the encounter rewrite: **retain the original
C# backend, change the frontend/art, bridge Godot to its protocol**. The temporary
encounter state-machine rewrite was removed before commit. No adapter, boss scene,
backend simulation, HP/timer port or dive wiring is delivered or claimed.

`src/bosses/fsod/source_data.gd` retains reusable Snakepit Guard data and pure
volley direction math; `selftest.gd` tests only those. Existing Warden, patterns,
dive, combat, player, systems and tracked Godot cache are unchanged. The player-
facing name would remain Warden, with `source_id = "Snakepit Guard"` in data.

## Provenance

Source: https://github.com/ossimc82/fabiano-swagger-of-doom, revision
`6fd20aad4a7905b13f25389c68368a942a2b68cb`, read-only `/home/jay/fsod-ref`.
AGPLv3 text is preserved verbatim in `src/bosses/fsod/LICENSE`.
Upstream README credits: ossimc82/Fabian Fischer, C453, Trapped, Donran,
creepylava, Krazyshank, Barm, Nilly, sebastianfra12, Kieron, and all other
contributors. The upstream C# source files have no individual copyright header.
No SWF, DLL, art or audio is copied into GRAVEBAG.

Read ForestMaze and Lich in full: Mama Megamoth is an unphased summon encounter;
Lich requires an evaluation/transform chain, phylacteries and several minion types.
Snakepit Guard instead has two complete solo states in `BehaviorDb.SnakePit.cs`
403–422. Phase 1 uses spawn leash/Wander; below **strictly** 60% HP Phase 2 uses
Follow/Wander plus a third projectile stream. Parent volleys continue across the
HP transition. `Shoot.cs` centers fan directions around aim; implicit spacing is
360/count, degrees become radians. Cooldowns check before subtracting elapsed
milliseconds, and `Cooldown.cs` variance is inclusive. These semantics must stay
on the server, not be replaced by a client animation timer.

XML is present, not missing: `db/data/dat1.xml` 62257–62297 defines HP 5500,
defense 50 and all three projectile records; 5887–5910 defines their visual IDs.
Projectile motion uses **Speed/10 tiles/second** (`Projectile.cs:55`), not the
predictive aiming helper's Speed/100. Movement is `(5.55*speed + .74)` tiles/s
(`Utils.cs:188–193`). At behavior speed .2 that is 1.85 tiles/s. The retained
32 px/tile default is an explicitly invented Godot presentation choice, not a
source value. Dazed durations, lifetimes, visual rotation and sizes are source
metadata; the math test does not implement condition effects or collisions.

## Original backend build proof

A disposable local clone with isolated HOME built successfully using
`xbuild wServer/wServer.csproj /p:Configuration=Release /verbosity:minimal`
on Mono 6.8.0.105/xbuild 14.0. No source/backend installation was changed.
Warnings exist; this is compilation proof, **not service/network/database proof**.
The project targets .NET Framework 4.6, references db + DungeonGen, and uses
vendored MySql.Data 6.9.6, Newtonsoft.Json 6.0.8, Ionic.ZLib, BouncyCastle,
log4net and zlib.net. Runtime provisioning belongs to the separate backend owner.

## Godot bridge boundary (readback only)

Keep the C# server authoritative for boss states, movement, cooldowns, defense,
HP, loot and respawns. Existing dive signals are a local prototype API only:
`died(int)`, `phase_changed(int,int)`, `volley_fired(StringName,Array[Vector2])`,
`minions_spawned(int)`; properties include max_hp, hp, phase, aim_target and adds.
`dive.gd:45` still preloads the existing Warden; nothing opts in automatically.
Its volley callback at 540–564 uses one global speed/damage and cannot represent
source projectile types/conditions. A bridge must not route server volleys back
through the local AI or reinterpret them as its generic "aimed" pattern.

Source protocol:
- `networking/Packet.cs:42–52`: big-endian total frame length, 1-byte packet ID,
  encrypted body; `svrPackets/ServerPacket.cs:5–7` uses the per-client send cipher.
  `Client.cs:39–50` initializes separate directional RC4 streams. Do not print
  cipher/auth material or treat each packet as a fresh stream.
- `UpdatePacket.cs`: tiles, new object definitions, removed object IDs.
- `NewTickPacket.cs`: tick ID/time and ObjectStats updates; consume authoritative
  position, HP, size and condition stats. There is no explicit boss phase packet.
- `ShootPacket.cs`: first bullet ID, owner ID, projectile type, position,
  **start** angle in radians, damage; NumShots/AngleInc omitted for single shots.
  Missing optional fields must default to one shot/zero spacing. Do not center
  this start angle again. Use the owner's projectile XML for lifetime/speed.
- `DamagePacket.cs`: target ID, effects, damage, killed, bullet ID and owner ID.
  Removal/damage are authoritative lifecycle events; clear visuals on world swap.

No connection to a live backend, boss visual proof, nexus/death hold tests or
respawn timing proof was attempted after the pivot. Those remain bridge work,
not passing claims from the source-data test.

## Checks

Godot 4.6 (`4.6.stable.official.89cea1439`) focused math selftest passed 51
assertions in a disposable clone with isolated HOME. Full `verify.sh --fast`
will be run on the committed tree in a disposable clone; only its fixed shared
`/tmp/gravebag-verify-tests.log` destination is redirected in that disposable
script, preserving the live worktree/cache and Jay's window.
