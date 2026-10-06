# FSoD → GRAVEBAG frontend integration

## Ownership / decision

The latest assignment supersedes the initial combat/stat port: retain the original
C# server; this commit changes ONLY `src/client/fsod/`, this plan, and the authorized
`tests/fsod-frontend.test.mjs`. No `GravebagPlayer` subclass, gameplay/stat simulation,
existing player/projectile/UI/system/dive changes, network ownership, or live restart.
The earlier math prototype is retained separately as an explicitly UNTESTED evidence
artifact, not committed, preloaded, or proposed for production integration.

Parent instantiates `res://src/client/fsod/frontend.tscn` and connects its signals
through `src/game/fsod_session.gd`; parent owns main-scene routing, networking,
PascalCase → snake_case packet adaptation, metadata adaptation, and authoritative
source/client movement/cadence parameters. Every unknown HUD value displays `—`.
Fixture values in tests/render fixture are synthetic, not source defaults.

## Public boundary (all positions are original server tiles)

```gdscript
set_player_id(id: int)
set_descriptors(metadata: Dictionary)
apply_map(packet: Dictionary)
apply_update(packet: Dictionary)
apply_tick(packet: Dictionary)
apply_projectile(packet: Dictionary)
remove_entity(id: int)
```

`apply_map`: `{width, height, name}` clears map/entities/projectile visuals.

`apply_update`:

```json
{
  "tiles": [{"x": 1, "y": 2, "tile": 10}],
  "new_objects": [{
    "object_type": 782,
    "stats": {"id": 123, "position": {"x": 4.5, "y": 6.5}, "stats": {"0": 100, "1": 90}}
  }],
  "removed_object_ids": [456]
}
```

`apply_tick`: `{tick_id, tick_time: milliseconds,
update_statuses: [{id, position: {x,y}, stats: {wire_stat_id: value}}]}`.
Stats accept integer/decimal-string dictionary keys, or `[{type, value}]` pairs.
Deltas merge; unknown tick entities do not invent object types. Incoming positions
remain authoritative; NPC visual interpolation uses `tick_time/1000` seconds.
Duplicate updates replace queued/freed nodes safely; removals are idempotent.

`set_descriptors`:

```json
{
  "objects": {
    "782": {"kind": "player", "name": "Wizard"},
    "1000": {
      "kind": "enemy",
      "projectiles": [{"BulletType": 7, "Speed": 100, "LifetimeMS": 1000, "Boomerang": true}]
    }
  },
  "tiles": {"10": {"color": "#344a44"}}
}
```

Object keys may be ints or decimal strings. `kind`/`class` (case-insensitive),
`player`/`enemy` booleans, `name`, `projectiles` are the view contract. Descriptor
extras, including parent's `source_descriptor`, are preserved but not interpreted
as backend rules. Parent maps original Class/Enemy/Player flags to view kinds.
Projectile aliases: `bullet_type|BulletType|id`, `speed|Speed`,
`lifetime_ms|LifetimeMS`, `wavy|Wavy`, `parametric|Parametric`,
`boomerang|Boomerang`, `amplitude|Amplitude`, `frequency|Frequency`,
`magnitude|Magnitude`. Select by declared BulletType, NEVER list offset.
`Shoot.cs:78` selects a behavior's projectileIndex, then `Shoot.cs:112` sends the
selected descriptor's BulletType; those numbers are not interchangeable.

`apply_projectile`:
`{owner_id, bullet_id, position|starting_pos: {x,y}, angle: radians,
container_type?, bullet_type?, num_shots?, angle_inc?, speed?, lifetime_ms?}`.
Missing start (ALLYSHOOT) uses the known owner's authoritative position. Descriptor
lookup uses container_type, otherwise owner's object_type, then declared BulletType.
Explicit speed/lifetime override metadata but retain SOURCE units. Missing metadata
means no fabricated projectile. Repeat owner:bullet IDs replace visuals; multishot
increments bullet IDs modulo 256. Own shot visualization must also be fed by parent;
`shoot_requested` alone does not fabricate bullet IDs/weapons/damage.

