extends Node
## Godot frontend session for the complete ORIGINAL FSoD server.
## Wire constants/rates from upstream 6fd20aad... PacketIds.cs, StatsManager.cs.
## AGPL-3.0 adaptation, 2026-10-06. No AI, loot, XP or damage simulation here.
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
const Commands := preload("res://src/net/fsod_inventory/commands.gd")
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
var entity_states: Dictionary = {}
var metadata: Dictionary = {}
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


func bind(network: Node, frontend: Node, descriptors: Dictionary = {}, items: Dictionary = {}) -> void:
	transport = network
	view = frontend
	metadata = descriptors.duplicate()
	metadata["items"] = items
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
	if view.has_signal("projectile_hit_requested"):
		view.connect("projectile_hit_requested", _on_projectile_hit)
	if view.has_signal("ability_requested"):
		view.connect("ability_requested", _on_ability)
	if view.has_signal("potion_requested"):
		view.connect("potion_requested", consume_potion)
	if view.has_signal("ground_damage_requested"):
		view.connect("ground_damage_requested", _on_ground_damage)
	if view.has_signal("inventory_swap_requested"):
		view.connect("inventory_swap_requested", _on_inventory_swap)
	if view.has_signal("item_use_requested"):
		view.connect("item_use_requested", _on_inventory_use)


func start(host: String, port: int, login_fields: Dictionary, load_character_id: int = -1) -> Error:
	# Local development only: never follow an upstream/public reconnect hostname.
	if host not in ["127.0.0.1", "localhost", "::1"] or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	if not is_instance_valid(transport) or not is_instance_valid(view):
		return ERR_UNCONFIGURED
	_host = host
	_port = port
	login = normalize_login(login_fields)
	if not login_fields.is_empty() and login.is_empty():
		return ERR_INVALID_PARAMETER
	character_id = load_character_id
	_clock_start = Time.get_ticks_msec()
	_set_state("connecting")
	transport.call("configure_login", login)
	return transport.call("connect_to_server", host, port)


## Playable-entry recovery. Original server creates/saves/authorizes; no delays.
## retry_connection() re-enters the stored Nexus with the saved character_id
## (MAPINFO then sends LOAD, or CREATE when no character is saved).
## restart_as_new_character() re-enters the stored Nexus as a fresh character
## (MAPINFO then sends CREATE, never LOADs the dead id).
## Both restore the original Nexus HELLO (GameId -2, KeyTime 0, empty Key),
## reuse the stored encrypted GUID/Password, and connect once to the stored
## Nexus host/port. View/map clearing happens only on real MAPINFO. Never
## resurrects a dead character or mutates HP/XP/inventory locally.
## Duplicate clicks while connecting/authenticating/loading/reconnecting/playing
## return ERR_BUSY without a second transport connect.
func retry_connection() -> Error:
	if state in ["connecting", "authenticating", "loading_character", "reconnecting", "playing"]:
		return ERR_BUSY
	if state not in ["offline", "failed"]:
		return ERR_INVALID_PARAMETER
	if not is_instance_valid(transport) or login.is_empty():
		return ERR_UNCONFIGURED
	_reset_to_nexus_hello()
	_set_state("connecting")
	transport.call("configure_login", login)
	var result: Error = transport.call("connect_to_server", _host, _port)
	if result != OK:
		_set_state("failed")
	return result


func restart_as_new_character() -> Error:
	if state in ["connecting", "authenticating", "loading_character", "reconnecting", "playing"]:
		return ERR_BUSY
	if state != "dead":
		return ERR_INVALID_PARAMETER
	if not is_instance_valid(transport) or login.is_empty():
		return ERR_UNCONFIGURED
	# Fresh Nexus character only; the dead id is never reloaded.
	character_id = -1
	player_id = -1
	_reset_to_nexus_hello()
	_set_state("connecting")
	transport.call("configure_login", login)
	var result: Error = transport.call("connect_to_server", _host, _port)
	if result != OK:
		_set_state("failed")
	return result


func _reset_to_nexus_hello() -> void:
	# Nexus entry only: clear portal reconnect tokens, keep encrypted credentials.
	login["GameId"] = -2
	login["KeyTime"] = 0
	login["Key"] = PackedByteArray()


