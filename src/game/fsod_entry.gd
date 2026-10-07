extends Node
## Opt-in server frontend entry during cutover. Original slice remains default.
const Session := preload("res://src/game/fsod_session.gd")
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
const RealmGuide := preload("res://src/client/fsod/realm_guide.gd")
const NETWORK := "res://src/net/fsod/client.gd"
const FRONTEND := "res://src/client/fsod/frontend.tscn"
const DATA := "res://src/data/fsod/"
const FEEDBACK_PATH := "res://src/client/fsod/combat_feedback.gd"
const CHROME_PATH := "res://src/client/fsod/account_chrome.gd"
var session: Node
var _status: Label
var _action: Button
var _profile_path := ""
var _profile: Dictionary = {}
var _frontend: Node
var _ready_reported := false
var _realm_guide: CanvasLayer
var _combat_feedback: Node
var _account_chrome: Node
var _last_error := ""
var _feedback_state := ""
var _feedback_map := ""
var _feedback_player := -2


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
	_attach_optional_hosts()
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
	if is_instance_valid(_realm_guide):
		_realm_guide.refresh(session, _frontend)
	_poll_feedback()
	_refresh_chrome()


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
	_refresh_chrome()


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
	if is_instance_valid(_account_chrome):
		_hide_legacy_overlay()
		return
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
	_last_error = message
	_status.text = message
	# Never log login profiles, packet fields or account credentials.
	printerr("FSOD CLIENT NOT READY: ", message)
	_refresh_action()


func _attach_optional_hosts() -> void:
	_combat_feedback = _spawn_optional(FEEDBACK_PATH)
	if is_instance_valid(_combat_feedback):
		if "layer" in _combat_feedback:
			_combat_feedback.layer = 80
		if _combat_feedback.has_method("initialize"):
			var argc := Callable(_combat_feedback, "initialize").get_argument_count()
			if argc >= 2:
				_combat_feedback.call("initialize", session, _frontend)
			else:
				_combat_feedback.call("initialize")
		_force_mouse_ignore(_combat_feedback)
	_account_chrome = _spawn_optional(CHROME_PATH)
	if is_instance_valid(_account_chrome):
		if "layer" in _account_chrome:
			_account_chrome.layer = 100
		if _account_chrome.has_signal("new_character_requested"):
			_account_chrome.connect("new_character_requested", _on_chrome_new_character)
		if _account_chrome.has_signal("reconnect_requested"):
			_account_chrome.connect("reconnect_requested", _on_chrome_reconnect)
		_hide_legacy_overlay()


func _spawn_optional(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var script: Variant = load(path)
	if not script is Script:
		return null
	var node: Variant = script.new()
	if not node is Node:
		return null
	add_child(node)
	return node


func _hide_legacy_overlay() -> void:
	if is_instance_valid(_status):
		_status.visible = false
		_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_action):
		_action.visible = false
		_action.disabled = true
		_action.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_chrome_new_character() -> void:
	if is_instance_valid(session) and session.has_method("restart_as_new_character"):
		session.call("restart_as_new_character")


func _on_chrome_reconnect() -> void:
	if is_instance_valid(session) and session.has_method("retry_connection"):
		session.call("retry_connection")


func _refresh_chrome() -> void:
	if not is_instance_valid(_account_chrome) or not _account_chrome.has_method("refresh"):
		return
	_account_chrome.call("refresh", _chrome_snapshot())
	_hide_legacy_overlay()
	var playing := is_instance_valid(session) and str(session.get("state")) == "playing"
	if _account_chrome is CanvasItem and (playing or _ready_reported):
		_account_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _chrome_snapshot() -> Dictionary:
	var snap := {
		"state": "",
		"ready": _ready_reported,
		"status": _status.text if is_instance_valid(_status) else "",
		"error": "",
		"character_name": "",
		"class_name": "",
	}
	if not is_instance_valid(session):
		return snap
	snap.state = str(session.get("state"))
	if snap.state == "failed":
		snap.error = _last_error
	if not is_instance_valid(_frontend):
		return snap
	var class_type := int(session.get("class_type"))
	var descriptors: Variant = _frontend.get("descriptors")
	if descriptors is Dictionary:
		var objects: Variant = descriptors.get("objects", {})
		if objects is Dictionary:
			var record: Variant = objects.get(class_type, objects.get(str(class_type), {}))
			if record is Dictionary:
				snap.class_name = str(record.get("name", ""))
	var player_id := int(session.get("player_id"))
	var entities: Variant = _frontend.get("entities")
	if entities is Dictionary and entities.has(player_id):
		var view: Variant = entities[player_id]
		if view != null and "stats" in view and view.stats is Dictionary:
			var named: Variant = view.stats.get(31, view.stats.get("31", ""))
			if named is String:
				snap.character_name = named
	return snap


