<!-- Provenance: FSoD /home/jay/fsod-ref at 6fd20aad4a7905b13f25389c68368a942a2b68cb;
upstream LICENSE: GNU Affero General Public License v3. Source observations below;
no upstream art, binaries, or replacement gameplay implementation included. -->
# FSoD inventory and gameplay command payload codec

## Scope after operator pivot

Preserve the original C# backend. The approved Godot client bridge lives at
`src/net/fsod_inventory/commands.gd`, class `FsodGameplayCommands` (RefCounted,
static helpers). It serializes **39 outgoing command payloads**, not inventory
rules or a replacement backend. No RefCounted inventory replacement was written
before the pivot; `src/systems/fsod_inventory/` remains absent. Original backend
handlers remain authoritative. No art/binaries were copied, no live window was
restarted, and no randomized item stat rolls or damage calculations are introduced.

Each command returns **Dictionary{id:int,payload:PackedByteArray}**, or **{}**
on invalid input. Parent passes valid output to `send_packet(packet.id,
packet.payload)` in `src/net/fsod/`. Do not send an empty/error Dictionary.
Helpers do not do framing, RC4, connection/session handling or state mutation.

All source paths below are relative to `/home/jay/fsod-ref`, verified at
`6fd20aad4a7905b13f25389c68368a942a2b68cb` (requested `6fd20aa`).
The provenance header must follow any future copied/adapted source.

## Commands and byte layouts

Numbers and IEEE-754 floats are big-endian (`db/NReader.cs:16-57`,
`db/NWriter.cs:21-67`). TCP packet framing is **length i32 including the 5-byte
header**, **packet ID u8**, then encrypted body (`wServer/networking/Packet.cs:42-52`).
Body encryption uses stateful, directional RC4 streams; see `wServer/networking/
cliPackets/ClientPacket.cs:3-8`, `svrPackets/ServerPacket.cs:3-8`, and
`Client.cs:40-50`. A plaintext WebSocket/JSON payload is not this protocol.
Transport/session/login implementation is outside this inventory handoff.

Shared structures (`wServer/Structures.cs:144-163,197-222`):

- `Position`: x f32, y f32 (8 bytes).
- `ObjectSlot`: object/entity ID i32, slot ID u8, item object type u16 (7 bytes).
  Empty item's type is the 0xffff bit pattern; stats use signed -1 instead.
  ObjectSlot.Read casts an i16 to u16; preserve all 16 bits.

Packet IDs are source-specific, not generic RotMG constants
(`wServer/PacketIds.cs:15-25`). Body field order:

- **INVSWAP = 34**: Time i32, Position, SlotObject1, SlotObject2 (26 bytes).
  `wServer/networking/cliPackets/InvSwapPacket.cs:20-33`.
- **USEITEM = 48**: Time i32, SlotObject, ItemUsePos Position, UseType u8
  (20 bytes). `wServer/networking/cliPackets/UseItemPacket.cs:21-34`.
  UseType is serialized but is not consulted by the inspected UseItemHandler or
  Player.Activate. Do not invent meaning for it; zero can be a client policy,
  not a newly asserted backend rule.
- **INVRESULT = 58**: Result i32 (4 bytes), 0 success / -1 failure in the
  inspected swap paths (`svrPackets/InvResultPacket.cs:17-24`). No request ID.
  Serializing pending UI swaps avoids attributing an uncorrelated result to the
  wrong drag. Inventory/stat updates, not a success result alone, settle state.

### UI intent adapters (parent-owned UI; helpers serialize intents only)

- `pickup(bag_id, bag_index, player_index)`: INVSWAP, bag slot first, player
  slot second. Select an empty player slot 4..11 from authoritative state;
  **never clear/despawn the bag locally**. With no room, do not send a command.
- `equip(index)`: map UI inventory index 0..7 to source index 4..11;
  send INVSWAP from that slot to one of player source slots 0..3, based on
  exact class SlotTypes. This is also an unequip/exchange if gear was occupied.
- `swap(from_slot,to_slot)`: encode both authoritative ObjectSlots, including
  current item types. UI drag slots are not the same as stat IDs.
- `consume_potion(kind)`: USEITEM, player's entity ID, slot 254 with object type
  0x0a22 for health or slot 255 with type 0x0a23 for magic. Ordinary potion items
  in inventory use their actual slot instead. Do not decrement counts locally.
- `equipment_stats()` / `snapshot()`: read-only views of the decoded server
  cache; return copied records/labels. No stat recomputation or mutation on read.

## Source dimensions and rules (not a replacement rules engine)

