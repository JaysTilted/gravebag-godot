extends Node
## SPDX-License-Identifier: AGPL-3.0-only
## Original FSoD wire client, revision 6fd20aad4a7905b13f25389c68368a942a2b68cb.
## Sources: wServer/networking/{Client,NetworkHandler,Packet}.cs and packet files.
## This is TRANSPORT, not a gameplay backend. C# server remains authoritative.
## No view paths, assets, AI or account credentials. Caller supplies RSA ciphertext.
const Codec := preload("res://src/net/fsod/codec.gd")
const Framing := preload("res://src/net/fsod/framing.gd")
const Ids := preload("res://src/net/fsod/ids.gd")
const MAX_PENDING_OUT := Framing.MAX_BUFFER
const MAX_IO_PER_POLL := 65536
const CONNECT_TIMEOUT_MS := 10000
const PARTIAL_FRAME_TIMEOUT_MS := 15000
signal connected
signal disconnected(reason: String)
signal protocol_error(reason: String)
signal packet_received(packet_id: int, fields: Dictionary)
signal map_info_received(fields: Dictionary)
signal entities_received(fields: Dictionary)
signal tick_received(fields: Dictionary)
signal projectile_received(packet_id: int, fields: Dictionary)
signal death_received(fields: Dictionary)
signal failure_received(fields: Dictionary)
signal reconnect_received(fields: Dictionary)
signal goto_received(fields: Dictionary)
signal damage_received(fields: Dictionary)
signal aoe_received(fields: Dictionary)

var auto_ack := true
var object_id := -1
var character_id := -1
var _peer := StreamPeerTCP.new()
var _wire := Framing.new()
var _out := PackedByteArray()
var _out_offset := 0
var _connecting := false
var _active := false
var _deadline := 0
var _partial_since := 0
var _clock_base := 0
var _generation := 0
var _login := {}

func _ready() -> void:
	set_process(true)

## Login never logs its parameters. GUID/Password are Base64 RSA-encrypted UTF8
## strings from the separate account helper; no plaintext encryption here.
func configure_login(parameters: Dictionary) -> void:
	if _login.is_empty():
		_login = {"BuildVersion": "27.3.2", "GameId": -2, "GUID": "", "IgnoredInt": 0,
			"Password": "", "randomint1": 0, "Secret": "", "KeyTime": 0,
			"Key": PackedByteArray(), "MapInfo": PackedByteArray(),
			"obf1": "", "obf2": "", "obf3": "", "obf4": "", "obf5": ""}
	# Partial portal updates retain caller-supplied encrypted login fields.
	_login.merge(parameters.duplicate(true), true)

func connect_to_server(host: String, port: int) -> Error:
	if host.is_empty() or port < 1 or port > 65535: return ERR_INVALID_PARAMETER
	disconnect_from_server("new connection")
	_peer = StreamPeerTCP.new()
	_wire.reset()
	_out.clear()
	_out_offset = 0
	_partial_since = 0
	object_id = -1
	character_id = -1
	var result := _peer.connect_to_host(host, port)
	if result != OK: return result
	_connecting = true
	_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	return OK

func disconnect_from_server(reason: String = "client disconnect") -> void:
	var notify := _active or _connecting
	_generation += 1
	_active = false
	_connecting = false
	_peer.disconnect_from_host()
	_wire.reset()
	_out.clear()
	_out_offset = 0
	_partial_since = 0
	if notify: disconnected.emit(reason)

func client_time_ms() -> int:
	return int((Time.get_ticks_msec() - _clock_base) & 0x7fffffff)

func send_hello() -> Error:
	if _login.is_empty(): return ERR_UNCONFIGURED
	if str(_login.GUID).is_empty() or str(_login.Password).is_empty(): return ERR_INVALID_PARAMETER
	return send_fields(Ids.HELLO, _login)

func send_fields(packet_id: int, fields: Dictionary) -> Error:
	var result := Codec.encode_client(packet_id, fields)
	if not result.error.is_empty(): return ERR_INVALID_PARAMETER
	return send_packet(packet_id, result.payload)

## Raw PLAINTEXT packet BODY. Framing+encryption are applied exactly once here.
## Separately owned inventory helpers can call this without codec/view coupling.
func send_packet(packet_id: int, payload: PackedByteArray) -> Error:
	if not _active: return ERR_UNCONFIGURED
	if packet_id < 0 or packet_id > 255 or payload.size() + 5 > Framing.MAX_FRAME: return ERR_INVALID_PARAMETER
	if _out.size() - _out_offset + payload.size() + 5 > MAX_PENDING_OUT:
		_fail("outbound queue exceeds bound")
		return ERR_OUT_OF_MEMORY
	if _out_offset > 0:
		_out = _out.slice(_out_offset)
		_out_offset = 0
	_out.append_array(_wire.pack(packet_id, payload))
	return OK

func send_create(class_type: int, skin_type: int = 0) -> Error:
	return send_fields(Ids.CREATE, {"ClassType": class_type, "SkinType": skin_type})

