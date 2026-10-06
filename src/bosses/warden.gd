extends CharacterBody2D
class_name WardenOfTheGate
## GRAVEBAG first boss: WARDEN OF THE GATE.
##
## A big chunky gate-brute (code-generated 32x32-feel sprite, dark outline).
## Three HP phases with a telegraphed taunt flash on each transition:
##   1. aimed bursts at the player,
##   2. radial rings + 2 WardenMinionStub adds (spawned once),
##   3. enrage: faster movement and fire rate, spiral volleys.
## Every transition grants a brief invulnerability flash; death emits
## [signal died] with a loot-grade int for the loot lane.
##
## Implements design/game-brief.md (phased bullet-hell boss, tiered loot).
## Tuning lives in @export vars (the scene file is the data); logic reads
## only the vars. Cross-system contact is signals-only, never UI code.
## No wiring required: aim target and arena are optional; without them the
## warden hovers and fires a default fan so the scene runs standalone.

## Emitted on death. loot_grade tiers the bag the loot lane should drop.
signal died(loot_grade: int)
## Emitted on every phase transition (old_phase, new_phase use Phase ints).
signal phase_changed(old_phase: int, new_phase: int)
## Emitted per volley so the combat lane can materialize bullets later.
signal volley_fired(pattern: StringName, directions: Array[Vector2])
## Emitted once when the phase-2 adds arrive.
signal minions_spawned(count: int)

## Phase ids. DEAD is terminal; the live walk is ONE -> TWO -> THREE.
enum Phase { DEAD = 0, ONE = 1, TWO = 2, THREE = 3 }

## Explicit transition table: phase -> allowed next phases.
## Escalation always steps one phase at a time; any live phase may die.
const TRANSITIONS := {1: [2, 0], 2: [3, 0], 3: [0]}
## Bellow shown (log only, no UI) when a new phase starts.
const TAUNT_LINE := "WARDEN OF THE GATE bars the way!"

## Local pattern helpers (integration dedups against combat/patterns later).
const Patterns := preload("res://src/bosses/boss_patterns.gd")
const Minion := preload("res://src/bosses/warden_minion.gd")

## --- Tuning (data: override per-scene, never branch on literals) ---
@export var max_hp: float = 900.0
@export var phase2_fraction: float = 0.66
@export var phase3_fraction: float = 0.33
@export var move_speed: float = 60.0
@export var enrage_speed_mult: float = 1.8
@export var volley_interval_p1: float = 1.1
@export var volley_interval_p2: float = 1.6
@export var volley_interval_p3: float = 0.65
@export var aimed_burst: int = 3
@export var aimed_spread: float = 0.18
@export var radial_count: int = 10
@export var spiral_arms: int = 2
@export var spiral_step: float = 0.35
@export var transition_invuln: float = 1.0
@export var taunt_time: float = 0.8
@export var loot_grade_base: int = 2
@export var loot_grade_enraged: int = 3
## Optional chase/aim target (player). Null-safe: the boss works without one.
@export var aim_target: Node2D

var hp: float = 900.0
var phase: int = Phase.ONE
var invuln_left: float = 0.0
var taunt_left: float = 0.0
var fire_left: float = 1.1
var spiral_tick: int = 0
var saw_enrage: bool = false
var adds_spawned: bool = false
## Live phase-2 adds (also lets tests free headless spawns).
var adds: Array = []
var _age: float = 0.0


func _ready() -> void:
	hp = max_hp
	phase = Phase.ONE
	fire_left = volley_interval_p1
	_ensure_sprite()


func _process(_delta: float) -> void:
	_flash_taunt()


func _physics_process(delta: float) -> void:
	if phase == Phase.DEAD:
		return
	_age += delta
	_tick_timers(delta)
	_drift(delta)
	_tick_firing(delta)


## Deal damage. Ignored while transitioning (invulnerable) or dead.
## Crosses at most one threshold per hit escalates stepwise (ONE->TWO->THREE).
func take_damage(amount: float) -> void:
	if phase == Phase.DEAD or invuln_left > 0.0 or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_die()
		return
	var want := phase_for_hp(hp)
	while phase != want:
		var step := _step_toward(phase, want)
		if step < 0:
			break
		_enter_phase(step)