static func normalize_login(fields: Dictionary) -> Dictionary:
	var normalized := fields.duplicate(true)
	# JSON numbers arrive as floats; the binary codec rightly requires typed integers.
	for key in ["GameId", "IgnoredInt", "randomint1", "KeyTime"]:
		if not normalized.has(key):
			continue
		var value: Variant = normalized[key]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)) or float(value) < -2147483648.0 or float(value) > 2147483647.0:
			return {}
		normalized[key] = int(value)
	for key in ["Key", "MapInfo"]:
		if not normalized.has(key) or normalized[key] is PackedByteArray:
			continue
		var value: Variant = normalized[key]
		if not value is Array:
			return {}
		var bytes := PackedByteArray()
		for byte in value:
			if not (byte is int or byte is float) or not is_finite(float(byte)) or float(byte) != floor(float(byte)) or float(byte) < 0.0 or float(byte) > 255.0:
				return {}
			bytes.append(int(byte))
		normalized[key] = bytes
	return normalized


func clock_ms() -> int:
	return int(Time.get_ticks_msec() - _clock_start)


func _set_state(next: String) -> void:
	state = next
	state_changed.emit(state)


func _on_connected() -> void:
	_set_state("authenticating")
	var result: Error = transport.call("send_hello")
	if result != OK:
		_on_protocol_error("Unable to serialize encrypted local login")


func _on_disconnected(reason: String = "") -> void:
	# Replacing a still-active death socket closes it synchronously before the
	# next peer is installed. Do not turn that intentional close into offline.
	if reason == "new connection" and state == "connecting":
		return
	if state not in ["reconnecting", "dead", "failed"]:
		_set_state("offline")


func _on_protocol_error(message: String) -> void:
	_set_state("failed")
	session_error.emit(message)


func receive_packet(packet_id: int, fields: Dictionary) -> void:
	match packet_id:
		65: # MAPINFO: server world loaded; original CREATE/LOAD now enters it.
			map_bounds = Vector2(float(fields["Width"]), float(fields["Height"]))
			object_types.clear()
			entity_states.clear()
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
				entity_states.erase(int(removed))
			view.call("apply_update", Adapter.update(fields))
			_update_interaction_target()
		80: # NEW_TICK; report client position + samples, server validates and simulates.
			for record in fields.get("UpdateStatuses", []):
				_observe_status(record)
			view.call("apply_tick", Adapter.tick(fields))
			if state == "playing":
				transport.call("send_move", int(fields["TickId"]), clock_ms(), pending_position, move_records.duplicate(true))
				move_records.clear()
			_update_interaction_target()
		84, 92, 96:
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
	var id := int(record["Id"])
	var snapshot: Dictionary = entity_states.get(id, {"stats": {}})
	snapshot["position"] = _vector(record["Position"])
	for pair in record.get("Stats", []):
		snapshot.stats[int(pair["Type"])] = pair["Value"]
	entity_states[id] = snapshot
	if id != player_id:
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
	var effects: int = (int(player_stats.get(29, 0)) & 0xffffffff) | ((int(player_stats.get(96, 0)) & 0xffffffff) << 32)
	# Original StatsManager GetSpeed/GetDex: client input/prediction only.
	var speed := 4.0 + 5.6 * float(player_stats.get(22, 0)) / 75.0
	if effects & ((1 << 14) | (1 << 47)):
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


func _class_for(entity_id: int) -> String:
	var record: Dictionary = metadata.get("objects", {}).get(str(object_types.get(entity_id, -1)), {})
	return String(record.get("class", ""))


func _update_interaction_target() -> void:
	var nearest := -1
	var distance := 1.0 # UI interaction affordance; original server checks actual distance.
	for id in entity_states:
		if id == player_id or _class_for(id) not in ["Portal", "Container"]:
			continue
		var candidate: float = pending_position.distance_to(entity_states[id].position)
		if candidate < distance:
			nearest = id
			distance = candidate
	# This optional view field is part of the current frontend contract.
	if _has_property(view, "interaction_target_id"):
		view.set("interaction_target_id", nearest)


func _has_property(object: Object, property: String) -> bool:
	for info in object.get_property_list():
		if info.name == property:
			return true
	return false


func _on_interact(entity_id: int, slot: int) -> void:
	if state != "playing" or not object_types.has(entity_id):
		return
	if _class_for(entity_id) == "Portal":
		transport.call("send_fields", 9, {"ObjectId": entity_id})
	elif _class_for(entity_id) == "Container":
		pickup(entity_id, slot)


