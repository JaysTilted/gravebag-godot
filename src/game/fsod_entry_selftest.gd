extends SceneTree
## Playable-entry recovery selftest. Actual Godot events + mock transport.
## Proves: CREATE (not LOAD) after death, LOAD saved char on reconnect,
## one connect per button, dead preserved across socket close, failures usable.
## Never logs credentials; uses dummy GUID/Password only.
const Session := preload("res://src/game/fsod_session.gd")
const Entry := preload("res://src/game/fsod_entry.gd")
const Codec := preload("res://src/net/fsod/codec.gd")

class Network extends Node:
	signal connected
	signal disconnected(reason: String)
	signal packet_received(id: int, fields: Dictionary)
	signal protocol_error(message: String)
	var sent: Array = []
	var configured: Dictionary = {}
	func configure_login(fields: Dictionary) -> void:
		configured = fields.duplicate(true)
	func connect_to_server(host: String, port: int) -> Error:
		sent.append({"method": "connect", "host": host, "port": port})
		# Match real client.connect_to_server replacing an active old peer.
		disconnected.emit("new connection")
		return OK
	func send_hello() -> Error:
		sent.append({"method": "hello"})
		return OK
	func send_fields(id: int, fields: Dictionary) -> Error:
		var encoded := Codec.encode_client(id, fields)
		if not encoded.error.is_empty():
			return ERR_INVALID_PARAMETER
		sent.append({"id": id, "fields": fields, "payload": encoded.payload})
		return OK
	func send_packet(id: int, payload: PackedByteArray) -> Error:
		sent.append({"id": id, "payload": payload})
		return OK
	func send_move(tick: int, time: int, position: Vector2, records: Array) -> void:
		sent.append({"method": "move", "tick": tick, "time": time, "position": position, "records": records})
	func send_shoot(time: int, bullet: int, weapon: int, position: Vector2, angle: float) -> void:
		sent.append({"method": "shoot", "time": time, "bullet": bullet, "weapon": weapon, "position": position, "angle": angle})
	func connect_count() -> int:
		var total := 0
		for item in sent:
			if item.get("method") == "connect":
				total += 1
		return total
	func last_field_id() -> int:
		for index in range(sent.size() - 1, -1, -1):
			if sent[index].has("id"):
				return int(sent[index].id)
		return -1

class Frontend extends Node:
	signal move_requested(position: Dictionary, records: Array)
	signal shoot_requested(angle: float)
	signal escape_requested
	signal interact_requested(entity: int, slot: int)
	signal projectile_hit_requested(owner: int, bullet: int, target: int, kind: String)
	signal ability_requested(position: Vector2)
	signal potion_requested(kind: String)
	signal ground_damage_requested(position: Vector2)
	signal inventory_swap_requested(source_id: int, source_slot: int, destination_id: int, destination_slot: int)
	signal item_use_requested(slot: int)
	var clock_ms: Callable
	var interaction_target_id := -1
	var prediction_speed_tiles := 0.0
	var shot_request_interval := 0.0
	var seen: Array = []
	func set_descriptors(value: Dictionary) -> void:
		seen.append({"method": "descriptors", "data": value})
	func apply_map(value: Dictionary) -> void:
		seen.append({"method": "map", "data": value})
	func apply_update(value: Dictionary) -> void:
		seen.append({"method": "update", "data": value})
	func apply_tick(value: Dictionary) -> void:
		seen.append({"method": "tick", "data": value})
	func apply_projectile(value: Dictionary) -> void:
		seen.append({"method": "projectile", "data": value})
	func set_player_id(value: int) -> void:
		seen.append({"method": "player", "id": value})
	func map_count() -> int:
		var total := 0
		for item in seen:
			if item.get("method") == "map":
				total += 1
		return total

func _login_fields() -> Dictionary:
	return {"GameId": -2, "GUID": "G", "Password": "P", "KeyTime": 0, "Key": PackedByteArray()}

