extends RefCounted
## SPDX-License-Identifier: AGPL-3.0-only
## Adapted wire DATA layouts from FSoD 6fd20aad4a7905b13f25389c68368a942a2b68cb,
## wServer/networking/{cliPackets,svrPackets}/*.cs, Structures.cs, realm/Stats.cs.
## Direction matters: encode CLIENT as SERVER.Read; decode SERVER as SERVER.Write.
## Keep original field names. Positions = Vector2 source tiles; angles = radians.
const Binary := preload("res://src/net/fsod/binary.gd")
const Ids := preload("res://src/net/fsod/ids.gd")
const UTF_STATS := [31, 38, 54, 62, 82] # StatsType.IsUTF, NOT ObjectStats.Read
const MAX_ITEMS := 32767
const CLIENT_SCHEMAS := {
	35: ["BuildVersion:utf", "GameId:i32", "GUID:utf", "IgnoredInt:i32", "Password:utf", "randomint1:i32", "Secret:utf", "KeyTime:i32", "Key:bytes16", "MapInfo:bytes32", "obf1:utf", "obf2:utf", "obf3:utf", "obf4:utf", "obf5:utf"],
	78: ["ClassType:u16", "SkinType:u16"], 8: ["CharacterId:i32", "IsFromArena:bool"],
	87: ["TickId:i32", "Time:i32", "Position:pos", "Records:timed_pos[]"],
	13: ["Time:i32", "BulletId:u8", "ContainerType:i16", "Position:pos", "Angle:f32"],
	52: ["Serial:i32", "Time:i32"], 45: [], 36: ["Time:i32"], 12: ["Time:i32"],
	95: ["Time:i32", "Position:pos"], 42: ["Time:i32", "BulletId:u8", "TargetId:i32", "Killed:bool"],
	17: ["BulletId:u8", "ObjectId:i32"], 59: ["Time:i32", "Position:pos"],
	14: ["Time:i32", "BulletId:u8", "ObjectId:i32", "TargetId:i32"], 86: ["Time:i32", "BulletId:u8", "ObjectId:i32"],
	47: [], 9: ["ObjectId:i32"]
}
# Every original concrete SERVER packet has a layout. Gameplay/UI consumers
# remain separate; schema support does NOT claim tested end-to-end feature support.
const SERVER_SCHEMAS := {
	0: ["ErrorId:i32", "ErrorDescription:utf"], 33: ["ObjectID:i32", "CharacterID:i32"],
	65: ["Width:i32", "Height:i32", "Name:utf", "ClientWorldName:utf", "Seed:u32", "Background:i32", "Difficulty:i32", "AllowTeleport:bool", "ShowDisplays:bool", "ClientXML:utf32[]", "ExtraXML:utf32[]"],
	7: ["Tiles:tile[]", "NewObjects:object_def[]", "RemovedObjectIds:i32[]"],
	80: ["TickId:i32", "TickTime:i32", "UpdateStatuses:object_stats[]"],
	3: ["ObjectId:i32", "Position:pos"], 46: ["Serial:i32"],
	84: ["BulletId:u8", "OwnerId:i32", "ContainerType:i32", "StartingPos:pos", "Angle:f32", "Damage:i16"],
	96: ["BulletId:u8", "OwnerId:i32", "BulletType:u8", "Position:pos", "Angle:f32", "Damage:i16"],
	92: ["BulletId:u8", "OwnerId:i32", "ContainerType:i16", "Angle:f32"],
	21: ["Name:utf", "Host:utf", "Port:i32", "GameId:i32", "KeyTime:i32", "IsFromArena:bool", "Key:bytes16"],
	63: ["AccountId:utf", "CharId:i32", "Killer:utf", "obf0:i32", "obf1:i32"],
	51: ["TargetId:i32", "Effects:effects", "Damage:u16", "Killed:bool", "BulletId:u8", "ObjectId:i32"],
	69: ["Position:pos", "Radius:f32", "Damage:u16", "Effects:u8", "EffectDuration:f32", "OriginType:i16"],
	20: ["AccountListId:i32", "AccountIds:utf[]", "LockAction:i32"],
	15: ["RestartPrice:i32"], 31: ["Type:i32"], 10: ["Result:i32", "Message:utf"],
	66: ["Name:utf", "Value:i32"], 4: ["Success:bool", "ErrorText:utf"],
	88: ["Name:utf", "Bytes:bytes32"], 30: ["Type:i32", "Text:utf"],
	81: ["PetName:utf", "PetSkinId:i32"], 58: ["Result:i32"], 79: ["Name:utf", "GuildName:utf"],
	62: ["Success:bool", "ErrorText:utf"], 97: ["Type:i32"],
	53: ["ObjectId:i32", "Text:utf", "Color:argb"], 74: ["CleanPasswordStatus:i32"],
	76: ["PetId1:i32", "SkinId1:i32", "SkinId2:i32"], 60: ["BitmapData:bitmap"],
	50: ["OwnerId:i32", "SoundId:u8"], 37: ["Tier:i32", "Goal:utf", "Description:utf", "Image:utf"],
	77: ["ObjectId:i32"], 18: ["Success:bool", "Message:utf"], 26: ["PetId:i32"],
	28: ["EffectType:u8", "TargetId:i32", "PosA:pos", "PosB:pos", "Color:argb"],
	67: ["Name:utf", "ObjectId:i32", "Stars:i32", "BubbleTime:u8", "Recipient:utf", "Text:utf", "CleanText:utf"],
	22: ["MyOffers:bool[]", "YourOffers:bool[]"], 56: ["Offers:bool[]"],
	25: ["Result:i32", "Message:utf"], 94: ["Name:utf"],
	64: ["MyItems:trade_item[]", "YourName:utf", "YourItems:trade_item[]"],
	11: ["SkinID:i32"], 83: ["PetId:i32"], 55: ["Type:i32"], 98: []
}
const STRUCTURES := {
	"timed_pos": ["Time:i32", "Position:pos"], "tile": ["X:i16", "Y:i16", "Tile:u16"],
	"object_def": ["ObjectType:u16", "Stats:object_stats"],
	"slot": ["ObjectId:i32", "SlotId:u8", "ObjectType:u16"],
	"trade_item": ["Item:i32", "SlotType:i32", "Tradeable:bool", "Included:bool"],
	"argb": ["A:u8", "R:u8", "G:u8", "B:u8"]
}

