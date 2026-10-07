extends SceneTree
## Real original-server acceptance probe; run only inside fsod_backend exec sandbox.
const Session := preload("res://src/game/fsod_session.gd")
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
const Client := preload("res://src/net/fsod/client.gd")
const Frontend := preload("res://src/client/fsod/frontend.tscn")
var session: Node
var frontend: Node
var network: Node
var started := 0
var ticks := 0
var updates := 0
var frame_count := 0
var capture_attempts := 0
var profile_path := ""
var profile: Dictionary = {}
var playing_at := -1
var _done := false
var _frame_dir := "/state/live-frames"
var _bot_realm := false
var _bot_injury := false
var _bot_loot := false
var _bot_death_cycle := false
var _dead_character_id := -1
var _recovering := false
var _deadline_ms := 90000
var _loot_request := {}
var _injury_observed := false
var _portal_used := false
var _visited_realm := false
var _realm_since := -1
var _last_log := 0
var _source_xp := -1
var _starting_xp := -1
var _nav_path: Array = []
var _nav_last := 0
var _source_hp := -1
var _moved := false
var _held_keys: Array = []

func _init() -> void:
	call_deferred("_start")

func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _start() -> void:
	started = Time.get_ticks_msec()
	var load_override := -2
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fsod-login-file="):
			profile_path = argument.trim_prefix("--fsod-login-file=")
		elif argument.begins_with("--fsod-load-character-id="):
			load_override = int(argument.trim_prefix("--fsod-load-character-id="))
		elif argument == "--fsod-bot-realm":
			_bot_realm = true
		elif argument == "--fsod-bot-injury":
			_bot_realm = true
			_bot_injury = true
		elif argument == "--fsod-bot-death-cycle":
			_bot_realm = true
			_bot_injury = true
			_bot_death_cycle = true
		elif argument.begins_with("--fsod-deadline-ms="):
			_deadline_ms = clampi(int(argument.trim_prefix("--fsod-deadline-ms=")), 1000, 300000)
		elif argument == "--fsod-bot-loot":
			_bot_realm = true
			_bot_loot = true
	if profile_path.is_empty():
		_fail("profile missing")
		return
	profile = _json(profile_path)
	if load_override >= 0:
		profile["character_id"] = load_override
	if not profile.has("hello"):
		_fail("invalid private profile")
		return
	network = Client.new()
	frontend = Frontend.instantiate()
	get_root().add_child(network)
	get_root().add_child(frontend)
	session = Session.new()
	get_root().add_child(session)
	var data := "res://src/data/fsod/"
	var metadata := Adapter.descriptors(_json(data + "objects.json"), _json(data + "object_descriptors.json"), _json(data + "projectiles.json"), _json(data + "grounds.json"))
	session.bind(network, frontend, metadata, _json(data + "items.json"))
	session.class_type = int(profile.get("class_type", 782))
	session.skin_type = int(profile.get("skin_type", 0))
	session.state_changed.connect(_on_state)
	session.session_error.connect(_fail)
	session.server_event.connect(_on_packet)
	var result: Error = session.start(String(profile.get("host", "127.0.0.1")), int(profile.get("port", 2050)), profile.hello, int(profile.get("character_id", -1)))
	if result != OK:
		_fail("start code%d" % result)

func _on_state(state: String) -> void:
	print("FSOD LIVE STATE ", state)
	if state == "dead":
		profile["character_id"] = -1
		var saved := FileAccess.open(profile_path, FileAccess.WRITE)
		if saved != null:
			saved.store_string(JSON.stringify(profile) + "\n")
			saved.close()
	if state == "playing":
		if _dead_character_id < 0: _dead_character_id = session.character_id
		playing_at = Time.get_ticks_msec()
		profile["character_id"] = session.character_id
		# Existing private file retains its mode; credentials are never logged.
		var saved := FileAccess.open(profile_path, FileAccess.WRITE)
		if saved != null:
			saved.store_string(JSON.stringify(profile) + "\n")
			saved.close()