Signals:

```gdscript
move_requested(pos: Dictionary, records: Array)
# pos={x,y}; records=[{time: milliseconds,position:{x,y}}]
shoot_requested(angle: float) # original continuous radians, never snapped
escape_requested()
interact_requested(entity: int, slot: int)
projectile_hit_requested(owner_id: int, bullet_id: int, target_id: int, hit_kind: String)
```

Input: WASD normalized; mouse aim remains continuous while moving/shooting;
R requests escape; E requests interaction only when parent sets
`interaction_target_id >= 0` and `inventory_slot`. No closest-enemy, attack damage,
inventory change, mana cost, collision blocking, growth, or teleport implemented.
UI clicks do not request shots; release over the rail clears held firing.

Parent must set `prediction_speed_tiles` (default 0 = no guessed movement speed)
and `shot_request_interval` seconds (default 0 = click only; positive = held requests).
These are original-client prediction/scheduling parameters, not authoritative state.
`clock_ms: Callable` supplies session-relative MOVE record time; fallback engine
monotonic milliseconds is suitable only when parent translates it to its wire clock.
MOVE sampling is every 50 ms while moving plus final stop: GRAVEBAG transport choice,
not an asserted FSoD server rule. Parent owns tick ID/envelope time/acknowledgments.

## Coordinate / visual projection

1 original server tile = 32 client pixels. `entity.position = tile_position * 32`.
Entity positions are continuous floats, not snapped tile centers. Parent receives
unscaled tile coordinates in MOVE requests. Prediction is reconciled at every tick
and never writes authoritative entity positions/stats. Visual corrections smooth;
NPCs interpolate between authoritative positions without extending backend state.

Projectile source units (`realm/entities/Projectile.cs:70-115`):
`distance_tiles = elapsed_seconds * (XML Speed / 10)`;
`lifetime_seconds = LifetimeMS / 1000`. Source boomerang, parametric, amplitude,
frequency and magnitude projections are visual only. Wavy deliberately preserves
the source's integer `elapsedTicks / 1000` in that branch. Example source Fire Wand:
Speed 150, LifetimeMS 600 → 15 tiles/s, 0.6 s, straight-line range 9 tiles.
No damage is applied and no projectile collision shapes are inferred from art.

Optional swept client hit reporting uses authoritative target positions and ONLY
an explicitly injected positive `hit_radius_tiles` on target descriptors, meaning
the effective legacy-client collision radius for a projectile center. Missing
geometry disables hit requests. The C# ObjectDesc/ProjectileDesc sources inspected
do NOT supply this radius; legacy SWF-only client geometry is an integration blocker,
not permission to guess a radius from Size/pixels. Reports are deduped per bullet and
target, `enemy` for local shots against enemy kinds, `player` for enemy shots against
the local player. Session maps those to ENEMYHIT/PLAYERHIT; server remains authoritative.
No OTHERHIT/world-cover or curved-trajectory substep collision is claimed.

Original generated 8×8 pixel player/enemy frames use two distinct walking frames;
object placeholders, sparse tile ground, bright projectile pixels, minimap and
HP/MP/level/inventory rail are presentation only. Unknown terrain remains unknown;
colors never imply server passability. Inventory shows wire IDs 8–19; backpack
71–78 and equipment interaction UI remain parent follow-up, not fake slots.

## Source provenance / inspected definitions

Upstream: https://github.com/ossimc82/fabiano-swagger-of-doom
Local read-only reference: `/home/jay/fsod-ref`.
Exact HEAD: `6fd20aad4a7905b13f25389c68368a942a2b68cb` (AGPLv3).
Adaptation headers use SPDX `AGPL-3.0-only`; full upstream license retained at
`src/client/fsod/LICENSE`. Original placeholder art is drawn in this module.

Inspected (not reimplemented):
- `wServer/realm/Stats.cs`: wire maxHP=0, HP=1, maxMP=3, MP=4, level=7,
  inventory=8–19, attack=20, defense=21, speed=22, vit=26, wis=27, dex=28.
