class_name CombatEnemy
extends CharacterBody2D
## GRAVEBAG bullet-hell enemy (design/game-brief.md: "enemies spray radial
## rings, spirals, aimed bursts").
##
## State machine (explicit transition table):
##   IDLE     --(initial/cooldown delay elapses)--> WINDUP
##   WINDUP   --(windup elapses: telegraph shown)--> fires pattern --> COOLDOWN
##   COOLDOWN --(cooldown elapses)--> WINDUP
##   ANY      --(hp <= 0 via take_damage)--> DEAD (hides, stops, starts respawn)
##   DEAD     --(respawn delay elapses)--> reform() --> IDLE
##
## Holds still while winding up (readable telegraph: red pulse + swell +
## drawn warning ring), drifts toward its target otherwise. Damage, death,
## and volleys are signals — a pool or spawner injects itself (dependency
## injection, no singletons). Sprite is code-generated (dark outline, no
## assets); hit feedback is a white flash via modulate.
##
## All tuning is @export so encounters stay data-driven per gameplay rules.
##
## Usage:
## [codeblock]
## var e := CombatEnemy.new()
## e.target = player
## e.pattern_kind = CombatEnemy.PatternKind.SPIRAL
## e.fire_requested.connect(pool.spawn_volley)
## e.died.connect(_on_enemy_died)
## add_child(e)
## [/codeblock]

## Fired when hp reaches 0. Carries self so spawners can loot/reform it.
signal died(enemy: CombatEnemy)
## Fired with current hp after a non-lethal hit (HUD hooks).
signal damaged(hp: float, max_hp: float)
## One volley: spawn a bullet per direction at origin. Matches
## CombatBulletPool.spawn_volley(origin, directions, speed, damage).
signal fire_requested(
	origin: Vector2, directions: PackedVector2Array, speed: float, damage: float
)

## Patterns script, preloaded so this file parses standalone (no class cache).
const Patterns := preload("res://src/combat/patterns.gd")

enum State { IDLE, WINDUP, COOLDOWN, DEAD }
enum PatternKind { RING, SPIRAL, AIMED }

## Body radius in pixels (collision + generated sprite).
const BODY_RADIUS := 20.0
## Hit-flash duration in seconds.
const FLASH_TIME := 0.09
## Telegraph ring color drawn during windup.
const TELEGRAPH_COLOR := Color(1.0, 0.25, 0.2, 0.85)

@export var max_hp := 30.0
@export var move_speed := 150.0
## Drift toward the target until this close, then hold (firing) position.
@export var preferred_range := 240.0
## Leash: beyond this distance from the target, chase back even while
## winding up so the formation never drifts off-camera.
@export var leash_range := 520.0
@export var leash_speed_mult := 2.0
@export var pattern_kind: PatternKind = PatternKind.RING
@export var ring_count := 14
@export var spiral_arm_count := 5
## Radians the spiral (and ring offset) rotates forward per volley.
@export var spiral_step := 0.6
@export var burst_count := 7
@export var burst_spread := 0.5
@export var bullet_speed := 240.0
@export var bullet_damage := 8.0
## Drawn radius for enemy orbs (materialized via the pool default). Big and
## bright so a 1280x720 frame reads instantly.
@export var bullet_radius := 13.0
@export var bullet_curve := 0.0
## Muzzle telegraph floor is 0.4s (RotMG fairness); windup + cooldown stays
## under ~2s so every live enemy fires at least every ~2s.
@export var windup_time := 0.5
@export var cooldown_time := 1.15
## Seconds a corpse waits before reforming at full hp. <= 0 disables respawn.
@export var respawn_delay := 3.0
## Delay before the first telegraph after spawn/reform.
@export var initial_delay := 0.35

## Current hp. Use take_damage()/reform(), never set directly.
var hp: float
## Aim + drift target, injected by the spawner. Null = face/shoot +X.
var target: Node2D

var _state: State = State.IDLE
var _timer := 0.0
var _respawn := 0.0
var _spiral_phase := 0.0
var _flash := 0.0
var _pulse := 0.0
var _telegraph_drawn := false
var _sprite: Sprite2D
var _shape: CollisionShape2D


func _ready() -> void:
	collision_layer = 2  # enemies (see CombatBullet header for the convention)
	collision_mask = 0  # ghost drift: damage travels via bullets, not contact
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	_shape.shape = circle
	add_child(_shape)
	_sprite = Sprite2D.new()
	_sprite.texture = CombatEnemy.make_texture()
	add_child(_sprite)
	hp = max_hp
	_state = State.IDLE
	_timer = initial_delay


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_drift(delta)
	match _state:
		State.IDLE, State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.WINDUP
				_timer = windup_time
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_fire_volley()
				_state = State.COOLDOWN
				_timer = cooldown_time


