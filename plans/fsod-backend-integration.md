# Original FSoD backend on Linux — integration handoff

## Direction and scope

Keep the **entire original C# backend**; Godot replaces frontend/art only.
No parallel GDScript generator, enemy/biome subset, or realm replacement is
shipped. The initial uncommitted prototype was deleted, not merged. Existing
GRAVEBAG world/game/player/systems/cache source files are untouched.

Source: `/home/jay/fsod-ref` or the integrator's `references/fsod`, pinned to
`6fd20aad4a7905b13f25389c68368a942a2b68cb`. FSoD repository license is AGPLv3;
DungeonGen source retains its original **Copyright (C) 2015 creepylava** and
AGPL-3.0-or-later headers. `git archive` preserves source/license headers in the
ignored runtime snapshot. Nothing modifies the source reference.

## Exact invocations (from repository root)

```bash
python3 scripts/fsod_backend/backend.py build \
  --source /home/jay/fsod-ref --dependencies /home/jay/.nuget/packages
python3 scripts/fsod_backend/backend.py bootstrap
python3 scripts/fsod_backend/backend.py start --ttl 1800
python3 scripts/fsod_backend/backend.py verify
python3 scripts/fsod_backend/backend.py stop
```

`build.sh`, `bootstrap.sh`, `start.sh`, `verify.sh`, `stop.sh` are equivalent
wrappers; `exec.sh` runs a bounded caller in the same namespace. Integrated trees default `--source` to `references/fsod`; package cache
default is `$HOME/.nuget/packages`. Both inputs are explicitly configurable.
Build works offline and refuses a different source revision or hash-mismatched
DLL. Populate an offline NuGet cache with the exact versions in
`scripts/fsod_backend/dependencies.lock.json`; no automatic downloads occur.

Required executables: Python 3.12+, git, Mono/xbuild, patch, Bubblewrap,
MariaDB server/client/install-db. Tested Mono 6.8, xbuild 14.0 and MariaDB 10.11.
Linux must permit unprivileged user/network namespaces; there is **no unsafe
fallback** when sandboxing is unavailable.

### Readiness and cleanup

`start` launches and returns, it does not block/poll for readiness. `verify` is
one bounded probe, returns exit zero only after all original services and realm
initialization pass. A caller may use a watcher with **90 seconds / 15 attempts**,
then report the private logs if it never becomes ready. Do not sleep-loop.
The automated Node test uses bounded native file events instead of polling.

Runtime lifetime has a hard TTL (default 1800 seconds, accepted 10..21600).
Database startup is event-driven with a 90-second / 10,000-log-event cap.
Every child termination has a five-second graceful limit then owned-child kill.
`stop` returns accepted; wait at most 15 seconds for `.state/control.sock` to
vanish. No existing services or desktop games are restarted/stopped.

## Isolation, data and network

Everything generated is under ignored `scripts/fsod_backend/.state/`, mode 0700:
source/build snapshot, binaries, generated configs, schema, logs, MariaDB data,
Unix control socket. Only this directory is writable inside the sandbox.
Host home, `/run` and `/tmp` sockets are not exposed. All services share a private
network namespace containing loopback only: **no outbound routes**, mail,
payments, CDN fetches or external service access. MariaDB commands start with
`--no-defaults`; no host database or stored credential configuration is used.

Original `.cfg`, App.config and account-unlock lists are excluded. Runtime configs
are generated. The original SQL dump contributes **19 CREATE TABLE declarations
only**, never its INSERTs/accounts/passwords/payments. A synthetic local account
is registered through the original handler during verification; email verification
is disabled. Only that disposable account and normal original game defaults are
written into the private fixture DB. Database/table names are case-insensitive
like the original Windows deployment; zero dates use the original permissive mode.

Private namespace listeners: MariaDB **33306**, account HTTP **18080**, realm
TCP **2050**, policy **1843**, all bound to 127.0.0.1. The host cannot connect to
these TCP ports. The private Unix control socket supports verify/stop and trusted
bounded caller launch, not a public HTTP proxy. Do not remove network isolation
or bind the original backend publicly to solve frontend integration.

### Same-namespace Godot/helper API (tested)

