extends CharacterBody2D
class_name GravebagPlayer
## RotMG-feel player controller for the GRAVEBAG vertical slice.
##
## Implements design/game-brief.md (WASD + mouse aim, hold-click / autofire,
## Space ability, R nexus escape, F/V potions) plus the feel rules relayed with
## this task (design/rotmg-feel-notes.md Bindings + aim rules: 8px deadzone,
## 45-degree snap, normalized strafe). NOTE: design/rotmg-feel-notes.md was not
## present in this worktree at implementation time; the three aim rules are
## implemented exactly as stated in the tasking message.
##
## Slice-tuning knobs live in the CONFIG block below (task requirement). The
## repo gameplay rules want these data-driven long-term; treat this block as
## the future config schema and move it to a config file when one exists.

# ── CONFIG: slice-tuning knobs (top of script, per task) ──────────────
## Top speed, px/s.
const MOVE_SPEED: float = 220.0
## Acceleration toward the target velocity, px/s^2. High = snappy.
const ACCEL: float = 2400.0
## Deceleration toward zero with no input, px/s^2. Higher than ACCEL = snappy stop.
const FRICTION: float = 3200.0
## Aim deadzone, px: cursor closer than this keeps the last aim direction.
const AIM_DEADZONE_PX: float = 8.0
## Aim snap step, degrees: aim/shots snap to the nearest 45-degree spoke.
const AIM_SNAP_DEG: float = 45.0
## Seconds between shots while firing.
const FIRE_INTERVAL: float = 0.22
## Max / starting health and mana.
const MAX_HP: float = 100.0
const MAX_MP: float = 100.0
## Mana regenerated per second.
const MP_REGEN: float = 8.0
## Dash-blink teleport distance, px.
const DASH_DISTANCE: float = 96.0
## Dash-blink cooldown, seconds.
const DASH_COOLDOWN: float = 2.5
## Sprite pixel scale: 1 texture pixel renders as N screen pixels (chunky look).
const PIXEL_SCALE: float = 4.0

## Runtime input bindings. Key codes map to InputEventKey keycodes, the mouse
## fire button maps to an InputEventMouseButton, per the feel-notes Bindings.
## Registered into the project InputMap at runtime so project.godot stays clean.
const BINDINGS: Dictionary = {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"ability_dash": [KEY_SPACE],
	"nexus_escape": [KEY_R],
	"potion_hp": [KEY_F],
	"potion_mp": [KEY_V],
	"autofire_toggle": [KEY_I],
}

const PROJECTILE_SCRIPT: Script = preload("res://src/player/projectile.gd")

# ── Signals (event boundary: no direct UI references) ────────────────
## Emitted whenever HP changes. Args: (hp, max_hp).
signal hp_changed(hp: float, max_hp: float)
## Emitted whenever MP changes. Args: (mp, max_mp).
signal mp_changed(mp: float, max_mp: float)
## Emitted once when HP reaches zero.
signal died
## Emitted on every shot fired.
signal fired
## Emitted when the I key toggles autofire. Arg: enabled.
signal autofire_toggled(enabled: bool)
## Emitted when the Space dash-blink fires.
signal ability_used
## Emitted when the dash-blink cooldown starts. Arg: cooldown seconds.
signal ability_cooldown_started(cooldown_sec: float)
## Emitted when the dash-blink cooldown finishes.
signal ability_cooldown_finished
## Stub: R instant escape to the safe Nexus. A realm manager handles it.
signal nexus_escape_requested
## Stub: F life-potion request. An inventory manager handles it.
signal hp_potion_requested
## Stub: V mana-potion request. An inventory manager handles it.
signal mp_potion_requested

## Current health. Clamp via damage()/heal(), never by direct assignment.
var hp: float = MAX_HP
## Current mana. Clamp via spend_mp()/restore_mp(), never by direct assignment.
var mp: float = MAX_MP
## When true, the player fires continuously without holding click (I toggles).
var autofire_enabled: bool = false

var _aim_dir: Vector2 = Vector2.RIGHT
var _fire_timer: float = 0.0
var _dash_timer: float = 0.0
var _dead: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _wand: Sprite2D = $AimPivot/Wand
@onready var _muzzle: Marker2D = $AimPivot/Muzzle


func _ready() -> void:
	_ensure_input_actions()
	_sprite.texture = _make_player_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	_wand.texture = _make_wand_texture()
	_wand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wand.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	_aim_pivot.rotation = 0.0
	hp_changed.emit(hp, MAX_HP)
	mp_changed.emit(mp, MAX_MP)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_tick_cooldowns(delta)
	_regen_mp(delta)
	_move(delta)
	_update_aim()
	_handle_fire(delta)
	_handle_buttons()


# ── Health / mana ─────────────────────────────────────────────────────
## Apply damage to HP. Emits hp_changed, and died exactly once at zero.
func damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, MAX_HP)
	if hp <= 0.0:
		_dead = true
		died.emit()


## Restore HP up to MAX_HP. No-op once dead. Emits hp_changed.
func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	hp = minf(MAX_HP, hp + amount)
	hp_changed.emit(hp, MAX_HP)


## Spend mana. Returns false when there is not enough. Emits mp_changed.
func spend_mp(amount: float) -> bool:
	if _dead or amount <= 0.0:
		return false
	if mp < amount:
		return false
	mp -= amount
	mp_changed.emit(mp, MAX_MP)
	return true