func _process(delta: float) -> void:
	_pulse += delta
	if _state == State.DEAD:
		if respawn_delay > 0.0:
			_respawn -= delta
			if _respawn <= 0.0:
				reform()
		return
	if _flash > 0.0:
		_flash -= delta
		_sprite.modulate = Color.WHITE
	elif _state == State.WINDUP:
		var progress := 1.0
		if windup_time > 0.0:
			progress = 1.0 - _timer / windup_time
		var blink: float = 0.5 + 0.5 * sin(_pulse * 18.0)
		_sprite.modulate = Color(1.0, lerpf(0.55, 0.2, blink), lerpf(0.55, 0.2, blink))
		_sprite.scale = Vector2.ONE * (1.0 + 0.25 * progress)
		queue_redraw()
	else:
		_sprite.modulate = Color.WHITE
		_sprite.scale = Vector2.ONE
		if _telegraph_drawn:
			_telegraph_drawn = false
			queue_redraw()


## Deal damage. Flashes white; at 0 hp emits died and starts the respawn clock.
func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	hp -= amount
	_flash = FLASH_TIME
	if hp <= 0.0:
		hp = 0.0
		_die()
	else:
		damaged.emit(hp, max_hp)


## Return to full hp, visible and firing after [member initial_delay].
func reform() -> void:
	hp = max_hp
	_state = State.IDLE
	_timer = initial_delay
	_flash = 0.0
	visible = true
	_shape.set_deferred("disabled", false)
	set_physics_process(true)


func _die() -> void:
	_state = State.DEAD
	_respawn = respawn_delay
	visible = false
	_shape.set_deferred("disabled", true)
	set_physics_process(false)
	died.emit(self)


## Drift toward the target until in range; hold still while telegraphing.
## Leash override: beyond leash_range, chase back at leash speed even while
## winding up so enemies hold formation around the player on-screen.
func _drift(_delta: float) -> void:
	var dir := Vector2.ZERO
	var speed := move_speed
	if target != null and is_instance_valid(target):
		var to_target: Vector2 = target.global_position - global_position
		var dist := to_target.length()
		if dist > leash_range:
			dir = to_target.normalized()
			speed = move_speed * leash_speed_mult
		elif _state != State.WINDUP and dist > preferred_range:
			dir = to_target.normalized()
	velocity = dir * speed
	move_and_slide()


## Emit one volley of the configured pattern, then advance the spiral phase.
func _fire_volley() -> void:
	var origin: Vector2 = global_position
	var aim: Vector2 = global_position + Vector2.RIGHT
	if target != null and is_instance_valid(target):
		aim = target.global_position
	var dirs := PackedVector2Array()
	match pattern_kind:
		PatternKind.RING:
			dirs = Patterns.radial_ring(origin, ring_count, _spiral_phase)
		PatternKind.SPIRAL:
			dirs = Patterns.spiral_arms(origin, aim, spiral_arm_count, _spiral_phase)
		PatternKind.AIMED:
			dirs = Patterns.aimed_burst(origin, aim, burst_count, burst_spread)
	_spiral_phase += spiral_step
	fire_requested.emit(origin, dirs, bullet_speed, bullet_damage)


## Telegraph warning ring, drawn only while winding up.
func _draw() -> void:
	if _state != State.WINDUP:
		_telegraph_drawn = false
		return
	_telegraph_drawn = true
	var progress := 1.0
	if windup_time > 0.0:
		progress = 1.0 - _timer / windup_time
	var r: float = lerpf(BODY_RADIUS * 0.6, BODY_RADIUS + 14.0, progress)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, TELEGRAPH_COLOR, 2.0)


## Code-generated grave brute: near-black outline, deep violet body, magenta
## inner glow, ember eyes, dark maw. No external assets.
static func make_texture() -> ImageTexture:
	var size := 48
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var col := _body_pixel(p)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _body_pixel(p: Vector2) -> Color:
	# Ember eyes (white-hot with red rims) and a dark maw, drawn first so the
	# body glow never covers them.
	if _in_rect(p, Vector2(-11.0, -7.0), Vector2(5.0, 6.0)) \
	or _in_rect(p, Vector2(6.0, -7.0), Vector2(5.0, 6.0)):
		var rim: bool = _in_rect(p, Vector2(-11.0, -7.0), Vector2(5.0, 1.5)) \
		or _in_rect(p, Vector2(6.0, -7.0), Vector2(5.0, 1.5))
		return Color(1.0, 0.25, 0.15, 1.0) if rim else Color(1.0, 0.95, 0.9, 1.0)
	if _in_rect(p, Vector2(-7.0, 7.0), Vector2(14.0, 4.0)):
		return Color(0.03, 0.01, 0.06, 1.0)
	var d: float = p.length()
	if d > 22.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	if d > 19.0:
		return Color(0.03, 0.02, 0.06, 1.0)
	if d > 13.0:
		var t: float = (d - 13.0) / 6.0
		return Color(lerpf(0.45, 0.12, t), lerpf(0.1, 0.03, t), lerpf(0.6, 0.16, t), 1.0)
	if d > 9.0:
		return Color(0.55, 0.12, 0.7, 1.0)
	return Color(lerpf(0.7, 0.45, d / 9.0), 0.16, lerpf(0.85, 0.6, d / 9.0), 1.0)


static func _in_rect(p: Vector2, rect_pos: Vector2, rect_size: Vector2) -> bool:
	return p.x >= rect_pos.x and p.x < rect_pos.x + rect_size.x \
	and p.y >= rect_pos.y and p.y < rect_pos.y + rect_size.y