Player XML provides 12 slots: gear 0 weapon, 1 ability, 2 armor, 3 ring; inventory
4..11. Backpack extends the original player to 20 slots, adding 12..19
(`realm/entities/player/Player.cs:112-150`; `Player.UseItem.cs:244-262`).
The current 4+8 UI is the unexpanded source layout, **not** permission to
silently discard server backpack entries. Preserve all received entries in the
cache even if the UI does not expose a backpack yet.

Class-specific exact types matter, not just four broad categories:
`db/data/dat1.xml:75068` Wizard = [17,11,14,9]; `75133` Warrior = [1,16,7,9];
`75166` Knight = [1,5,7,9]. Remaining XML slot types 0 become universal type 10
in `Player.cs:166-172`. `realm/Utils.cs:288-291` accepts empty items, universal
slots, or an exact item SlotType match. Four occupied gear items need not belong
to the same class by broad labels; the numeric checks decide.

Bags are 8-slot Containers (`realm/entities/Container.cs:19-28`). Ordinary swaps
run in a queued Networking action, reject distance >1 and validate before the
paired writes (`networking/handlers/InvSwapHandler.cs:37-43,87-109,164-165`).
This is sequential authoritative handling, **not** a general ACID transaction
or an assertion that every branch is safe. Player/player swaps validate both
ways; invalid equipment can disconnect instead of returning a benign failure.
A normal bag-to-player exchange can return the displaced item into the bag;
public-bag soulbound items get rerouted through DropBag. OneWayContainer has
separate gift/discard semantics. Do not route all container classes through a
single optimistic frontend exchange.

Health/magic stack counters are separate from inventory, capacity 6 each in the
stack pickup branch (`InvSwapHandler.cs:45-78`), with pseudo-slots 254/255.
They are persisted separately in `db/Models.cs:445-461` and
`Player.cs:663-664`. UseItemHandler decrements positive counters; its empty-stack
path may buy with credits and still reaches Activate even if no purchase occurs
(`UseItemHandler.cs:49-142,150-244`). See findings below before exposing stack
commands to a new client. No local free-heal policy is authorized by this note.

## Authoritative updates: IDs and records

Initial world UPDATE = 7 contains tile list, new ObjectDefs, removed entity IDs
(`networking/svrPackets/UpdatePacket.cs:24-66`). ObjectDef = object type u16 then
ObjectStats (`Structures.cs:230-245`). NEW_TICK = 80 contains TickId i32,
TickTime i32, status count u16, then ObjectStats per entity
(`networking/svrPackets/NewTickPacket.cs:20-37`). Status inclusion uses entity
UpdateCount (`realm/entities/player/Player.Update.cs:193-224`).

ObjectStats = entity ID i32, Position, stat count u16, then repeated stat ID u8
plus value. Inventory/stat values are i32; UTF stats instead carry byte-length
u16 + UTF-8 bytes. **Decode using StatsType.IsUTF, not just Guild/Name:** the
server writer also serializes AccountId, OwnerAccountId and PetSkin as UTF
(`Structures.cs:248-283`; `realm/Stats.cs:123-130`). The generic source reader
only special-cases Guild/Name and is not a safe template for a new client decoder.

`realm/Stats.cs:13-39,71-79,91-102` and `Player.cs:347-397` establish:

- Player stat IDs **8..19** = source inventory slots **0..11**, value item
  object type or -1 empty. Bag stat IDs **8..15** = bag slots **0..7**
  (`realm/entities/Container.cs:61-74`).
- **69** = health stack count; **70** = magic stack count.
- **71..78** = backpack slots **12..19**; **79** = Has_Backpack.
- Final stat totals: max HP **0**, max MP **3**, attack **20**, defense **21**,
  speed **22**, vitality **26**, wisdom **27**, dexterity **28**.
- Bonus amounts: HP **46**, MP **47**, attack **48**, defense **49**, speed **50**,
  vitality **51**, wisdom **52**, dexterity **53**. These are already included
  in totals; **do not add bonuses again in the Godot client**.

Item labels/records are descriptor lookup by object type, not strings received
in inventory slot updates. XML is present (`db/data/dat0.xml`, `dat1.xml`,
`Addition.xml`, `EquipmentSets.xml`). `Descriptors.cs:455-519` extracts exact
SlotType, Consumable/Potion flags, ActivateOnEquip stat/amount pairs, Activate
use effects and projectile definitions. `Player.cs:408-434` sums only equipped
0..3 stat boosts plus set-type bonuses; `Player.Inventory.cs:15-49` controls
matching-set skin/bonuses. Do not assume a weapon's projectile damage is an
Attack stat contribution, or omit set bonuses by recalculating locally.