## Phase id for the given HP under the exported fractions.
func phase_for_hp(hp_value: float) -> int:
	if max_hp <= 0.0:
		return Phase.ONE
	var frac := hp_value / max_hp
	if frac <= phase3_fraction:
		return Phase.THREE
	if frac <= phase2_fraction:
		return Phase.TWO
	return Phase.ONE


## Loot grade for the killer: enraged grade if phase 3 was reached.
func get_loot_grade() -> int:
	return loot_grade_enraged if saw_enrage else loot_grade_base


## Spawn the two phase-2 adds. Idempotent: later calls return empty.
## Adds join the parent when inside a tree; otherwise they are returned
## unparented (headless/selftest). Returns the spawned minions.
func spawn_minions() -> Array:
	var out: Array = []
	if adds_spawned:
		return out
	adds_spawned = true
	for off in [Vector2(-56, 8), Vector2(56, 8)]:
		var m := Minion.new() as CharacterBody2D
		m.position = position + off
		if m.has_method("set"):
			m.set("aim_target", aim_target)
		if is_inside_tree():
			var host := get_parent()
			if host != null:
				host.add_child(m)
				if "global_position" in m:
					m.set("global_position", global_position + off)
				_connect_minion(m)
			else:
				add_child(m)
				_connect_minion(m)
		out.append(m)
		adds.append(m)
	minions_spawned.emit(out.size())
	return out


## Code-generated brute sprite: horned helm, ember eyes, plated torso with
## a gate-rune core, bulky fists; near-black outline throughout.
static func make_brute_texture() -> ImageTexture:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := Color(0.08, 0.06, 0.12)
	var plate := Color(0.23, 0.24, 0.32)
	var plate_dark := Color(0.15, 0.16, 0.23)
	var flesh := Color(0.45, 0.38, 0.36)
	var fist := Color(0.33, 0.27, 0.27)
	var horn := Color(0.85, 0.80, 0.68)
	var eye := Color(1.0, 0.42, 0.12)
	var core := Color(0.62, 0.16, 0.38)
	var trim := Color(0.62, 0.48, 0.20)
	# Silhouette (outline).
	_rect(img, 3, 4, 6, 6, outline) # left horn block
	_rect(img, 23, 4, 6, 6, outline) # right horn block
	_rect(img, 8, 5, 16, 9, outline) # helm dome
	_rect(img, 6, 14, 20, 13, outline) # torso
	_rect(img, 2, 15, 5, 10, outline) # left arm
	_rect(img, 25, 15, 5, 10, outline) # right arm
	_rect(img, 9, 27, 6, 4, outline) # left stump
	_rect(img, 17, 27, 6, 4, outline) # right stump
	# Horns and helm.
	_rect(img, 4, 5, 4, 4, horn)
	_rect(img, 24, 5, 4, 4, horn)
	_rect(img, 9, 6, 14, 7, plate)
	_rect(img, 9, 6, 14, 2, plate_dark)
	# Ember eyes.
	_rect(img, 11, 10, 3, 2, eye)
	_rect(img, 18, 10, 3, 2, eye)
	# Torso: flesh under plate, bronze trim, rune core.
	_rect(img, 7, 15, 18, 11, flesh)
	_rect(img, 10, 15, 12, 4, plate)
	_rect(img, 15, 15, 2, 11, trim)
	_rect(img, 15, 19, 2, 2, core)
	_px(img, 14, 20, core)
	_px(img, 17, 20, core)
	# Arms and fists.
	_rect(img, 3, 16, 3, 8, flesh)
	_rect(img, 26, 16, 3, 8, flesh)
	_rect(img, 3, 22, 3, 3, fist)
	_rect(img, 26, 22, 3, 3, fist)
	# Stumps.
	_rect(img, 10, 28, 4, 2, plate_dark)
	_rect(img, 18, 28, 4, 2, plate_dark)
	return ImageTexture.create_from_image(img)


