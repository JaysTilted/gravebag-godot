extends Node
## Godot frontend session for the complete ORIGINAL FSoD server.
## Wire constants/rates from upstream 6fd20aad... PacketIds.cs, StatsManager.cs.
## AGPL-3.0 adaptation, 2026-10-06. No AI, loot, XP or damage simulation here.
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
signal state_changed(state: String)
signal server_event(packet_id: int, fields: Dictionary)
signal session_error(message: String)

var transport: Node
var view: Node
var state := "offline"
var player_id := -1
var character_id := -1
var class_type := 782 # Original XML Wizard, 0x030e.
var skin_type := 0
var map_bounds := Vector2.ZERO
var object_types: Dictionary = {}
var player_stats: Dictionary = {}
var item_descriptors: Dictionary = {}
var login: Dictionary = {}
var pending_position := Vector2.ZERO
var move_records: Array = []
var _clock_start := 0
var _bullet_id := 0
var _last_shot_ms := -1000000
var _host := "127.0.0.1"
var _port := 2050


func bind(network: Node, frontend: Node, metadata: Dictionary = {}, items: Dictionary = {}) -> void:
	transport = network
	view = frontend
	item_descriptors = items
	transport.connect("connected", _on_connected)
	transport.connect("disconnected", _on_disconnected)
	transport.connect("packet_received", receive_packet)
	transport.connect("protocol_error", _on_protocol_error)
	view.connect("move_requested", _on_move)
	view.connect("shoot_requested", _on_shoot)
	view.connect("escape_requested", _on_escape)
	view.connect("interact_requested", _on_interact)
	view.call("set_descriptors", metadata)
	view.set("clock_ms", Callable(self, "clock_ms"))


func start(host: String, port: int, login_fields: Dictionary, load_character_id: int = -1) -> Error:
	# Local development only: never follow an upstream/public reconnect hostname.
	if host not in ["127.0.0.1", "localhost", "::1"] or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	if not is_instance_valid(transport) or not is_instance_valid(view):
		return ERR_UNCONFIGURED
	_host = host
	_port = port
	login = login_fields.duplicate(true)
	character_id = load_character_id
	_clock_start = Time.get_ticks_msec()
	_set_state("connecting")
	transport.call("configure_login", login)
	return transport.call("connect_to_server", host, port)


func clock_ms() -> int:
	return int(Time.get_ticks_msec() - _clock_start)


func _set_state(next: String) -> void:
	state = next
	state_changed.emit(state)


func _on_connected() -> void:
	_set_state("authenticating")
	transport.call("send_hello")


func _on_disconnected() -> void:
	if state != "reconnecting":
		_set_state("offline")


func _on_protocol_error(message: String) -> void:
	_set_state("failed")
	session_error.emit(message)


func receive_packet(packet_id: int, fields: Dictionary) -> void:
	match packet_id:
		65: # MAPINFO: server world loaded; original CREATE/LOAD now enters it.
			map_bounds = Vector2(float(fields["Width"]), float(fields["Height"]))
			object_types.clear()
			player_stats.clear()
			move_records.clear()
			view.call("apply_map", Adapter.map_info(fields))
			_set_state("loading_character")
			if character_id >= 0:
				transport.call("send_fields", 8, {"CharacterId": character_id, "IsFromArena": false})
			else:
				transport.call("send_fields", 78, {"ClassType": class_type, "SkinType": skin_type})
		33: # CREATE_SUCCESS
			player_id = int(fields["ObjectID"])
			character_id = int(fields["CharacterID"])
			view.call("set_player_id", player_id)
			_set_state("playing")
		7: # UPDATE; transport owns original UPDATEACK.
			for object in fields.get("NewObjects", []):
				var record: Dictionary = object["Stats"]
				object_types[int(record["Id"])] = int(object["ObjectType"])
				_observe_status(record)
			for removed in fields.get("RemovedObjectIds", []):
				object_types.erase(int(removed))
			view.call("apply_update", Adapter.update(fields))
		80: # NEW_TICK; report client position + samples, server validates and simulates.
			for record in fields.get("UpdateStatuses", []):
				_observe_status(record)
			view.call("apply_tick", Adapter.tick(fields))
			if state == "playing":
				transport.call("send_move", int(fields["TickId"]), clock_ms(), pending_position, move_records.duplicate(true))
				move_records.clear()
		84, 96:
			var owner_type := int(object_types.get(int(fields["OwnerId"]), -1))
			view.call("apply_projectile", Adapter.projectile(fields, owner_type))
		3: # GOTO: codec sends GOTOACK; view updates authoritative position.
			var record := {"Id": int(fields["ObjectId"]), "Position": fields["Position"], "Stats": []}
			if int(fields["ObjectId"]) == player_id:
				pending_position = _vector(fields["Position"])
			_observe_status(record)
			view.call("apply_tick", Adapter.tick({"TickId": -1, "TickTime": 0, "UpdateStatuses": [record]}))
		63: # DEATH: never fake a respawn or local fame award.
			character_id = -1
			_set_state("dead")
		0:
			_set_state("failed")
			session_error.emit(String(fields.get("ErrorDescription", "Server rejected connection")))
		21:
			_reconnect(fields)
	# Other original server commands are retained for inventory/trade/guild UI.
	server_event.emit(packet_id, fields)


