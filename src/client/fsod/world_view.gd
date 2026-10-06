# SPDX-License-Identifier: AGPL-3.0-only
# Original GRAVEBAG client/art for FSoD server 6fd20aad4a7905b13f25389c68368a942a2b68cb.
# Wire names adapted from wServer/Structures.cs and networking/{cli,svr}Packets.
# Projectile visual units from realm/entities/Projectile.cs. No backend mechanics.
extends Node2D

const EntityView = preload("res://src/client/fsod/entity_view.gd")
const TILE_PIXELS: float = 32.0
const RAIL_WIDTH: float = 256.0
signal move_requested(pos: Dictionary, records: Array)
signal shoot_requested(angle: float)
signal escape_requested
signal interact_requested(entity: int, slot: int)
# Emitted only with injected, source-derived hit_radius_tiles metadata; no damage.
signal projectile_hit_requested(owner_id: int, bullet_id: int, target_id: int, hit_kind: String)

# Supplied by the original-client/session bridge, NOT guessed backend defaults.
var prediction_speed_tiles: float = 0.0
var shot_request_interval: float = 0.0 # 0: click only; positive: held request period.
var interaction_target_id: int = -1
var inventory_slot: int = 0
var clock_ms: Callable
var descriptors: Dictionary = {}
var entities: Dictionary = {}
var projectiles: Dictionary = {} # Visual only, owner:bullet keys.
var tiles: Dictionary = {} # Vector2i -> tile type; unknown cells stay unknown.
var player_id: int = -1
var map_width: int = 0
var map_height: int = 0
var map_name: String = "Awaiting server"
var _world: Node2D
var _ground: Node2D
var _rail: PanelContainer
var _minimap: Control
var _summary: Label
var _inventory: Label
var _prediction: Vector2 = Vector2.ZERO
var _move_clock: float = 0.0
var _shoot_clock: float = 0.0
var _mouse_held: bool = false
var _last_move: bool = false
var _ready_built: bool = false


func _ready() -> void:
	_ensure_nodes()
	_refresh_rail()


func _ensure_nodes() -> void:
	if _ready_built: return
	_ready_built = true
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_ground = Node2D.new()
	_world.add_child(_ground)
	_ground.draw.connect(_draw_ground)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_rail = PanelContainer.new()
	_rail.name = "AuthoritativeRail"
	overlay.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_rail.offset_left = -RAIL_WIDTH
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_rail.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "GRAVEBAG / FSoD"
	title.add_theme_color_override("font_color", Color("efcf7a"))
	column.add_child(title)
	_minimap = Control.new()
	_minimap.custom_minimum_size = Vector2(224, 136)
	_minimap.draw.connect(_draw_minimap)
	column.add_child(_minimap)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 14)
	column.add_child(_summary)
	_inventory = Label.new()
	_inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory.add_theme_font_size_override("font_size", 12)
	column.add_child(_inventory)
	var keys := Label.new()
	keys.text = "WASD  move\nMouse  aim / shoot\nR  escape     E  interact\n\nServer owns all game state"
	keys.add_theme_color_override("font_color", Color("8996af"))
	keys.add_theme_font_size_override("font_size", 12)
	column.add_child(keys)


func set_descriptors(metadata: Dictionary) -> void:
	descriptors = metadata.duplicate(true)
	for id: Variant in entities:
		var view: Variant = entities[id]
		if _live(view): view.configure(int(id), view.object_type, _object_descriptor(view.object_type))
	_refresh_rail()
	_redraw()


func set_player_id(id: int) -> void:
	player_id = id
	for key: Variant in entities:
		var view: Variant = entities[key]
		if _live(view): view.is_local_player = int(key) == id
	var player: Variant = _player()
	if player != null: _prediction = player.authoritative_position
	_refresh_rail()


