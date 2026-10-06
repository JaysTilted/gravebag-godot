class_name GraveSplitter
extends "res://src/combat/enemy.gd"
## GRAVEBAG wave3 foe: SPLITTER (original design, code-drawn).
##
## Slow tank on the full CombatEnemy contract (hp / take_damage / died /
## windup telegraph, radial volleys while alive). On death it splits into
## [member mini_count] GraveSplitterMinis beside the corpse and emits
## [signal split_spawned] so the spawner can wire each mini's
## fire_requested to its pool (same injection as any enemy). Minis inherit
## the splitter's target.
##
## Look: bulky moss-olive hex tank with dark seams and twin ember eyes,
## drawn oversized (64px) next to the 48px roster. No external assets.

## Mini script, preloaded so this file parses standalone (no class cache).
const Mini := preload("res://src/combat/variants/splitter_mini.gd")

## Emitted after a lethal hit with the spawned minis (pool-wiring hook).
signal split_spawned(minis: Array)

## Minis per split.
@export var mini_count := 2
## Minis from the latest split (oldest first). Cleared on the next split.
var spawned_minis: Array = []


func _ready() -> void:
	# Variant tuning (code-spawned slice; graduates to data with encounters).
	# Slow tank: 0.6s telegraph + 1.3s cooldown keeps the ~2s fire cycle.
	max_hp = 85.0
	move_speed = 60.0
	preferred_range = 200.0
	windup_time = 0.6
	cooldown_time = 1.3
	ring_count = 12
	bullet_speed = 200.0
	bullet_damage = 10.0
	super._ready()
	_sprite.texture = GraveSplitter.make_texture()


## Split first so the minis exist before the died signal frees the corpse.
func _die() -> void:
	_split()
	super._die()


## Spawn [member mini_count] live minis beside the corpse. They join the
## same parent (sibling position) or, outside a tree, are recorded only.
func _split() -> void:
	spawned_minis.clear()
	var parent := get_parent()
	for i in mini_count:
		var m := Mini.new()
		var side := -1.0 if i % 2 == 0 else 1.0
		m.target = target
		if parent != null:
			parent.add_child(m)
			m.global_position = global_position + Vector2(28.0 * side, 0.0)
		else:
			m.position = position + Vector2(28.0 * side, 0.0)
		spawned_minis.append(m)
	if not spawned_minis.is_empty():
		split_spawned.emit(spawned_minis)


## Code-generated olive tank: dark seams/rim, moss-olive plate gradient,
## twin ember eyes with pale cores. Bulky hex silhouette, 64px, no assets.
static func make_texture() -> ImageTexture:
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var col := _tank_pixel(p)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _tank_pixel(p: Vector2) -> Color:
	var hex: float = absf(p.x) / 30.0 + absf(p.y) / 26.0
	if hex > 1.0 and p.length() > 30.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	# Twin ember eyes with pale cores, drawn over the plate.
	for ex in [-11.0, 11.0]:
		var eye: float = Vector2((p.x - ex) * 1.2, (p.y + 6.0) * 1.5).length()
		if eye <= 3.0:
			return Color(1.0, 0.9, 0.75, 1.0)
		if eye <= 5.0:
			return Color(1.0, 0.3, 0.12, 1.0)
		if eye <= 6.5:
			return Color(0.08, 0.05, 0.04, 1.0)
	# Dark plate seams, drawn over the gradient.
	if (absf(p.x) < 1.5 or absf(p.y) < 1.5) and p.length() < 27.0:
		return Color(0.10, 0.10, 0.05, 1.0)
	if hex > 0.88:
		return Color(0.10, 0.10, 0.05, 1.0)
	var g: float = clampf(hex, 0.0, 1.0)
	return Color(lerpf(0.55, 0.30, g), lerpf(0.55, 0.32, g), lerpf(0.25, 0.12, g), 1.0)