func _on_packet(id: int, _fields: Dictionary) -> void:
	if id == 80:
		ticks += 1
	elif id == 7:
		updates += 1
	elif id == 65 and _portal_used:
		_visited_realm = true
		_realm_since = Time.get_ticks_msec()
		print("FSOD LIVE REALM ", String(_fields.get("Name", "")))

func _process(_delta: float) -> bool:
	if _done or session == null:
		return false
	if Time.get_ticks_msec() - started > (_deadline_ms if _bot_realm else 20000):
		_fail("real-client bounded deadline")
		return false
	if _recovering and session.state == "playing" and not session.player_stats.is_empty():
		if session.character_id == _dead_character_id or session.character_id < 0:
			_fail("server recovery returned dead character")
			return false
		_capture("07-original-recovery")
		_done = true
		print("FSOD LIVE RECOVERY PASS dead_character_id=%d new_character_id=%d original_server=true" % [_dead_character_id, session.character_id])
		quit(0)
		return false
	if _bot_realm and session.state == "playing" and not session.player_stats.is_empty():
		_drive_bot()
		return false
	if _bot_realm and session.state == "dead":
		_release_keys()
		print("FSOD LIVE DEATH original_server=true visited_realm=%s xp=%d" % [_visited_realm, _source_xp])
		if _bot_death_cycle and _visited_realm:
			_recovering = true
			var result: int = session.restart_as_new_character()
			if result != OK: _fail("new character request refused code%d" % result)
		else:
			_done = true
			quit(0 if _visited_realm else 1)
		return false
	if playing_at >= 0 and ticks >= 3 and updates >= 1 and not session.player_stats.is_empty():
		var elapsed := Time.get_ticks_msec() - playing_at
		if capture_attempts == 0 and elapsed > 600:
			_capture("01-nexus")
		elif capture_attempts == 1 and elapsed > 1200:
			_capture("02-source-hud")
		elif capture_attempts >= 2 and elapsed > 1800:
			_done = true
			print("FSOD LIVE PASS player_id=%d char_id=%d ticks=%d updates=%d entities=%d tiles=%d hp=%d weapon=%d frames=%d" % [session.player_id, session.character_id, ticks, updates, session.object_types.size(), frontend.tiles.size(), int(session.player_stats.get(1, -1)), int(session.player_stats.get(8, -1)), frame_count])
			quit(0)
	return false

