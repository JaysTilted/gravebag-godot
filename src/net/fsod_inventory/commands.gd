# SPDX-License-Identifier: AGPL-3.0-only
# Protocol port from FSoD /home/jay/fsod-ref, revision
# 6fd20aad4a7905b13f25389c68368a942a2b68cb: wServer/PacketIds.cs,
# Structures.cs and networking/cliPackets/*.cs; upstream LICENSE AGPLv3.
# Serialization only: no backend gameplay, framing, encryption, or transport.
extends RefCounted
class_name FsodGameplayCommands

const SOURCE_REVISION := "6fd20aad4a7905b13f25389c68368a942a2b68cb"
const IDS := {
	"INVSWAP": 34, "USEITEM": 48, "INVDROP": 90,
	"REQUESTTRADE": 41, "CHANGETRADE": 1, "ACCEPTTRADE": 6, "CANCELTRADE": 5,
	"CREATEGUILD": 44, "JOINGUILD": 61, "GUILDINVITE": 23,
	"GUILDREMOVE": 24, "CHANGEGUILDRANK": 89, "PLAYERTEXT": 39,
	"TELEPORT": 40, "ESCAPE": 47, "USEPORTAL": 9,
	"BUY": 75, "CHECKCREDITS": 19, "EDITACCOUNTLIST": 93, "CHOOSENAME": 82,
	"SETCONDITION": 91, "RESKIN": 68, "PETCOMMAND": 57, "PETYARDCOMMAND": 85,
	"ENTER_ARENA": 27, "LEAVEARENA": 49, "VIEWQUESTS": 16, "TINKERQUEST": 38,
	"ENEMYHIT": 42, "PLAYERHIT": 17, "OTHERHIT": 14, "GROUNDDAMAGE": 59,
	"SQUAREHIT": 86, "AOEACK": 95, "GOTOACK": 12, "SHOOTACK": 36,
	"UPDATEACK": 45, "PONG": 52, "FAILURE": 0,
}
const I32_MIN := -2147483648
const I32_MAX := 2147483647
const F32_MAX := 3.4028234663852886e38
const MAX_UTF_BYTES := 32767 # Source ReadUTF uses signed ReadInt16.
const TRADE_SLOTS := 12 # Player.Trade / TradeManager use exactly twelve entries.


# Each helper returns {id: int, payload: PackedByteArray}, or {} on invalid input.
# Validate without coercion/wrapping, and never truncate or mutate caller records.
class Body extends RefCounted:
	var stream := StreamPeerBuffer.new()
	var valid := true

	func _init() -> void:
		stream.big_endian = true

	func integer(value: Variant, minimum: int, maximum: int, width: int) -> void:
		if typeof(value) != TYPE_INT or value < minimum or value > maximum:
			valid = false
			return
		match width:
			1: stream.put_u8(value)
			2: stream.put_u16(value)
			4:
				if minimum < 0:
					stream.put_32(value)
				else:
					stream.put_u32(value)

	func i32(value: Variant) -> void:
		integer(value, I32_MIN, I32_MAX, 4)

	func byte(value: Variant) -> void:
		integer(value, 0, 255, 1)

	func flag(value: Variant) -> void:
		if typeof(value) != TYPE_BOOL:
			valid = false
			return
		stream.put_u8(1 if value else 0)

	func real32(value: Variant) -> void:
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			valid = false
			return
		if not is_finite(float(value)) or abs(float(value)) > F32_MAX:
			valid = false
			return
		stream.put_float(float(value))

	func position(value: Variant) -> void:
		if typeof(value) != TYPE_VECTOR2:
			valid = false
			return
		real32(value.x)
		real32(value.y)

	func text(value: Variant, allow_empty: bool = true) -> void:
		if typeof(value) != TYPE_STRING:
			valid = false
			return
		var encoded: PackedByteArray = value.to_utf8_buffer()
		if encoded.size() > MAX_UTF_BYTES or (not allow_empty and encoded.is_empty()):
			valid = false
			return
		stream.put_u16(encoded.size())
		stream.put_data(encoded)

	func slot(value: Variant) -> void:
		if typeof(value) != TYPE_DICTIONARY or not value.has_all(["object_id", "slot_id", "object_type"]):
			valid = false
			return
		i32(value.object_id)
		byte(value.slot_id)
		var item: Variant = value.object_type
		if typeof(item) == TYPE_INT and item == -1:
			item = 65535
		integer(item, 0, 65535, 2)

	func offers(value: Variant) -> void:
		if typeof(value) != TYPE_ARRAY or value.size() != TRADE_SLOTS:
			valid = false
			return
		stream.put_u16(value.size())
		for offered in value:
			flag(offered)

	func packet(id: int) -> Dictionary:
		if not valid:
			return {}
		return {"id": id, "payload": stream.data_array.duplicate()}


