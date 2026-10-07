# SPDX-License-Identifier: AGPL-3.0-only
# Original GRAVEBAG client/art for FSoD server 6fd20aad4a7905b13f25389c68368a942a2b68cb.
# Wire names adapted from wServer/Structures.cs and networking/{cli,svr}Packets.
# Projectile visual units from realm/entities/Projectile.cs. No backend mechanics.
extends Node2D

const EntityView = preload("res://src/client/fsod/entity_view.gd")
const InventoryPanel = preload("res://src/client/fsod/inventory_panel.gd")
const HudPanel = preload("res://src/client/fsod/hud_panel.gd")
const UiTheme = preload("res://src/client/fsod/ui_theme.gd")
const TILE_PIXELS: float = 32.0
const RAIL_WIDTH: float = 256.0
signal move_requested(pos: Dictionary, records: Array)
signal shoot_requested(angle: float)
signal escape_requested
signal interact_requested(entity: int, slot: int)
signal ability_requested(position: Vector2)
signal potion_requested(kind: String)
signal ground_damage_requested(position: Vector2)
signal inventory_swap_requested(source_id: int, source_slot: int, destination_id: int, destination_slot: int)
signal item_use_requested(slot: int)
# Contact geometry comes from recovered original-client facts; no local damage.
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
var _hud: Control
var _tile_revision: int = 0
var _hud_cells_revision: int = -1
var _summary: Label
var _inventory: Label # Hidden debug projection retained for fixture/diagnostic readback.
var _inventory_panel: PanelContainer
var _inventory_snapshot: Dictionary = {}
var _prediction: Vector2 = Vector2.ZERO
var _prediction_ready: bool = false
# Sent MOVE samples, in order, not every physics step. A delayed NEW_TICK that
# matches one of those samples is an echo: keep predicting. Anything else is a
# correction. Contact/hit sampling stays on the authoritative Node position;
# only the render pose follows the lead. Immobilization (condition bit 13)
# always hard-corrects, including a 0.2-tile freeze inside the noise dead zone.
const SENT_MOVE_MAX: int = 64
const SENT_ECHO_EPSILON_TILES: float = 0.02
const POSE_DEADZONE_TILES: float = 0.20
var _sent_moves: Array = []
var _move_clock: float = 0.0
var _shoot_clock: float = 0.0
var _mouse_held: bool = false
var _ground_contact_times: Dictionary = {}
var _last_move: bool = false
var _ready_built: bool = false
# Display-only camera/world smoothing (original-FSoD "feels jagged" follow).
# Physics records _camera_target framing from the displayed player center and
# _process eases the visible _world.position toward it at render rate. Entity authority,
# prediction, collision, MOVE/contact timing, and projectile trajectories are
# untouched. No camera rounding: fractional display offsets are preserved so the
# follow never reintroduces pixel judder.
const CAMERA_SMOOTHING_RATE: float = 14.0
const CAMERA_TELEPORT_TILES: float = 4.0
var _camera_target: Vector2 = Vector2.ZERO
var _camera_ready: bool = false
var _camera_hold_auth: bool = false


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
	overlay.name = "HudOverlay"
	add_child(overlay)
	_rail = PanelContainer.new()
	_rail.name = "AuthoritativeRail"
	_rail.mouse_filter = Control.MOUSE_FILTER_STOP
	_rail.focus_mode = Control.FOCUS_NONE
	_rail.add_theme_stylebox_override("panel", UiTheme.panel_style())
	overlay.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_hud = HudPanel.new()
	_hud.name = "HudPanel"
	_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(_hud)
	_summary = Label.new()
	_summary.name = "SummaryDebug"
	_summary.visible = false
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_summary)
	_inventory = Label.new()
	_inventory.name = "InventoryDebug"
	_inventory.visible = false
	_inventory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_inventory)
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.inventory_host().add_child(_inventory_panel)
	_inventory_panel.swap_requested.connect(func(source_id: int, source_slot: int, destination_id: int, destination_slot: int): inventory_swap_requested.emit(source_id, source_slot, destination_id, destination_slot))
	_inventory_panel.use_requested.connect(func(slot: int): item_use_requested.emit(slot))
	_inventory_panel.selection_changed.connect(func(slot: int): inventory_slot = maxi(slot, 0))
	_layout_rail()
	if is_inside_tree() and not get_viewport().size_changed.is_connected(_layout_rail):
		get_viewport().size_changed.connect(_layout_rail)


