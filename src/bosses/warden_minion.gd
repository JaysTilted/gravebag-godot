extends CharacterBody2D
class_name WardenMinionStub
## Phase-2 add stub for the WARDEN OF THE GATE.
##
## A small gate-shard that drifts toward the warden's aim point and shoves
## the player. Placeholder melee body only: the combat lane replaces contact
## handling later. Code-generated 16x16-feel sprite, dark outline.
## Implements design/game-brief.md (boss spawns minions in phase 2).

## Emitted on death. Carries the dead minion for loot/tally hooks.
signal died(minion)

## Tuning (scene data overrides these; logic reads only the vars).
@export var max_hp: float = 30.0
@export var move_speed: float = 70.0

var hp: float = 30.0
var aim_target: Node2D
var _age: float = 0.0


func _ready() -> void:
	hp = max_hp
	_ensure_sprite()


## Deal damage to this stub. Lethal damage emits [signal died].
func take_damage(amount: float) -> void:
	if hp <= 0.0 or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		died.emit(self)
		if is_inside_tree():
			queue_free()


func _physics_process(delta: float) -> void:
	_age += delta
	var dir := Vector2(cos(_age * 2.1), sin(_age * 1.6)) * 0.4
	if aim_target != null and is_instance_valid(aim_target):
		var to: Vector2 = aim_target.global_position - global_position
		if to.length() > 4.0:
			dir += to.normalized()
	if dir.length() > 0.01:
		velocity = dir.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _ensure_sprite() -> void:
	var spr := get_node_or_null("Body") as Sprite2D
	if spr != null and spr.texture == null:
		spr.texture = make_stub_texture()


## Builds the shard sprite: dark husk, ember eyes, bronze crack.
static func make_stub_texture() -> ImageTexture:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := Color(0.07, 0.05, 0.10)
	var husk := Color(0.24, 0.22, 0.30)
	var husk_dark := Color(0.15, 0.14, 0.20)
	var eye := Color(1.0, 0.30, 0.10)
	var crack := Color(0.62, 0.48, 0.20)
	_rect(img, 4, 3, 8, 10, outline)
	_rect(img, 6, 1, 4, 3, outline)
	_rect(img, 5, 4, 6, 8, husk)
	_rect(img, 7, 2, 2, 2, husk_dark)
	_rect(img, 5, 10, 6, 2, husk_dark)
	_px(img, 6, 6, eye)
	_px(img, 9, 6, eye)
	_px(img, 7, 8, crack)
	_px(img, 8, 9, crack)
	return ImageTexture.create_from_image(img)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, c)
