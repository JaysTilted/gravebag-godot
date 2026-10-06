class_name CombatBullet
extends Area2D
## Pooled bullet for GRAVEBAG (design/game-brief.md bullet-hell realm).
##
## One instance flies one shot at a time; a [CombatBulletPool] owns the
## instances and reuses them, so gameplay never allocates mid-volley.
## Look (rotmg-feel: dense bright enemy shots with white cores vs thin cyan
## player needle) is code-generated — see [method make_texture], dark outlines
## included, no external assets.
##
## Collision convention (no player files touched; player side must match):
## layer 1 = player body, layer 2 = enemies,
## layer 3 (value 4) = player bullets (mask 2), layer 4 (value 8) = enemy
## bullets (mask 1).
##
## Usage:
## [codeblock]
## var b: CombatBullet = pool.spawn(origin, dir, 400.0)
## b.curve = 1.2  # radians/sec clockwise spin (y-down)
## [/codeblock]

## Emitted exactly once per [method deactivate] so the pool can audit reuse.
signal released(bullet: CombatBullet)

## Team ids. Kept as ints (not typed across files) so each combat script
## parses standalone under `--check-only --script`.
enum Team { PLAYER = 0, ENEMY = 1 }

## Despawn this far past the viewport edge, in pixels.
const DESPAWN_MARGIN := 48.0
## Hard lifetime cap so a missed despawn can never leak a live bullet.
const MAX_LIFE := 6.0
## Pixel size of the generated textures; sprite scale maps radius onto it.
const BASE_TEX_SIZE := 32
## Collision radius the base textures are drawn for.
const BASE_RADIUS := 8.0

## Texture cache keyed by `"team_radius"` — generated once, reused forever.
static var _tex_cache: Dictionary = {}

## True while flying. False while parked in the pool.
var active := false
## Team.PLAYER (thin cyan needle) or Team.ENEMY (dense bright orb, white core).
var team: int = Team.ENEMY
## Collision radius in pixels. Also scales the sprite.
var radius := BASE_RADIUS
## Turn rate in radians/sec applied to the flight direction (0 = straight).
var curve := 0.0
## Flight speed in pixels/sec, set by [method fire].
var speed := 400.0
## Damage dealt on hit, read by the victim's hurtbox.
var damage := 10.0
## Current velocity (direction * speed, bent by [member curve]).
var velocity := Vector2.ZERO

var _life := 0.0
var _sprite: Sprite2D
var _shape: CollisionShape2D


func _ready() -> void:
	_shape = CollisionShape2D.new()
	_shape.shape = CircleShape2D.new()
	add_child(_shape)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_apply_team_look()
	deactivate()


## Launch from [param origin] along [param direction] (need not be normalized).
## Re-enables collision, shows the sprite, and starts the lifetime clock.
func fire(
	origin: Vector2,
	direction: Vector2,
	p_speed: float,
	p_team: int = Team.ENEMY,
	p_radius: float = BASE_RADIUS,
	p_curve: float = 0.0,
	p_damage: float = 10.0
) -> void:
	var dir := Vector2.RIGHT
	if direction.length_squared() > 0.0001:
		dir = direction.normalized()
	global_position = origin
	team = p_team
	radius = p_radius
	curve = p_curve
	speed = p_speed
	damage = p_damage
	velocity = dir * speed
	_life = MAX_LIFE
	(_shape.shape as CircleShape2D).radius = radius
	_apply_team_look()
	visible = true
	active = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_physics_process(true)


## Park the bullet: hide, stop, stop colliding, notify the pool via [signal released].
func deactivate() -> void:
	if active:
		released.emit(self)
	active = false
	visible = false
	velocity = Vector2.ZERO
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if curve != 0.0:
		velocity = velocity.rotated(curve * delta)
		_face_velocity()
	position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		deactivate()
		return
	if is_inside_tree():
		var bounds: Rect2 = get_viewport_rect().grow(DESPAWN_MARGIN)
		if not bounds.has_point(global_position):
			deactivate()


## Team look: collision layer/mask, texture (cached), needle faces travel dir.
func _apply_team_look() -> void:
	if team == Team.PLAYER:
		collision_layer = 4
		collision_mask = 2
	else:
		collision_layer = 8
		collision_mask = 1
	_sprite.texture = CombatBullet.make_texture(team, radius)
	var s: float = radius / BASE_RADIUS
	_sprite.scale = Vector2(s, s)
	_face_velocity()


## Needle texture points up; orbs are symmetric so facing is a no-op for them.
func _face_velocity() -> void:
	if team == Team.PLAYER and velocity.length_squared() > 0.0:
		_sprite.rotation = velocity.angle() + PI * 0.5
	else:
		_sprite.rotation = 0.0


## Code-generated bullet art (dark outlines, no assets). Enemy orbs are dense
## and bright with white cores; player shots are thin cyan needles with a
## white-hot center stripe. Results are cached by team + rounded radius.
static func make_texture(p_team: int, p_radius: float) -> ImageTexture:
	var key: String = "%d_%d" % [p_team, int(roundf(p_radius))]
	if _tex_cache.has(key):
		return _tex_cache[key] as ImageTexture
	var size: int = BASE_TEX_SIZE
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var col := _orb_pixel(p) if p_team != Team.PLAYER else _needle_pixel(p)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## Dense bright orb: near-black purple outline, hot orange-red band, white core.
static func _orb_pixel(p: Vector2) -> Color:
	var d: float = p.length()
	if d > 15.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	if d > 12.5:
		return Color(0.05, 0.01, 0.08, 1.0)
	if d > 7.0:
		var t: float = (d - 7.0) / 5.5  # 0 core-side .. 1 outline-side
		return Color(1.0, lerpf(0.92, 0.22, t), lerpf(0.88, 0.08, t), 1.0)
	return Color(1.0, 0.97, 0.93, 1.0)


## Thin cyan needle, drawn pointing up: dark outline, cyan body, white core.
static func _needle_pixel(p: Vector2) -> Color:
	var e: float = Vector2(p.x / 3.6, p.y / 14.0).length()
	if e > 1.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	if e > 0.8:
		return Color(0.01, 0.09, 0.13, 1.0)
	if absf(p.x) <= 1.1:
		return Color(0.92, 1.0, 1.0, 1.0)
	return Color(0.25, 0.9, 1.0, 1.0)
