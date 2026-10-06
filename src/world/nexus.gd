class_name GravebagNexus
extends Node2D
## Safe-hub stub (design/game-brief.md: R escapes to the Nexus).
## SpawnPoint marks where the player appears; HealZone emits `healed` when a
## body enters; VaultStub labels the future vault. No healing/vault logic here.

## Emitted when a body enters the HealZone. Connect healing logic to this.
signal healed

const HUB_RADIUS := 128.0
const HEAL_RADIUS := 96.0


func _ready() -> void:
	var zone := get_node_or_null("HealZone") as Area2D
	if zone != null:
		zone.body_entered.connect(_on_heal_zone_body_entered)
	queue_redraw()


func _on_heal_zone_body_entered(_body: Node2D) -> void:
	healed.emit()


func _draw() -> void:
	draw_circle(Vector2.ZERO, HUB_RADIUS, Color(0.13, 0.17, 0.24))
	draw_arc(Vector2.ZERO, HUB_RADIUS, 0.0, TAU, 48, Color(0.55, 0.48, 0.30), 3.0, true)
	draw_circle(Vector2.ZERO, HEAL_RADIUS, Color(0.25, 0.70, 0.45, 0.15))