func predicted_position() -> Vector2:
	return _prediction


func _prediction_snap(auth: Vector2) -> void:
	_prediction = auth
	_prediction_ready = true
	_sent_moves.clear()
	_sent_moves.append(auth)
	var player: Variant = _player()
	if player != null:
		player.predict_position(auth)


func _immobilized(player: Variant) -> bool:
	# Source condition bit 13 (paralysis). Stat 29 holds the low condition word.
	if not _live(player):
		return false
	return (int(player.stats.get(29, 0)) & (1 << 13)) != 0


func _matches_sent_move(auth: Vector2) -> bool:
	for point: Variant in _sent_moves:
		if point is Vector2 and point.is_finite() and auth.distance_to(point) <= SENT_ECHO_EPSILON_TILES:
			return true
	return false


func _record_sent_move(sample: Vector2) -> void:
	if not sample.is_finite():
		return
	if not _sent_moves.is_empty() and _sent_moves[-1] is Vector2 and (_sent_moves[-1] as Vector2).distance_to(sample) <= SENT_ECHO_EPSILON_TILES:
		return
	_sent_moves.append(sample)
	while _sent_moves.size() > SENT_MOVE_MAX:
		_sent_moves.pop_front()


# Reconcile a server authoritative position against sent MOVE samples.
# Returns true when prediction hard-snapped. A delayed echo of a sent sample
# leaves prediction alone. Occupied cells do not snap by themselves: an
# OccupySquare overlap must not rewind onto the echo every tick.
func _reconcile_prediction(auth: Variant, hard_snap: bool = false) -> bool:
	if not (auth is Vector2) or not auth.is_finite():
		return false
	var player: Variant = _player()
	if hard_snap or not _prediction_ready or _sent_moves.is_empty():
		_prediction_snap(auth)
		return true
	if _prediction.distance_to(auth) > CAMERA_TELEPORT_TILES:
		_prediction_snap(auth)
		return true
	if _immobilized(player):
		_prediction_snap(auth)
		return true
	if _matches_sent_move(auth):
		return false
	if _prediction.distance_to(auth) <= POSE_DEADZONE_TILES:
		return false
	# Not an echo and outside the 0.20 pose dead zone. Snap. There is no
	# second off-trail threshold: 0.30 and 0.50 both correct.
	_prediction_snap(auth)
	return true


func set_descriptors(metadata: Dictionary) -> void:
	descriptors = metadata.duplicate(true)
	_inventory_snapshot.clear()
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
	if player != null:
		_prediction_snap(player.authoritative_position)
	else:
		_prediction_ready = false
		_sent_moves.clear()
	_camera_ready = false # Player identity discontinuity: next camera target hard-snaps.
	_camera_hold_auth = false
	_refresh_rail()


func apply_map(packet: Dictionary) -> void:
	_ensure_nodes()
	for id: Variant in entities.keys(): remove_entity(int(id))
	projectiles.clear()
	_ground_contact_times.clear()
	tiles.clear()
	map_width = clampi(_integer(packet.get("width", 0)), 0, 65535)
	map_height = clampi(_integer(packet.get("height", 0)), 0, 65535)
	map_name = str(packet.get("name", "Unnamed server map"))
	_tile_revision += 1
	_prediction = Vector2.ZERO
	_prediction_ready = false
	_sent_moves.clear()
	_mouse_held = false
	_move_clock = 0.0
	_shoot_clock = 0.0
	_last_move = false
	interaction_target_id = -1
	_camera_ready = false # Map reset: stale display offset must not slew into the new map.
	_camera_target = Vector2.ZERO
	_camera_hold_auth = false
	_refresh_rail()
	_redraw()