func apply_map(packet: Dictionary) -> void:
	_ensure_nodes()
	for id: Variant in entities.keys(): remove_entity(int(id))
	projectiles.clear()
	tiles.clear()
	map_width = clampi(_integer(packet.get("width", 0)), 0, 65535)
	map_height = clampi(_integer(packet.get("height", 0)), 0, 65535)
	map_name = str(packet.get("name", "Unnamed server map"))
	_prediction = Vector2.ZERO
	_mouse_held = false
	_move_clock = 0.0
	_shoot_clock = 0.0
	_last_move = false
	interaction_target_id = -1
	_refresh_rail()
	_redraw()


func apply_update(packet: Dictionary) -> void:
	_ensure_nodes()
	var incoming_tiles: Variant = packet.get("tiles", [])
	if incoming_tiles is Array:
		for tile: Variant in incoming_tiles:
			if not tile is Dictionary: continue
			var x: int = _integer(tile.get("x", -1), -1)
			var y: int = _integer(tile.get("y", -1), -1)
			if x < 0 or y < 0 or x >= map_width or y >= map_height: continue
			tiles[Vector2i(x, y)] = _integer(tile.get("tile", 0))
	var objects: Variant = packet.get("new_objects", [])
	if objects is Array:
		for object: Variant in objects:
			if not object is Dictionary: continue
			var status: Variant = object.get("stats", {})
			if not status is Dictionary: continue
			var id: int = _integer(status.get("id", -1), -1)
			if id < 0: continue
			var type: int = _integer(object.get("object_type", 0))
			var view: Variant = entities.get(id)
			if not _live(view):
				view = EntityView.new()
				_world.add_child(view)
				entities[id] = view
			view.configure(id, type, _object_descriptor(type))
			view.is_local_player = id == player_id
			view.apply_status(status)
			if id == player_id: _prediction = view.authoritative_position
	var removed: Variant = packet.get("removed_object_ids", [])
	if removed is Array:
		for id: Variant in removed: remove_entity(_integer(id, -1))
	_refresh_rail()
	_redraw()


func apply_tick(packet: Dictionary) -> void:
	var seconds: float = clampf(_number(packet.get("tick_time", 100)) / 1000.0, 0.001, 2.0)
	var statuses: Variant = packet.get("update_statuses", [])
	if not statuses is Array: return
	for status: Variant in statuses:
		if not status is Dictionary: continue
		var id: int = _integer(status.get("id", -1), -1)
		var view: Variant = entities.get(id)
		if not _live(view):
			entities.erase(id)
			continue # Unknown tick IDs never invent entities/type metadata.
		view.apply_status(status, seconds)
		if id == player_id: _prediction = view.authoritative_position
	_refresh_rail()
	_redraw()


func remove_entity(id: int) -> void:
	var view: Variant = entities.get(id)
	entities.erase(id)
	if _live(view): view.queue_free()
	for key: Variant in projectiles.keys():
		if projectiles[key]["owner_id"] == id: projectiles.erase(key)
	_refresh_rail()
	_redraw()


func apply_projectile(packet: Dictionary) -> void:
	_ensure_nodes()
	var owner_id: int = _integer(packet.get("owner_id", -1), -1)
	var owner: Variant = entities.get(owner_id)
	var start: Variant = EntityView.parse_position(packet.get("position", packet.get("starting_pos")))
	if start == null and _live(owner): start = owner.authoritative_position
	if start == null or owner_id < 0: return
	var type: int = _integer(packet.get("container_type", owner.object_type if _live(owner) else 0))
	var desc: Dictionary = _object_descriptor(type)
	var definitions: Variant = desc.get("projectiles", [])
	var projectile_desc: Dictionary = {}
	if definitions is Array:
		var bullet_type: int = _integer(packet.get("bullet_type", 0))
		for candidate: Variant in definitions:
			if not candidate is Dictionary: continue
			var declared_type: int = _integer(candidate.get("bullet_type", candidate.get("BulletType", candidate.get("id", 0))))
			if declared_type == bullet_type:
				projectile_desc = _normalize_projectile(candidate)
				break
	var speed: float = _number(packet.get("speed", projectile_desc.get("speed", 0))) / 10.0
	var lifetime: float = _number(packet.get("lifetime_ms", projectile_desc.get("lifetime_ms", 0))) / 1000.0
	var angle: float = _number(packet.get("angle", 0), -TAU * 1000.0, TAU * 1000.0)
	if speed <= 0.0 or lifetime <= 0.0: return # Missing source metadata: no invented range.
	var count: int = clampi(_integer(packet.get("num_shots", 1)), 1, 256)
	var increment: float = _number(packet.get("angle_inc", 0), -TAU * 1000.0, TAU * 1000.0)
	var first_id: int = _integer(packet.get("bullet_id", 0))
	for i: int in count:
		var bullet_id: int = (first_id + i) % 256
		projectiles["%d:%d" % [owner_id, bullet_id]] = {
			"owner_id": owner_id, "bullet_id": bullet_id, "start": start,
			"angle": angle + increment * i, "speed": speed, "lifetime": lifetime,
			"age": 0.0, "descriptor": projectile_desc.duplicate(true), "reported_hits": {},
		}
	_redraw()


