class_name GravebagNexus
extends Node2D
## Safe-hub stub (design/game-brief.md: R escapes to the Nexus).
## SpawnPoint marks where the player appears; HealZone emits `healed` when a
## body enters; VaultStub labels the future vault. No healing/vault logic here.

## Emitted when a body enters the HealZone. Connect healing logic to this.
signal healed

const HUB_RADIUS := 128.0
const HEAL_RADIUS := 96.0
## Heal tick while bodies stay inside: the hub tops divers up over time.
const HEAL_TICK_SEC := 0.5

var _inside: Array = []
var _tick_left: float = 0.0


func _ready() -> void:
	var zone := get_node_or_null("HealZone") as Area2D
	if zone != null:
		if not zone.body_entered.is_connected(_on_heal_zone_body_entered):
			zone.body_entered.connect(_on_heal_zone_body_entered)
		if not zone.body_exited.is_connected(_on_heal_zone_body_exited):
			zone.body_exited.connect(_on_heal_zone_body_exited)
	queue_redraw()


func _process(delta: float) -> void:
	# Tick-heal: while any body stays in the zone, re-emit healed on a
	# timer so divers tick back to full. Prunes freed bodies defensively.
	for i in range(_inside.size() - 1, -1, -1):
		var b: Variant = _inside[i]
		if not (b is Node and is_instance_valid(b)):
			_inside.remove_at(i)
	if _inside.is_empty():
		_tick_left = 0.0
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = HEAL_TICK_SEC
		healed.emit()


func _on_heal_zone_body_entered(body: Node2D) -> void:
	if not _inside.has(body):
		_inside.append(body)
	_tick_left = 0.0
	healed.emit()


func _on_heal_zone_body_exited(body: Node2D) -> void:
	_inside.erase(body)


func _draw() -> void:
	draw_circle(Vector2.ZERO, HUB_RADIUS, Color(0.13, 0.17, 0.24))
	draw_arc(Vector2.ZERO, HUB_RADIUS, 0.0, TAU, 48, Color(0.55, 0.48, 0.30), 3.0, true)
	draw_circle(Vector2.ZERO, HEAL_RADIUS, Color(0.25, 0.70, 0.45, 0.15))