func apply_update(packet: Dictionary) -> void:
	_ensure_nodes()
	var _previous_auth: Variant = _player_auth_snapshot()
	var incoming_tiles: Variant = packet.get("tiles", [])
	if incoming_tiles is Array:
		for tile: Variant in incoming_tiles:
			if not tile is Dictionary: continue
			var x: int = _integer(tile.get("x", -1), -1)
			var y: int = _integer(tile.get("y", -1), -1)
			if x < 0 or y < 0 or x >= map_width or y >= map_height: continue
			tiles[Vector2i(x, y)] = _integer(tile.get("tile", 0))
			_tile_revision += 1
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
			if id == player_id: _reconcile_prediction(view.authoritative_position)
	var removed: Variant = packet.get("removed_object_ids", [])
	if removed is Array:
		for id: Variant in removed: remove_entity(_integer(id, -1))
	_snap_camera_on_discontinuity(_previous_auth)
	_refresh_rail()
	_redraw()


func apply_tick(packet: Dictionary) -> void:
	var _previous_tick_auth: Variant = _player_auth_snapshot()
	var seconds: float = clampf(_number(packet.get("tick_time", 100)) / 1000.0, 0.001, 2.0)
	var statuses: Variant = packet.get("update_statuses", [])
	if not statuses is Array: return
	var explicit_goto_tick := int(packet.get("tick_id", 0)) == -1 and float(packet.get("tick_time", 100)) <= 0.0
	for status: Variant in statuses:
		if not status is Dictionary: continue
		var id: int = _integer(status.get("id", -1), -1)
		var view: Variant = entities.get(id)
		if not _live(view):
			entities.erase(id)
			continue # Unknown tick IDs never invent entities/type metadata.
		view.apply_status(status, seconds)
		if id == player_id: _reconcile_prediction(view.authoritative_position, explicit_goto_tick)
	var explicit_goto := int(packet.get("tick_id", 0)) == -1 and float(packet.get("tick_time", 100)) <= 0.0
	_snap_camera_on_discontinuity(_previous_tick_auth, explicit_goto)
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
	# Aim maps through the DISPLAYED world transform (smoothed _world.position),
	# never the unsmoothed target, so the cursor stays aligned with rendered pixels.
	# The angle is measured from the displayed player center; outbound packet
	# trajectory origins still use _prediction (server-authored semantics).
	var mouse: Vector2 = screen_to_world_tiles(get_global_mouse_position())
	var aim: Vector2 = mouse - _display_player_pixels(player) / TILE_PIXELS
	if aim.length_squared() > 0.000001: player.aim_angle = aim.angle() # No angle snap.
	_shoot_clock = maxf(0.0, _shoot_clock - delta)
	if _mouse_held and _shoot_clock <= 0.0 and is_finite(shot_request_interval) and shot_request_interval > 0.0:
		shoot_requested.emit(player.aim_angle)
		_shoot_clock = maxf(0.001, shot_request_interval)
	_check_ground_contact()
	# Physics only records the desired framing; the smoothed display transform is
	# presented in _process at render rate. Simulation, input, contact, and MOVE
	# timing are unchanged: advance_visuals stays here (hit sampling reads the
	# semantic Node positions, so it must not move to render rate).
	_update_camera_target(player)
	if not _camera_ready:
		snap_camera_to_target()


# Render-rate presentation only: entity render poses (parallel entity worker's
# optional advance_presentation, _draw offsets) and the smoothed camera display.
# Never advances simulation age, hit sampling, prediction, contact, or MOVE here.
func _process(delta: float) -> void:
	if not _ready_built or _world == null:
		return
	for id: Variant in entities.keys():
		var view: Variant = entities[id]
		if _live(view) and view.has_method("advance_presentation"):
			view.call("advance_presentation", delta)
	advance_camera_display(delta)