func send_load(id: int, from_arena: bool = false) -> Error:
	return send_fields(Ids.LOAD, {"CharacterId": id, "IsFromArena": from_arena})

func send_move(tick_id: int, time_ms: int, position_tiles: Vector2, records: Array = []) -> Error:
	return send_fields(Ids.MOVE, {"TickId": tick_id, "Time": time_ms, "Position": position_tiles, "Records": records})

func send_shoot(time_ms: int, bullet_id: int, container_type: int, position_tiles: Vector2, angle_radians: float) -> Error:
	return send_fields(Ids.PLAYERSHOOT, {"Time": time_ms, "BulletId": bullet_id, "ContainerType": container_type, "Position": position_tiles, "Angle": angle_radians})

func send_pong(serial: int, time_ms: int) -> Error:
	return send_fields(Ids.PONG, {"Serial": serial, "Time": time_ms})

func send_update_ack() -> Error:
	return send_fields(Ids.UPDATEACK, {})

func send_goto_ack(time_ms: int) -> Error:
	return send_fields(Ids.GOTOACK, {"Time": time_ms})

func send_shoot_ack(time_ms: int) -> Error:
	return send_fields(Ids.SHOOTACK, {"Time": time_ms})

func send_aoe_ack(time_ms: int, position_tiles: Vector2) -> Error:
	return send_fields(Ids.AOEACK, {"Time": time_ms, "Position": position_tiles})

func _process(_delta: float) -> void:
	poll()

## Public for headless fixtures or a caller-owned polling loop. Never sleeps.
func poll() -> void:
	if not _active and not _connecting: return
	_peer.poll()
	var status := _peer.get_status()
	if _connecting:
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_connecting = false
			_active = true
			_clock_base = Time.get_ticks_msec()
			_peer.set_no_delay(true)
			connected.emit()
		elif status == StreamPeerTCP.STATUS_ERROR or Time.get_ticks_msec() >= _deadline:
			_fail("connection failed or timed out")
			return
	if not _active: return
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		disconnect_from_server("socket closed")
		return
	if _out.size() > _out_offset:
		var result := _peer.put_partial_data(_out.slice(_out_offset, mini(_out.size(), _out_offset + MAX_IO_PER_POLL)))
		if result[0] != OK:
			_fail("socket write failed")
			return
		_out_offset += int(result[1])
		if _out_offset == _out.size():
			_out.clear()
			_out_offset = 0
	var available := _peer.get_available_bytes()
	var chunk := PackedByteArray()
	if available > 0:
		var result := _peer.get_partial_data(mini(available, MAX_IO_PER_POLL))
		if result[0] != OK:
			_fail("socket read failed")
			return
		chunk = result[1]
	var session := _generation
	var frames := _wire.feed(chunk)
	if not _wire.error.is_empty():
		_fail(_wire.error)
		return
	for frame in frames:
		_handle_packet(frame.id, frame.payload)
		if session != _generation: return # Callback closed/reconnected this session.
	if _wire.buffered_bytes() > 0:
		if _partial_since == 0: _partial_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _partial_since > PARTIAL_FRAME_TIMEOUT_MS:
			_fail("partial frame deadline exceeded")
	else:
		_partial_since = 0

func _handle_packet(id: int, payload: PackedByteArray) -> void:
	var decoded := Codec.decode_server(id, payload)
	if not decoded.error.is_empty():
		_fail(decoded.error)
		return
	var fields: Dictionary = decoded.fields
	if id == Ids.CREATE_SUCCESS:
		object_id = fields.ObjectID
		character_id = fields.CharacterID
	var session := _generation
	packet_received.emit(id, fields.duplicate(true))
	if session != _generation: return
	match id:
		Ids.MAPINFO: map_info_received.emit(fields)
		Ids.UPDATE: entities_received.emit(fields)
		Ids.NEW_TICK: tick_received.emit(fields)
		Ids.SHOOT, Ids.SHOOT2, Ids.ALLYSHOOT: projectile_received.emit(id, fields)
		Ids.DEATH: death_received.emit(fields)
		Ids.FAILURE: failure_received.emit(fields)
		Ids.RECONNECT: reconnect_received.emit(fields)
		Ids.GOTO: goto_received.emit(fields)
		Ids.DAMAGE: damage_received.emit(fields)
		Ids.AOE: aoe_received.emit(fields)
	if session != _generation or not auto_ack or not _active: return
	var result: Error = OK
	match id:
		Ids.UPDATE: result = send_update_ack()
		Ids.PING: result = send_pong(fields.Serial, client_time_ms())
		Ids.GOTO: result = send_goto_ack(client_time_ms())
		Ids.SHOOT, Ids.SHOOT2: result = send_shoot_ack(client_time_ms())
	if result != OK: _fail("required acknowledgement failed")
	# NEW_TICK requires real movement/time records; AOE requires real position.
	# Never fabricate these, auto-login, follow Reconnect or select a character.

func _fail(reason: String) -> void:
	disconnect_from_server(reason)
	protocol_error.emit(reason) # Generic reason only, never payload/credentials.

func _exit_tree() -> void:
	disconnect_from_server("client removed")
	_login.clear()
