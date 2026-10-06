class_name GravebagPortal
extends Area2D
## Realm portal stub. Blue swirl drawn in code. Emits `entered` with the
## destination key when a body touches it; travel logic lives elsewhere
## (no wiring here).

## Emitted when a body enters the portal. Connect travel logic to this.
signal entered(destination: String)

## Where this portal leads ("nexus", "realm", ...). Travel wiring comes later.
@export var destination: String = "nexus"

const RADIUS := 28.0
const _SWIRL := Color(0.25, 0.55, 1.0)
const _SWIRL_DEEP := Color(0.10, 0.25, 0.80)
const _CORE := Color(0.65, 0.85, 1.0)


func _ready() -> void:
	_ensure_shape()
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _on_body_entered(_body: Node2D) -> void:
	entered.emit(destination)


func _ensure_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			return
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape_node.shape = circle
	add_child(shape_node)


func _draw() -> void:
	var center := Vector2.ZERO
	draw_circle(center, RADIUS + 6.0, Color(_SWIRL, 0.18))
	draw_arc(center, RADIUS, 0.0, TAU * 0.85, 32, _SWIRL, 4.0, true)
	draw_arc(center, RADIUS * 0.65, 1.2, 1.2 + TAU * 0.7, 28, _SWIRL_DEEP, 3.0, true)
	draw_arc(center, RADIUS * 0.35, 2.4, 2.4 + TAU * 0.6, 20, _SWIRL, 2.0, true)
	draw_circle(center, 5.0, _CORE)
