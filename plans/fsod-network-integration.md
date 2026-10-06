# Original FSoD backend / Godot client bridge

**Client transport delivered; no full game/backend integration claim.**
C# server is the ONLY gameplay authority. No AI, loot, world, stat or combat
behavior port is included in this branch. No existing game/cache code changed;
no game restarted. Parent integrates the client with generated Godot visuals.

## Provenance and branch separation

FSoD `/home/jay/fsod-ref` at `6fd20aad4a7905b13f25389c68368a942a2b68cb`,
AGPLv3. Adapted packet data and public RC4 protocol constants only; no assets,
SWF, DLL, server binaries, account credentials or private RSA key included.
`src/net/fsod/LICENSE` is upstream LICENSE verbatim; each script attributes its
source. `ids.gd` retains original ossimc82-generated-file credit.
Sources inspected: all concrete `networking/cliPackets/*.cs` and
`svrPackets/*.cs`, `Packet.cs`, `NetworkHandler.cs`, `Client.cs`, `RC4.cs`,
`Structures.cs`, `PacketIds.cs`, `realm/Stats.cs`, `db/NReader.cs`/`NWriter.cs`.
Line-numbered audit: `/home/jay/.pi/agent/runs/generalist-muwwmei65/evidence/packet-audit.md`.

Old GDScript AI reference remains ONLY on separate `fsod/combat` history at
`2c37a96520c7d45db5a513f073e2fb9526946326`.
Current `fsod/network` branched from its original base, not that partial port.
Do not integrate that abandoned reference as a second gameplay authority.
Old combat note's claim of16 selftests was erroneous; the actual log says8.

## Parent usage

```gdscript
const FSoDClient = preload("res://src/net/fsod/client.gd")
var network = FSoDClient.new()
add_child(network)
network.configure_login({"GUID": encrypted_guid, "Password": encrypted_password})
network.connected.connect(func(): network.send_hello())
network.packet_received.connect(on_packet)
network.map_info_received.connect(on_map)
network.connect_to_server(host, port)
# After MapInfo choose ONE, according to authoritative account characters:
# network.send_load(character_id, false)
# network.send_create(class_type, skin_type)
```

No automatic Hello/Create/Load/account choice, no plaintext encryption, no
automatic redirect on Reconnect. The separately owned account helper supplies
Base64 RSA ciphertext strings as GUID/Password (not plaintext). Callers must
NOT print login dictionaries. `configure_login` PATCHES existing parameters:
portal GameId/KeyTime/Key changes retain previously supplied ciphertext. A
new account must explicitly replace GUID and Password. `_exit_tree` clears login.

Defaults, from source: BuildVersion `27.3.2` (`Client.cs.SERVER_VERSION`),
GameId `-2` (`World.cs.NEXUS_ID`), IgnoredInt0, randomint1=0, Secret='',
KeyTime0, Key empty bytes, MapInfo empty bytes, obf1..obf5=''. GUID and Password
have no usable default; `send_hello` rejects empties. No default class or char.
HELLO byte order follows SERVER Hello.Read, NOT asymmetric client Hello.Write:
BuildVersion:utf16,GameId:i32,GUID:utf16,IgnoredInt:i32,Password:utf16,
randomint1:i32,Secret:utf16,KeyTime:i32,Key:bytes16,MapInfo:bytes32,
obf1..obf5:utf16. All numeric fields network endian.

## API

- `connect_to_server(host,port)->Error`; `disconnect_from_server(reason)`;
  `poll()` (also called by `_process`); `client_time_ms()`; `configure_login(dict)`.
- `send_packet(id, PackedByteArray plaintext_body)->Error`: bounds, framing,
  continuous directional RC4 once. Intended for separate inventory helpers.
- `send_fields(id, PascalCase_fields)->Error`: only the client schemas listed below.
- `send_hello`, `send_create(class_type,skin_type=0)`,
  `send_load(character_id,from_arena=false)`,
  `send_move(tick_id,time_ms,Vector2_tiles,records=[])`,
  `send_shoot(time_ms,bullet_id,container_type,Vector2_tiles,angle_radians)`.
- `send_pong(serial,time_ms)`, `send_update_ack()`, `send_goto_ack(time_ms)`,
  `send_shoot_ack(time_ms)`, `send_aoe_ack(time_ms,Vector2_tiles)`.
- Signals `connected`, `disconnected(reason)`, `protocol_error(reason)`;
  **`packet_received(id,fields)`** plus `map_info_received`, `entities_received`,
  `tick_received`, `death_received`, `failure_received`, `reconnect_received`,
  `goto_received`, `damage_received`, `aoe_received` (each one Dictionary), and
  `projectile_received(id,fields)` for SHOOT/SHOOT2/ALLYSHOOT.
