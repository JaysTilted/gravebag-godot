class_name GraveSplitterMini
extends "res://src/combat/enemy.gd"
## GRAVEBAG wave3 foe: SPLITTER MINI (original design, code-drawn).
##
## Fast fragile chaser spawned by GraveSplitter._split (two per death). Full
## CombatEnemy contract (hp / take_damage / died / windup telegraph) with a
## small dense ring volley. Never reforms (respawn_delay 0): minis stay dead
## so splits cannot farm.
##
## Look: small rose-red shard chunk with one ember eye. No external assets.


func _ready() -> void:
	# Mini tuning (code-spawned slice; graduates to data with encounters).
	max_hp = 10.0
	move_speed = 230.0
	preferred_range = 80.0
	windup_time = 0.4
	cooldown_time = 1.0
	ring_count = 6
	bullet_speed = 220.0
	bullet_damage = 6.0
	bullet_radius = 8.0
	respawn_delay = 0.0
	super._ready()
	_sprite.texture = GraveSplitterMini.make_texture()


## Code-generated rose shard: dark rim, rose gradient chunk, one ember eye
## with a dark socket. Small round silhouette, 32px, no assets.
static func make_texture() -> ImageTexture:
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var col := _shard_pixel(p)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _shard_pixel(p: Vector2) -> Color:
	var d: float = p.length()
	if d > 14.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	# Single ember eye with a dark socket, drawn over the body.
	var eye: float = Vector2(p.x, (p.y + 1.0) * 1.5).length()
	if eye <= 2.8:
		return Color(1.0, 0.85, 0.7, 1.0)
	if eye <= 4.0:
		return Color(0.12, 0.04, 0.06, 1.0)
	if d > 12.0:
		return Color(0.12, 0.04, 0.06, 1.0)
	if d > 8.0:
		var t: float = (d - 8.0) / 4.0
		return Color(lerpf(0.75, 0.35, t), lerpf(0.25, 0.10, t), lerpf(0.30, 0.14, t), 1.0)
	return Color(lerpf(0.85, 0.70, d / 8.0), lerpf(0.35, 0.22, d / 8.0), lerpf(0.38, 0.26, d / 8.0), 1.0)