func _physics_process(delta: float) -> void:
	advance_visuals(delta)
	var player: Variant = _player()
	if player == null: return
	var input_vector := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	).limit_length(1.0)
	predict_motion(input_vector, delta)
	var mouse: Vector2 = _world.to_local(get_global_mouse_position()) / TILE_PIXELS
	var aim: Vector2 = mouse - _prediction
	if aim.length_squared() > 0.000001: player.aim_angle = aim.angle() # No angle snap.
	_shoot_clock = maxf(0.0, _shoot_clock - delta)
	if _mouse_held and _shoot_clock <= 0.0 and is_finite(shot_request_interval) and shot_request_interval > 0.0:
		shoot_requested.emit(player.aim_angle)
		_shoot_clock = maxf(0.001, shot_request_interval)
	var size: Vector2 = get_viewport_rect().size
	_world.position = Vector2(maxf(0.0, size.x - RAIL_WIDTH) / 2.0, size.y / 2.0) - player.position


# Testable input/prediction boundary. No collision, backend updates, damage, or RNG.
func predict_motion(input_vector: Vector2, delta: float) -> void:
	var player: Variant = _player()
	if player == null or not is_finite(delta) or delta <= 0.0: return
	if not is_finite(input_vector.x) or not is_finite(input_vector.y): return
	var moving: bool = input_vector.length_squared() > 0.0 and is_finite(prediction_speed_tiles) and prediction_speed_tiles > 0.0
	if moving:
		_prediction += input_vector.limit_length(1.0) * prediction_speed_tiles * minf(delta, 0.25)
	# Visual smoothing of authoritative corrections. Player position remains server-owned.
	player.predict_position(player.position.lerp(_prediction * TILE_PIXELS, minf(1.0, delta * 20.0)) / TILE_PIXELS)
	_move_clock += delta
	if (moving or _last_move) and _move_clock >= 0.05:
		_move_clock = 0.0
		var pos: Dictionary = {"x": _prediction.x, "y": _prediction.y}
		var timestamp: int = int(clock_ms.call()) if clock_ms.is_valid() else Time.get_ticks_msec()
		move_requested.emit(pos, [{"time": timestamp, "position": pos.duplicate()}])
	_last_move = moving


func _input(event: InputEvent) -> void:
	# A release over the UI rail must not leave held-fire latched.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_mouse_held = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_held = event.pressed
		if event.pressed and _player() != null:
			shoot_requested.emit(_player().aim_angle)
			_shoot_clock = maxf(0.001, shot_request_interval)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: escape_requested.emit()
		if event.physical_keycode == KEY_E and interaction_target_id >= 0:
			interact_requested.emit(interaction_target_id, inventory_slot)