- `object_id`, `character_id` set by CREATE_SUCCESS. `auto_ack=true` by default.
  UPDATE→UPDATEACK; PING→PONG(serial/client clock); GOTO→GOTOACK; both
  SHOOT and SHOOT2→SHOOTACK. Ack queues after signals, so a callback closing
  or reconnecting cannot send stale-session acknowledgements. Disable auto_ack
  only if another owner sends these. NEW_TICK requires caller's send_move with
  actual records; AOE requires caller's actual position for send_aoe_ack.

## Canonical decoded fields (source names retained)

Position/StartingPos/PosA/PosB are `Vector2` in **source TILE units**. All angles
are **radians** on the wire. TickTime and Time are **milliseconds**. Codec does
NOT convert any positions or times. Frontend projection uses one explicit
scale (current realm TILE_SIZE64 pixels); do not feed world pixels to send_move.

- MAPINFO65: Width,Height,Name,ClientWorldName,Seed,Background,Difficulty,
  AllowTeleport,ShowDisplays,ClientXML,ExtraXML. XML strings use **length32**
  because original SERVER.Write does, despite SERVER.Read incorrectly using16.
- UPDATE7: Tiles `[{X,Y,Tile}]`, NewObjects `[{ObjectType,Stats:ObjectStats}]`,
  RemovedObjectIds `[int]`.
- NEW_TICK80: TickId,TickTime,UpdateStatuses `[ObjectStats]`.
- ObjectStats: `{Id,Position,Stats:[{Type,Value}]}` (ordered array, not dictionary).
  UTF Values for types31 Name,38 AccountId,54 OwnerAccountId,62 Guild,82 PetSkin;
  all others int32. Follows `StatsType.IsUTF` in SERVER.Write, NOT the asymmetric
  ObjectStats.Read which recognizes only Name/Guild.
- CREATE_SUCCESS33: **ObjectID,CharacterID** (capital ID, unlike ObjectStats.Id).
- SHOOT96 (EnemyShoot): BulletId,OwnerId,BulletType,Position,Angle,Damage,
  NumShots (default1),AngleInc (default0). Optional tail is exactly5 bytes.
  Angle is already the FIRST shot, not fan center; directions angle+i*AngleInc.
  BulletType indexes owner's XML Projectile; client looks up speed/lifetime/path.
- SHOOT2=84 (ServerPlayerShoot): BulletId,OwnerId,ContainerType **int32**,
  StartingPos,Angle,Damage. Client PLAYERSHOOT13 instead has ContainerType int16.
- ALLYSHOOT92: BulletId,OwnerId,ContainerType int16,Angle. No position; use owner.
- GOTO3: ObjectId,Position. RECONNECT21: Name,Host,Port,GameId,KeyTime,
  IsFromArena,Key(bytes). DEATH63: AccountId,CharId,Killer,obf0,obf1.
- FAILURE0: ErrorId,ErrorDescription. DAMAGE51: TargetId,Effects (raw byte
  effect-index ARRAY),Damage,Killed,BulletId,ObjectId. Do not reinterpret indices
  using C#'s masked32-bit shifts. AOE69: Position,Radius,Damage,Effects(byte),
  EffectDuration,OriginType; commented-out Color is NOT transmitted.
- All other concrete source server packet layouts are listed in
  `Codec.SERVER_SCHEMAS` (47 IDs). UTF strings decode strictly; unknown IDs are
  surfaced as `{Unsupported:true,RawPayload:decrypted_body}` without losing RC4
  position. These other layouts have source inspection, not independent golden
  coverage for every feature. No all-game-complete claim.

## Outbound supported command matrix

All have independent literal binary fixture tests. `p`=two float32 tiles,
`slot`=ObjectId:i32,SlotId:u8,ObjectType:u16; arrays are length16.

| Name / ID | Exact SERVER.Read payload |
|---|---|
| HELLO35 | see explicit login order above |
| CREATE78 | ClassType:u16,SkinType:u16 (server reads signed16; same wire bits) |
| LOAD8 | CharacterId:i32,IsFromArena:bool |
| MOVE87 | TickId:i32,Time:i32,Position:p,Records:[{Time:i32,Position:p}] |
| PLAYERSHOOT13 | Time:i32,BulletId:u8,ContainerType:i16,Position:p,Angle:f32 |
| PONG52 | Serial:i32,Time:i32 |
| UPDATEACK45 / ESCAPE47 | empty |
| GOTOACK12 / SHOOTACK36 | Time:i32 |
| AOEACK95 / GROUNDDAMAGE59 | Time:i32,Position:p |
| ENEMYHIT42 | Time:i32,BulletId:u8,TargetId:i32,Killed:bool |
| PLAYERHIT17 | BulletId:u8,ObjectId:i32 |
| OTHERHIT14 | Time:i32,BulletId:u8,ObjectId:i32,TargetId:i32 |
| SQUAREHIT86 | Time:i32,BulletId:u8,ObjectId:i32 |
| USEPORTAL9 | ObjectId:i32 |

**Missing typed outbound commands** (`send_fields` rejects; raw send_packet can
carry separately owned helper payloads). Complete concrete-cli-file matrix:

