# SPDX-License-Identifier: AGPL-3.0-only
# FSoD wire fixtures: 6fd20aad4a7905b13f25389c68368a942a2b68cb,
# wServer/PacketIds.cs, Structures.cs, networking/cliPackets; upstream AGPLv3.
# Fixed source serialization examples, NOT inventory/backend gameplay fixtures.
extends SceneTree

const Commands = preload("res://src/net/fsod_inventory/commands.gd")
var failures := 0
var checks := 0


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)


func _gold(packet: Dictionary, id: int, hex: String, label: String) -> void:
	_check(packet.size() == 2 and packet.has_all(["id", "payload"]), label + " shape")
	if not packet.has_all(["id", "payload"]):
		return
	_check(typeof(packet.id) == TYPE_INT and packet.id == id, label + " source ID")
	_check(typeof(packet.payload) == TYPE_PACKED_BYTE_ARRAY, label + " payload type")
	_check(packet.payload == hex.replace(" ", "").hex_decode(), label + " golden bytes")


func _initialize() -> void:
	var source := Commands.slot_record(0x01020304, 4, 0x0a22)
	var destination := Commands.slot_record(0x05060708, 11, -1)
	var my: Array = [false, false, false, false, true, false, true, false, false, true, false, false]
	var their: Array = [false, false, false, false, false, true, false, true, false, false, false, true]
	_gold(Commands.inv_swap(0x11223344, Vector2(1.0, -2.5), source, destination), 34,
		"11223344 3f800000 c0200000 01020304 04 0a22 05060708 0b ffff", "INVSWAP")
	_gold(Commands.use_item(0x11223344, source, Vector2(1.0, -2.5), 7), 48,
		"11223344 01020304 04 0a22 3f800000 c0200000 07", "USEITEM")
	_gold(Commands.use_item(0, Commands.slot_record(1, 254, 0x0a22), Vector2.ZERO), 48,
		"00000000 00000001 fe 0a22 00000000 00000000 00", "health pseudo-slot")
	_gold(Commands.use_item(0, Commands.slot_record(1, 255, 0x0a23), Vector2.ZERO), 48,
		"00000000 00000001 ff 0a23 00000000 00000000 00", "magic pseudo-slot")
	_gold(Commands.inv_drop(source), 90, "01020304 04 0a22", "INVDROP")
	_gold(Commands.request_trade("é"), 41, "0002 c3a9", "REQUESTTRADE UTF8 bytes")
	_gold(Commands.change_trade(my), 1, "000c 00 00 00 00 01 00 01 00 00 01 00 00", "CHANGETRADE")
	_gold(Commands.accept_trade(my, their), 6,
		"000c 00 00 00 00 01 00 01 00 00 01 00 00 000c 00 00 00 00 00 01 00 01 00 00 00 01", "ACCEPTTRADE")
	_gold(Commands.cancel_trade(), 5, "", "CANCELTRADE")
	_gold(Commands.create_guild("Bag"), 44, "0003 426167", "CREATEGUILD")
	_gold(Commands.join_guild("Bag"), 61, "0003 426167", "JOINGUILD")
	_gold(Commands.guild_invite("Jay"), 23, "0003 4a6179", "GUILDINVITE")
	_gold(Commands.guild_remove("Jay"), 24, "0003 4a6179", "GUILDREMOVE")
	_gold(Commands.change_guild_rank("Jay", 20), 89, "0003 4a6179 00000014", "CHANGEGUILDRANK")
	_gold(Commands.player_text("/help"), 39, "0005 2f68656c70", "PLAYERTEXT command")
	_gold(Commands.player_text("😀"), 39, "0004 f09f9880", "PLAYERTEXT astral UTF8")
	_gold(Commands.teleport(0x01020304), 40, "01020304", "TELEPORT")
	_gold(Commands.escape(), 47, "", "ESCAPE")
	_gold(Commands.use_portal(0x01020304), 9, "01020304", "USEPORTAL")
	_gold(Commands.buy(0x01020304), 75, "01020304", "BUY")
	_gold(Commands.check_credits(), 19, "", "CHECKCREDITS")
	_gold(Commands.edit_account_list(1, true, 0x01020304), 93, "00000001 01 01020304", "EDITACCOUNTLIST add")
	_gold(Commands.edit_account_list(0, false, -1), 93, "00000000 00 ffffffff", "EDITACCOUNTLIST remove")
	_gold(Commands.choose_name("Jay"), 82, "0003 4a6179", "CHOOSENAME")
	_gold(Commands.set_condition(5, 2.5), 91, "00000005 40200000", "SETCONDITION")
	_gold(Commands.reskin(0x01020304), 68, "01020304", "RESKIN")
	_gold(Commands.pet_command(2, 4294967295), 57, "02 ffffffff", "PETCOMMAND uint32 bits")
	_gold(Commands.pet_yard_command(2, 1, -1, 0x01020304, source, 3), 85,
		"02 00000001 ffffffff 01020304 01020304 04 0a22 03", "PETYARDCOMMAND")
	_gold(Commands.enter_arena(1), 27, "00000001", "ENTER_ARENA")
	_gold(Commands.leave_arena(0), 49, "00000000", "LEAVEARENA field not empty")
	_gold(Commands.view_quests(), 16, "", "VIEWQUESTS")
	_gold(Commands.tinker_quest(source), 38, "01020304 04 0a22", "TINKERQUEST")
	_gold(Commands.enemy_hit(0x11223344, 5, 0x01020304, true), 42,
		"11223344 05 01020304 01", "ENEMYHIT killed")
	_gold(Commands.enemy_hit(0, 255, -1, false), 42,
		"00000000 ff ffffffff 00", "ENEMYHIT not killed")
	_gold(Commands.player_hit(5, 0x01020304), 17, "05 01020304", "PLAYERHIT no time")
	_gold(Commands.other_hit(0x11223344, 5, 0x01020304, 0x05060708), 14,
		"11223344 05 01020304 05060708", "OTHERHIT")
	_gold(Commands.ground_damage(0x11223344, Vector2(1, -2.5)), 59,
		"11223344 3f800000 c0200000", "GROUNDDAMAGE")
	_gold(Commands.square_hit(0x11223344, 5, 0x01020304), 86,
		"11223344 05 01020304", "SQUAREHIT")
	_gold(Commands.aoe_ack(0x11223344, Vector2(1, -2.5)), 95,
		"11223344 3f800000 c0200000", "AOEACK")
	_gold(Commands.goto_ack(0x11223344), 12, "11223344", "GOTOACK")
	_gold(Commands.shoot_ack(0x11223344), 36, "11223344", "SHOOTACK")
	_gold(Commands.update_ack(), 45, "", "UPDATEACK")
	_gold(Commands.pong(0x11223344, 0x01020304), 52, "11223344 01020304", "PONG serial then time")
	_gold(Commands.failure(7, "bad"), 0, "00000007 0003 626164", "client FAILURE schema")

	# Golden numeric extrema: no host-order dependence, silent wrapping or coercion.
	_gold(Commands.teleport(-2147483648), 40, "80000000", "i32 min")
	_gold(Commands.teleport(2147483647), 40, "7fffffff", "i32 max")
	_gold(Commands.inv_drop(Commands.slot_record(-1, 0, 65534)), 90,
		"ffffffff 00 fffe", "slot item high unsigned")
	_gold(Commands.inv_drop(Commands.slot_record(0, 255, -1)), 90,
		"00000000 ff ffff", "empty item sentinel")
	_gold(Commands.create_guild(""), 44, "0000", "empty UTF serializable")
	_gold(Commands.pet_command(255, 0), 57, "ff 00000000", "byte and uint32 bounds")
	_check(Commands.IDS.size() == 39, "all assigned packet IDs covered")

	for invalid in [-2147483649, 2147483648, 1.0, "1", true, null]:
		_check(Commands.teleport(invalid).is_empty(), "i32 invalid %s" % str(invalid))
	for invalid in [-1, 256, 1.0, "1", null]:
		_check(Commands.use_item(0, source, Vector2.ZERO, invalid).is_empty(), "byte invalid")
	for invalid in [-1, 4294967296, 1.0, null]:
		_check(Commands.pet_command(1, invalid).is_empty(), "uint32 invalid")
	for invalid in [-2, 65536, 10.0, "10", null]:
		_check(Commands.slot_record(1, 4, invalid).is_empty(), "u16 invalid")
	_check(Commands.slot_record(1, -1, 1).is_empty(), "negative slot")
	_check(Commands.slot_record(1, 256, 1).is_empty(), "slot overflow")
	_check(Commands.slot_record("1", 4, 1).is_empty(), "record no ID coercion")
	for invalid in [{}, {"object_id": 1, "slot_id": 4}, [], null]:
		_check(Commands.inv_drop(invalid).is_empty(), "incomplete/wrong slot")
	_check(Commands.inv_swap(0, Vector2.ZERO, source, {}).is_empty(), "invalid destination rejects whole swap")
	_check(Commands.inv_swap(-2147483649, Vector2.ZERO, source, destination).is_empty(), "invalid time rejects swap")
	for invalid in [NAN, INF, -INF, 1e39, "1", null]:
		_check(Commands.set_condition(1, invalid).is_empty(), "float invalid")
	_check(Commands.use_item(0, source, Vector2(INF, 0)).is_empty(), "position non-finite")
	_check(Commands.inv_swap(0, [1, 2], source, destination).is_empty(), "position wrong type")
	_check(Commands.edit_account_list(0, 1, 1).is_empty(), "bool no coercion")
	_check(Commands.edit_account_list(0, true, 2147483648).is_empty(), "invalid later field discards body")
	_check(Commands.pet_yard_command(1, 1, 1, 1, source, 256).is_empty(), "currency no wrap")
	_check(Commands.enemy_hit(0, 256, 1, false).is_empty(), "hit bullet no wrap")
	_check(Commands.enemy_hit(0, 1, 1, 1).is_empty(), "killed bool no coercion")
	_check(Commands.player_hit(-1, 1).is_empty(), "player hit bullet negative")
	_check(Commands.other_hit(0, 1, 1, 2147483648).is_empty(), "other hit target overflow")
	_check(Commands.ground_damage(0, Vector2(0, NAN)).is_empty(), "ground position nonfinite")
	_check(Commands.aoe_ack(0, null).is_empty(), "aoe position wrong type")
	_check(Commands.pong(0, 2147483648).is_empty(), "pong time overflow")
	_check(Commands.failure(0, null).is_empty(), "failure description wrong type")
	_check(Commands.player_text("").is_empty(), "reject empty chat handler indexing")
	for invalid in [null, 10, false, "a".repeat(32768), "é".repeat(16384)]:
		_check(Commands.request_trade(invalid).is_empty(), "UTF invalid bytes/type")
	var largest := Commands.request_trade("a".repeat(32767))
	_check(largest.payload.size() == 32769 and largest.payload[0] == 127 and largest.payload[1] == 255, "signed UTF length maximum")
	for invalid in [[], my.slice(0, 11), my + [false], PackedByteArray([0, 1]), null]:
		_check(Commands.change_trade(invalid).is_empty(), "trade must have twelve booleans")
	var bad_offers := my.duplicate()
	bad_offers[0] = 1
	_check(Commands.change_trade(bad_offers).is_empty(), "trade flag wrong type")
	_check(Commands.accept_trade(my, bad_offers).is_empty(), "accept invalid second array")

	# Inputs are read-only; each packet owns detached bytes.
	var source_before := source.duplicate(true)
	var destination_before := destination.duplicate(true)
	var my_before := my.duplicate()
	var packet := Commands.inv_swap(0, Vector2.ZERO, source, destination)
	_check(source == source_before and destination == destination_before, "swap input records unchanged")
	var bytes: PackedByteArray = packet.payload
	source.object_id = 9
	destination.slot_id = 0
	_check(packet.payload == bytes, "record mutation cannot alter existing bytes")
	var trade := Commands.change_trade(my)
	_check(my == my_before, "trade input unchanged")
	my[4] = false
	_check(trade.payload[6] == 1, "offers mutation cannot alter packet")
	var first := Commands.escape()
	var first_bytes: PackedByteArray = first.payload
	first_bytes.append(123)
	first.payload = first_bytes
	_check(Commands.escape().payload.is_empty(), "fresh empty packet isolation")
	_check(Commands.inv_drop(source_before) == Commands.inv_drop(source_before), "deterministic packet construction")

	if failures == 0:
		print("FSOD INVENTORY WIRE SELFTEST PASS: ", checks, " checks, 39 packet families")
	else:
		printerr("FSOD INVENTORY WIRE SELFTEST FAIL: ", failures, "/", checks)
	quit(0 if failures == 0 else 1)
