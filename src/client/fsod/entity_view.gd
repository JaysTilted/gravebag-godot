# SPDX-License-Identifier: AGPL-3.0-only
# FSoD wire semantics: wServer/Structures.cs ObjectDef/ObjectStats and realm/Stats.cs
# at 6fd20aad4a7905b13f25389c68368a942a2b68cb. Original GRAVEBAG placeholder art.
# Visual interpolation only. No combat, collision, health, or growth simulation.
extends Node2D

const TILE_PIXELS: float = 32.0
const PIXEL: float = 3.0
const PLAYER_FRAMES: Array[String] = [
	"..HHHH../.HFFFFH./..FEEF../..CCCC../.ACCCCA./..CCCC../..B..B../.BB..BB.",
	"..HHHH../.HFFFFH./..FEEF../..CCCC../.ACCCCA./..CCCC../.B....B./.BB..BB.",
]
const ENEMY_FRAMES: Array[String] = [
	"..RRRR../.RRRRRR./.RE..ER./.RRMMRR./..RRRR../.RRRRRR./..R..R../.RR..RR.",
	"..RRRR../.RRRRRR./.RE..ER./.RRMMRR./..RRRR../.RRRRRR./.R....R./.RR..RR.",
]
var entity_id: int = -1
var object_type: int = 0
var stats: Dictionary = {} # Wire stat ID -> authoritative value, merged deltas.
var kind: String = "object"
var is_local_player: bool = false
var authoritative_position: Vector2 = Vector2.ZERO # Source tile units.
var aim_angle: float = 0.0 # Unsnappped mouse aim, radians.
var animation_frame: int = 0
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _duration: float = 0.1
var _walk_clock: float = 0.0
var _moving: bool = false
var _initialized: bool = false
var _pulse: float = 0.0
var _label: String = ""
var _visual_size: float = 1.0
# Presentation-only smoothing/edge polish. Authoritative state (stats,
# authoritative_position, targets) and Node2D.position evolution are NEVER
# derived from these; position keeps its exact baseline linear semantic
# evolution at physics rate (world_view _physics_process), which is what
# world_view:401+ projectile-hit sampling reads (target.position/TILE_PIXELS).
# Sprite texels stay hard Nearest rects at source _visual_size (no integer snap,
# no blur). Only vector decorations (portal arcs, aim, shadow) use AA/feather.
# Render pose (_render_pos, drawn via _render_offset) is cosmetic only: a
# framerate-independent damped follower of the authoritative target, advanced by
# the OPTIONAL advance_presentation(delta) that the camera worker calls from
# _process at render rate. No _process is added here (would double-step under
# the world camera owner). display_position() exposes the render pose if the
# camera worker wants it. Without advance_presentation calls, _render_offset
# stays ZERO and visuals are baseline-identical.
const SNAP_PIXELS: float = 256.0 # 8 source tiles at 32px: render pose snaps, never slides.
const INSTANT_DURATION: float = 0.002 # GOTO TickTime:0 path (clamped 0.001) snaps render.
const PRESENT_RATE: float = 20.0 # Render follower rate; exp() form is FPS-independent.
var _render_pos: Vector2 = Vector2.ZERO # Cosmetic render pose, pixels. Never read by contact.
var _render_target: Vector2 = Vector2.ZERO # Latest authoritative target, pixels.
var _render_offset: Vector2 = Vector2.ZERO # _draw origin shift; position semantics untouched.
var _render_ready: bool = false


func configure(id: int, type: int, descriptor: Dictionary) -> void:
	entity_id = id
	object_type = type
	_label = String(descriptor.get("name", "")).to_lower()
	_visual_size = clampf(float(descriptor.get("source_descriptor", {}).get("MinSize", 100)) / 100.0, 0.5, 3.0)
	kind = str(descriptor.get("kind", descriptor.get("class", "object"))).to_lower()
	if descriptor.get("player", false) == true: kind = "player"
	if descriptor.get("enemy", false) == true: kind = "enemy"
	queue_redraw()


