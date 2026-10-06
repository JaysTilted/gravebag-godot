extends Node2D
## GRAVEBAG entry scene. Vertical slice target: WASD + mouse-aim bullet-heaven
## realm, tiered loot bags, XP/fame with permadeath, right-rail HUD + minimap.
##
## Spawns the player (res://src/player/player.tscn) at center-screen on ready.


const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")


func _ready() -> void:
	var player: Node2D = PLAYER_SCENE.instantiate()
	player.position = get_viewport_rect().size * 0.5
	add_child(player)
	print("GRAVEBAG ready")