Fixed real examples: Health Potion 0x0a22 and Magic Potion 0x0a23, SlotType 10,
Consumable/Potion flags, Heal/Magic amount 100 respectively
(`db/data/dat1.xml:30806-30841`). Effects are clamped to max HP/MP server-side
(`Player.UseItem.cs:102-147`). No fixtures or art have been copied.

## Source gaps / upstream findings (outside owned writable scope)

1. `InvSwapHandler.cs:45-78`: pseudo-slot handling bypasses normal distance/type
   validation; magic-stack withdrawal indexes con2 using SlotObject1.SlotId
   (255), not destination. Quoted source at line 69:
   `con2.Inventory[packet.SlotObject1.SlotId] = null;`
   That exceeds an ordinary 8/12/20-slot inventory. Preserve backend ownership;
   add source-handler validation/bounded destination regression tests before
   exposing withdrawal. Do not claim all swaps are atomic or safe.
2. `UseItemHandler.cs:49-142,242-244`: an empty health stack with insufficient
   credits does not return before `client.Player.Activate(t, item, packet)`;
   the real Health Potion Heal effect may still run. Magic has the analogous
   path (`UseItemHandler.cs:150-238`). Add backend regression coverage for zero-count/no-credit usage and
   require a validated potion debit before activation in the owning module.
3. `Structures.cs:261-266` vs `281`: ObjectStats.Read only treats Guild/Name
   as UTF whereas Write uses the broader StatsType.IsUTF predicate. Reusing
   that reader in a Godot bridge desynchronizes statuses containing account /
   owner / pet-skin strings. The client decoder must follow the actual writer;
   any backend reader repair remains an upstream change, not this task.

4. `InvDropHandler.cs:45-55` decrements pseudo-slot potion counts unconditionally:
   `client.Player.HealthPotions--;` and `client.Player.MagicPotions--;`.
   Zero-count drops can make counters negative and create a potion. The owning
   backend must require an available potion before decrementing/spawning; the
   pure wire codec does not mutate counters or claim this source rule is safe.
5. `networking/handlers/OtherHitHandler.cs:18-21` is a TODO/no-op. Serializing
   OTHERHIT exactly does not implement a missing server effect. Keep this source
   limitation visible in acceptance; any gameplay repair belongs to that handler.

## Function / packet coverage matrix

All rows are covered by fixed golden byte fixtures in
`src/net/fsod_inventory/selftest.gd`. Layout notation: i32 signed integer,
u32/u16/u8 unsigned wire bits, f32 float, bool single 0/1 byte,
UTF = signed-safe u16 byte count + UTF8, pos = two f32, slot = i32+u8+u16.
Source is `wServer/networking/cliPackets/<Name>Packet.cs` with the corresponding
uppercase `wServer/PacketIds.cs` entry, unless noted.

| Function (arguments in wire order) | Source packet / ID | Payload |
|---|---|---|
| inv_swap(time, position, source, destination) | InvSwap / 34 | i32,pos,slot,slot |
| use_item(time, slot, position, use_type=0) | UseItem / 48 | i32,slot,pos,u8 |
| inv_drop(slot) | InvDrop / 90 | slot |
| request_trade(name) | RequestTrade / 41 | UTF |
| change_trade(offers) | ChangeTrade / 1 | u16 count, bool[] |
| accept_trade(my_offers, your_offers) | AcceptTrade / 6 | u16 count,bool[],u16 count,bool[] |
| cancel_trade() | CancelTrade / 5 | empty |
| create_guild(name) | CreateGuild / 44 | UTF |
| join_guild(guild_name) | JoinGuild / 61 | UTF |
| guild_invite(name) | GuildInvite / 23 | UTF |
| guild_remove(name) | GuildRemove / 24 | UTF |
| change_guild_rank(name, rank) | ChangeGuildRank / 89 | UTF,i32 |
| player_text(text) | PlayerText / 39 | UTF |
| teleport(object_id) | Teleport / 40 | i32 |
| escape() | Escape / 47 | empty |
| use_portal(object_id) | UsePortal / 9 | i32 |
| buy(object_id) | Buy / 75 | i32 |
| check_credits() | CheckCredits / 19 | empty |
| edit_account_list(list_id, add, object_id) | EditAccountList / 93 | i32,bool,i32 |
| choose_name(name) | ChooseName / 82 | UTF |
| set_condition(effect, duration) | SetCondition / 91 | i32,f32 |
| reskin(skin_id) | Reskin / 68 | i32 |
| pet_command(command_id, pet_id) | PetCommand / 57 | u8,u32 (source casts to i32 on write) |
| pet_yard_command(command_id, pet_id1, pet_id2, object_id, slot, currency) | PetYardCommand / 85 | u8,i32,i32,i32,slot,u8 |
| enter_arena(currency) | EnterArena / 27 | i32 |
| leave_arena(source_li) | LeaveArena / 49 | i32 (not empty) |
| view_quests() | ViewQuests / 16 | empty |
| tinker_quest(slot) | TinkerQuest / 38 | slot |
| enemy_hit(time, bullet_id, target_id, killed) | EnemyHit / 42 | i32,u8,i32,bool |
| player_hit(bullet_id, object_id) | PlayerHit / 17 | u8,i32 (no time field) |
| other_hit(time, bullet_id, object_id, target_id) | OtherHit / 14 | i32,u8,i32,i32 |
| ground_damage(time, position) | GroundDamage / 59 | i32,pos |
| square_hit(time, bullet_id, object_id) | SquareHit / 86 | i32,u8,i32 |
| aoe_ack(time, position) | AoEAck / 95 | i32,pos |
| goto_ack(time) | GotoAck / 12 | i32 |
| shoot_ack(time) | ShootAck / 36 | i32 |
| update_ack() | UpdateAck / 45 | empty |
| pong(serial, time) | Pong / 52 | i32,i32 |
| failure(error_id, description) | cliPackets/Failure / 0 | i32,UTF |