func desired_camera_position(player_pixels: Vector2, viewport_size: Vector2) -> Vector2:
	return Vector2(maxf(0.0, viewport_size.x - RAIL_WIDTH) / 2.0, viewport_size.y / 2.0) - player_pixels


static func smooth_camera_step(display: Vector2, target: Vector2, delta: float, rate: float = 14.0) -> Vector2:
	if not display.is_finite() or not target.is_finite():
		return display
	if not is_finite(delta) or delta <= 0.0 or not is_finite(rate) or rate <= 0.0:
		return display
	var blend: float = 1.0 - exp(-rate * minf(delta, 0.25))
	if not is_finite(blend) or blend <= 0.0:
		return display
	if blend >= 1.0:
		return target
	return display.lerp(target, blend)


# Displayed player center in _world-local pixels. Prefers the entity render pose
# (display_position(), parallel entity lane) when provided; falls back to the
# semantic Node position so the camera keeps working with or without that
# optional interface (standalone baseline compat).
func _display_player_pixels(player: Variant) -> Vector2:
	if not _live(player):
		return Vector2.ZERO
	if player.has_method("display_position"):
		var pose: Variant = player.call("display_position")
		if pose is Vector2 and pose.is_finite():
			return pose
	return player.position


func screen_to_world_tiles(screen_global: Vector2) -> Vector2:
	if not _ready_built or _world == null:
		return Vector2.ZERO
	return _world.to_local(screen_global) / TILE_PIXELS


func snap_camera_to_target() -> void:
	if not _ready_built or _world == null:
		return
	_world.position = _camera_target
	_camera_ready = true


func _update_camera_target(player: Variant) -> void:
	if not _ready_built or _world == null:
		return
	if not _live(player):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if _camera_hold_auth:
		# Teleport/GOTO hold: stay snapped to the authoritative landing while the
		# render pose catches up, so the camera never slews across the jump.
		var landing: Vector2 = player.authoritative_position * TILE_PIXELS
		if landing.is_finite():
			_camera_target = desired_camera_position(landing, viewport_size)
		var pose: Vector2 = _display_player_pixels(player)
		if pose.is_finite() and pose.distance_to(landing) <= TILE_PIXELS:
			_camera_hold_auth = false
		return
	_camera_target = desired_camera_position(_display_player_pixels(player), viewport_size)


func advance_camera_display(delta: float) -> void:
	if not _ready_built or _world == null:
		return
	var player: Variant = _player()
	if player == null:
		return
	_update_camera_target(player)
	if not _camera_ready:
		snap_camera_to_target()
		return
	# Display-only ease toward the recorded target. No rounding: fractional
	# offsets are preserved so the follow never reintroduces pixel judder.
	_world.position = smooth_camera_step(_world.position, _camera_target, delta, CAMERA_SMOOTHING_RATE)


func _player_auth_snapshot() -> Variant:
	var player: Variant = _player()
	return player.authoritative_position if player != null else null


func _snap_camera_on_discontinuity(previous: Variant, force_snap: bool = false) -> void:
	if not (previous is Vector2):
		return
	var player: Variant = _player()
	if player == null:
		return
	if not previous.is_finite() or not player.authoritative_position.is_finite():
		return
	if not force_snap and previous.distance_to(player.authoritative_position) <= CAMERA_TELEPORT_TILES:
		return
	# Map/GOTO/teleport discontinuity: hard-snap so smoothing never slews across
	# the jump. Packet trajectory origins stay _prediction (untouched).
	_camera_hold_auth = true
	_update_camera_target(player)
	snap_camera_to_target()