## Restore mana up to MAX_MP. Emits mp_changed.
func restore_mp(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	mp = minf(MAX_MP, mp + amount)
	mp_changed.emit(mp, MAX_MP)


# ── Internals ─────────────────────────────────────────────────────────
func _move(delta: float) -> void:
	# Normalized strafe: get_vector clamps length to 1, so diagonals are not
	# faster; limit_length is belt-and-suspenders for analog pads.
	var input_vec: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	).limit_length(1.0)
	var target: Vector2 = input_vec * MOVE_SPEED
	if input_vec == Vector2.ZERO:
		velocity = velocity.move_toward(target, FRICTION * delta)
	else:
		velocity = velocity.move_toward(target, ACCEL * delta)
	move_and_slide()


func _update_aim() -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	# 8px deadzone: a cursor on top of the player keeps the last aim.
	if to_mouse.length() >= AIM_DEADZONE_PX:
		_aim_dir = to_mouse.normalized()
	# 45-degree snap: aim spokes and shots lock to 8-way spokes.
	var step: float = deg_to_rad(AIM_SNAP_DEG)
	var snapped: float = roundf(_aim_dir.angle() / step) * step
	_aim_pivot.rotation = snapped
	# Face the aim: flip the upright body sprite, never rotate the pixels.
	_sprite.flip_h = cos(snapped) < 0.0


func _handle_fire(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)
	var mouse_held: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if (mouse_held or autofire_enabled) and _fire_timer <= 0.0:
		_fire()
		_fire_timer = FIRE_INTERVAL


func _fire() -> void:
	var bolt: Area2D = PROJECTILE_SCRIPT.new()
	bolt.direction = Vector2.RIGHT.rotated(_aim_pivot.rotation)
	get_parent().add_child(bolt)
	bolt.global_position = _muzzle.global_position
	fired.emit()


func _handle_buttons() -> void:
	if Input.is_action_just_pressed("autofire_toggle"):
		autofire_enabled = not autofire_enabled
		autofire_toggled.emit(autofire_enabled)
	if Input.is_action_just_pressed("ability_dash"):
		_try_dash()
	if Input.is_action_just_pressed("nexus_escape"):
		nexus_escape_requested.emit()
	if Input.is_action_just_pressed("potion_hp"):
		hp_potion_requested.emit()
	if Input.is_action_just_pressed("potion_mp"):
		mp_potion_requested.emit()


func _try_dash() -> void:
	if _dash_timer > 0.0:
		return
	# Blink toward movement, else toward aim when standing still.
	var blink_dir: Vector2 = velocity.normalized() if velocity.length() > 1.0 else _aim_dir
	global_position += blink_dir * DASH_DISTANCE
	_dash_timer = DASH_COOLDOWN
	ability_used.emit()
	ability_cooldown_started.emit(DASH_COOLDOWN)


func _tick_cooldowns(delta: float) -> void:
	if _dash_timer > 0.0:
		_dash_timer = maxf(0.0, _dash_timer - delta)
		if _dash_timer <= 0.0:
			ability_cooldown_finished.emit()


func _regen_mp(delta: float) -> void:
	if mp < MAX_MP:
		mp = minf(MAX_MP, mp + MP_REGEN * delta)
		mp_changed.emit(mp, MAX_MP)


## Registers the BINDINGS actions (InputEventKey keycodes) if missing.
func _ensure_input_actions() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			for code: int in BINDINGS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = code as Key
				InputMap.action_add_event(action, event)


## Chunky outlined adventurer sprite, generated in code. No external assets.
## 12-wide pixel rows scaled up by PIXEL_SCALE with a dark outline.
func _make_player_texture() -> ImageTexture:
	var rows: Array[String] = [
		"....KKKK....",
		"...KCCCCK...",
		"..KCCCCCCK..",
		"..KCCCCCCK..",
		"..KCFCCFCK..",
		"..KFEFFEFK..",
		"...KFFFFK...",
		"...KCCCCK...",
		"..KCCCCCCK..",
		"..KCKCCKCK..",
		"..KCKCCKCK..",
		"...KBBBBK...",
		"...KK..KK...",
	]
	var palette: Dictionary = {
		"K": Color(0.08, 0.06, 0.12, 1.0), # dark outline
		"C": Color(0.36, 0.20, 0.56, 1.0), # cloak purple
		"F": Color(0.95, 0.80, 0.60, 1.0), # face
		"E": Color(0.40, 1.00, 1.00, 1.0), # glowing eyes
		"B": Color(0.95, 0.75, 0.25, 1.0), # gold belt
	}
	var h: int = rows.size()
	var w: int = rows[0].length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in h:
		for x: int in w:
			var key: String = rows[y][x]
			if key == ".":
				continue
			img.set_pixel(x, y, palette[key])
	return ImageTexture.create_from_image(img)


## Tiny gold wand for the aim pivot, generated in code. No external assets.
func _make_wand_texture() -> ImageTexture:
	var rows: Array[String] = [
		"KKKKKKKK",
		"KYYYYYYW",
		"KKKKKKKK",
	]
	var palette: Dictionary = {
		"K": Color(0.08, 0.06, 0.12, 1.0), # dark outline
		"Y": Color(0.72, 0.45, 0.16, 1.0), # wood shaft
		"W": Color(1.00, 0.95, 0.70, 1.0), # bright tip
	}
	var h: int = rows.size()
	var w: int = rows[0].length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in h:
		for x: int in w:
			var key: String = rows[y][x]
			if key == ".":
				continue
			img.set_pixel(x, y, palette[key])
	return ImageTexture.create_from_image(img)