func _poll_feedback() -> void:
	if not is_instance_valid(_combat_feedback):
		return
	var state := str(session.get("state"))
	var map_key := "%s:%s" % [_frontend.get("map_name"), _frontend.get("map_width")]
	var player_id := int(session.get("player_id"))
	if state != _feedback_state or map_key != _feedback_map or player_id != _feedback_player:
		_feedback_state = state
		_feedback_map = map_key
		_feedback_player = player_id
		if _combat_feedback.has_method("clear"):
			_combat_feedback.call("clear")
		elif _combat_feedback.has_method("reset"):
			_combat_feedback.call("reset")
	if _combat_feedback.has_method("refresh"):
		_combat_feedback.call("refresh", session, _frontend)


func _force_mouse_ignore(node: Node) -> void:
	if node is CanvasItem:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Node:
			_force_mouse_ignore(child)


func ui_diagnostics() -> Dictionary:
	var base: Dictionary = {}
	if is_instance_valid(_frontend) and _frontend.has_method("ui_diagnostics"):
		var child: Variant = _frontend.call("ui_diagnostics")
		if child is Dictionary:
			base = child
	if base.is_empty():
		var viewport := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
		base = {
			"schema": "gravebag.ui_diagnostics.v1",
			"viewport": {"w": viewport.x, "h": viewport.y},
			"regions": [],
			"bars": {},
			"actions": [],
			"focus": {"owner": "", "traps_gameplay": false},
			"state": "",
		}
	var regions: Array = base.get("regions", [])
	_ensure_region(regions, "guide", _realm_guide)
	if is_instance_valid(_account_chrome) and _account_chrome.has_method("ui_diagnostics"):
		var chrome: Variant = _account_chrome.call("ui_diagnostics")
		if chrome is Dictionary:
			for item: Variant in chrome.get("regions", []):
				_replace_region(regions, item)
	else:
		_legacy_action_regions(regions)
	base.regions = regions
	base.state = str(session.get("state")) if is_instance_valid(session) else ""
	base.actions = _available_actions()
	return base


func _available_actions() -> Array:
	if not is_instance_valid(session):
		return []
	var state := str(session.get("state"))
	if state == "dead":
		return ["new_character"]
	if state in ["offline", "failed"]:
		return ["reconnect"]
	return []


func _ensure_region(regions: Array, id: String, node: Node) -> void:
	var found := false
	for item: Variant in regions:
		if item is Dictionary and str(item.get("id", "")) == id:
			found = true
			break
	if found:
		return
	if is_instance_valid(node) and node.has_method("ui_diagnostics"):
		var child: Variant = node.call("ui_diagnostics")
		if child is Dictionary:
			for item: Variant in child.get("regions", []):
				if item is Dictionary and str(item.get("id", "")) == id:
					regions.append(item)
					return
	var region := {
		"id": id, "rect": {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0},
		"visible": false, "clipped": false, "text": "", "focusable": false, "focused": false,
}
	if is_instance_valid(node):
		var panel: Node = node
		for child in node.get_children():
			if child is Control:
				panel = child
				break
		var control := panel as Control
		if control != null and control.is_inside_tree():
			var rect: Rect2 = control.get_global_rect()
			region.rect = {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
			region.visible = control.is_visible_in_tree()
	regions.append(region)


func _legacy_action_regions(regions: Array) -> void:
	var death := {
		"id": "death", "rect": {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0},
		"visible": false, "clipped": false, "text": "", "focusable": false, "focused": false,
}
	var offline := death.duplicate(true)
	offline.id = "offline"
	if is_instance_valid(_action) and _action.visible:
		var rect := _action.get_global_rect() if _action.is_inside_tree() else Rect2()
		var record := {
			"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
			"visible": true, "clipped": false, "text": _action.text,
			"focusable": true, "focused": _action.has_focus(),
		}
		if _action.text == "New character":
			death.merge(record, true)
		elif _action.text == "Reconnect":
			offline.merge(record, true)
	_replace_region(regions, death)
	_replace_region(regions, offline)


func _replace_region(regions: Array, item: Variant) -> void:
	if not item is Dictionary or not item.has("id"):
		return
	for i in regions.size():
		if str(regions[i].get("id", "")) == str(item["id"]):
			regions[i] = item
			return
	regions.append(item)