static func encode_client(id: int, fields: Dictionary) -> Dictionary:
	return _encode(CLIENT_SCHEMAS, id, fields)

## Fixture/oracle utility only. No server gameplay implementation.
static func encode_server(id: int, fields: Dictionary) -> Dictionary:
	return _encode(SERVER_SCHEMAS, id, fields)

static func _encode(schemas: Dictionary, id: int, fields: Dictionary) -> Dictionary:
	if not schemas.has(id): return {"error": "unsupported packet encoder", "payload": PackedByteArray()}
	var b := Binary.new()
	_write_fields(b, schemas[id], fields)
	if id == Ids.SHOOT:
		var count := int(fields.get("NumShots", 1))
		var increment := float(fields.get("AngleInc", 0.0))
		if count != 1 and increment != 0.0:
			b.write_value("u8", count)
			b.write_value("f32", increment)
	return {"error": b.error, "payload": b.bytes() if b.error.is_empty() else PackedByteArray()}

static func decode_server(id: int, payload: PackedByteArray) -> Dictionary:
	if not SERVER_SCHEMAS.has(id):
		return {"error": "", "fields": {"RawPayload": payload, "Unsupported": true}}
	var b := Binary.new(payload)
	var fields := _read_fields(b, SERVER_SCHEMAS[id])
	if id == Ids.SHOOT:
		fields["NumShots"] = 1
		fields["AngleInc"] = 0.0
		if b.remaining() != 0:
			if b.remaining() != 5:
				b.fail("invalid EnemyShoot optional tail")
			else:
				fields.NumShots = b.read_value("u8")
				fields.AngleInc = b.read_value("f32")
				if int(fields.NumShots) < 1: b.fail("empty EnemyShoot volley")
	if b.remaining() != 0: b.fail("trailing packet bytes")
	return {"error": b.error, "fields": fields if b.error.is_empty() else {}}

static func _read_fields(b: RefCounted, schema: Array) -> Dictionary:
	var out := {}
	for entry in schema:
		if not b.error.is_empty(): break
		var parts: PackedStringArray = entry.split(":")
		out[parts[0]] = _read(b, parts[1])
	return out

