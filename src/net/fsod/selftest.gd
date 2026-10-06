extends SceneTree
## SPDX-License-Identifier: AGPL-3.0-only
## FSoD protocol fixtures at 6fd20aad4a7905b13f25389c68368a942a2b68cb.
## Three independent golden payloads emitted by ORIGINAL C# protected Write
## via parent's oracle commit 5777822e4a1c22dd44768c0c12abe80e03135c0b.
const Codec := preload("res://src/net/fsod/codec.gd")
const RC4 := preload("res://src/net/fsod/rc4.gd")
const Framing := preload("res://src/net/fsod/framing.gd")
const Binary := preload("res://src/net/fsod/binary.gd")
const Client := preload("res://src/net/fsod/client.gd")
const Ids := preload("res://src/net/fsod/ids.gd")
const MAP_HEX := "000000640000005000054e6578757300084752415645424147000030390000000000000001010000010000000a3c4f626a656374732f3e00010000000a3c47726f756e64732f3e"
const TICK_HEX := "00000007000000c80001000004d241480000c0500000000701000000571f00084772617665626167260002343236000234333e00054e65787573520004736b696e0000000064"
const UPDATE_HEX := "0001000c000901230001030e000004d241480000c0500000000701000000571f00084772617665626167260002343236000234333e00054e65787573520004736b696e000000006400020000002c0000002d"
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FSoD wire: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_rc4()
	_test_original_oracles()
	_test_source_layouts()
	_test_framing()
	_test_bounds()
	await _test_transport()
	print("FSOD NETWORK PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_rc4() -> void:
	var rc := RC4.new()
	rc.initialize("Key".to_ascii_buffer())
	check(rc.crypt("Plaintext".to_ascii_buffer()).hex_encode() == "bbf316e8d940af0ad3", "RC4 Key/Plaintext independent known vector")
	rc.initialize("Wiki".to_ascii_buffer())
	check(rc.crypt("pedia".to_ascii_buffer()).hex_encode() == "1021bf0420", "RC4 Wiki independent known vector")
	rc.initialize("Key".to_ascii_buffer())
	var split: PackedByteArray = rc.crypt("Plain".to_ascii_buffer())
	split.append_array(rc.crypt("text".to_ascii_buffer()))
	check(split.hex_encode() == "bbf316e8d940af0ad3", "RC4 state retained across calls")

func _test_original_oracles() -> void:
	var decoded := Codec.decode_server(Ids.MAPINFO, MAP_HEX.hex_decode())
	check(decoded.error.is_empty(), "ORIGINAL MapInfo.Write decoded")
	if decoded.error.is_empty():
		var f: Dictionary = decoded.fields
		check(f.Width == 100 and f.Height == 80 and f.Name == "Nexus" and f.ClientWorldName == "GRAVEBAG", "map source field names")
		check(f.Seed == 12345 and f.Difficulty == 1 and f.AllowTeleport and not f.ShowDisplays, "map flags/seed/difficulty")
		check(f.ClientXML == ["<Objects/>"] and f.ExtraXML == ["<Grounds/>"], "MapInfo uses Write32UTF NOT buggy ReadUTF")
	decoded = Codec.decode_server(Ids.NEW_TICK, TICK_HEX.hex_decode())
	check(decoded.error.is_empty(), "ORIGINAL NewTick.Write decoded")
	if decoded.error.is_empty():
		check(decoded.fields.TickId == 7 and decoded.fields.TickTime == 200, "server tick milliseconds")
		_check_stats(decoded.fields.UpdateStatuses[0])
	decoded = Codec.decode_server(Ids.UPDATE, UPDATE_HEX.hex_decode())
	check(decoded.error.is_empty(), "ORIGINAL Update.Write decoded")
	if decoded.error.is_empty():
		check(decoded.fields.Tiles == [{"X": 12, "Y": 9, "Tile": 0x123}], "tile schema")
		check(decoded.fields.NewObjects[0].ObjectType == 0x30e and decoded.fields.RemovedObjectIds == [44, 45], "object type and removals")
		_check_stats(decoded.fields.NewObjects[0].Stats)

func _check_stats(s: Dictionary) -> void:
	check(s.Id == 1234 and s.Position == Vector2(12.5, -3.25), "ObjectStats tile position")
	check(s.Stats == [{"Type": 1, "Value": 87}, {"Type": 31, "Value": "Gravebag"},
		{"Type": 38, "Value": "42"}, {"Type": 54, "Value": "43"}, {"Type": 62, "Value": "Nexus"},
		{"Type": 82, "Value": "skin"}, {"Type": 0, "Value": 100}], "ALL five IsUTF stat types; int follows strings without drift")

func _gold_client(id: int, fields: Dictionary, hex: String, label: String) -> void:
	var encoded := Codec.encode_client(id, fields)
	check(encoded.error.is_empty() and encoded.payload.hex_encode() == hex, label)

func _gold_server(id: int, hex: String, expected: Dictionary, label: String) -> void:
	var decoded := Codec.decode_server(id, hex.hex_decode())
	check(decoded.error.is_empty() and decoded.fields == expected, label)

func _test_source_layouts() -> void:
	_gold_client(Ids.CREATE, {"ClassType": 0x30e, "SkinType": 0}, "030e0000", "CREATE two16-bit fields")
	_gold_client(Ids.LOAD, {"CharacterId": 42, "IsFromArena": false}, "0000002a00", "LOAD i32/bool")
	_gold_client(Ids.PONG, {"Serial": 7, "Time": 1000}, "00000007000003e8", "PONG int32 serial/time")
	_gold_client(Ids.UPDATEACK, {}, "", "UPDATEACK empty body")
	_gold_client(Ids.ESCAPE, {}, "", "ESCAPE empty body")
	_gold_client(Ids.USEPORTAL, {"ObjectId": 42}, "0000002a", "USEPORTAL source object id")
	for id in [Ids.GOTOACK, Ids.SHOOTACK]:
		_gold_client(id, {"Time": 1000}, "000003e8", "time acknowledgement %d" % id)
	_gold_client(Ids.AOEACK, {"Time": 1000, "Position": Vector2(1, -2)}, "000003e83f800000c0000000", "AOEACK tile position")
	_gold_client(Ids.MOVE, {"TickId": 7, "Time": 1000, "Position": Vector2(1, -2), "Records": [{"Time": 900, "Position": Vector2(0.5, 2)}]},
		"00000007000003e83f800000c00000000001000003843f00000040000000", "MOVE TimedPosition writes time BEFORE x/y")
	_gold_client(Ids.PLAYERSHOOT, {"Time": 1000, "BulletId": 2, "ContainerType": 0x1234, "Position": Vector2(1, -2), "Angle": 0.5},
		"000003e80212343f800000c00000003f000000", "PLAYERSHOOT source short container and radians")
	var login := {"BuildVersion": "27.3.2", "GameId": -2, "GUID": "G", "IgnoredInt": 0,
		"Password": "P", "randomint1": 7, "Secret": "", "KeyTime": 0, "Key": PackedByteArray(),
		"MapInfo": PackedByteArray(), "obf1": "", "obf2": "", "obf3": "", "obf4": "", "obf5": ""}
	_gold_client(Ids.HELLO, login,
		"000632372e332e32fffffffe000147000000000001500000000700000000000000000000000000000000000000000000", "HELLO matches authoritative Hello.Read (not asymmetric Write)")
	_gold_client(Ids.ENEMYHIT, {"Time": 1000, "BulletId": 2, "TargetId": 42, "Killed": false}, "000003e8020000002a00", "ENEMYHIT")
	_gold_client(Ids.PLAYERHIT, {"BulletId": 2, "ObjectId": 42}, "020000002a", "PLAYERHIT")
	_gold_client(Ids.GROUNDDAMAGE, {"Time": 1000, "Position": Vector2(1, -2)}, "000003e83f800000c0000000", "GROUNDDAMAGE")
	_gold_client(Ids.OTHERHIT, {"Time": 1000, "BulletId": 2, "ObjectId": 42, "TargetId": 43}, "000003e8020000002a0000002b", "OTHERHIT")
	_gold_client(Ids.SQUAREHIT, {"Time": 1000, "BulletId": 2, "ObjectId": 42}, "000003e8020000002a", "SQUAREHIT")
	_gold_server(Ids.CREATE_SUCCESS, "0000002a00000003", {"ObjectID": 42, "CharacterID": 3}, "CREATE_SUCCESS")
	_gold_server(Ids.PING, "00000007", {"Serial": 7}, "PING")
	_gold_server(Ids.GOTO, "0000002a3f800000c0000000", {"ObjectId": 42, "Position": Vector2(1, -2)}, "GOTO")
	_gold_server(Ids.SHOOT2, "020000002a000012343f800000c00000003f000000000a",
		{"BulletId": 2, "OwnerId": 42, "ContainerType": 0x1234, "StartingPos": Vector2(1, -2), "Angle": 0.5, "Damage": 10}, "ServerPlayerShoot has INT32 container unlike client shoot")
	var shot := {"BulletId": 2, "OwnerId": 42, "BulletType": 1, "Position": Vector2(1, -2), "Angle": 0.5, "Damage": 10, "NumShots": 1, "AngleInc": 0.0}
	_gold_server(Ids.SHOOT, "020000002a013f800000c00000003f000000000a", shot, "EnemyShoot absent tail defaults to ONE shot")
	shot.NumShots = 3
	shot.AngleInc = 0.25
	_gold_server(Ids.SHOOT, "020000002a013f800000c00000003f000000000a033e800000", shot, "EnemyShoot optional multishot tail")
	_gold_server(Ids.FAILURE, "000000040003626164", {"ErrorId": 4, "ErrorDescription": "bad"}, "FAILURE")
	_gold_server(Ids.RECONNECT, "00014e00016800000803fffffffe000000070000020102",
		{"Name": "N", "Host": "h", "Port": 2051, "GameId": -2, "KeyTime": 7, "IsFromArena": false, "Key": PackedByteArray([1, 2])}, "RECONNECT preserves portal key bytes; no auto-follow")
	_gold_server(Ids.DEATH, "000234320000000300016b0000000400000005",
		{"AccountId": "42", "CharId": 3, "Killer": "k", "obf0": 4, "obf1": 5}, "DEATH complete source obfuscated fields")
	var node := Client.new()
	node.configure_login({"GUID": "G", "Password": "P"})
	check(node._login.BuildVersion == "27.3.2" and node._login.GameId == -2, "actual source login defaults")
	node.configure_login({"GameId": 10, "KeyTime": 7, "Key": PackedByteArray([1, 2])})
	check(node._login.GUID == "G" and node._login.Password == "P" and node._login.GameId == 10, "portal login patches retain ciphertext fields")
	check(node.send_packet(Ids.UPDATEACK, PackedByteArray()) == ERR_UNCONFIGURED, "no sends while disconnected")
	node.free()

func _test_framing() -> void:
	var server := Framing.new(true)
	var a: PackedByteArray = server.pack(Ids.PING, "00000007".hex_decode())
	var b: PackedByteArray = server.pack(Ids.CREATE_SUCCESS, "0000002a00000003".hex_decode())
	check(a.slice(0, 5).hex_encode() == "000000092e", "frame length INCLUDES5 clear header bytes and clear ID")
	check(a.hex_encode() == "000000092e7320b43c", "independent public server SendKey ciphertext fixture")
	var directional := Framing.new()
	check(directional.pack(Ids.PONG, "00000007".hex_decode()).hex_encode() == "00000009347ee7e257", "independent public server ReceiveKey ciphertext fixture")
	for split in a.size() + 1:
		var receiver := Framing.new()
		var frames := receiver.feed(a.slice(0, split))
		frames.append_array(receiver.feed(a.slice(split)))
		check(frames.size() == 1 and frames[0].payload.hex_encode() == "00000007", "partial packet split %d" % split)
	var receiver := Framing.new()
	var both: PackedByteArray = a.duplicate()
	both.append_array(b)
	var frames := receiver.feed(both)
	check(frames.size() == 2 and frames[1].payload.hex_encode() == "0000002a00000003", "coalesced packets keep continuous directional RC4")
	receiver = Framing.new()
	for byte in both:
		frames = receiver.feed(PackedByteArray([byte]))
		if not frames.is_empty(): check(frames[0].id in [Ids.PING, Ids.CREATE_SUCCESS], "one byte at a time")
	var client := Framing.new()
	server = Framing.new(true)
	frames = server.feed(client.pack(Ids.UPDATEACK, PackedByteArray()))
	check(frames.size() == 1 and frames[0].payload.is_empty(), "empty payload does not consume cipher")
	frames = server.feed(client.pack(Ids.PONG, "00000007000003e8".hex_decode()))
	check(frames[0].payload.hex_encode() == "00000007000003e8", "opposite direction uses server ReceiveKey")
	client.reset()
	var fresh := Framing.new(true)
	check(fresh.feed(client.pack(Ids.PONG, "00000007000003e8".hex_decode()))[0].payload.hex_encode() == "00000007000003e8", "new connection resets directional cipher")
	server = Framing.new(true)
	receiver = Framing.new()
	var unknown: PackedByteArray = server.pack(250, PackedByteArray([1, 2, 3]))
	unknown.append_array(server.pack(Ids.PING, "00000007".hex_decode()))
	frames = receiver.feed(unknown)
	check(frames.size() == 2 and frames[1].payload.hex_encode() == "00000007", "unknown packet still advances cipher exactly once")
	check(Codec.decode_server(250, frames[0].payload).fields.Unsupported, "unsupported packets surfaced explicitly")
	server = Framing.new(true)
	receiver = Framing.new()
	var many := PackedByteArray()
	for i in 1025: many.append_array(server.pack(Ids.PING, "00000007".hex_decode()))
	check(receiver.feed(many).size() == 1024 and receiver.feed(PackedByteArray()).size() == 1, "bounded frame work per poll without losing queued complete frames")

func _test_bounds() -> void:
	for hex in ["0000000000", "0000000400", "8000000000", "0008000500"]:
		var f := Framing.new()
		check(f.feed(hex.hex_decode()).is_empty() and not f.error.is_empty(), "malformed frame rejected " + hex)
		check(f.feed("0000000500".hex_decode()).is_empty(), "sticky malformed frame error")
	var f := Framing.new()
	var huge := PackedByteArray()
	huge.resize(Framing.MAX_BUFFER + 1)
	check(f.feed(huge).is_empty() and not f.error.is_empty() and f.buffered_bytes() == 0, "buffer growth capped")
	f = Framing.new()
	check(f.pack(256, PackedByteArray()).is_empty() and not f.error.is_empty(), "invalid outbound ID rejected before RC4")
	for id in [Ids.MAPINFO, Ids.NEW_TICK, Ids.UPDATE, Ids.SHOOT2, Ids.RECONNECT, Ids.DEATH]:
		check(not Codec.decode_server(id, PackedByteArray()).error.is_empty(), "truncated payload %d" % id)
	check(not Codec.decode_server(Ids.FAILURE, "00000000ffff".hex_decode()).error.is_empty(), "negative signed UTF length rejected")
	check(not Codec.decode_server(Ids.NEW_TICK, "0000000100000001ffff".hex_decode()).error.is_empty(), "unbounded status count rejected")
	check(not Codec.decode_server(Ids.GOTO, "000000017fc0000000000000".hex_decode()).error.is_empty(), "NaN position rejected")
	check(not Codec.decode_server(Ids.PING, "0000000700".hex_decode()).error.is_empty(), "trailing bytes rejected")
	check(not Codec.decode_server(Ids.SHOOT, "020000002a013f800000c00000003f000000000a02".hex_decode()).error.is_empty(), "truncated multishot tail rejected")
	check(not Codec.encode_client(Ids.PLAYERSHOOT, {"Time": 0, "BulletId": 256, "ContainerType": 0, "Position": Vector2.ZERO, "Angle": 0.0}).error.is_empty(), "oversized uint8 not silently truncated")
	check(not Codec.encode_client(Ids.MOVE, {"TickId": 1, "Time": 0, "Position": Vector2(INF, 0), "Records": []}).error.is_empty(), "non-finite outbound values rejected")
	check(not Codec.encode_client(Ids.CREATE, {}).error.is_empty(), "missing source fields rejected")
	var b := Binary.new()
	b.write_value("utf", "a".repeat(32768))
	check(not b.error.is_empty(), "signed UTF16 length capped32767")

func _test_transport() -> void:
	var listener := TCPServer.new()
	var err := listener.listen(0, "127.0.0.1")
	check(err == OK, "isolated loopback fixture server")
	if err != OK: return
	var client := Client.new()
	root.add_child(client)
	client.set_process(false) # bounded test drives real poll itself
	var received: Array = []
	var projectiles: Array = []
	var errors: Array = []
	client.packet_received.connect(func(id: int, fields: Dictionary) -> void: received.append([id, fields]))
	client.projectile_received.connect(func(id: int, fields: Dictionary) -> void: projectiles.append([id, fields]))
	client.protocol_error.connect(func(reason: String) -> void: errors.append(reason))
	check(client.connect_to_server("127.0.0.1", listener.get_local_port()) == OK, "StreamPeerTCP connect initiated")
	var peer: StreamPeerTCP = null
	var deadline := Time.get_ticks_msec() + 5000
	for i in 300:
		client.poll()
		if peer == null and listener.is_connection_available(): peer = listener.take_connection()
		if peer != null: peer.poll()
		if client._active and peer != null: break
		if Time.get_ticks_msec() > deadline: break
		await process_frame
	check(client._active and peer != null, "connection completed within deadline/max attempts")
	if peer == null or not client._active:
		client.free()
		listener.stop()
		return
	var server := Framing.new(true)
	var frames: PackedByteArray = server.pack(Ids.UPDATE, UPDATE_HEX.hex_decode())
	frames.append_array(server.pack(Ids.PING, "00000007".hex_decode()))
	frames.append_array(server.pack(Ids.GOTO, "0000002a3f800000c0000000".hex_decode()))
	frames.append_array(server.pack(Ids.SHOOT2, "020000002a000012343f800000c00000003f000000000a".hex_decode()))
	frames.append_array(server.pack(Ids.SHOOT, "020000002a013f800000c00000003f000000000a".hex_decode()))
	peer.put_data(frames.slice(0, 3))
	client.poll()
	check(received.is_empty(), "TCP partial header emits nothing")
	peer.put_data(frames.slice(3))
	var acknowledgements: Array = []
	deadline = Time.get_ticks_msec() + 5000
	for i in 300:
		client.poll()
		peer.poll()
		if peer.get_available_bytes() > 0:
			acknowledgements.append_array(server.feed(peer.get_data(peer.get_available_bytes())[1]))
		if acknowledgements.size() >= 5: break
		if Time.get_ticks_msec() > deadline: break
		await process_frame
	check(errors.is_empty() and received.size() == 5 and projectiles.size() == 2, "generic and typed transport signals")
	check(acknowledgements.map(func(a: Dictionary) -> int: return a.id) == [Ids.UPDATEACK, Ids.PONG, Ids.GOTOACK, Ids.SHOOTACK, Ids.SHOOTACK], "real outbound ack order and continuous client RC4")
	if acknowledgements.size() == 5:
		check(acknowledgements[0].payload.is_empty() and acknowledgements[1].payload.slice(0, 4).hex_encode() == "00000007", "UpdateAck empty; Pong echoes serial")
		for i in [2, 3, 4]: check(acknowledgements[i].payload.size() == 4, "ack milliseconds layout %d" % i)
	check(client.send_move(7, 1000, Vector2(1, -2)) == OK, "movement remains caller-owned command")
	deadline = Time.get_ticks_msec() + 5000
	var movement: Array = []
	for i in 300:
		client.poll()
		peer.poll()
		if peer.get_available_bytes() > 0: movement.append_array(server.feed(peer.get_data(peer.get_available_bytes())[1]))
		if not movement.is_empty() or Time.get_ticks_msec() > deadline: break
		await process_frame
	check(movement.size() == 1 and movement[0].id == Ids.MOVE and movement[0].payload.hex_encode() == "00000007000003e83f800000c00000000000", "wire send_move golden body")
	peer.put_data("8000000000".hex_decode())
	deadline = Time.get_ticks_msec() + 5000
	for i in 300:
		client.poll()
		if not errors.is_empty() or Time.get_ticks_msec() > deadline: break
		await process_frame
	check(not client._active and errors.size() == 1, "malformed real TCP frame closes session without stale buffer")
	check(client._wire.buffered_bytes() == 0 and client._out.is_empty(), "disconnect clears queues")
	peer.disconnect_from_host()
	client.free()
	listener.stop()
