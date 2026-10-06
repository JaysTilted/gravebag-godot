class_name GraveSniper
extends "res://src/combat/enemy.gd"
## GRAVEBAG wave3 foe: SNIPER (original design, code-drawn).
##
## Extends the CombatEnemy contract (hp / take_damage / died / windup
## telegraph) as a long-range marksman: a long readable windup (base red
## pulse + swell + ring, plus a thin aim beam), then ONE fast thin aimed
## bolt via Patterns.aimed_fan. Thinness/speed live on bullet_radius /
## bullet_speed so the spawner materializes them; the volley itself is a
## single direction so the pool path is unchanged.
##
## Look: tall narrow teal sentinel with a dark barrel, one cyan scope eye,
## deep-violet rim. No external assets.


func _ready() -> void:
	# Variant tuning (code-spawned slice; graduates to data with encounters).
	# Long windup (0.9s) + 1.0s cooldown keeps the ~2s fire cycle fair.
	max_hp = 20.0
	move_speed = 110.0
	preferred_range = 320.0
	windup_time = 0.9
	cooldown_time = 1.0
	burst_count = 1
	bullet_speed = 560.0
	bullet_radius = 6.0
	bullet_damage = 10.0
	super._ready()
	_sprite.texture = GraveSniper.make_texture()


## One fast thin bolt exactly on the aim bearing.
func _fire_volley() -> void:
	var origin: Vector2 = global_position
	var aim: Vector2 = global_position + Vector2.RIGHT
	if target != null and is_instance_valid(target):
		aim = (target as Node2D).global_position
	var dirs := Patterns.aimed_fan(origin, aim, 1, 0.0)
	_spiral_phase += spiral_step
	fire_requested.emit(origin, dirs, bullet_speed, bullet_damage)


## Base warning ring plus a thin aim beam toward the victim while winding up.
func _draw() -> void:
	super._draw()
	if _state == State.WINDUP and target != null and is_instance_valid(target):
		var to: Vector2 = (target as Node2D).global_position - global_position
		if to.length_squared() > 0.0001:
			var beam: Vector2 = to.normalized() * 320.0
			draw_line(Vector2.ZERO, beam, Color(1.0, 0.3, 0.25, 0.45), 1.5)


## Code-generated teal sentinel: deep-violet rim, teal gradient spire, dark
## barrel with a bright muzzle tip, one cyan scope eye. Tall narrow
## silhouette, 48px, no assets.
static func make_texture() -> ImageTexture:
	var size := 48
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var col := _sentinel_pixel(p)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _sentinel_pixel(p: Vector2) -> Color:
	var shape: float = Vector2(p.x / 9.5, p.y / 20.0).length()
	var in_body: bool = shape <= 1.0
	var barrel: bool = absf(p.x) <= 2.5 and p.y >= -26.0 and p.y <= -13.0
	if not (in_body or barrel):
		return Color(0.0, 0.0, 0.0, 0.0)
	# Cyan scope eye with a dark socket ring, drawn over the body.
	var eye: float = Vector2(p.x, (p.y + 4.0) * 1.4).length()
	if eye <= 4.2:
		return Color(0.75, 1.0, 1.0, 1.0)
	if eye <= 6.0:
		return Color(0.05, 0.10, 0.14, 1.0)
	# Bright muzzle tip on an otherwise dark barrel.
	if barrel and p.y <= -23.0:
		return Color(0.85, 1.0, 1.0, 1.0)
	if (shape > 0.8 and shape <= 1.0) or (barrel and absf(p.x) > 1.5):
		return Color(0.06, 0.08, 0.16, 1.0)
	if barrel:
		return Color(0.10, 0.16, 0.22, 1.0)
	var g: float = clampf(shape, 0.0, 1.0)
	return Color(lerpf(0.35, 0.10, g), lerpf(0.75, 0.35, g), lerpf(0.70, 0.40, g), 1.0)