func apply_status(status: Dictionary, seconds: float = 0.1) -> void:
	var incoming: Variant = status.get("stats", {})
	if incoming is Dictionary:
		for key: Variant in incoming:
			var wire_id: int = _stat_id(key)
			if wire_id >= 0: stats[wire_id] = incoming[key]
	elif incoming is Array:
		for pair: Variant in incoming:
			if pair is Dictionary and pair.has("type") and pair.has("value"):
				var wire_id: int = _stat_id(pair["type"])
				if wire_id >= 0: stats[wire_id] = pair["value"]
	if stats.has(2):
		_visual_size = clampf(float(stats[2]) / 100.0, 0.5, 3.0)
	var parsed: Variant = parse_position(status.get("position"))
	if parsed is Vector2:
		authoritative_position = parsed
		var target: Vector2 = parsed * TILE_PIXELS
		var duration: float = clampf(seconds, 0.001, 2.0) if is_finite(seconds) else 0.1
		# Baseline contact track: exact original linear evolution, reset every tick.
		_from = position if _initialized else target
		_to = target
		position = _from
		_elapsed = 0.0
		_duration = duration
		_moving = _from.distance_squared_to(_to) > 0.01
		_initialized = true
		# Cosmetic render track only: snap on discontinuity, otherwise the
		# advance_presentation() follower converges toward _render_target.
		_render_target = target
		if not _render_ready:
			_render_pos = target
			_render_ready = true
		elif duration <= INSTANT_DURATION or _render_pos.distance_to(target) > SNAP_PIXELS:
			_render_pos = target
		_render_offset = _render_pos - position
	queue_redraw()


# Called by world controller: display/input prediction only, reconciled every tick.
func predict_position(tile_position: Vector2) -> void:
	if not is_finite(tile_position.x) or not is_finite(tile_position.y): return
	_moving = position.distance_squared_to(tile_position * TILE_PIXELS) > 0.01
	position = tile_position * TILE_PIXELS
	_from = position
	_to = position
	_elapsed = _duration
	_render_target = position
	_render_pos = position
	_render_ready = true
	_render_offset = Vector2.ZERO
	queue_redraw()