func _enter_phase(next: int) -> void:
	var old := phase
	phase = next
	if next == Phase.THREE:
		saw_enrage = true
	invuln_left = transition_invuln
	taunt_left = taunt_time
	fire_left = taunt_time + 0.2
	if next == Phase.TWO:
		spawn_minions()
	print(TAUNT_LINE, " phase ", old, " -> ", next)
	phase_changed.emit(old, next)


func _die() -> void:
	if phase == Phase.DEAD:
		return
	hp = 0.0
	phase = Phase.DEAD
	velocity = Vector2.ZERO
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		col.set_deferred("disabled", true)
	var grade := get_loot_grade()
	print("WARDEN OF THE GATE has fallen. loot_grade=", grade)
	died.emit(grade)


func _step_toward(from_phase: int, want: int) -> int:
	if want <= from_phase or want > Phase.THREE or from_phase < Phase.ONE:
		return -1
	var step: int = from_phase + 1
	var allowed: Array = TRANSITIONS.get(from_phase, [])
	if step in allowed:
		return step
	return -1


func _tick_timers(delta: float) -> void:
	if invuln_left > 0.0:
		invuln_left = maxf(0.0, invuln_left - delta)
	if taunt_left > 0.0:
		taunt_left = maxf(0.0, taunt_left - delta)


func _drift(delta: float) -> void:
	var speed := move_speed * (enrage_speed_mult if phase == Phase.THREE else 1.0)
	var dir := Vector2.ZERO
	var to: Vector2 = _get_aim_point() - global_position
	if to.length() > 4.0:
		dir = to.normalized()
	var bob := Vector2(cos(_age * 1.7), sin(_age * 2.3)) * 0.35
	var push := dir + bob
	if push.length() > 0.01:
		velocity = push.normalized() * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _tick_firing(delta: float) -> void:
	if taunt_left > 0.0:
		return
	fire_left -= delta
	if fire_left > 0.0:
		return
	match phase:
		Phase.ONE:
			_fire_aimed()
			fire_left = volley_interval_p1
		Phase.TWO:
			_fire_radial()
			fire_left = volley_interval_p2
		Phase.THREE:
			_fire_spiral()
			fire_left = volley_interval_p3


func _fire_aimed() -> void:
	var dirs: Array[Vector2] = Patterns.aimed(global_position, _get_aim_point(), aimed_burst, aimed_spread)
	volley_fired.emit(&"aimed", dirs)


func _fire_radial() -> void:
	var dirs: Array[Vector2] = Patterns.radial(radial_count, _age)
	volley_fired.emit(&"radial", dirs)


func _fire_spiral() -> void:
	var dirs: Array[Vector2] = Patterns.spiral(spiral_tick, spiral_arms, spiral_step)
	spiral_tick += 1
	volley_fired.emit(&"spiral", dirs)


func _get_aim_point() -> Vector2:
	if aim_target != null and is_instance_valid(aim_target):
		return aim_target.global_position
	if is_inside_tree():
		return global_position + Vector2.DOWN
	return Vector2.DOWN


func _connect_minion(m: CharacterBody2D) -> void:
	if m.has_signal("died"):
		m.connect("died", _on_minion_died)


func _on_minion_died(_minion) -> void:
	pass


func _flash_taunt() -> void:
	var spr := get_node_or_null("Body") as Sprite2D
	if spr == null:
		return
	if invuln_left > 0.0:
		var on := int(Time.get_ticks_msec() / 90) % 2 == 0
		spr.modulate = Color(1, 1, 1, 1) if on else Color(1.0, 0.45, 0.45, 1)
	elif taunt_left > 0.0:
		spr.modulate = Color(1.0, 0.55, 0.55, 1)
	else:
		spr.modulate = Color(1, 1, 1, 1)


func _ensure_sprite() -> void:
	var spr := get_node_or_null("Body") as Sprite2D
	if spr != null and spr.texture == null:
		spr.texture = make_brute_texture()


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, c)