- `StatsManager.cs:25-139`: source stat+boost; attack multiplier 0.5+1.5*ATT/75;
  defense max(damage-defense,15% damage), later integer cast at hit sites;
  speed 4+5.6*SPD/75 tiles/s; dex 1.5+6.5*DEX/75; regen 1+0.12*VIT HP/s,
  0.5+0.06*WIS MP/s, source effects/precedence. GetDex is not called anywhere else
  in the inspected server; reciprocal(GetDex*RateOfFire) is not a proven server
  scheduling expression. No production stat/attack/growth port is included.
- `realm/entities/player/Player.cs:150-161,947-978`: source stat order and integer
  regen accumulator; `Player.Effects.cs:73-85`: sick/bleeding/oxygen/quiet gates.
- `Player.Projectile.cs:5-13`: source random attack float → integer projectile damage.
- `Player.Leveling.cs:196-225`: random inclusive XML min/max increases, cap at class
  max, levels through 20. Not deterministic by level alone; no invented set_level.
- `db/data/Descriptors.cs:221-281,448-528`: ProjectileDesc and Item including default
  RateOfFire=1, optional trajectories, NumProjectiles/ArcGap. Definitions present.
- `db/data/dat1.xml:28509-28533`: Fire Wand (20–35 source random max-exclusive);
  `33878-33905`: Energy Staff (180 speed,475 ms,amplitude0.5,frequency2,two shots);
  `75057-75085`: Wizard class start/caps/growth definitions. No missing XML claimed.
- `Structures.cs:172-304`: TimedPosition, Position, ObjectDef, ObjectStats;
  `networking/svrPackets/{MapInfo,Update,NewTick,AllyShoot,Shoot,Shoot2}Packet.cs`.

## Original command payloads / validation observations

MOVE (`PacketIds.cs`: ID87): int32 tickId,int32 time,float32 x,float32 y,
int16 record count, records[int32 time,float32 x,float32 y].
`MoveHandler.cs:20-48` flushes, rejects paralyzed or position component -1, then
accepts packet position and calls ClientTick. `CheckLabConditions:53` indexes map
using packet coordinates before any bounds/finite/speed validation in this handler.
This is an upstream validation defect; frontend input does not repair server trust.

PLAYERSHOOT (ID13): int32 time,byte bulletId,int16 containerType,float32 x,y,
float32 angle. `PlayerShootHandler.cs:26-67` directly indexes Items by containerType,
finds matching first-four inventory entry but defaults slot to0 when absent,
checks slot type for rank<2, selects Projectiles[0], creates server-owned shot/damage.
No finite angle/origin/cadence/strict inventory-membership validation in this handler.
ENEMYHIT handler forces server projectile hit; PLAYERHIT handler resolves owner+bullet
and applies original server damage/effects. Parent must preserve required ack flows.

## Proof

`node --test tests/fsod-frontend.test.mjs` imports first, launches actual Godot4.6
SceneTree selftests with isolated HOME, verifies process exit/PASS/no-script-error,
then uses xvfb-run GL rendering for two real 1280×720 PNG frames. Tests cover stat
updates/removals/freed and queued nodes, sparse tiles, authoritative interpolation,
normalized independent prediction while firing, unsnapped aim, no fabricated HUD,
BulletType resolution, source speed/lifetime/trajectory projections and optional
geometry-gated hit reports without damage. Scratch HOME/frames are removed finally.
`FSOD_PROOF_DIR` optionally copies actual PNGs to the explicitly supplied evidence dir.

Run `bash scripts/verify.sh --fast` in a private bwrap `/tmp` namespace to isolate
its hard-coded `/tmp/gravebag-verify-tests.log`; retain gate stdout and copied test
log under the run evidence directory. Nothing starts/restarts the live desktop game.
Fresh-clone, isolated-HOME verification is required after commit; parent owns routing
and live original-server end-to-end proof (not claimed by these synthetic fixtures).
