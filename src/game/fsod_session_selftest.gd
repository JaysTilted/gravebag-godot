extends SceneTree
const Session := preload("res://src/game/fsod_session.gd")

class Network extends Node:
	signal connected
	signal disconnected
	signal packet_received(id: int, fields: Dictionary)
	signal protocol_error(message: String)
	var sent: Array = []
	var configured: Dictionary = {}
	func configure_login(fields: Dictionary) -> void: configured = fields.duplicate(true)
	func connect_to_server(host: String, port: int) -> Error:
		sent.append({"method": "connect", "host": host, "port": port})
		return OK
	func send_hello() -> void: sent.append({"method": "hello"})
	func send_fields(id: int, fields: Dictionary) -> Error:
		sent.append({"id": id, "fields": fields})
		return OK
	func send_move(tick: int, time: int, position: Vector2, records: Array) -> void: sent.append({"method": "move", "tick": tick, "time": time, "position": position, "records": records})
	func send_shoot(time: int, bullet: int, weapon: int, position: Vector2, angle: float) -> void: sent.append({"method": "shoot", "time": time, "bullet": bullet, "weapon": weapon, "position": position, "angle": angle})

class Frontend extends Node:
	signal move_requested(position: Dictionary, records: Array)
	signal shoot_requested(angle: float)
	signal escape_requested
	signal interact_requested(entity: int, slot: int)
	signal projectile_hit_requested(owner: int, bullet: int, target: int, kind: String)
	var clock_ms: Callable
	var interaction_target_id := -1
	var prediction_speed_tiles := 0.0
	var shot_request_interval := 0.0
	var seen: Array = []
	func set_descriptors(value: Dictionary) -> void: seen.append({"method": "descriptors", "data": value})
	func apply_map(value: Dictionary) -> void: seen.append({"method": "map", "data": value})
	func apply_update(value: Dictionary) -> void: seen.append({"method": "update", "data": value})
	func apply_tick(value: Dictionary) -> void: seen.append({"method": "tick", "data": value})
	func apply_projectile(value: Dictionary) -> void: seen.append({"method": "projectile", "data": value})
	func set_player_id(value: int) -> void: seen.append({"method": "player", "id": value})

func _init() -> void:
	var network := Network.new()
	var view := Frontend.new()
	var session := Session.new()
	session.bind(network, view, {"objects": {"782": {"class": "Player"}, "900": {"class": "Container"}, "901": {"class": "Portal"}}}, {"100": {"RateOfFire": 1.0, "NumProjectiles": 3, "ArcGap": 10.0}})
	assert(session.start("example.com", 2050, {}) == ERR_INVALID_PARAMETER)
	assert(network.sent.is_empty(), "no external connection")
	assert(session.start("127.0.0.1", 2050, {"GameId": -2}) == OK)
	network.connected.emit()
	assert(session.state == "authenticating" and network.sent[-1].method == "hello")
	session.receive_packet(65, {"Width": 100, "Height": 80, "Name": "Nexus"})
	assert(network.sent[-1].id == 78 and network.sent[-1].fields.ClassType == 782)
	session.receive_packet(33, {"ObjectID": 1234, "CharacterID": 5})
	assert(session.state == "playing" and session.player_id == 1234 and session.character_id == 5)
	var status := {"Id": 1234, "Position": Vector2(12, 9), "Stats": [{"Type": 8, "Value": 100}, {"Type": 22, "Value": 75}, {"Type": 28, "Value": 75}, {"Type": 29, "Value": 0}]}
	session.receive_packet(7, {"Tiles": [], "NewObjects": [{"ObjectType": 782, "Stats": status}], "RemovedObjectIds": []})
	assert(is_equal_approx(view.prediction_speed_tiles, 9.6))
	assert(is_equal_approx(view.shot_request_interval, 0.125))
	view.move_requested.emit({"x": 13.0, "y": 10.0}, [{"time": 100, "position": {"x": 13.0, "y": 10.0}}])
	session.receive_packet(80, {"TickId": 7, "TickTime": 200, "UpdateStatuses": []})
	assert(network.sent[-1].method == "move" and network.sent[-1].position == Vector2(13, 10))
	assert(network.sent[-1].records[0].Position == Vector2(13, 10))
	var old_position: Vector2 = session.pending_position
	view.move_requested.emit({"x": -1.0, "y": 2.0}, [])
	assert(session.pending_position == old_position)
	var shots_before := network.sent.size()
	view.shoot_requested.emit(0.0)
	assert(network.sent.size() == shots_before + 3, "original item NumProjectiles honored")
	assert(is_equal_approx(network.sent[-3].angle, -deg_to_rad(10.0)))
	assert(network.sent[-2].angle == 0.0 and is_equal_approx(network.sent[-1].angle, deg_to_rad(10.0)))
	view.shoot_requested.emit(0.4)
	assert(network.sent.size() == shots_before + 3, "source dex cadence guards burst")
	session.receive_packet(3, {"ObjectId": 1234, "Position": Vector2(20, 22)})
	assert(session.pending_position == Vector2(20, 22))
	view.escape_requested.emit()
	assert(network.sent[-1].id == 47)
	var bag := {"Id": 99, "Position": Vector2(20, 22), "Stats": [{"Type": 8, "Value": 123}]}
	session.receive_packet(7, {"Tiles": [], "NewObjects": [{"ObjectType": 900, "Stats": bag}], "RemovedObjectIds": []})
	assert(view.interaction_target_id == 99)
	assert(session.pickup(99, 0) == OK and network.sent[-1].id == 34)
	assert(network.sent[-1].fields.SlotObject1.ObjectType == 123)
	assert(network.sent[-1].fields.SlotObject2.SlotId == 4)
	assert(session.entity_states[99].stats[8] == 123, "no optimistic item destruction")
	for slot in range(4, 12):
		session.player_stats[8 + slot] = 1
	assert(session.pickup(99, 0) == ERR_OUT_OF_MEMORY)
	assert(session.use_item(0, Vector2(21, 22)) == OK and network.sent[-1].id == 48)
	assert(session.use_item(0, Vector2(21, 22), 256) == ERR_INVALID_PARAMETER)
	view.projectile_hit_requested.emit(1234, 2, 100, "enemy")
	assert(network.sent[-1].id == 42 and not network.sent[-1].fields.Killed)
	view.projectile_hit_requested.emit(100, 3, 1234, "player")
	assert(network.sent[-1].id == 17 and network.sent[-1].fields.ObjectId == 100)
	assert(session._slot_stat(12) == 71 and session._slot_stat(19) == 78)
	session.receive_packet(63, {"AccountId": "42"})
	assert(session.state == "dead" and session.character_id == -1)
	var messages := network.sent.size()
	view.shoot_requested.emit(0.0)
	assert(network.sent.size() == messages, "death never locally fires or respawns")
	# Portal reconnect preserves server key/game and original existing character on living runs.
	session.character_id = 5
	session.receive_packet(21, {"Host": "", "Port": -1, "GameId": -10, "KeyTime": 123, "Key": PackedByteArray([1, 2])})
	assert(session.state == "reconnecting" and network.configured.GameId == -10)
	assert(network.configured.Key == PackedByteArray([1, 2]))
	session.receive_packet(65, {"Width": 40, "Height": 40, "Name": "Realm"})
	assert(network.sent[-1].id == 8 and network.sent[-1].fields.CharacterId == 5)
	session.free()
	view.free()
	network.free()
	print("FSOD SESSION SELFTEST PASS")
	quit(0)
