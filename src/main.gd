extends Node2D
## GRAVEBAG entry scene. Vertical slice target: WASD + mouse-aim bullet-heaven
## realm, tiered loot bags, XP/fame with permadeath, right-rail HUD + minimap.
##
## Spawns the dive orchestrator (res://src/game/dive.gd), which owns realm +
## player + HUD + SFX + spawns. Prints GRAVEBAG ready (smoke proof).


const DIVE_SCRIPT: Script = preload("res://src/game/dive.gd")
const FSOD_ENTRY: Script = preload("res://src/game/fsod_entry.gd")


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--fsod-client"):
		var client: Node = FSOD_ENTRY.new()
		client.name = "ServerClient"
		add_child(client)
		return
	var dive: Node2D = DIVE_SCRIPT.new()
	dive.name = "Dive"
	add_child(dive)
	print("GRAVEBAG ready")