`slot_record(object_id,slot_id,object_type)` returns the three-field Dictionary;
it accepts -1 as the empty item sentinel and normalizes that to 65535. Every
command serializes supplied records without mutation; snapshots/stats/UI state
belong to the parent, not this pure command module.

### Bounds and deliberate client adapters

- Integers must actually be Variant INT, not float/string/bool coerced to int.
  i32 accepts -2147483648..2147483647, u8 0..255, u16 0..65535 (plus the
  record -1 empty-item adapter), PetId u32 0..4294967295. No wrapping/truncation.
- Positions must be Vector2; f32 fields reject nonfinite or out-of-range values.
- Strings must be String and <=32767 UTF8 **bytes**, not characters. Source
  ReadUTF uses signed ReadInt16, so the apparent u16 capacity is not 65535.
- Trade offers must be Array of exactly **12 bools**. Packet serializers have
  variable length, but `Player.Trade.cs:42-67` and `TradeManager.cs:34-35,53-87`
  allocate/index twelve slots, and accept compares against twelve entries.
  This bound is an explicit client adapter, not a new randomized gameplay rule.
- Empty chat is rejected because `PlayerTextHandler.cs:25` indexes Text[0].
  Other UTF commands still serialize empty strings for backend validation.
- No guild ranks/currency permissions/item equip restrictions/cooldowns are
  guessed or enforced here. These remain server responsibilities.
- EnemyHit includes the source Killed flag but `EnemyHitHandler.cs:24-33` uses
  projectile ForceHit instead of trusting a client damage amount. PlayerHit
  identifies the server projectile and calls server Damage; GroundDamage reads
  the server tile and calculates damage. The helpers only encode notifications.
- SETCONDITION has a source packet class but no matching handler file in the
  inspected handlers directory; client FAILURE also has a source class but no
  handler. A serialized source command is not a claim of server functionality.

### Complete missing-command list / ownership boundary

The inspected cliPackets directory contains 45 files: abstract ClientPacket,
39 concrete commands here, and **five** intentionally delegated to the core
network owner: **Hello 35, Create 78, Load 8, Move 87, PlayerShoot 13**.
No other concrete client command file is omitted by this matrix. Confirm those
five in the parent's acceptance matrix; this module does not send them.

`PacketIds.cs` declares **90** entries (source comments slotid 1..90), not 91
client commands. `networking/Packet.cs:71-76` additionally defines NopPacket ID
255, giving 91 identities if the sentinel is included in the full catalog.
Other entries are server messages, and some have no client class in this source.
A full 91-identity transport/receive catalog is parent-owned; the 39 outgoing
helpers must not be misreported as full server-message support.

## Delivery / verification boundaries

`node --test tests/fsod-inventory-wire.test.mjs` is the authorized receipt check.
The Node adapter creates a temporary Godot project and HOME, imports first,
runs the owned SceneTree golden fixtures, checks exit/PASS/no script errors,
and removes its scratch data in finally. It needs a Godot 4.6 executable on PATH
or the existing `/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64`.

The declared check is additionally rerun in a fresh clone with an isolated HOME.
`bash scripts/verify.sh --fast` is run there under a private /tmp mount so
`/tmp/gravebag-verify-tests.log` cannot collide with other workers. Results/log
hashes live in the worker evidence receipt. This branch is committed/pushed,
not merged; parent owns integration, CI and install.
No backend build, live-server integration, transport/session handshake, damage
calculation, inventory rules implementation or inventory UI wiring is claimed.