func advance_visuals(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	for id: Variant in entities.keys():
		var view: Variant = entities[id]
		if _live(view): view.advance_visual(delta)
		else: entities.erase(id)
	for key: Variant in projectiles.keys():
		var bullet: Dictionary = projectiles.get(key, {})
		if bullet.is_empty(): continue # Hit signal subscribers may clear the world.
		var previous: Vector2 = projectile_position(bullet)
		var expires: bool = bullet["age"] + delta > bullet["lifetime"]
		bullet["age"] = minf(bullet["age"] + delta, bullet["lifetime"])
		_request_visual_hits(bullet, previous, projectile_position(bullet))
		if expires: projectiles.erase(key)
	_redraw()


func _request_visual_hits(bullet: Dictionary, from: Vector2, to: Vector2) -> void:
	var owner: Variant = entities.get(bullet["owner_id"])
	var local_shot: bool = bullet["owner_id"] == player_id
	var hostile_shot: bool = _live(owner) and owner.kind == "enemy"
	if not local_shot and not hostile_shot: return
	for id: Variant in entities.keys():
		var target: Variant = entities.get(id)
		if not _live(target) or int(id) == bullet["owner_id"] or bullet["reported_hits"].has(id): continue
		var hit_kind: String = "enemy" if local_shot and target.kind == "enemy" else "player" if hostile_shot and int(id) == player_id else ""
		if hit_kind.is_empty(): continue
		# No inferred radius from art, XML Size, or tile size. Parent must supply
		# legacy-client geometry; the server descriptors do not define that radius.
		var radius: float = _number(_object_descriptor(target.object_type).get("hit_radius_tiles", 0))
		if radius <= 0.0: continue
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(target.authoritative_position, from, to)
		if nearest.distance_squared_to(target.authoritative_position) <= radius * radius:
			bullet["reported_hits"][id] = true
			projectile_hit_requested.emit(bullet["owner_id"], bullet["bullet_id"], int(id), hit_kind)


# Purely visual source trajectory (no hit detection). Handles source descriptor
# amplitude/boomerang/parametric flags; metadata values use source tile units.
func projectile_position(bullet: Dictionary) -> Vector2:
	var age: float = bullet["age"]
	var lifetime: float = bullet["lifetime"]
	var angle: float = bullet["angle"]
	var desc: Dictionary = bullet["descriptor"]
	var id: int = bullet["bullet_id"]
	var distance: float = age * bullet["speed"]
	var period: float = 0.0 if id % 2 == 0 else PI
	if desc.get("wavy", false) == true:
		# C# source's elapsedTicks/1000 is INTEGER division in this branch.
		return bullet["start"] + Vector2.from_angle(angle + PI * 64.0 * sin(period + 6.0 * PI * int(age))) * distance
	if desc.get("parametric", false) == true:
		var theta: float = age / lifetime * TAU
		var a: float = sin(theta) * (1.0 if id % 2 != 0 else -1.0)
		var b: float = sin(theta * 2.0) * (1.0 if id % 4 < 2 else -1.0)
		return bullet["start"] + Vector2(a, b).rotated(angle) * _number(desc.get("magnitude", 3))
	if desc.get("boomerang", false) == true:
		var halfway: float = lifetime * bullet["speed"] / 2.0
		if distance > halfway: distance = halfway - (distance - halfway)
	var offset: Vector2 = Vector2.from_angle(angle) * distance
	var amplitude: float = _number(desc.get("amplitude", 0), -1000000.0)
	var frequency: float = _number(desc.get("frequency", 1), -1000000.0)
	offset += Vector2.from_angle(angle + PI / 2.0) * amplitude * sin(period + age / lifetime * frequency * TAU)
	return bullet["start"] + offset


func _draw_ground() -> void:
	# Only render visible sparse cells; unseen server map is not filled with fake tiles.
	var visible: Rect2 = Rect2(-_world.position - Vector2.ONE * TILE_PIXELS, get_viewport_rect().size + Vector2.ONE * TILE_PIXELS * 2.0)
	for cell: Variant in tiles:
		var rect := Rect2(Vector2(cell) * TILE_PIXELS, Vector2.ONE * TILE_PIXELS)
		if not visible.intersects(rect): continue
		var color: Color = _tile_color(tiles[cell])
		_ground.draw_rect(rect, color)
		_ground.draw_rect(Rect2(rect.position + Vector2(4, 7), Vector2(4, 3)), color.lightened(0.08))
		_ground.draw_line(rect.position, rect.position + Vector2(TILE_PIXELS, 0), color.darkened(0.12), 1.0)
	for key: Variant in projectiles:
		var bullet: Dictionary = projectiles[key]
		var point: Vector2 = projectile_position(bullet) * TILE_PIXELS
		_ground.draw_rect(Rect2(point - Vector2(4, 2), Vector2(8, 4)), Color("ffe49b"))
		_ground.draw_rect(Rect2(point - Vector2(2, 1), Vector2(4, 2)), Color("fff9df"))


func _draw_minimap() -> void:
	_minimap.draw_rect(Rect2(Vector2.ZERO, _minimap.size), Color("111829"))
	if map_width <= 0 or map_height <= 0: return
	var scale: float = minf(_minimap.size.x / map_width, _minimap.size.y / map_height)
	for cell: Variant in tiles:
		_minimap.draw_rect(Rect2(Vector2(cell) * scale, Vector2.ONE * maxf(1.0, scale)), _tile_color(tiles[cell]))
	for id: Variant in entities:
		var view: Variant = entities[id]
		if _live(view):
			_minimap.draw_rect(Rect2(view.authoritative_position * scale - Vector2.ONE * 2, Vector2.ONE * 4), Color("f9de86") if int(id) == player_id else Color("d36573"))


func _refresh_rail() -> void:
	if not _ready_built: return
	var player: Variant = _player()
	var stats: Dictionary = player.stats if player != null else {}
	_summary.text = "%s\n\nHP  %s / %s\nMP  %s / %s\nLevel  %s" % [map_name, _stat_text(stats, 1), _stat_text(stats, 0), _stat_text(stats, 4), _stat_text(stats, 3), _stat_text(stats, 7)]
	var lines: PackedStringArray = ["INVENTORY (server)"]
	for slot: int in 12:
		var wire_id: int = 8 + slot
		var text: String = "—"
		if stats.has(wire_id):
			var type: int = _integer(stats[wire_id], -1)
			text = "empty" if type < 0 else str(_object_descriptor(type).get("name", "0x%04x" % type))
		lines.append("%02d  %s" % [slot, text.left(28)])
	_inventory.text = "\n".join(lines)
	_minimap.queue_redraw()


func _object_descriptor(type: int) -> Dictionary:
	var objects: Variant = descriptors.get("objects", {})
	if not objects is Dictionary: return {}
	var result: Variant = objects.get(type, objects.get(str(type), {}))
	return result if result is Dictionary else {}


static func _normalize_projectile(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	for pair: Array in [["speed", "Speed"], ["lifetime_ms", "LifetimeMS"], ["wavy", "Wavy"], ["parametric", "Parametric"], ["boomerang", "Boomerang"], ["amplitude", "Amplitude"], ["frequency", "Frequency"], ["magnitude", "Magnitude"]]:
		if not result.has(pair[0]) and source.has(pair[1]): result[pair[0]] = source[pair[1]]
	return result


func _tile_color(type: int) -> Color:
	var definitions: Variant = descriptors.get("tiles", {})
	if definitions is Dictionary:
		var desc: Variant = definitions.get(type, definitions.get(str(type), {}))
		if desc is Dictionary:
			var value: Variant = desc.get("color")
			if value is Color: return value
			if value is String and Color.html_is_valid(value): return Color(value)
	# Original-art presentation palette; not a tile collision/terrain classification.
	return Color("303c48").lightened(float(type % 7) * 0.015)


func _player() -> Variant:
	var view: Variant = entities.get(player_id)
	return view if _live(view) else null


func _redraw() -> void:
	if not _ready_built: return
	_ground.queue_redraw()
	_minimap.queue_redraw()


static func _stat_text(stats: Dictionary, id: int) -> String:
	return str(stats[id]) if stats.has(id) else "—"


static func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and not node.is_queued_for_deletion()


static func _integer(value: Variant, fallback: int = 0) -> int:
	if not (value is int or value is float): return fallback
	if not is_finite(float(value)): return fallback
	return int(clampf(float(value), -2147483648.0, 2147483647.0))


static func _number(value: Variant, minimum: float = 0.0, maximum: float = 1000000.0) -> float:
	if not (value is int or value is float) or not is_finite(float(value)): return 0.0
	return clampf(float(value), minimum, maximum)