func advance_visual(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	_elapsed += delta
	_pulse += delta
	if not is_local_player:
		position = _from.lerp(_to, clampf(_elapsed / _duration, 0.0, 1.0))
	if _moving:
		_walk_clock += delta
		animation_frame = int(_walk_clock * 8.0) % 2
	else:
		animation_frame = 0
	queue_redraw()


# OPTIONAL render-rate cosmetic pass. Called by the world camera owner from
# _process (never from physics). Moves only the render pose toward the latest
# authoritative target; Node2D.position and contact sampling are untouched.
# Safe to never call: _render_offset then stays ZERO (baseline visuals).
func advance_presentation(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	if not _render_ready:
		_render_pos = position
		_render_target = position
		_render_ready = true
		_render_offset = Vector2.ZERO
		return
	if is_local_player:
		_render_pos = position
		_render_target = position
		_render_offset = Vector2.ZERO
		return
	var rate: float = 1.0 - exp(-PRESENT_RATE * delta)
	_render_pos = _render_pos.lerp(_render_target, rate)
	if _render_pos.distance_to(_render_target) > SNAP_PIXELS:
		_render_pos = _render_target # Safety: never trail a discontinuity.
	_render_offset = _render_pos - position


# Render pose for the camera worker (display only). Falls back to the contact
# position until the first status/prediction initializes the render track.
func display_position() -> Vector2:
	return _render_pos if _render_ready else position


func _draw() -> void:
	# Visual scale only; original client contact geometry is supplied separately.
	# _render_offset shifts only the drawing origin; Node2D.position is untouched.
	# Vector decorations below use antialiased draws; sprite texels stay hard rects.
	draw_set_transform(_render_offset, 0.0, Vector2.ONE * _visual_size)
	draw_ellipse_shadow()
	if kind == "enemy" or kind == "player" or is_local_player:
		var frames: Array[String] = PLAYER_FRAMES if kind == "player" or is_local_player else ENEMY_FRAMES
		var rows: PackedStringArray = frames[animation_frame].split("/")
		var colors: Dictionary = {
			"H": Color("c39a59"), "F": Color("f1caa5"), "E": Color("9ce8ff"),
			"C": Color("7866ae"), "A": Color("efb85b"), "B": Color("30324e"),
			"R": Color("d36573"), "M": Color("612e45"),
		}
		for y: int in rows.size():
			for x: int in rows[y].length():
				var key: String = rows[y][x]
				if key != ".": draw_rect(Rect2(Vector2(x - 4, y - 6) * PIXEL, Vector2.ONE * PIXEL), colors[key])
	elif kind == "portal":
		draw_circle(Vector2(0, -7), 13.0, Color("182f43"), true, -1.0, true)
		draw_arc(Vector2(0, -7), 12.0, 0.0, TAU, 48, Color("64cbd3"), 2.0, true)
		for index in 3:
			var angle := _pulse * 1.8 + index * TAU / 3.0
			draw_arc(Vector2(0, -7), 4.0 + index * 2.0, angle, angle + 1.9, 24, Color("b2e9de"), 2.0, true)
	elif kind == "container" and "bag" in _label:
		var bag_color := Color("ad8560")
		if "white" in _label:
			bag_color = Color("e8e5d8")
		elif "blue" in _label:
			bag_color = Color("6b9cce")
		elif "purple" in _label:
			bag_color = Color("a98bcc")
		elif "pink" in _label:
			bag_color = Color("d99bae")
		draw_rect(Rect2(-6, -7, 12, 10), bag_color)
		draw_rect(Rect2(-4, -11, 8, 4), bag_color.darkened(0.15))
		draw_rect(Rect2(-4, -8, 8, 2), Color("e6c479"))
	elif "tree" in _label or "bush" in _label:
		draw_rect(Rect2(-3, -6, 6, 12), Color("71614d"))
		draw_rect(Rect2(-11, -19, 22, 15), Color("436a4d"))
		draw_rect(Rect2(-8, -25, 16, 10), Color("608653"))
	else:
		draw_rect(Rect2(-10, -18, 20, 22), Color("525c78"))
		draw_rect(Rect2(-7, -15, 14, 6), Color("d3b677"))
	if is_local_player:
		var dir: Vector2 = Vector2.from_angle(aim_angle)
		draw_line(dir * 8.0, dir * 22.0, Color("efcf7a"), 3.0, true)
		draw_circle(dir * 23.0, 2.0, Color("fff1bd"), true, -1.0, true)


func draw_ellipse_shadow() -> void:
	# Same 22x4 core footprint at source alpha; 1px feather bands only soften the
	# hard rect edge. No blur node/filter, no geometry change.
	draw_rect(Rect2(-12, 3, 24, 6), Color(0.02, 0.02, 0.04, 0.10))
	draw_rect(Rect2(-11.5, 3.5, 23, 5), Color(0.02, 0.02, 0.04, 0.22))
	draw_rect(Rect2(-11, 4, 22, 4), Color(0.02, 0.02, 0.04, 0.5))


static func parse_position(value: Variant) -> Variant:
	var result: Vector2
	if value is Vector2:
		result = value
	elif value is Dictionary:
		var x: Variant = value.get("x")
		var y: Variant = value.get("y")
		if not (x is int or x is float) or not (y is int or y is float): return null
		result = Vector2(float(x), float(y))
	else:
		return null
	# Presentation safety bound, not a server movement/passability rule.
	return result if is_finite(result.x) and is_finite(result.y) and absf(result.x) <= 1000000.0 and absf(result.y) <= 1000000.0 else null


static func _stat_id(value: Variant) -> int:
	if not (value is int or (value is String and value.is_valid_int())): return -1
	var id: int = int(value)
	return id if id >= 0 and id <= 255 else -1