| Name / ID | Exact SERVER.Read payload, not implemented here |
|---|---|
| ACCEPTTRADE6 | MyOffers:bool[],YourOffers:bool[] |
| BUY75 | ObjectId:i32 |
| CANCELTRADE5 / CHECKCREDITS19 / VIEWQUESTS16 | empty |
| CHANGEGUILDRANK89 | Name:utf16,GuildRank:i32 |
| CHANGETRADE1 | Offers:bool[] |
| CHOOSENAME82 / CREATEGUILD44 | Name:utf16 |
| EDITACCOUNTLIST93 | AccountListId:i32,Add:bool,ObjectId:i32 |
| ENTER_ARENA27 | Currency:i32 |
| FAILURE0 (client-side class) | ErrorId:i32,ErrorDescription:utf16 |
| GUILDINVITE23 / GUILDREMOVE24 / REQUESTTRADE41 | Name:utf16 |
| INVDROP90 | SlotObject:slot |
| INVSWAP34 | Time:i32,Position:p,SlotObject1:slot,SlotObject2:slot |
| JOINGUILD61 | GuildName:utf16 |
| LEAVEARENA49 | _li:i32 |
| PETCOMMAND57 | CommandId:u8,PetId:i32 |
| PETYARDCOMMAND85 | CommandId:u8,PetId1:i32,PetId2:i32,ObjectId:i32,ObjectSlot:slot,Currency:u8 |
| PLAYERTEXT39 | Text:utf16 |
| RESKIN68 | SkinId:i32 |
| SETCONDITION91 | ConditionEffect:i32,ConditionDuration:f32 |
| TELEPORT40 | ObjectId:i32 |
| TINKERQUEST38 | Object:slot |
| USEITEM48 | Time:i32,SlotObject:slot,ItemUsePos:p,UseType:u8 |

Enum-only or absent concrete source packet classes have no guessed layout here.
Login RSA crypto, character discovery, inventory commands, collision reporting,
local own-shot rendering, projectile XML/path interpretation and backend
lifecycle all belong to parent/other assigned modules. send_packet is available
without accepting a parallel authority. Do not auto-report hypothetical hits:
use original client collision model and server-issued projectile identities.

## Bounds, timing, lifetimes

Original BUFFER_SIZE=int.MaxValue/4096=524287 body bytes. Max total frame524292,
receive buffer1048584, outbound pending bound1048584, read/write at most65536
bytes/poll, at most1024 frames parsed/poll. Complete queued frames drain next
poll. Signed16 UTF/key byte lengths max32767; arrays max32767 decoded items;
bitmap dimensions and body lengths checked before reads/allocation. Strict bool,
UTF8 and finite float32 validation intentionally rejects malformed inputs rather
than reproducing tolerant .NET reader behavior. No packet/header/body resync
following corruption; error closes connection and clears queues/ciphers.
Connect deadline10s; partial-buffer deadline15s. Test loops use5s+300-frame
attempt caps. All I/O nonblocking StreamPeerTCP partial reads/writes.

Directional RC4 stream starts fresh only on new connection. Header/ID clear,
only body encrypted. Empty bodies consume zero keystream. Unknown IDs STILL
consume body keystream once. Public server SendKey becomes client receive;
public server ReceiveKey becomes client send. No cipher resets per packet.

## Evidence and checks

`node --test tests/fsod-network.test.mjs` imports REAL Godot4.6 project in a
scratch copy with isolated HOME/XDG and no .godot cache, checks exit code,
PASS marker AND absence of script/parse errors, deletes scratch in finally.
106 assertions passed, including two independent standard RC4 vectors,
public directional ciphertext fixtures, every split boundary, one-byte reads,
coalescing, unknown packet followed by known packet, reconnect cipher reset,
work budget, bounds/truncation/NaN, golden commands and actual local TCP ack flow.

MapInfo/NewTick/Update literals are independently emitted by original C#
protected Write via reflection, parent commit
`5777822e4a1c22dd44768c0c12abe80e03135c0b`, not self-codec roundtrips. Required
other packets use literal hex from their inspected source byte order.

`bash scripts/verify.sh --fast`: **VERIFY PASS**,8 selftests passed.
Bubblewrap isolates original scripts' hardcoded /tmp logs into owned
`src/net/fsod/.test-output/tmp/`, and binds a disposable .godot/HOME from a
unique /tmp build directory. Source tree tracked cache remains unchanged.
Node logs: `src/net/fsod/.test-output/node-{import,selftest,test}.log`.
Gate log: `src/net/fsod/.test-output/verify-fast.log`.

Remaining proof gaps: no live original backend connect/auth/create/load/map walk,
no actual reconnect across worlds, no client collision/hit or inventory/UI
integration in this scoped delivery. Server fixture codecs beyond listed golden
cases need end-to-end coverage when their frontend features are integrated.
The three upstream READ/WRITE asymmetries are noted, not patched in original C#;
server behavior otherwise remains original. Parent owns CI/merge/install; this
worker does not wait for CI or claim merge/install approval.