func _drive_bot() -> void:
	var now := Time.get_ticks_msec()
	var pos: Vector2 = session.pending_position
	_source_xp = int(session.player_stats.get(6, 0))
	# Wire XP6 resets at level-up; original GetLevelExp(level)=50*(level-1)^2.
	# Inspect total source XP so genuine level-up never looks like lost progress.
	var source_level := maxi(1, int(session.player_stats.get(7, 1)))
	var source_lifetime_xp := _source_xp + 50 * (source_level - 1) * (source_level - 1)
	if _starting_xp < 0:
		_starting_xp = source_lifetime_xp
	_source_hp = int(session.player_stats.get(1, -1))
	if now - _last_log > 5000:
		_last_log = now
		print("FSOD LIVE BOT pos=%.2f,%.2f entities=%d tiles=%d hp=%d xp=%d" % [pos.x, pos.y, session.object_types.size(), frontend.tiles.size(), _source_hp, _source_xp])
	if not _visited_realm:
		var target_id := -1
		var target_dist := INF
		for id in session.entity_states:
			if session._class_for(id) != "Portal":
				continue
			var type := int(session.object_types.get(id, -1))
			var name := String(session.metadata.objects.get(str(type), {}).get("name", "")).to_lower()
			# Original RealmPortalMonitor creates bound realms using0x0712 (Nexus Portal).
			if type != 0x0712 and "realm" not in name:
				continue
			var dist: float = pos.distance_to(session.entity_states[id].position)
			if dist < target_dist:
				target_id = id
				target_dist = dist
		if target_id >= 0:
			if target_dist < 0.8:
				_release_keys()
				_portal_used = true
				frontend.interact_requested.emit(target_id, 0)
			else:
				_navigate(session.entity_states[target_id].position)
		else:
			_navigate(Vector2.ZERO, true)
		return
	var enemy_id := -1
	var enemy_dist := INF
	for id in session.entity_states:
		var type := int(session.object_types.get(id, -1))
		var meta: Dictionary = session.metadata.objects.get(str(type), {})
		if not bool(meta.get("enemy", false)):
			continue
		var dist: float = pos.distance_to(session.entity_states[id].position)
		if dist < enemy_dist:
			enemy_id = id
			enemy_dist = dist
	if _bot_loot and _drive_loot(): return
	if enemy_id >= 0:
		var target: Vector2 = session.entity_states[enemy_id].position
		if not _bot_injury: frontend.shoot_requested.emit((target - pos).angle())
		if enemy_dist > (1.0 if _bot_injury else 3.5):
			_navigate(target)
		else:
			_release_keys()
	else:
		_navigate(Vector2.ZERO, true)
	if _realm_since >= 0 and now - _realm_since > 6000 and capture_attempts < 3:
		_capture("03-original-realm-%02d" % capture_attempts)
	if _bot_injury and not _bot_death_cycle and _source_hp < int(session.player_stats.get(0, _source_hp)):
		_injury_observed = true
		_release_keys()
		_capture("05-original-damage")
		_done = true
		print("FSOD LIVE DAMAGE PASS original_server_hp=%d maximum=%d realm=true" % [_source_hp, session.player_stats.get(0, -1)])
		quit(0)
	if not _bot_injury and not _bot_loot and source_lifetime_xp > _starting_xp and _realm_since >= 0 and now - _realm_since > 10000:
		_release_keys()
		_capture("04-original-combat")
		_done = true
		print("FSOD LIVE COMBAT PASS realm=true original_server_xp=%d hp=%d ticks=%d frames=%d" % [_source_xp, _source_hp, ticks, frame_count])
		quit(0)

func _drive_loot() -> bool:
	if not _loot_request.is_empty():
		var wire: int = 8 + int(_loot_request.destination_slot)
		if int(session.player_stats.get(wire, -1)) == int(_loot_request.type):
			_release_keys()
			_capture("06-original-loot")
			_done = true
			print("FSOD LIVE LOOT PASS original_server_item=%d inventory_slot=%d source_bag=%d" % [_loot_request.type, _loot_request.destination_slot, _loot_request.source_id])
			quit(0)
		return true
	var nearest := -1
	var nearest_distance := INF
	var item_slot := -1
	for id in session.entity_states:
		if session._class_for(id) != "Container": continue
		var stats: Dictionary = session.entity_states[id].get("stats", {})
		var nonempty := -1
		for slot in range(8):
			if int(stats.get(8 + slot, -1)) >= 0:
				nonempty = slot
				break
		if nonempty < 0: continue
		var distance: float = session.pending_position.distance_to(session.entity_states[id].position)
		if distance < nearest_distance:
			nearest = id
			nearest_distance = distance
			item_slot = nonempty
	if nearest < 0: return false
	if nearest_distance >= 1.0:
		_navigate(session.entity_states[nearest].position)
		return true
	_release_keys()
	var destination_slot := -1
	for slot in range(4, 12):
		if int(session.player_stats.get(8 + slot, -1)) < 0:
			destination_slot = slot
			break
	if destination_slot < 0:
		_fail("source inventory full: no destructive loot request")
		return true
	var type: int = int(session.entity_states[nearest].stats.get(8 + item_slot, -1))
	var result: int = session.swap_slots(nearest, item_slot, session.player_id, destination_slot)
	if result != OK:
		_fail("original loot request refused")
		return true
	_loot_request = {"source_id": nearest, "source_slot": item_slot, "destination_slot": destination_slot, "type": type}
	print("FSOD LIVE LOOT REQUEST source_bag=%d type=%d destination_slot=%d; awaiting actual server snapshot" % [nearest, type, destination_slot])
	return true