# Client prediction uses streamed source solid-tile flags; no backend mutation/damage/RNG.
func predict_motion(input_vector: Vector2, delta: float) -> void:
	var player: Variant = _player()
	if player == null or not is_finite(delta) or delta <= 0.0: return
	if not is_finite(input_vector.x) or not is_finite(input_vector.y): return
	var moving: bool = input_vector.length_squared() > 0.0 and is_finite(prediction_speed_tiles) and prediction_speed_tiles > 0.0
	if moving:
		var offset := input_vector.limit_length(1.0) * prediction_speed_tiles * minf(delta, 0.25)
		# Original client checks displacement in dominant-axis steps no larger than0.4tiles.
		var steps := maxi(1, ceili(maxf(absf(offset.x), absf(offset.y)) / 0.4))
		var step := offset / float(steps)
		for index in steps:
			_prediction = _clip_movement(_prediction, _prediction + step)
	# Render follows the lead. Node.position stays on the last echo so shots
	# aimed at the server position still meet the contact box.
	player.present_prediction(_prediction)
	_move_clock += delta
	if (moving or _last_move) and _move_clock >= 0.05:
		_move_clock = 0.0
		_record_sent_move(_prediction)
		var pos: Dictionary = {"x": _prediction.x, "y": _prediction.y}
		var timestamp: int = int(clock_ms.call()) if clock_ms.is_valid() else Time.get_ticks_msec()
		move_requested.emit(pos, [{"time": timestamp, "position": pos.duplicate()}])
	_last_move = moving


func _clip_movement(from: Vector2, requested: Vector2) -> Vector2:
	# Recovered original Player half-grid clipping: don't just reject a blocked step.
	var cross_x := (fmod(from.x, 0.5) == 0.0 and requested.x != from.x) or int(from.x / 0.5) != int(requested.x / 0.5)
	var cross_y := (fmod(from.y, 0.5) == 0.0 and requested.y != from.y) or int(from.y / 0.5) != int(requested.y / 0.5)
	if (not cross_x and not cross_y) or _can_walk(requested): return requested
	var clipped := from
	if cross_x:
		clipped.x = float(int(requested.x * 2.0)) / 2.0 if requested.x > from.x else float(int(from.x * 2.0)) / 2.0
		if int(clipped.x) > int(from.x): clipped.x -= 0.01
	if cross_y:
		clipped.y = float(int(requested.y * 2.0)) / 2.0 if requested.y > from.y else float(int(from.y * 2.0)) / 2.0
		if int(clipped.y) > int(from.y): clipped.y -= 0.01
	if not cross_x: return Vector2(requested.x, clipped.y)
	if not cross_y: return Vector2(clipped.x, requested.y)
	var overshoot_x := requested.x - clipped.x if requested.x > from.x else clipped.x - requested.x
	var overshoot_y := requested.y - clipped.y if requested.y > from.y else clipped.y - requested.y
	var first := Vector2(requested.x, clipped.y) if overshoot_x > overshoot_y else Vector2(clipped.x, requested.y)
	var second := Vector2(clipped.x, requested.y) if overshoot_x > overshoot_y else Vector2(requested.x, clipped.y)
	if _can_walk(first): return first
	if _can_walk(second): return second
	return clipped


func _can_walk(position_tiles: Vector2) -> bool:
	if not position_tiles.is_finite() or position_tiles.x < 0.0 or position_tiles.y < 0.0 or position_tiles.x >= map_width or position_tiles.y >= map_height: return false
	var center := Vector2i(floori(position_tiles.x), floori(position_tiles.y))
	if _cell_blocked(center, false): return false
	# Neighbors use FullOccupy/void, NOT neighboring ground NoWalk/OccupySquare.
	var fractional := position_tiles - Vector2(center)
	var neighbors: Array = []
	if fractional.x < 0.5: neighbors.append(Vector2i.LEFT)
	elif fractional.x > 0.5: neighbors.append(Vector2i.RIGHT)
	if fractional.y < 0.5: neighbors.append(Vector2i.UP)
	elif fractional.y > 0.5: neighbors.append(Vector2i.DOWN)
	if neighbors.size() == 2: neighbors.append(neighbors[0] + neighbors[1])
	for offset in neighbors:
		if _cell_blocked(center + offset, true): return false
	return true


