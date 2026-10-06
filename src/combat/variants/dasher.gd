class_name GraveDasher
extends "res://src/combat/enemy.gd"
## GRAVEBAG wave3 foe: DASHER (original design, code-drawn).
##
## Extends the CombatEnemy contract (hp / take_damage / died / windup
## telegraph) as a melee lunger: holds still while winding up (base red
## pulse + swell + warning ring, plus a short lunge-lane tick), then lunges
## along Patterns.charge_vector. Damage is contact-only during the dash, one
## hit per lunge, via the victim's damage()/take_damage() if present — it
## never emits fire_requested, so no pool wiring is needed.
##
## Look: wide ember-orange chevron dart with a white-hot nose slit and dark
## fins. No external assets.

## Emitted when a lunge starts. Carries the dash bearing (SFX hooks).
signal lunged(direction: Vector2)
## Emitted on a contact hit. Carries the victim.
signal contact_hit(victim: Node2D)

## Lunge speed in px/s.
@export var dash_speed := 620.0
## How long a lunge carries, in seconds.
@export var dash_time := 0.28
## Contact damage per lunge (one hit per lunge).
@export var contact_damage := 12.0
## Victim counts as contacted within this + ~16px of its own radius.
@export var contact_radius := 26.0

var _dash_dir := Vector2.RIGHT
var _dash_left := 0.0
var _hit_done := false


## True while a lunge is carrying.
func is_dashing() -> bool:
	return _dash_left > 0.0


func _ready() -> void:
	# Variant tuning (code-spawned slice; graduates to data with encounters).
	max_hp = 25.0
	move_speed = 210.0
	preferred_range = 180.0
	windup_time = 0.5
	cooldown_time = 1.0
	super._ready()
	_sprite.texture = GraveDasher.make_texture()


## Telegraph done: start the lunge instead of a volley. Never fires bullets.
func _fire_volley() -> void:
	var aim: Vector2 = global_position + Vector2.RIGHT
	if target != null and is_instance_valid(target):
		aim = (target as Node2D).global_position
	_dash_dir = Patterns.charge_vector(global_position, aim)
	_dash_left = dash_time
	_hit_done = false
	lunged.emit(_dash_dir)


## Carry the lunge (fast, straight, contact check); otherwise base drift.
func _drift(delta: float) -> void:
	if _dash_left > 0.0:
		_dash_left -= delta
		velocity = _dash_dir * dash_speed
		move_and_slide()
		_try_contact_hit()
		return
	super._drift(delta)


## One contact hit per lunge, only while carrying. Player-side damage() wins
## when present; generic take_damage() is the fallback. Missing API = miss.
func _try_contact_hit() -> void:
	if _hit_done or target == null or not is_instance_valid(target):
		return
	var t := target as Node2D
	if t == null:
		return
	if global_position.distance_to(t.global_position) > contact_radius + 16.0:
		return
	_hit_done = true
	if target.has_method("damage"):
		target.call("damage", contact_damage)
	elif target.has_method("take_damage"):
		target.call("take_damage", contact_damage)
	else:
		return
	contact_hit.emit(t)


## Base warning ring plus a short lunge-lane tick toward the victim.
func _draw() -> void:
	super._draw()
	if _state == State.WINDUP and target != null and is_instance_valid(target):
		var to: Vector2 = (target as Node2D).global_position - global_position
		if to.length_squared() > 0.0001:
			var lane: Vector2 = to.normalized() * 110.0
			draw_line(Vector2.ZERO, lane, TELEGRAPH_COLOR, 3.0)


## Code-generated ember dart: dark fins/rim, orange gradient body,
## white-hot nose slit. Wide chevron silhouette, 48px, no assets.
static func make_texture() -> ImageTexture:
	var size := 48
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var col := _dart_pixel(p)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _dart_pixel(p: Vector2) -> Color:
	var shape: float = Vector2(p.x / 19.0, p.y / 10.5).length()
	var in_body: bool = shape <= 1.0
	var tip: bool = p.x >= 6.0 and p.x <= 21.0 and absf(p.y) <= (21.0 - p.x) * 0.55
	var fin: bool = p.x >= -21.0 and p.x <= -9.0 and absf(p.y) >= 7.0 and absf(p.y) <= 13.0
	if not (in_body or tip or fin):
		return Color(0.0, 0.0, 0.0, 0.0)
	# White-hot nose slit, drawn over the body glow.
	if p.x >= 3.0 and p.x <= 9.0 and absf(p.y) <= 2.2:
		return Color(1.0, 0.95, 0.85, 1.0)
	if fin or (shape > 0.82 and not tip):
		return Color(0.10, 0.03, 0.05, 1.0)
	if tip:
		var t: float = clampf((p.x - 6.0) / 15.0, 0.0, 1.0)
		return Color(1.0, lerpf(0.45, 0.85, t), 0.15, 1.0)
	var g: float = clampf(shape, 0.0, 1.0)
	return Color(lerpf(0.85, 0.45, g), lerpf(0.25, 0.08, g), 0.10, 1.0)