func _init() -> void:
	_session_create_after_death()
	_session_load_on_reconnect()
	_session_failures_usable()
	_entry_buttons_via_real_events()
	print("FSOD ENTRY SELFTEST PASS")
	quit(0)

func _make_session() -> Array:
	var network := Network.new()
	var view := Frontend.new()
	var session := Session.new()
	session.bind(network, view, {"objects": {"782": {"class": "Player"}}}, {})
	root.add_child(network)
	root.add_child(view)
	root.add_child(session)
	return [network, view, session]

func _free_session(parts: Array) -> void:
	for node in parts:
		node.free()

func _session_create_after_death() -> void:
	var parts := _make_session()
	var network: Network = parts[0]
	var view: Frontend = parts[1]
	var session: Node = parts[2]
	assert(session.start("127.0.0.1", 2050, _login_fields(), -1) == OK)
	network.connected.emit()
	assert(session.state == "authenticating", "hello flow")
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(network.last_field_id() == 78, "fresh Nexus entry sends CREATE")
	session.receive_packet(33, {"ObjectID": 111, "CharacterID": 5})
	assert(session.state == "playing" and session.character_id == 5)
	# Living portal reconnect keeps the existing character on LOAD path.
	session.receive_packet(21, {"Host": "", "Port": -1, "GameId": -10, "KeyTime": 123, "Key": PackedByteArray([1, 2])})
	assert(session.state == "reconnecting" and network.configured["GameId"] == -10)
	session.receive_packet(65, {"Width": 40, "Height": 40, "Name": "Realm"})
	assert(network.last_field_id() == 8 and network.sent[-1].fields["CharacterId"] == 5, "living portal LOADs existing char")
	session.receive_packet(33, {"ObjectID": 222, "CharacterID": 5})
	assert(session.state == "playing")
	var status := {"Id": 222, "Position": Vector2(10, 8), "Stats": [{"Type": 1, "Value": 200}, {"Type": 8, "Value": 100}]}
	session.receive_packet(7, {"Tiles": [], "NewObjects": [{"ObjectType": 782, "Stats": status}], "RemovedObjectIds": []})
	var stats_before: Dictionary = session.player_stats.duplicate()
	assert(stats_before.get(1) == 200, "authoritative stats observed")
	# Server DEATH never fakes a respawn.
	session.receive_packet(63, {"AccountId": "42"})
	assert(session.state == "dead" and session.character_id == -1, "death clears char, state dead")
	# Socket close after death must preserve dead (no silent offline flip).
	network.disconnected.emit("socket closed")
	assert(session.state == "dead" and session.character_id == -1, "dead preserved across socket close")
	var connects_before: int = network.connect_count()
	var maps_before: int = view.map_count()
	var result: Error = session.retry_connection()
	assert(result == ERR_INVALID_PARAMETER, "dead must not LOAD via retry")
	assert(network.connect_count() == connects_before, "rejected retry sends nothing")
	assert(session.restart_as_new_character() == OK, "dead restarts as new character")
	assert(session.state == "connecting", "restart connects")
	assert(session.character_id == -1, "dead id never resurrected")
	assert(session.login["GameId"] == -2 and session.login["KeyTime"] == 0 and session.login["Key"] == PackedByteArray(), "Nexus HELLO restored")
	assert(session.login["GUID"] == "G" and session.login["Password"] == "P", "encrypted credentials reused")
	assert(session.player_stats == stats_before, "no local HP/XP/inventory mutation on restart")
	assert(view.map_count() == maps_before, "view clears only on real MAPINFO, not on restart")
	assert(network.connect_count() == connects_before + 1, "exactly one connect")
	assert(network.configured["GameId"] == -2, "transport reconfigured to Nexus")
	# Duplicate click while connecting is refused without a second connect.
	assert(session.restart_as_new_character() == ERR_BUSY, "duplicate restart refused")
	assert(session.retry_connection() == ERR_BUSY, "retry while connecting refused")
	assert(network.connect_count() == connects_before + 1, "one connect per button")
	network.connected.emit()
	assert(session.state == "authenticating")
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(view.map_count() == maps_before + 1, "real MAPINFO clears view")
	assert(network.last_field_id() == 78, "CREATE after death, never LOAD of dead id")
	assert(session.character_id == -1, "no resurrection before server CREATE_SUCCESS")
	session.receive_packet(33, {"ObjectID": 333, "CharacterID": 6})
	assert(session.state == "playing" and session.character_id == 6, "server authorizes new char")
	_free_session(parts)