func _cell_blocked(cell: Vector2i, neighbor: bool) -> bool:
	if not tiles.has(cell) or int(tiles[cell]) == 255: return true
	if not neighbor:
		var tile_type := int(tiles[cell])
		var tile_meta: Dictionary = descriptors.get("tiles", {}).get(str(tile_type), descriptors.get("tiles", {}).get(tile_type, {}))
		if bool(tile_meta.get("source_descriptor", {}).get("NoWalk", false)): return true
	for id in entities:
		var entity: Variant = entities[id]
		if not _live(entity) or int(id) == player_id: continue
		if Vector2i(floori(entity.authoritative_position.x), floori(entity.authoritative_position.y)) != cell: continue
		var meta: Dictionary = _object_descriptor(entity.object_type).get("source_descriptor", {})
		if bool(meta.get("FullOccupy" if neighbor else "OccupySquare", false)): return true
	return false


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
		if event.physical_keycode == KEY_SPACE:
			ability_requested.emit(screen_to_world_tiles(get_global_mouse_position()))
		if event.physical_keycode == KEY_F: potion_requested.emit("health")
		if event.physical_keycode == KEY_V: potion_requested.emit("magic")
		if event.physical_keycode == KEY_E and interaction_target_id >= 0:
			interact_requested.emit(interaction_target_id, inventory_slot)


func _check_ground_contact() -> void:
	var player: Variant = _player()
	if player == null:
		return
	var cell := Vector2i(floori(_prediction.x), floori(_prediction.y))
	if not tiles.has(cell):
		return
	var tile_meta: Dictionary = descriptors.get("tiles", {}).get(str(tiles[cell]), descriptors.get("tiles", {}).get(tiles[cell], {}))
	var ground: Dictionary = tile_meta.get("source_descriptor", {})
	# Server GroundDamageHandler ignores these effects; don't advance contact clocks.
	if int(player.stats.get(29, 0)) & ((1 << 15) | (1 << 23)):
		return
	if int(ground.get("MaxDamage", 0)) <= 0:
		return
	for id in entities:
		var entity: Variant = entities[id]
		if not _live(entity):
			continue
		if Vector2i(floori(entity.authoritative_position.x), floori(entity.authoritative_position.y)) == cell and bool(_object_descriptor(entity.object_type).get("source_descriptor", {}).get("ProtectFromGroundDamage", false)):
			return
	var now := int(clock_ms.call()) if clock_ms.is_valid() else Time.get_ticks_msec()
	if now > int(_ground_contact_times.get(cell, 0)) + 500:
		_ground_contact_times[cell] = now
		ground_damage_requested.emit(_prediction)


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
		if expires or bullet.get("consumed", false): projectiles.erase(key)
	_redraw()