static func _write_fields(b: RefCounted, schema: Array, fields: Dictionary) -> void:
	for entry in schema:
		var parts: PackedStringArray = entry.split(":")
		if not fields.has(parts[0]):
			b.fail("missing field " + parts[0])
			return
		_write(b, parts[1], fields[parts[0]])

static func _read(b: RefCounted, kind: String) -> Variant:
	if kind.ends_with("[]") or kind == "effects":
		var item := "u8" if kind == "effects" else kind.trim_suffix("[]")
		var count := int(b.read_value("u8" if kind == "effects" else "u16"))
		var out: Array = []
		# At least one byte per item. Also limits decoded object allocations.
		if count > MAX_ITEMS or count > b.remaining():
			b.fail("array count exceeds remaining payload or item bound")
			return out
		for i in count:
			if not b.error.is_empty(): break
			out.append(_read(b, item))
		return out
	if STRUCTURES.has(kind): return _read_fields(b, STRUCTURES[kind])
	match kind:
		"pos":
			return Vector2(b.read_value("f32"), b.read_value("f32"))
		"object_stats":
			var result := {"Id": b.read_value("i32"), "Position": _read(b, "pos"), "Stats": []}
			var count := int(b.read_value("u16"))
			if count > MAX_ITEMS or count > b.remaining() / 3:
				b.fail("stat count exceeds bounds")
				return result
			for i in count:
				if not b.error.is_empty(): break
				var type := int(b.read_value("u8"))
				result.Stats.append({"Type": type, "Value": b.read_value("utf" if type in UTF_STATS else "i32")})
			return result
		"bitmap":
			var width := int(b.read_value("i32"))
			var height := int(b.read_value("i32"))
			if width < 0 or height < 0 or width > 131071 or height > 131071 or width * height * 4 > b.remaining():
				b.fail("bitmap dimensions exceed payload")
				return {}
			return {"Width": width, "Height": height, "Bytes": b.stream.get_data(width * height * 4)[1]}
	return b.read_value(kind)

static func _write(b: RefCounted, kind: String, value: Variant) -> void:
	if not b.error.is_empty(): return
	if kind.ends_with("[]") or kind == "effects":
		if typeof(value) != TYPE_ARRAY or value.size() > (255 if kind == "effects" else MAX_ITEMS):
			b.fail("invalid array or excessive count")
			return
		b.write_value("u8" if kind == "effects" else "u16", value.size())
		for item in value: _write(b, "u8" if kind == "effects" else kind.trim_suffix("[]"), item)
		return
	if STRUCTURES.has(kind):
		if typeof(value) != TYPE_DICTIONARY:
			b.fail("structure dictionary required")
			return
		_write_fields(b, STRUCTURES[kind], value)
		return
	match kind:
		"pos":
			if typeof(value) != TYPE_VECTOR2:
				b.fail("tile Vector2 required")
				return
			b.write_value("f32", value.x)
			b.write_value("f32", value.y)
		"object_stats":
			if typeof(value) != TYPE_DICTIONARY or not value.has("Stats") or typeof(value.Stats) != TYPE_ARRAY or value.Stats.size() > MAX_ITEMS:
				b.fail("invalid ObjectStats")
				return
			_write_fields(b, ["Id:i32", "Position:pos"], value)
			b.write_value("u16", value.Stats.size())
			for stat in value.Stats:
				if typeof(stat) != TYPE_DICTIONARY or not stat.has("Type") or not stat.has("Value"):
					b.fail("invalid stat")
					return
				b.write_value("u8", stat.Type)
				b.write_value("utf" if stat.Type in UTF_STATS else "i32", stat.Value)
		"bitmap":
			if typeof(value) != TYPE_DICTIONARY or not value.has("Bytes") or typeof(value.Bytes) != TYPE_PACKED_BYTE_ARRAY:
				b.fail("invalid bitmap")
				return
			_write_fields(b, ["Width:i32", "Height:i32"], value)
			if value.Width < 0 or value.Height < 0 or value.Width * value.Height * 4 != value.Bytes.size():
				b.fail("bitmap dimensions mismatch")
				return
			b.stream.put_data(value.Bytes)
		_:
			b.write_value(kind, value)