func _navigate(target: Vector2, explore: bool = false) -> void:
	var pos: Vector2 = session.pending_position
	if _nav_path.is_empty() or Time.get_ticks_msec() - _nav_last > 700:
		_nav_last = Time.get_ticks_msec()
		var start := Vector2i(floori(pos.x), floori(pos.y))
		var goal := Vector2i(floori(target.x), floori(target.y))
		var blocked: Dictionary = {}
		for id in session.entity_states:
			var type := int(session.object_types.get(id, -1))
			var meta: Dictionary = session.metadata.objects.get(str(type), {}).get("source_descriptor", {})
			if bool(meta.get("OccupySquare", false)):
				var point: Vector2 = session.entity_states[id].position
				blocked[Vector2i(floori(point.x), floori(point.y))] = true
		var queue: Array = [start]
		var came: Dictionary = {start: start}
		var index := 0
		var chosen := start
		var score := INF
		while index < queue.size() and queue.size() < 5000:
			var cell: Vector2i = queue[index]
			index += 1
			var candidate_score: float = cell.y + absf(cell.x - start.x) * 0.15 if explore else Vector2(cell).distance_squared_to(Vector2(goal))
			if candidate_score < score:
				score = candidate_score
				chosen = cell
			if not explore and cell == goal:
				break
			for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var next: Vector2i = cell + step
				if came.has(next) or blocked.has(next) or not frontend.tiles.has(next):
					continue
				var tile := int(frontend.tiles[next])
				var desc: Dictionary = session.metadata.tiles.get(str(tile), {}).get("source_descriptor", {})
				if tile == 255 or bool(desc.get("NoWalk", false)):
					continue
				came[next] = cell
				queue.append(next)
		_nav_path.clear()
		while chosen != start:
			_nav_path.push_front(Vector2(chosen) + Vector2.ONE * 0.5)
			chosen = came[chosen]
	if not _nav_path.is_empty():
		var next: Vector2 = _nav_path[0]
		if pos.distance_to(next) < 0.18:
			_nav_path.pop_front()
			if not _nav_path.is_empty():
				next = _nav_path[0]
		_move_toward(next)
	else:
		_release_keys()

func _move_toward(target: Vector2) -> void:
	var offset: Vector2 = target - session.pending_position
	var desired: Array = []
	if absf(offset.x) > 0.2:
		desired.append(KEY_D if offset.x > 0 else KEY_A)
	if absf(offset.y) > 0.2:
		desired.append(KEY_S if offset.y > 0 else KEY_W)
	for key in _held_keys:
		if key not in desired:
			_key(key, false)
	for key in desired:
		if key not in _held_keys:
			_key(key, true)
	_held_keys = desired

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _release_keys() -> void:
	for key in _held_keys:
		_key(key, false)
	_held_keys.clear()

func _capture(tag: String) -> void:
	capture_attempts += 1
	if DisplayServer.get_name() == "headless":
		return # Network-only run reports zero rendered frames.
	DirAccess.make_dir_recursive_absolute(_frame_dir)
	var image := get_root().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty actual viewport")
		return
	var result := image.save_png(_frame_dir + "/" + tag + ".png")
	if result != OK:
		_fail("frame write code%d" % result)
		return
	frame_count += 1
	print("FSOD LIVE FRAME ", tag, " ", image.get_width(), "x", image.get_height())

func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	# No login data or decrypted credentials in output.
	printerr("FSOD LIVE FAIL: ", message)
	quit(1)