func _request_visual_hits(bullet: Dictionary, from: Vector2, to: Vector2) -> void:
	var owner: Variant = entities.get(bullet["owner_id"])
	var local_shot: bool = bullet["owner_id"] == player_id
	var hostile_shot: bool = _live(owner) and owner.kind == "enemy"
	if not local_shot and not hostile_shot: return
	var closest_id := -1
	var closest_kind := ""
	var closest_distance := INF
	for id: Variant in entities.keys():
		var target: Variant = entities.get(id)
		if not _live(target) or int(id) == bullet["owner_id"] or bullet["reported_hits"].has(id): continue
		var hit_kind: String = "enemy" if local_shot and target.kind == "enemy" else "player" if hostile_shot and int(id) == player_id else ""
		if hit_kind.is_empty(): continue
		var radius: float = _number(_object_descriptor(target.object_type).get("hit_radius_tiles", 0))
		if radius <= 0.0: continue
		var center: Vector2 = target.position / TILE_PIXELS
		var offset := (to - center).abs()
		var hit := offset.x <= radius and offset.y <= radius
		# Keep synthetic-fixture circle geometry explicit; live metadata uses recovered AABB.
		if _object_descriptor(target.object_type).get("hit_shape", "circle") == "circle":
			hit = offset.length_squared() <= radius * radius
		if hit and offset.length_squared() < closest_distance:
			closest_id = int(id)
			closest_kind = hit_kind
			closest_distance = offset.length_squared()
	# Original client samples the current point and selects ONE nearest eligible target.
	if closest_id >= 0:
		bullet["reported_hits"][closest_id] = true
		projectile_hit_requested.emit(bullet["owner_id"], bullet["bullet_id"], closest_id, closest_kind)
		if not bool(bullet["descriptor"].get("MultiHit", false)):
			bullet["consumed"] = true


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
		# Original Flash client's projection uses PI/64 and fractional seconds.
		# C# server's PI*64/integer-seconds expression is NOT client rendering math.
		return bullet["start"] + Vector2.from_angle(angle + PI / 64.0 * sin(period + 6.0 * PI * age)) * distance
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
		_ground.draw_line(rect.position, rect.position + Vector2(TILE_PIXELS, 0), color.darkened(0.12), 1.0, true)
	for key: Variant in projectiles:
		var bullet: Dictionary = projectiles[key]
		var point: Vector2 = projectile_position(bullet) * TILE_PIXELS
		_ground.draw_rect(Rect2(point - Vector2(4, 2), Vector2(8, 4)), Color("ffe49b"))
		_ground.draw_rect(Rect2(point - Vector2(2, 1), Vector2(4, 2)), Color("fff9df"))


func _layout_rail() -> void:
	if not is_instance_valid(_rail):
		return
	var viewport := get_viewport_rect().size
	var width := minf(RAIL_WIDTH, maxf(0.0, viewport.x))
	_rail.offset_left = -width
	_rail.offset_right = 0.0
	_rail.offset_top = 0.0
	_rail.offset_bottom = 0.0


func _minimap_payload(player: Variant) -> Dictionary:
	var payload := {"width": map_width, "height": map_height, "revision": _tile_revision, "player": Vector2.ZERO, "aim": -PI / 2.0, "markers": [], "player_name": ""}
	if player != null:
		payload.player = player.authoritative_position
		payload.aim = float(player.aim_angle) if "aim_angle" in player else -PI / 2.0
		var named: Variant = player.stats.get(31, "") if player.stats is Dictionary else ""
		if named is String:
			payload.player_name = named
		if payload.player_name.is_empty():
			payload.player_name = str(_object_descriptor(player.object_type).get("name", ""))
	for id: Variant in entities:
		var view: Variant = entities[id]
		if not _live(view):
			continue
		var kind := "enemy"
		if int(id) == player_id:
			kind = "player"
		elif view.kind == "portal":
			kind = "portal"
		elif view.kind == "container":
			kind = "container"
		payload.markers.append({"pos": view.authoritative_position, "kind": kind})
	if _tile_revision != _hud_cells_revision:
		_hud_cells_revision = _tile_revision
		var cells := {}
		for cell: Variant in tiles:
			if cell is Vector2i:
				cells[cell] = _tile_color(int(tiles[cell]))
		payload.cells = cells
	return payload