func _session_load_on_reconnect() -> void:
	var parts := _make_session()
	var network: Network = parts[0]
	var view: Frontend = parts[1]
	var session: Node = parts[2]
	assert(session.start("127.0.0.1", 2050, _login_fields(), 9) == OK)
	network.connected.emit()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(network.last_field_id() == 8 and network.sent[-1].fields["CharacterId"] == 9, "saved char LOADs")
	session.receive_packet(33, {"ObjectID": 444, "CharacterID": 9})
	assert(session.state == "playing")
	network.disconnected.emit("socket closed")
	assert(session.state == "offline", "unexpected close becomes offline")
	var connects_before: int = network.connect_count()
	assert(session.restart_as_new_character() == ERR_INVALID_PARAMETER, "offline must not CREATE via restart")
	assert(network.connect_count() == connects_before)
	assert(session.retry_connection() == OK, "offline retries with saved char")
	assert(session.state == "connecting" and session.character_id == 9, "saved char preserved")
	assert(session.login["GameId"] == -2 and session.login["KeyTime"] == 0, "Nexus HELLO restored on retry")
	assert(network.connect_count() == connects_before + 1)
	assert(session.retry_connection() == ERR_BUSY, "duplicate reconnect click refused")
	assert(network.connect_count() == connects_before + 1, "one connect per button")
	network.connected.emit()
	var maps_before: int = view.map_count()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(view.map_count() == maps_before + 1, "real MAPINFO clears view on retry")
	assert(network.last_field_id() == 8 and network.sent[-1].fields["CharacterId"] == 9, "LOAD saved char on reconnect")
	_free_session(parts)

func _session_failures_usable() -> void:
	var parts := _make_session()
	var network: Network = parts[0]
	var view: Frontend = parts[1]
	var session: Node = parts[2]
	assert(session.start("127.0.0.1", 2050, _login_fields(), -1) == OK)
	network.connected.emit()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	session.receive_packet(33, {"ObjectID": 555, "CharacterID": 11})
	assert(session.state == "playing")
	var failures: Array = []
	session.session_error.connect(func(message: String) -> void: failures.append(message))
	# Server FAILURE is usable, not fake success.
	session.receive_packet(0, {"ErrorId": 7, "ErrorDescription": "boom"})
	assert(session.state == "failed", "failure state")
	assert(failures.size() == 1, "failure emits usable error, not silent")
	network.disconnected.emit("socket closed")
	assert(session.state == "failed", "failed preserved across socket close")
	var connects_before: int = network.connect_count()
	assert(session.retry_connection() == OK, "failure retry usable")
	assert(session.state == "connecting")
	assert(network.connect_count() == connects_before + 1)
	network.connected.emit()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(session.state == "loading_character", "retry not faked to playing")
	assert(network.last_field_id() == 8, "saved char LOADs after failure")
	# Protocol errors also land in failed with a usable retry.
	_free_session(parts)
	var parts2 := _make_session()
	var network2: Network = parts2[0]
	var session2: Node = parts2[2]
	assert(session2.start("127.0.0.1", 2050, _login_fields(), -1) == OK)
	network2.connected.emit()
	network2.protocol_error.emit("socket write failed")
	assert(session2.state == "failed", "protocol error becomes failed")
	assert(session2.retry_connection() == OK, "protocol failure retry usable")
	_free_session(parts2)
	# Wrong-state guards never invent connects.
	var parts3 := _make_session()
	var network3: Network = parts3[0]
	var session3: Node = parts3[2]
	assert(session3.start("127.0.0.1", 2050, _login_fields(), -1) == OK)
	assert(session3.retry_connection() == ERR_BUSY, "no retry while connecting")
	assert(session3.restart_as_new_character() == ERR_BUSY, "no restart while connecting")
	assert(network3.connect_count() == 1, "guards send nothing extra")
	_free_session(parts3)