# Slot records reference authoritative entity IDs and item object types, not UI labels.
# This allows ordinary slots plus source pseudo-slots 254 (health), 255 (magic).
static func slot_record(object_id: Variant, slot_id: Variant, object_type: Variant) -> Dictionary:
	var record := {"object_id": object_id, "slot_id": slot_id, "object_type": object_type}
	var body := Body.new()
	body.slot(record)
	if not body.valid:
		return {}
	if object_type == -1:
		record.object_type = 65535
	return record


static func inv_swap(time: Variant, position: Variant, source: Variant, destination: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(time)
	body.position(position)
	body.slot(source)
	body.slot(destination)
	return body.packet(IDS.INVSWAP)


static func use_item(time: Variant, slot: Variant, position: Variant, use_type: Variant = 0) -> Dictionary:
	var body := Body.new()
	body.i32(time)
	body.slot(slot)
	body.position(position)
	body.byte(use_type)
	return body.packet(IDS.USEITEM)


static func inv_drop(slot: Variant) -> Dictionary:
	return _slot_packet(IDS.INVDROP, slot)


static func request_trade(name: Variant) -> Dictionary:
	return _text_packet(IDS.REQUESTTRADE, name)


static func change_trade(offers: Variant) -> Dictionary:
	var body := Body.new()
	body.offers(offers)
	return body.packet(IDS.CHANGETRADE)


static func accept_trade(my_offers: Variant, your_offers: Variant) -> Dictionary:
	var body := Body.new()
	body.offers(my_offers)
	body.offers(your_offers)
	return body.packet(IDS.ACCEPTTRADE)


static func cancel_trade() -> Dictionary:
	return _empty_packet(IDS.CANCELTRADE)


static func create_guild(name: Variant) -> Dictionary:
	return _text_packet(IDS.CREATEGUILD, name)


static func join_guild(guild_name: Variant) -> Dictionary:
	return _text_packet(IDS.JOINGUILD, guild_name)


static func guild_invite(name: Variant) -> Dictionary:
	return _text_packet(IDS.GUILDINVITE, name)


static func guild_remove(name: Variant) -> Dictionary:
	return _text_packet(IDS.GUILDREMOVE, name)


static func change_guild_rank(name: Variant, rank: Variant) -> Dictionary:
	var body := Body.new()
	body.text(name)
	body.i32(rank)
	return body.packet(IDS.CHANGEGUILDRANK)


static func player_text(text: Variant) -> Dictionary:
	var body := Body.new()
	body.text(text, false) # Source PlayerTextHandler indexes Text[0].
	return body.packet(IDS.PLAYERTEXT)


static func teleport(object_id: Variant) -> Dictionary:
	return _i32_packet(IDS.TELEPORT, object_id)


static func escape() -> Dictionary:
	return _empty_packet(IDS.ESCAPE)


static func use_portal(object_id: Variant) -> Dictionary:
	return _i32_packet(IDS.USEPORTAL, object_id)


static func buy(object_id: Variant) -> Dictionary:
	return _i32_packet(IDS.BUY, object_id)


static func check_credits() -> Dictionary:
	return _empty_packet(IDS.CHECKCREDITS)


static func edit_account_list(list_id: Variant, add: Variant, object_id: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(list_id)
	body.flag(add)
	body.i32(object_id)
	return body.packet(IDS.EDITACCOUNTLIST)


static func choose_name(name: Variant) -> Dictionary:
	return _text_packet(IDS.CHOOSENAME, name)


static func set_condition(effect: Variant, duration: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(effect)
	body.real32(duration)
	return body.packet(IDS.SETCONDITION)


static func reskin(skin_id: Variant) -> Dictionary:
	return _i32_packet(IDS.RESKIN, skin_id)


static func pet_command(command_id: Variant, pet_id: Variant) -> Dictionary:
	var body := Body.new()
	body.byte(command_id)
	body.integer(pet_id, 0, 4294967295, 4)
	return body.packet(IDS.PETCOMMAND)


static func pet_yard_command(command_id: Variant, pet_id1: Variant, pet_id2: Variant,
		object_id: Variant, slot: Variant, currency: Variant) -> Dictionary:
	var body := Body.new()
	body.byte(command_id)
	body.i32(pet_id1)
	body.i32(pet_id2)
	body.i32(object_id)
	body.slot(slot)
	body.byte(currency)
	return body.packet(IDS.PETYARDCOMMAND)


static func enter_arena(currency: Variant) -> Dictionary:
	return _i32_packet(IDS.ENTER_ARENA, currency)


static func leave_arena(source_li: Variant) -> Dictionary:
	return _i32_packet(IDS.LEAVEARENA, source_li)


static func view_quests() -> Dictionary:
	return _empty_packet(IDS.VIEWQUESTS)


static func tinker_quest(slot: Variant) -> Dictionary:
	return _slot_packet(IDS.TINKERQUEST, slot)


# Hit reports carry source identifiers/flags only. The C# handlers decide effects
# and damage; Killed is a serialized source field, not a client damage calculation.
static func enemy_hit(time: Variant, bullet_id: Variant, target_id: Variant, killed: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(time)
	body.byte(bullet_id)
	body.i32(target_id)
	body.flag(killed)
	return body.packet(IDS.ENEMYHIT)


static func player_hit(bullet_id: Variant, object_id: Variant) -> Dictionary:
	var body := Body.new()
	body.byte(bullet_id)
	body.i32(object_id)
	return body.packet(IDS.PLAYERHIT)


static func other_hit(time: Variant, bullet_id: Variant, object_id: Variant, target_id: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(time)
	body.byte(bullet_id)
	body.i32(object_id)
	body.i32(target_id)
	return body.packet(IDS.OTHERHIT)


static func ground_damage(time: Variant, position: Variant) -> Dictionary:
	return _timed_position_packet(IDS.GROUNDDAMAGE, time, position)


static func square_hit(time: Variant, bullet_id: Variant, object_id: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(time)
	body.byte(bullet_id)
	body.i32(object_id)
	return body.packet(IDS.SQUAREHIT)


static func aoe_ack(time: Variant, position: Variant) -> Dictionary:
	return _timed_position_packet(IDS.AOEACK, time, position)


static func goto_ack(time: Variant) -> Dictionary:
	return _i32_packet(IDS.GOTOACK, time)


static func shoot_ack(time: Variant) -> Dictionary:
	return _i32_packet(IDS.SHOOTACK, time)


static func update_ack() -> Dictionary:
	return _empty_packet(IDS.UPDATEACK)


static func pong(serial: Variant, time: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(serial)
	body.i32(time)
	return body.packet(IDS.PONG)


static func failure(error_id: Variant, description: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(error_id)
	body.text(description)
	return body.packet(IDS.FAILURE)


static func _timed_position_packet(id: int, time: Variant, position: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(time)
	body.position(position)
	return body.packet(id)


static func _empty_packet(id: int) -> Dictionary:
	return Body.new().packet(id)


static func _i32_packet(id: int, value: Variant) -> Dictionary:
	var body := Body.new()
	body.i32(value)
	return body.packet(id)


static func _text_packet(id: int, value: Variant) -> Dictionary:
	var body := Body.new()
	body.text(value)
	return body.packet(id)


static func _slot_packet(id: int, value: Variant) -> Dictionary:
	var body := Body.new()
	body.slot(value)
	return body.packet(id)