Copy an isolated Godot executable and client fixture into `.state/Godot` and
`.state/client` (parent-owned fixture). Then, while backend is running:

```bash
python3 scripts/fsod_backend/backend.py exec --timeout 120 -- \\
  xvfb-run -a /state/Godot --path /state/client --quit-after 120
```

`exec` returns immediately with `{id,log,result}`; sandbox `/state` maps the host
`.state` directory. Watch host `.state/exec-ID.json` with a bounded deadline and
attempt count; require `exit_code:0` and `timed_out:false`. Output is in matching
`.state/exec-ID.log`, never dumped to console. Limits: four concurrent callers,
1..600 seconds each, backend TTL also applies; owned process groups/descendants
are killed on timeout/stop. Bad executable paths do not kill the backend.
Node proof calls original account HTTP from a child in this **same** namespace
and asserts `/proc/net/route` has zero routes. No nsenter/root permissions or
host TCP listener are needed. An optional profile helper can run identically,
writing only private `/state` files. The parent implements that helper.

Build also invokes **original `db.dll` `XmlData` + Dispose** through
`MetadataIds.cs` before startup. This persists authoritative
`/state/source/bin/Debug/autoId.cfg` (host `.state/source/bin/Debug/autoId.cfg`).
Source IDs are not guessed or regenerated by a Godot port. Data exporter/helper
must use that exact file and the same data directory; set its working directory
with `env --chdir=/state/source/bin/Debug ...` inside `exec`. The original loader
writes its relative SimpleSettings file only on Dispose, hence this bootstrap
step is necessary before the live realm's first shutdown.

## What is original, and what was adapted

Original full projects built: `wServer`, `server`, `db`, `DungeonGen`, `terrain`.
All AI/behavior/content/dungeon/terrain source algorithms stay byte-identical;
the test checks ten representative source files, including biome/noise/features,
room collision/generation, Pirate Cave AI, Oryx and XML content.

Infrastructure-only `linux-isolation.patch`:

1. Correct 13 account csproj filename/directory case mismatches on Linux.
2. Bind account/realm/policy to loopback, configurable nonprivileged policy port.
3. Add `FSOD_DB_PORT`, preserving original default 3306.
4. Target .NET Framework 4.7.2 and reference pinned MySql.Data **8.4.0** plus
   hash-locked transitive DLLs. Original 6.9.6 crashes in LoadCharacterSets on
   MariaDB 10.11 due to DBNull collation IDs. No opaque DLL/IL rewriting.
5. Preserve old connector numeric-to-string reader behavior explicitly for
   account IDs and age-verification fields; new connector otherwise throws.
6. Map Windows `Pacific Standard Time` to equivalent `America/Los_Angeles`,
   retaining the original daily-quest timezone/calculation.

Generated logging replaces Windows-only ColoredConsoleAppender with the ordinary
ConsoleAppender and removes color mappings. Mono receives a real PTY and its
cursor-position query response, retaining the original Console.ReadKey lifetime.
Relative `app/` templates are supplied with original contents at the path used by
original HTTP handlers. No behavior, item, economy, drop or spawn formula changes.

Upstream warnings are retained in build logs, including unresolved **NuGet.Core**
references and null-valued descriptor comparisons. Builds succeed; this handoff
does not claim those independent upstream issues were repaired. The separate
`terrain.exe` is a compiled original WinForms development tool; it is not run
as a headless service or silently rewritten. The server's realm terrain/map
loader, Oryx, setpieces and generated dungeon caches run normally.

## Real verification

```bash
PI_INSTALL_DIR=$HOME/.cache/pi-ci/1.0.0/node_modules/@earendil-works/pi-coding-agent \
  node --test tests/fsod-backend.test.mjs
```

The Node test builds all projects, checks algorithms/content/provenance bytes and
pinned dependency hashes, initializes a private schema-only DB, launches the
original HTTP+realm servers, exercises registration and account reads, checks
47 behavior modules, 2232 objects, all three generated dungeon caches, original
setpieces/Oryx/minions, policy response, then stops all owned children. It is not
a passthrough heartbeat. A fresh clone with isolated HOME runs the same test;
explicit source/package fixtures avoid dependence on operator plans/config.