func _entry_buttons_via_real_events() -> void:
	var parts := _make_session()
	var network: Network = parts[0]
	var view: Frontend = parts[1]
	var session: Node = parts[2]
	var entry: Node = Entry.new()
	var status_label := Label.new()
	entry.add_child(status_label)
	entry._status = status_label
	var button := Button.new()
	entry.add_child(button)
	entry._action = button
	entry._profile_path = "/tmp/fsod-entry-selftest-profile.json"
	entry._profile = {"character_id": -1, "hello": _login_fields(), "host": "127.0.0.1", "port": 2050}
	entry.session = session
	button.pressed.connect(entry._on_action)
	session.state_changed.connect(entry._on_state)
	session.session_error.connect(entry._fail)
	root.add_child(entry)
	assert(session.start("127.0.0.1", 2050, _login_fields(), -1) == OK)
	# Connecting hides the button (duplicate clicks disabled).
	assert(button.visible == false and button.disabled == true, "no button while connecting")
	network.connected.emit()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	session.receive_packet(33, {"ObjectID": 777, "CharacterID": 21})
	assert(session.state == "playing")
	assert(button.visible == false, "no button while playing")
	# Normal portal reconnect never shows the failure button.
	session.receive_packet(21, {"Host": "", "Port": -1, "GameId": -10, "KeyTime": 5, "Key": PackedByteArray([9])})
	assert(session.state == "reconnecting")
	assert(button.visible == false, "no failure button during portal reconnect")
	session.receive_packet(65, {"Width": 40, "Height": 40, "Name": "Realm"})
	session.receive_packet(33, {"ObjectID": 778, "CharacterID": 21})
	assert(session.state == "playing")
	# Death shows a real New character button via the actual state signal.
	session.receive_packet(63, {"AccountId": "42"})
	assert(session.state == "dead")
	assert(button.visible == true and button.disabled == false and button.text == "New character", "death shows New character")
	var connects_before: int = network.connect_count()
	button.pressed.emit()
	assert(session.state == "connecting", "button press connects")
	assert(network.connect_count() == connects_before + 1, "one connect per button press")
	assert(button.visible == false, "button hides while connecting")
	button.pressed.emit()
	assert(network.connect_count() == connects_before + 1, "duplicate press sends nothing")
	network.connected.emit()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(network.last_field_id() == 78, "entry death path CREATEs")
	session.receive_packet(33, {"ObjectID": 779, "CharacterID": 22})
	assert(session.state == "playing")
	# Offline shows a real Reconnect button.
	network.disconnected.emit("socket closed")
	assert(session.state == "offline")
	assert(button.visible == true and button.text == "Reconnect" and button.disabled == false, "offline shows Reconnect")
	connects_before = network.connect_count()
	button.pressed.emit()
	assert(network.connect_count() == connects_before + 1, "reconnect press connects once")
	assert(session.login["GameId"] == -2, "entry retry restores Nexus HELLO")
	network.connected.emit()
	session.receive_packet(65, {"Width": 60, "Height": 40, "Name": "Nexus"})
	assert(network.last_field_id() == 8, "entry reconnect LOADs saved char")
	session.receive_packet(33, {"ObjectID": 780, "CharacterID": 22})
	# Failure shows a usable Reconnect button, not a fake success.
	session.receive_packet(0, {"ErrorId": 1, "ErrorDescription": "nope"})
	assert(session.state == "failed")
	assert(button.visible == true and button.text == "Reconnect", "failure shows Reconnect")
	connects_before = network.connect_count()
	button.pressed.emit()
	assert(network.connect_count() == connects_before + 1, "failure retry connects")
	assert(session.state == "connecting", "failure retry not faked to playing")
	entry.free()
	_free_session(parts)