func _observe_status(record: Dictionary) -> void:
	if int(record["Id"]) != player_id:
		return
	# Initialize position on first authoritative state; preserve active prediction until GOTO.
	if player_stats.is_empty():
		pending_position = _vector(record["Position"])
	for pair in record.get("Stats", []):
		player_stats[int(pair["Type"])] = pair["Value"]
	_update_input_rates()


func _vector(value: Variant) -> Vector2:
	var normalized := Adapter.position(value)
	return Vector2(normalized.x, normalized.y)


func _on_move(position_tiles: Variant, records: Array) -> void:
	if state != "playing":
		return
	var requested := _vector(position_tiles)
	if not requested.is_finite() or requested.x < 0 or requested.y < 0 or requested.x >= map_bounds.x or requested.y >= map_bounds.y:
		return
	pending_position = requested
	# Source TimedPosition records use Time + Position (two tile floats).
	for record in records:
		if move_records.size() >= 128:
			break
		var pos := _vector(record.get("position", position_tiles))
		if pos.is_finite():
			move_records.append({"Time": int(record.get("time", clock_ms())), "Position": pos})


func _update_input_rates() -> void:
	var effects := int(player_stats.get(29, 0))
	# Original StatsManager GetSpeed/GetDex: client input/prediction only.
	var speed := 4.0 + 5.6 * float(player_stats.get(22, 0)) / 75.0
	if effects & (1 << 14):
		speed *= 1.5
	if effects & (1 << 3):
		speed = 4.0
	if effects & (1 << 13):
		speed = 0.0
	var dex := 0.0 if effects & (1 << 5) else float(player_stats.get(28, 0))
	var attacks := 1.5 + 6.5 * dex / 75.0
	if effects & (1 << 19):
		attacks *= 1.5
	if effects & (1 << 6):
		attacks = 0.0
	var weapon_type := int(player_stats.get(8, -1))
	var item: Dictionary = item_descriptors.get(str(weapon_type), {})
	item = item.get("descriptor", item)
	# Missing item data must disable firing, not invent weapon stats.
	var rate := float(item.get("RateOfFire", 0.0))
	view.set("prediction_speed_tiles", speed)
	view.set("shot_request_interval", 1.0 / (attacks * rate) if attacks * rate > 0.0 else 0.0)


func _on_shoot(angle_radians: float) -> void:
	if state != "playing" or not is_finite(angle_radians):
		return
	var interval := float(view.get("shot_request_interval"))
	if interval <= 0.0 or clock_ms() - _last_shot_ms < int(ceil(interval * 1000.0)):
		return
	var weapon_type := int(player_stats.get(8, -1))
	if weapon_type < 0:
		return
	var item: Dictionary = item_descriptors.get(str(weapon_type), {})
	item = item.get("descriptor", item)
	var count := int(item.get("NumProjectiles", 1))
	var arc := deg_to_rad(float(item.get("ArcGap", 0.0)))
	if count < 1 or count > 256:
		return
	_last_shot_ms = clock_ms()
	for index in count:
		var angle := angle_radians + (float(index) - float(count - 1) * 0.5) * arc
		transport.call("send_shoot", clock_ms(), _bullet_id, weapon_type, pending_position, angle)
		# Original server broadcasts AllyShoot to OTHER clients, not the shooter.
		# Render our own shot; hits still become commands to the original server.
		view.call("apply_projectile", {"owner_id": player_id, "bullet_id": _bullet_id, "container_type": weapon_type, "bullet_type": 0, "position": Adapter.position(pending_position), "angle": angle})
		_bullet_id = (_bullet_id + 1) & 255


func _on_escape() -> void:
	if state == "playing":
		transport.call("send_fields", 47, {})


func _on_interact(entity_id: int, _slot: int) -> void:
	if state == "playing" and object_types.has(entity_id):
		transport.call("send_fields", 9, {"ObjectId": entity_id})


func _reconnect(fields: Dictionary) -> void:
	var host := String(fields.get("Host", ""))
	if host.is_empty():
		host = _host
	if host not in ["127.0.0.1", "localhost", "::1"]:
		_on_protocol_error("Non-local reconnect refused by local-development launcher")
		return
	var port := int(fields.get("Port", _port))
	if port == -1:
		port = _port
	if port < 1 or port > 65535:
		_on_protocol_error("Invalid reconnect port")
		return
	login["GameId"] = fields["GameId"]
	login["KeyTime"] = fields.get("KeyTime", 0)
	login["Key"] = fields.get("Key", PackedByteArray())
	move_records.clear()
	player_stats.clear()
	object_types.clear()
	_set_state("reconnecting")
	transport.call("configure_login", login)
	transport.call("connect_to_server", host, port)
