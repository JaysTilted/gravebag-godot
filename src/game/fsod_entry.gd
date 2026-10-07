extends Node
## Opt-in server frontend entry during cutover. Original slice remains default.
const Session := preload("res://src/game/fsod_session.gd")
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
const RealmGuide := preload("res://src/client/fsod/realm_guide.gd")
const NETWORK := "res://src/net/fsod/client.gd"
const FRONTEND := "res://src/client/fsod/frontend.tscn"
const DATA := "res://src/data/fsod/"
var session: Node
var _status: Label
var _action: Button
var _profile_path := ""
var _profile: Dictionary = {}
var _frontend: Node
var _ready_reported := false
var _realm_guide: CanvasLayer


func _ready() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	_status = Label.new()
	_status.position = Vector2(16, 16)
	_status.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_status)
	_action = Button.new()
	_action.position = Vector2(16, 48)
	_action.add_theme_font_size_override("font_size", 18)
	_action.visible = false
	_action.disabled = true
	canvas.add_child(_action)
	add_child(canvas)
	_action.pressed.connect(_on_action)
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
	_frontend = frontend
	# Realm entry overlay: display-only labels, no gameplay writes. Created only
	# on the live entry path; early-_fail selftest fixtures leave it null and
	# _process no-ops so existing entry checks are unaffected.
	_realm_guide = RealmGuide.new()
	add_child(_realm_guide)
	# Observe after the session consumes packets. CREATE_SUCCESS alone is not
	# a spawned player: the original constructor can fail after that packet.
	network.connect("packet_received", _on_packet_readback)
	session.class_type = int(_profile.get("class_type", 782))
	session.skin_type = int(_profile.get("skin_type", 0))
	session.state_changed.connect(_on_state)
	session.session_error.connect(_fail)
	var result: Error = session.start(String(_profile.get("host", "127.0.0.1")), int(_profile.get("port", 2050)), _profile.hello, int(_profile.get("character_id", -1)))
	if result != OK:
		_fail("Could not start local backend connection (code %d)" % result)


## Realm guide poll: readonly display refresh once per frame. Lightweight
## single pass inside the guide; never sends gameplay/transport requests,
## never touches focus/input. Null-safe for early-_fail fixtures.
func _process(_delta: float) -> void:
	if not is_instance_valid(session) or not is_instance_valid(_frontend):
		return
	if not is_instance_valid(_realm_guide):
		return
	_realm_guide.refresh(session, _frontend)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _on_state(state: String) -> void:
	print("FSOD CLIENT STATE " + state)
	_status.text = "GRAVEBAG — " + state.replace("_", " ")
	if state != "playing": _ready_reported = false
	if state == "playing":
		_profile["character_id"] = session.character_id
		_save_profile()
		_status.text = "Entering the world…"
		print("FSOD CLIENT PLAYING") # Server CREATE_SUCCESS, not a local simulated world.
	elif state == "dead":
		_profile["character_id"] = -1
		_save_profile()
		_status.text = "YOU DIED · character saved by server"
	_refresh_action()


func _on_packet_readback(_id: int, _fields: Dictionary) -> void:
	if _ready_reported or not is_instance_valid(session) or session.state != "playing": return
	if session.player_id < 0 or int(session.player_stats.get(1, 0)) <= 0: return
	if not is_instance_valid(_frontend) or not _frontend.entities.has(session.player_id) or _frontend.tiles.is_empty(): return
	_ready_reported = true
	_status.text = "GRAVEBAG · original backend"
	print("FSOD CLIENT READY player_id=%d character_id=%d hp=%d entities=%d tiles=%d" % [session.player_id, session.character_id, session.player_stats.get(1, 0), _frontend.entities.size(), _frontend.tiles.size()])


## Playable-entry recovery buttons. Same layer/aesthetic, real Button nodes.
## "New character" only after server DEATH (CREATE path, never LOADs dead id).
## "Reconnect" only after offline/failed with saved encrypted credentials.
## Hidden during connecting/authenticating/loading/playing and during normal
## portal reconnecting. Original server creates/saves/authorizes; no delays.
func _refresh_action() -> void:
	if not is_instance_valid(_action):
		return
	if not is_instance_valid(session):
		_action.visible = false
		_action.disabled = true
		return
	if session.get("state") == "dead":
		_action.text = "New character"
		_action.visible = true
		_action.disabled = false
	elif session.get("state") in ["offline", "failed"]:
		_action.text = "Reconnect"
		_action.visible = true
		_action.disabled = false
	else:
		_action.visible = false
		_action.disabled = true


func _on_action() -> void:
	if not is_instance_valid(session) or not is_instance_valid(_action):
		return
	if _action.disabled or not _action.visible:
		return
	# Disable at press time so a double click cannot queue a second connect.
	_action.disabled = true
	var result: Error = ERR_INVALID_PARAMETER
	if session.get("state") == "dead":
		result = session.call("restart_as_new_character")
	elif session.get("state") in ["offline", "failed"]:
		result = session.call("retry_connection")
	else:
		_refresh_action()
		return
	# Session emits state_changed synchronously (connecting or failed); refresh
	# covers an immediate refusal without inventing a second connect attempt.
	_refresh_action()
	if result != OK and is_instance_valid(session):
		_refresh_action()


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
	_refresh_action()