func _refresh_rail() -> void:
	if not _ready_built: return
	var player: Variant = _player()
	var stats: Dictionary = player.stats if player != null else {}
	_summary.text = "%s\n\nHP  %s / %s\nMP  %s / %s\nLevel  %s" % [map_name, _stat_text(stats, 1), _stat_text(stats, 0), _stat_text(stats, 4), _stat_text(stats, 3), _stat_text(stats, 7)]
	_summary.text += "\nXP  %s / %s\nFame  %s" % [_stat_text(stats, 6), _stat_text(stats, 5), _stat_text(stats, 57)]
	var lines: PackedStringArray = ["INVENTORY (server)"]
	for slot: int in 12:
		var wire_id: int = 8 + slot
		var text: String = "—"
		if stats.has(wire_id):
			var type: int = _integer(stats[wire_id], -1)
			text = "empty" if type < 0 else str(_object_descriptor(type).get("name", "0x%04x" % type))
		lines.append("%02d  %s" % [slot, text.left(28)])
	_inventory.text = "\n".join(lines)
	_refresh_inventory_panel(stats)
	if is_instance_valid(_hud) and _hud.has_method("set_snapshot"):
		_hud.set_snapshot(stats, map_name, _minimap_payload(player))


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


func ui_diagnostics() -> Dictionary:
	var base: Dictionary = _hud.ui_diagnostics() if is_instance_valid(_hud) and _hud.has_method("ui_diagnostics") else {
		"schema": "gravebag.ui_diagnostics.v1", "viewport": {"w": 0.0, "h": 0.0}, "regions": [],
		"bars": {}, "actions": [], "focus": {"owner": "", "traps_gameplay": false}, "state": "world",
	}
	var regions: Array = base.get("regions", [])
	if is_instance_valid(_inventory_panel) and _inventory_panel.has_method("ui_diagnostics"):
		var child: Variant = _inventory_panel.call("ui_diagnostics")
		if child is Dictionary:
			for item: Variant in child.get("regions", []):
				if not item is Dictionary or not item.has("id"):
					continue
				var replaced := false
				for i in regions.size():
					if str(regions[i].get("id", "")) == str(item["id"]):
						regions[i] = item
						replaced = true
						break
				if not replaced:
					regions.append(item)
	base.regions = regions
	base.state = "world"
	if is_inside_tree():
		var viewport := get_viewport_rect().size
		base.viewport = {"w": viewport.x, "h": viewport.y}
		base.logical_viewport = {"w": viewport.x, "h": viewport.y}
	return base


func _refresh_inventory_panel(stats: Dictionary) -> void:
	if not is_instance_valid(_inventory_panel): return
	var source_slots: Dictionary = {}
	for wire in range(8, 20):
		if stats.has(wire): source_slots[wire] = stats[wire]
	for wire in range(71, 80):
		if stats.has(wire): source_slots[wire] = stats[wire]
	var bag_id := -1
	var bag_stats: Dictionary = {}
	var player: Variant = _player()
	var distance := 1.5
	if player != null:
		for id in entities:
			var candidate: Variant = entities[id]
			if not _live(candidate) or candidate.kind != "container": continue
			var separation: float = _prediction.distance_to(candidate.authoritative_position)
			if separation < distance:
				distance = separation
				bag_id = int(id)
				bag_stats = candidate.stats
	var snapshot := {"player_id": player_id, "slots": source_slots, "bag_id": bag_id, "bag_stats": bag_stats.duplicate(true)}
	if snapshot == _inventory_snapshot: return # Keep a drag valid across unrelated HP/tick updates.
	_inventory_snapshot = snapshot.duplicate(true)
	# Clone only occupied item metadata, not the entire multi-MB descriptor catalog per tick.
	var item_meta: Dictionary = {}
	var object_meta: Dictionary = {}
	for values in [source_slots, bag_stats]:
		for wire in values:
			if int(wire) not in range(8, 20) and int(wire) not in range(71, 79): continue
			var type := int(values[wire])
			if type < 0: continue
			var key := str(type)
			var item: Dictionary = descriptors.get("items", {}).get(key, descriptors.get("items", {}).get(type, {}))
			var object: Dictionary = descriptors.get("objects", {}).get(key, descriptors.get("objects", {}).get(type, {}))
			if not item.is_empty(): item_meta[key] = item
			if not object.is_empty(): object_meta[key] = object
	_inventory_panel.set_snapshot(player_id, source_slots, bag_id, bag_stats, {"items": item_meta, "objects": object_meta})

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
