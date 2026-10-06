class_name CombatBulletPool
extends Node2D
## Pre-allocated bullet pool for GRAVEBAG (design/game-brief.md bullet-hell).
##
## Owns N bullets created once in [method _ready]; [method spawn] reuses an
## inactive one, so volleys never allocate. When exhausted it drops the shot
## and counts it in [member dropped_shots] (graceful degradation: dense
## spirals thin out instead of hitching).
##
## Usage:
## [codeblock]
## # Wire an enemy once (dependency injection, no singletons):
## enemy.fire_requested.connect(pool.spawn_volley)
## [/codeblock]

## Bullet script, preloaded so this file parses standalone (no class cache).
const Bullet := preload("res://src/combat/bullet.gd")

## How many bullets to pre-allocate. Combat-density pass: 6 enemies firing
## ~14-shot volleys every ~1.7s with ~2.5s flight time keep 100+ live;
## 512 covers the formation plus warden/minions without drops.
@export var pool_size := 512

## Shots dropped because every bullet was flying. Diagnostic only.
var dropped_shots := 0

var _bullets: Array[Bullet] = []


func _ready() -> void:
	for i in pool_size:
		var b: Bullet = Bullet.new()
		b.name = "Bullet%d" % i
		add_child(b)
		_bullets.append(b)


## Launch one bullet. Returns the bullet, or null when the pool is exhausted
## (counts [member dropped_shots]). Never allocates after [method _ready].
func spawn(
	origin: Vector2,
	direction: Vector2,
	speed: float = 260.0,
	team: int = 1,
	radius: float = 13.0,
	curve: float = 0.0,
	damage: float = 8.0
) -> Bullet:
	for b in _bullets:
		if is_instance_valid(b) and not b.active:
			b.fire(origin, direction, speed, team, radius, curve, damage)
			return b
	dropped_shots += 1
	return null


## Fan helper matching [signal CombatEnemy.fire_requested]: one pooled bullet
## per direction, all sharing speed / team / radius / curve / damage.
## Returns how many bullets launched.
func spawn_volley(
	origin: Vector2,
	directions: PackedVector2Array,
	speed: float,
	damage: float,
	team: int = 1,
	radius: float = 13.0,
	curve: float = 0.0
) -> int:
	var launched := 0
	for dir in directions:
		if spawn(origin, dir, speed, team, radius, curve, damage) != null:
			launched += 1
	return launched


## How many bullets are currently flying.
func active_count() -> int:
	var n := 0
	for b in _bullets:
		if is_instance_valid(b) and b.active:
			n += 1
	return n


## Park every bullet (scene transitions, test teardown). Never allocates.
func clear_all() -> void:
	for b in _bullets:
		if is_instance_valid(b):
			b.deactivate()
	dropped_shots = 0