func pickup(container_id: int, source_slot: int) -> Error:
	if state != "playing" or source_slot < 0 or source_slot > 7 or not entity_states.has(container_id):
		return ERR_INVALID_PARAMETER
	var item_type := int(entity_states[container_id].stats.get(8 + source_slot, -1))
	if item_type < 0:
		return ERR_DOES_NOT_EXIST
	for destination_slot in range(4, 12):
		if int(player_stats.get(8 + destination_slot, -1)) < 0:
			return swap_slots(container_id, source_slot, player_id, destination_slot)
	return ERR_OUT_OF_MEMORY # Full inventory leaves bag and player unchanged.


func swap_slots(source_id: int, source_slot: int, destination_id: int, destination_slot: int) -> Error:
	if state != "playing" or not entity_states.has(source_id) or not entity_states.has(destination_id):
		return ERR_UNCONFIGURED
	if source_slot < 0 or source_slot > 19 or destination_slot < 0 or destination_slot > 19:
		return ERR_INVALID_PARAMETER
	var source_type := int(entity_states[source_id].stats.get(_slot_stat(source_slot), -1))
	var destination_type := int(entity_states[destination_id].stats.get(_slot_stat(destination_slot), -1))
	# Inventory is mutated ONLY by subsequent authoritative server updates.
	return send_gameplay(Commands.inv_swap(clock_ms(), pending_position,
		Commands.slot_record(source_id, source_slot, source_type),
		Commands.slot_record(destination_id, destination_slot, destination_type)))


func _slot_stat(slot: int) -> int:
	return 8 + slot if slot < 12 else 71 + slot - 12


func use_item(slot: int, target_position: Vector2, use_type: int = 0) -> Error:
	if state != "playing" or slot < 0 or slot > 19 or use_type < 0 or use_type > 255 or not target_position.is_finite():
		return ERR_INVALID_PARAMETER
	var type := int(player_stats.get(_slot_stat(slot), -1))
	if type < 0:
		return ERR_DOES_NOT_EXIST
	return send_gameplay(Commands.use_item(clock_ms(), Commands.slot_record(player_id, slot, type), target_position, use_type))


func send_gameplay(command: Dictionary) -> Error:
	if state != "playing" or command.is_empty():
		return ERR_INVALID_PARAMETER
	return transport.call("send_packet", int(command.id), command.payload)


func _on_inventory_swap(source_id: int, source_slot: int, destination_id: int, destination_slot: int) -> void:
	var result := swap_slots(source_id, source_slot, destination_id, destination_slot)
	if result != OK: session_error.emit("Inventory request refused: %s" % error_string(result))


func _on_inventory_use(slot: int) -> void:
	var result := use_item(slot, pending_position)
	if result != OK: session_error.emit("Item request refused: %s" % error_string(result))


func _on_ability(target_position: Vector2) -> void:
	use_item(1, target_position)


func consume_potion(kind: String) -> Error:
	if state != "playing" or kind not in ["health", "magic"]:
		return ERR_INVALID_PARAMETER
	var health := kind == "health"
	var counter := 69 if health else 70
	if int(player_stats.get(counter, 0)) <= 0:
		return ERR_DOES_NOT_EXIST # Empty hotkey does not silently buy with virtual credits.
	var slot := 254 if health else 255
	var item_type := 2594 if health else 2595 # Original Health Potion0xa22 / Magic Potion0xa23.
	return send_gameplay(Commands.use_item(clock_ms(), Commands.slot_record(player_id, slot, item_type), pending_position))


func _on_ground_damage(position_tiles: Vector2) -> void:
	if state == "playing" and position_tiles.is_finite():
		transport.call("send_fields", 59, {"Time": clock_ms(), "Position": position_tiles})


func _on_projectile_hit(owner_id: int, bullet_id: int, target_id: int, hit_kind: String) -> void:
	if state != "playing":
		return
	if hit_kind == "player" and target_id == player_id:
		transport.call("send_fields", 17, {"BulletId": bullet_id, "ObjectId": owner_id})
	elif hit_kind == "enemy" and owner_id == player_id:
		transport.call("send_fields", 42, {"Time": clock_ms(), "BulletId": bullet_id, "TargetId": target_id, "Killed": false})


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
	entity_states.clear()
	_set_state("reconnecting")
	transport.call("configure_login", login)
	transport.call("connect_to_server", host, port)
