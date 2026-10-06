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


func configure(id: int, type: int, descriptor: Dictionary) -> void:
	entity_id = id
	object_type = type
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
	var parsed: Variant = parse_position(status.get("position"))
	if parsed is Vector2:
		authoritative_position = parsed
		var target: Vector2 = parsed * TILE_PIXELS
		_from = position if _initialized else target
		_to = target
		position = _from
		_elapsed = 0.0
		_duration = clampf(seconds, 0.001, 2.0) if is_finite(seconds) else 0.1
		_moving = _from.distance_squared_to(_to) > 0.01
		_initialized = true
	queue_redraw()


# Called by world controller: display/input prediction only, reconciled every tick.
func predict_position(tile_position: Vector2) -> void:
	if not is_finite(tile_position.x) or not is_finite(tile_position.y): return
	_moving = position.distance_squared_to(tile_position * TILE_PIXELS) > 0.01
	position = tile_position * TILE_PIXELS
	_from = position
	_to = position
	_elapsed = _duration
	queue_redraw()


func advance_visual(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	_elapsed += delta
	if not is_local_player:
		position = _from.lerp(_to, clampf(_elapsed / _duration, 0.0, 1.0))
	if _moving:
		_walk_clock += delta
		animation_frame = int(_walk_clock * 8.0) % 2
	else:
		animation_frame = 0
	queue_redraw()


func _draw() -> void:
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
	else:
		draw_rect(Rect2(-10, -18, 20, 22), Color("525c78"))
		draw_rect(Rect2(-7, -15, 14, 6), Color("d3b677"))
	if is_local_player:
		var dir: Vector2 = Vector2.from_angle(aim_angle)
		draw_line(dir * 8.0, dir * 22.0, Color("efcf7a"), 3.0)
		draw_circle(dir * 23.0, 2.0, Color("fff1bd"))


func draw_ellipse_shadow() -> void:
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
