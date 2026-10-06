extends Area2D
class_name GravebagProjectile
## Placeholder player projectile: flies straight, fades out, frees itself.
##
## Spawned by [GravebagPlayer] toward the snapped cursor aim. Visual only for
## the vertical slice (no damage wiring yet).

## Pixels per second at full flight.
const SPEED: float = 720.0
## Seconds before the projectile frees itself.
const LIFE: float = 1.2

## Normalized travel direction in global space. Set by the spawner.
var direction: Vector2 = Vector2.RIGHT

var _age: float = 0.0


func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta
	_age += delta
	if _age >= LIFE:
		queue_free()


func _draw() -> void:
	# Cheap "glowing bolt": soft halo, hot core, white center. No assets.
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.85, 0.3, 0.35))
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.9, 0.4, 1.0))
	draw_circle(Vector2.ZERO, 1.5, Color(1.0, 1.0, 1.0, 1.0))