The existing GRAVEBAG `bash scripts/verify.sh --fast` also passes, with `/tmp`
remapped to a private worktree-backed directory and HOME/TMPDIR isolated so the
script's hardcoded log names cannot collide with other writers.

## Source map and frontend protocol facts

Actual generator chain: `DungeonGen/DungeonGen.cs` → `Generator.cs` target path,
specials, branches → `Rasterizer.cs` → `JsonMap.Save`. `RoomCollision.cs` expands
candidate bounds one tile; `Range.Random` includes endpoints. `Dungeon/Edge.cs`
uses South=0, East=1, North=2, West=3. `DungeonGraph.cs` computes variable bounds
with four-tile padding and shifts room/link offsets together. Pirate Cave uses
separation [3,7], corridor width 2, normal sizes [8,14], start/boss radius 10;
its depth sampler is external `RotMG.Common.NormDist`, not an invented formula.

`terrain/Biome.cs`, `Noise.cs`, `MapFeatures.cs` are the original moisture/biome,
3D-simplex, river/road source. `wServer/realm/Oryx.cs` maps 12 spawn terrain
classes to literal enemy probabilities and integer tile-count/divisor populations.
The divisors are tiles per spawn, not HP/damage multipliers. `RandRealm.cs` is
commented out; `GameWorld.cs` loads embedded world maps and runs setpieces/Oryx.
`GeneratorCache.NextPirateCave` returns a cached map and schedules its successor:
MAPINFO seed alone cannot replay the actual selected map.

`DungeonGen/JsonMap.cs` server asset format: width/height in tiles, dictionary of
ground/object/region names, `data` = base64(zlib(row-major big-endian uint16
dictionary indices)). This is **not** the client's network map stream.

Wire framing (`networking/Packet.cs`): big-endian i32 total length, u8 packet ID,
stateful directional RC4-encrypted body. `db/NWriter.cs` writes network-order
numbers/floats; UTF lengths count encoded bytes, not characters.

- MAPINFO=65: i32 width,height; UTF16-length name,client-world-name; u32 seed;
  i32 background,difficulty; bool allow-teleport,show-displays; u16 XML count,
  repeated **i32-length** UTF8 XML; u16 extra-XML count, same i32-length entries.
  Follow server **Write**, not its asymmetric Read (which uses u16 XML lengths).
- UPDATE=7: i16 tile count; repeated i16 x,y + u16 ground ID; i16 object count,
  ObjectDefs; i16 removed count, i32 IDs. ACK each applied update with empty
  UPDATEACK=45. Tiles are incremental within sight radius 15, not a room graph
  or whole-map download (`Player.Update.cs`). Unknown/unseen is not walkable.
- ObjectDef: u16 type then ObjectStats: i32 instance ID, f32 tile-unit x,y,
  u16 stat count; each stat is u8 type plus UTF or i32 per `StatsType.IsUTF()`.
  NEW_TICK=80 carries i32 tick ID/time, u16 status count, ObjectStats.

Actual source JSON headers: summer nexus **126×124** tiles, winter **127×123**.
Existing GRAVEBAG realm is 2048×2048 pixels with 64-pixel cells (32×32), so it
must not truncate server-selected MAPINFO dimensions. A 64-pixel display tile
is a frontend convention only: pixels=server tile position×64; floor pixels/64
for tile lookup; bounds=MAPINFO dimensions×64. Summer would be 8064×7936 pixels.
Upstream SWF display scale was not verified. Ground/object XML supplies NoWalk,
OccupySquare/EnemyOccupySquare/FullOccupy; visual ground colors alone are not
collision. Server owns safety, respawn, enemies and progression.

## Next blocker / limitations

No Godot socket/bridge, live client session, map renderer, world replacement or
combat interoperability is implemented by this backend-runtime scope. Parent
can launch its Godot frontend/helper through the tested same-namespace exec API
and must implement full original packet/session semantics. Headless HTTP+world proof is
not an end-to-end Godot gameplay claim. Original generator attempt loops remain
unbounded inside the unchanged backend; sandbox startup/test deadlines contain
stalls without altering generation. RotMG.Common.dll's source is absent upstream;
its binary remains an original runtime dependency in the ignored snapshot.
