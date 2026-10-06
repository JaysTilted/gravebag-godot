extends Node
## Opt-in server frontend entry during cutover. Original slice remains default.
const Session := preload("res://src/game/fsod_session.gd")
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
const NETWORK := "res://src/net/fsod/client.gd"
const FRONTEND := "res://src/client/fsod/frontend.tscn"
const DATA := "res://src/data/fsod/"
var session: Node
var _status: Label
var _profile_path := ""
var _profile: Dictionary = {}


func _ready() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	_status = Label.new()
	_status.position = Vector2(16, 16)
	_status.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_status)
	add_child(canvas)
	_status.text = "GRAVEBAG — connecting to original backend"
	for required in [NETWORK, FRONTEND, DATA + "objects.json", DATA + "object_descriptors.json", DATA + "projectiles.json", DATA + "grounds.json", DATA + "items.json"]:
		if not ResourceLoader.exists(required) and not FileAccess.file_exists(required):
			_fail("Backend cutover dependency not yet installed: " + required)
			return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fsod-login-file="):
			_profile_path = argument.trim_prefix("--fsod-login-file=")
	if _profile_path.is_empty():
		_fail("No local backend login profile supplied")
		return
	_profile = _read_json(_profile_path)
	if not _profile.has("hello") or not _profile.hello is Dictionary:
		_fail("Invalid local login profile (expected hello dictionary)")
		return
	var network_script: Script = load(NETWORK)
	var frontend_scene: PackedScene = load(FRONTEND)
	if network_script == null or frontend_scene == null:
		_fail("Unable to load server client modules")
		return
	var network: Node = network_script.new()
	var frontend: Node = frontend_scene.instantiate()
	add_child(network)
	add_child(frontend)
	session = Session.new()
	add_child(session)
	var metadata := Adapter.descriptors(_read_json(DATA + "objects.json"), _read_json(DATA + "object_descriptors.json"), _read_json(DATA + "projectiles.json"), _read_json(DATA + "grounds.json"))
	session.bind(network, frontend, metadata, _read_json(DATA + "items.json"))
	session.class_type = int(_profile.get("class_type", 782))
	session.skin_type = int(_profile.get("skin_type", 0))
	session.state_changed.connect(_on_state)
	session.session_error.connect(_fail)
	var result: Error = session.start(String(_profile.get("host", "127.0.0.1")), int(_profile.get("port", 2050)), _profile.hello, int(_profile.get("character_id", -1)))
	if result != OK:
		_fail("Could not start local backend connection (code %d)" % result)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _on_state(state: String) -> void:
	_status.text = "GRAVEBAG — " + state.replace("_", " ")
	if state == "playing":
		_profile["character_id"] = session.character_id
		_save_profile()
		_status.text = "GRAVEBAG · original backend"
		print("FSOD CLIENT PLAYING") # Server CREATE_SUCCESS, not a local simulated world.
	elif state == "dead":
		_profile["character_id"] = -1
		_save_profile()
		_status.text = "YOU DIED · character saved by server"


func _save_profile() -> void:
	# Existing private profile keeps its file permissions; never echo auth fields.
	var saved := FileAccess.open(_profile_path, FileAccess.WRITE)
	if saved != null:
		saved.store_string(JSON.stringify(_profile) + "\n")
		saved.close()


func _fail(message: String) -> void:
	_status.text = message
	# Never log login profiles, packet fields or account credentials.
	printerr("FSOD CLIENT NOT READY: ", message)
