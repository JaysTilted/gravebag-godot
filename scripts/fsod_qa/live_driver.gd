extends SceneTree
## SPDX-License-Identifier: AGPL-3.0-only
## Isolated live QA driver. Preloads shipped session, frontend, and realm guide.
## Does not edit those sources. Movement and E go through Input events only.
## Not a synthetic walking/realm fixture: positions come from the original server.
const Session := preload("res://src/game/fsod_session.gd")
const Adapter := preload("res://src/game/fsod_view_adapter.gd")
const Client := preload("res://src/net/fsod/client.gd")
const Frontend := preload("res://src/client/fsod/frontend.tscn")
const RealmGuide := preload("res://src/client/fsod/realm_guide.gd")
const MOVE_ID := 87
const REALM_TYPE := 1810

var session: Node
var frontend: Node
var network: Node
var guide: CanvasLayer
var started := 0
var deadline_ms := 180000
var report_path := "/state/qa-live-report.json"
var frame_dir := "/state/qa-frames"
var _done := false
var _phase := "boot"
var _held: Array = []
var _phase_ends := 0
var _hold_axis := Vector2.ZERO
var _turn_axis := Vector2.ZERO
var _reverse_axis := Vector2.ZERO
var _release_pred := Vector2.INF
var _move_requests := 0
var _move_wire := 0
var _ticks := 0
var _physics_frames := 0
var _backward := 0
var _rewinds := 0
var _rewind_tiles := 0.0
var _trailed := 0
var _max_lead := 0.0
var _prev_pred := Vector2.INF
var _prev_disp := Vector2.INF
var _hold_origin := Vector2.INF
var _disp_origin := Vector2.INF
var _auth_origin := Vector2.INF
var _auth_last := Vector2.INF
var _hold_pred_disp := 0.0
var _samples: Array = []
var _release_delta := 99.0
var _turn_disp := 0.0
var _reverse_disp := 0.0
var _turn_origin := Vector2.INF
var _reverse_origin := Vector2.INF
var _collider := {"found": false}
var _collider_target := Vector2i(-99999, -99999)
var _e_presses := 0
var _interact_id := -1
var _portal_id := -1
var _portal_label := ""
var _prompt := ""
var _direction := ""
var _reconnects := 0
var _nexus_map := ""
var _realm_map := ""
var _realm_since := -1
var _frames: Array = []
var _speed := 0.0
var _hp := -1
var _failures: Array = []
var _goto := 0
var _entry_snap := false
var _pred_before_reconnect := Vector2.INF

class MotionSampler extends Node:
	var host: SceneTree
	func _physics_process(delta: float) -> void:
		if host != null:
			host.call("sample_physics", delta)

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	started = Time.get_ticks_msec()
	var profile_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fsod-login-file="):
			profile_path = argument.trim_prefix("--fsod-login-file=")
		elif argument.begins_with("--fsod-report="):
			report_path = argument.trim_prefix("--fsod-report=")
		elif argument.begins_with("--fsod-frame-dir="):
			frame_dir = argument.trim_prefix("--fsod-frame-dir=")
		elif argument.begins_with("--fsod-deadline-ms="):
			deadline_ms = clampi(int(argument.trim_prefix("--fsod-deadline-ms=")), 1000, 300000)
	if profile_path.is_empty():
		_fail("profile missing")
		return
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if not profile is Dictionary or not (profile as Dictionary).has("hello"):
		_fail("invalid private profile")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_root().size = Vector2i(1280, 720)
	network = Client.new()
	frontend = Frontend.instantiate()
	get_root().add_child(network)
	get_root().add_child(frontend)
	session = Session.new()
	get_root().add_child(session)
	var data := "res://src/data/fsod/"
	var metadata := Adapter.descriptors(_json(data + "objects.json"), _json(data + "object_descriptors.json"), _json(data + "projectiles.json"), _json(data + "grounds.json"))
	session.bind(network, frontend, metadata, _json(data + "items.json"))
	guide = RealmGuide.new()
	get_root().add_child(guide)
	var sampler := MotionSampler.new()
	sampler.host = self
	get_root().add_child(sampler)
	frontend.move_requested.connect(_on_move_requested)
	frontend.interact_requested.connect(_on_shipped_interact)
	network.packet_received.connect(_on_packet)
	session.state_changed.connect(func(state: String) -> void: print("FSOD QA LIVE STATE ", state))
	session.session_error.connect(_fail)
	session.class_type = int(profile.get("class_type", 782))
	session.skin_type = int(profile.get("skin_type", 0))
	var result: Error = session.start(String(profile.get("host", "127.0.0.1")), int(profile.get("port", 2050)), profile.hello, int(profile.get("character_id", -1)))
	if result != OK:
		_fail("start code %d" % result)

func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _on_move_requested(_pos: Variant, _records: Array) -> void:
	if _phase == "hold":
		_move_requests += 1

func _on_shipped_interact(entity_id: int, _slot: int) -> void:
	_interact_id = entity_id
	print("FSOD QA LIVE INTERACT shipped_target=%d" % entity_id)

func _on_packet(id: int, fields: Dictionary) -> void:
	if id == 80 and _phase == "hold":
		_ticks += 1
		if _buffer_has_move():
			_move_wire += 1
	elif id == 21:
		_reconnects += 1
		_pred_before_reconnect = frontend._prediction
		print("FSOD QA LIVE RECONNECT local=true")
	elif id == 65:
		var name := String(fields.get("Name", ""))
		print("FSOD QA LIVE MAP ", name)
		if _nexus_map.is_empty():
			_nexus_map = name
		elif name != _nexus_map:
			_realm_map = name
			_realm_since = Time.get_ticks_msec()
	elif id == 3 and int(fields.get("ObjectId", -1)) == session.player_id:
		_goto += 1

func _buffer_has_move() -> bool:
	var buf: PackedByteArray = network._out
	var index := 0
	while index + 5 <= buf.size():
		var length := (int(buf[index]) << 24) | (int(buf[index + 1]) << 16) | (int(buf[index + 2]) << 8) | int(buf[index + 3])
		var packet_id := int(buf[index + 4])
		if packet_id == MOVE_ID:
			return true
		if length < 5 or length > 65536:
			return false
		index += length
	return false

func sample_physics(delta: float) -> void:
	if _done or session == null or session.state != "playing" or _phase != "hold":
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	var pred: Vector2 = frontend._prediction
	var player: Variant = frontend.entities.get(session.player_id)
	if player == null or not pred.is_finite():
		return
	var shown: Vector2 = player.display_position() / 32.0
	var auth: Vector2 = player.authoritative_position
	if _hold_origin == Vector2.INF:
		_hold_origin = pred
		_disp_origin = shown
		_auth_origin = auth
		_prev_pred = pred
		_prev_disp = shown
		return
	_physics_frames += 1
	var axis_sign := _hold_axis
	var pred_step := (pred - _prev_pred).dot(axis_sign)
	var disp_step := (shown - _prev_disp).dot(axis_sign)
	if disp_step < -0.01:
		_backward += 1
	if pred_step < -0.05:
		_rewinds += 1
		_rewind_tiles += -pred_step
	var lead := (pred - auth).dot(axis_sign)
	if lead > 0.05:
		_trailed += 1
	_max_lead = maxf(_max_lead, lead)
	_auth_last = auth
	if _physics_frames % 8 == 0 and _samples.size() < 40:
		_samples.append({"p": [snappedf(pred.x, 0.01), snappedf(pred.y, 0.01)], "d": [snappedf(shown.x, 0.01), snappedf(shown.y, 0.01)], "a": [snappedf(auth.x, 0.01), snappedf(auth.y, 0.01)]})
	_prev_pred = pred
	_prev_disp = shown

func _process(_delta: float) -> bool:
	if _done or session == null:
		return false
	if Time.get_ticks_msec() - started > deadline_ms:
		_fail("bounded deadline")
		return false
	if is_instance_valid(guide) and is_instance_valid(frontend):
		guide.refresh(session, frontend)
	if session.state == "dead":
		_fail("qa character died before proof")
		return false
	if session.state != "playing" or session.player_stats.is_empty() or not frontend.entities.has(session.player_id):
		return false
	_speed = float(frontend.prediction_speed_tiles)
	_hp = int(session.player_stats.get(1, -1))
	if _phase == "boot":
		if _speed <= 0.0 or frontend.tiles.size() < 16:
			return false
		_begin_motion()
		return false
	if Time.get_ticks_msec() < _phase_ends:
		return false
	if _phase == "hold":
		_finish_hold()
	elif _phase == "release":
		_finish_release()
	elif _phase == "turn":
		_finish_turn()
	elif _phase == "reverse":
		_finish_reverse()
	elif _phase == "collider":
		_finish_collider()
	elif _phase == "approach":
		_approach()
	elif _phase == "realm":
		_await_realm()
	return false

func _begin_motion() -> void:
	var best := Vector2.ZERO
	var best_run := -1
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var run := _clear_run(Vector2i(axis))
		var score := run + (2 if absf(axis.x) > 0.0 else 0)
		if score > best_run:
			best_run = score
			best = axis
	_hold_axis = best if best_run >= 2 else Vector2.RIGHT
	_phase = "hold"
	_phase_ends = Time.get_ticks_msec() + 1200
	_key_axis(_hold_axis)
	print("FSOD QA LIVE HOLD axis=%.0f,%.0f clear=%d speed=%.2f" % [_hold_axis.x, _hold_axis.y, maxi(best_run, 0), _speed])

func _finish_hold() -> void:
	_release_keys()
	_release_pred = frontend._prediction
	_hold_pred_disp = (_release_pred - _hold_origin).dot(_hold_axis) if _hold_origin.is_finite() else 0.0
	_phase = "release"
	_phase_ends = Time.get_ticks_msec() + 400

func _finish_release() -> void:
	_release_delta = frontend._prediction.distance_to(_release_pred)
	_turn_axis = Vector2.UP if absf(_hold_axis.x) > 0.0 else Vector2.RIGHT
	if _clear_run(Vector2i(_turn_axis)) < 2:
		_turn_axis = -_turn_axis
	_turn_origin = frontend._prediction
	_phase = "turn"
	_phase_ends = Time.get_ticks_msec() + 500
	_key_axis(_turn_axis)

func _finish_turn() -> void:
	_turn_disp = (frontend._prediction - _turn_origin).dot(_turn_axis)
	_release_keys()
	_reverse_axis = -_turn_axis
	_reverse_origin = frontend._prediction
	_phase = "reverse"
	_phase_ends = Time.get_ticks_msec() + 500
	_key_axis(_reverse_axis)

func _finish_reverse() -> void:
	_reverse_disp = (frontend._prediction - _reverse_origin).dot(_reverse_axis)
	_release_keys()
	_collider_target = _nearest_blocked(8)
	_collider["found"] = _collider_target.x != -99999
	if not _collider["found"]:
		_phase = "approach"
		_phase_ends = 0
		print("FSOD QA LIVE COLLIDER none_in_streamed_radius")
		return
	_phase = "collider"
	_phase_ends = Time.get_ticks_msec() + 2500
	_key_axis(_axis_toward(Vector2(_collider_target) + Vector2(0.5, 0.5)))

func _finish_collider() -> void:
	_release_keys()
	var pred: Vector2 = frontend._prediction
	var entered := Vector2i(floori(pred.x), floori(pred.y)) == _collider_target
	_collider = {"found": true, "cell": [_collider_target.x, _collider_target.y], "entered": entered, "pred": [snappedf(pred.x, 0.01), snappedf(pred.y, 0.01)]}
	print("FSOD QA LIVE COLLIDER cell=%d,%d entered=%s" % [_collider_target.x, _collider_target.y, entered])
	_phase = "approach"
	_phase_ends = 0

func _approach() -> void:
	if _e_presses > 0:
		_release_keys()
		if not _realm_map.is_empty():
			_phase = "realm"
		return
	if not _realm_map.is_empty():
		_phase = "realm"
		return
	var portal := _nearest_realm()
	if portal.is_empty():
		_key_axis(Vector2.UP)
		return
	_portal_id = int(portal["id"])
	_portal_label = String(portal["label"])
	_prompt = String(guide._prompt_label.text) if guide._prompt_label != null else ""
	_direction = String(guide._direction_label.text) if guide._direction_label != null else ""
	var player: Variant = frontend.entities.get(session.player_id)
	var shown: Vector2 = player.display_position() / 32.0 if player != null else session.pending_position
	var pending_dist: float = session.pending_position.distance_to(portal["pos"])
	var shown_dist: float = shown.distance_to(portal["pos"])
	var target_ok: bool = frontend.interaction_target_id == _portal_id and not _portal_label.is_empty() and _prompt.begins_with("E · Enter realm") and _prompt.contains(_portal_label) and int(portal["type"]) == REALM_TYPE
	if target_ok and _label_visible(_portal_id) and pending_dist < 0.55 and shown_dist < 0.7:
		_release_keys()
		if _e_presses == 0:
			_capture("01-nexus-realm-portal")
			_press_e()
			_e_presses = 1
			print("FSOD QA LIVE E portal=%d label=%s prompt=%s target=%d" % [_portal_id, _portal_label, _prompt, frontend.interaction_target_id])
		return
	if frontend.interaction_target_id >= 0 and frontend.interaction_target_id != _portal_id:
		_release_keys()
		_key_axis(_sidestep(portal["pos"]))
		return
	_key_axis(_axis_toward(portal["pos"]))

func _await_realm() -> void:
	_release_keys()
	if _realm_map.is_empty() or _realm_since < 0 or Time.get_ticks_msec() - _realm_since < 800:
		return
	if not frontend.entities.has(session.player_id) or frontend.tiles.size() < 16:
		return
	var after: Vector2 = frontend._prediction
	if _pred_before_reconnect.is_finite() and after.distance_to(_pred_before_reconnect) > 4.0:
		_entry_snap = true
	_capture("02-realm-after-entry")
	_finish()

func _finish() -> void:
	if _done:
		return
	var pred_disp := _hold_pred_disp
	var disp_disp := 0.0
	var auth_disp := 0.0
	if _disp_origin.is_finite() and _prev_disp.is_finite():
		disp_disp = (_prev_disp - _disp_origin).dot(_hold_axis)
	if _auth_origin.is_finite() and _auth_last.is_finite():
		auth_disp = (_auth_last - _auth_origin).dot(_hold_axis)
	var report := {
		"kind": "fsod-qa-live",
		"synthetic_fixture": false,
		"held": {"axis": [_hold_axis.x, _hold_axis.y], "physics_frames": _physics_frames, "new_ticks": _ticks, "move_requested": _move_requests, "move_wire_frames": _move_wire, "pred_disp": snappedf(pred_disp, 0.001), "display_disp": snappedf(disp_disp, 0.001), "auth_disp": snappedf(auth_disp, 0.001), "backward_steps": _backward, "rewinds": _rewinds, "rewind_tiles": snappedf(_rewind_tiles, 0.001), "auth_trailed_samples": _trailed, "max_lead": snappedf(_max_lead, 0.001), "speed": snappedf(_speed, 0.01), "samples": _samples},
		"release_delta": snappedf(_release_delta, 0.001),
		"turn_disp": snappedf(_turn_disp, 0.001),
		"reverse_disp": snappedf(_reverse_disp, 0.001),
		"collider": _collider,
		"portal": {"id": _portal_id, "type": REALM_TYPE, "label": _portal_label, "prompt": _prompt, "direction": _direction, "e_presses": _e_presses, "shipped_interact_id": _interact_id},
		"maps": {"nexus": _nexus_map, "realm": _realm_map, "reconnects": _reconnects, "goto": _goto, "entry_snap": _entry_snap},
		"frames": _frames,
		"hp": _hp,
	}
	_judge(report)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("report write failed")
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	_done = true
	if _failures.is_empty():
		print("FSOD QA LIVE PASS realm=%s portal=%d moves=%d ticks=%d rewinds=%d" % [_realm_map, _portal_id, _move_requests, _ticks, _rewinds])
		quit(0)
	else:
		print("FSOD QA LIVE FAIL %s" % ", ".join(_failures))
		quit(1)

func _judge(report: Dictionary) -> void:
	var held: Dictionary = report["held"]
	if int(held["physics_frames"]) < 40:
		_failures.append("short_hold")
	if int(held["new_ticks"]) < 8:
		_failures.append("few_delayed_ticks")
	if int(held["move_requested"]) < 12:
		_failures.append("few_move_requests")
	if int(held["move_wire_frames"]) < 6:
		_failures.append("few_move_wires")
	if float(held["pred_disp"]) < 1.5:
		_failures.append("short_prediction")
	if float(held["display_disp"]) < 1.0:
		_failures.append("short_display")
	if int(held["backward_steps"]) != 0 or int(held["rewinds"]) != 0:
		_failures.append("held_stutter")
	if int(held["auth_trailed_samples"]) < 5:
		_failures.append("auth_did_not_trail")
	if float(report["release_delta"]) > 0.08:
		_failures.append("release_snap")
	if float(report["turn_disp"]) < 0.6:
		_failures.append("turn_short")
	if float(report["reverse_disp"]) < 0.6:
		_failures.append("reverse_short")
	if bool(_collider.get("found", false)) and bool(_collider.get("entered", false)):
		_failures.append("entered_blocked_cell")
	var portal: Dictionary = report["portal"]
	if int(portal["e_presses"]) != 1 or int(portal["shipped_interact_id"]) != int(portal["id"]) or int(portal["id"]) < 0:
		_failures.append("e_target_mismatch")
	if not String(portal["prompt"]).begins_with("E · Enter realm"):
		_failures.append("guide_prompt_missing")
	var maps: Dictionary = report["maps"]
	var realm := String(maps["realm"])
	# Original worlds are named NexusPortal.<Name>. That is a realm, not Nexus.
	if realm.is_empty() or realm.to_lower() == String(maps["nexus"]).to_lower() or int(maps["reconnects"]) < 1:
		_failures.append("realm_entry_missing")
	if _frames.size() < 2:
		_failures.append("frames_missing")

func _clear_run(step: Vector2i) -> int:
	var cell := Vector2i(floori(frontend._prediction.x), floori(frontend._prediction.y))
	var count := 0
	for _i in 8:
		cell += step
		if not frontend._can_walk(Vector2(cell) + Vector2(0.5, 0.5)):
			break
		count += 1
	return count

func _nearest_blocked(radius: int) -> Vector2i:
	var origin := Vector2i(floori(frontend._prediction.x), floori(frontend._prediction.y))
	var best := Vector2i(-99999, -99999)
	var best_dist := 999999
	for y in range(origin.y - radius, origin.y + radius + 1):
		for x in range(origin.x - radius, origin.x + radius + 1):
			var cell := Vector2i(x, y)
			if cell == origin or not _tile_blocked(cell):
				continue
			var dist := origin.distance_squared_to(cell)
			if dist < best_dist:
				best_dist = dist
				best = cell
	return best

func _tile_blocked(cell: Vector2i) -> bool:
	if not frontend.tiles.has(cell):
		return false
	var tile := int(frontend.tiles[cell])
	if tile == 255:
		return true
	var desc: Dictionary = session.metadata.tiles.get(str(tile), {}).get("source_descriptor", {})
	return bool(desc.get("NoWalk", false))

func _nearest_realm() -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	var pos: Vector2 = session.pending_position
	for id in session.entity_states:
		if int(session.object_types.get(id, -1)) != REALM_TYPE:
			continue
		var record: Dictionary = session.entity_states[id]
		var portal_pos: Vector2 = record.get("position", Vector2.INF)
		if not portal_pos.is_finite():
			continue
		var dist := pos.distance_to(portal_pos)
		if dist < best_dist:
			best_dist = dist
			var stats: Dictionary = record.get("stats", {})
			best = {"id": int(id), "type": REALM_TYPE, "pos": portal_pos, "label": RealmGuide.portal_label(session.metadata, REALM_TYPE, stats)}
	return best

func _label_visible(entity_id: int) -> bool:
	var node: Variant = guide._portal_labels.get(entity_id)
	return is_instance_valid(node) and String(node.text) == _portal_label and not String(node.text).is_empty()

func _axis_toward(target: Vector2) -> Vector2:
	var offset: Vector2 = target - frontend._prediction
	var axis := Vector2.ZERO
	if absf(offset.x) > 0.2:
		axis.x = signf(offset.x)
	if absf(offset.y) > 0.2:
		axis.y = signf(offset.y)
	if axis == Vector2.ZERO:
		axis = Vector2(signf(offset.x), 0.0) if absf(offset.x) > absf(offset.y) else Vector2(0.0, signf(offset.y))
	return axis

func _sidestep(target: Vector2) -> Vector2:
	var toward := _axis_toward(target)
	return Vector2(-toward.y, toward.x) if toward != Vector2.ZERO else Vector2.RIGHT

func _key_axis(axis: Vector2) -> void:
	var desired: Array = []
	if axis.x > 0.0:
		desired.append(KEY_D)
	elif axis.x < 0.0:
		desired.append(KEY_A)
	if axis.y > 0.0:
		desired.append(KEY_S)
	elif axis.y < 0.0:
		desired.append(KEY_W)
	for key in _held:
		if key not in desired:
			_key(key, false)
	for key in desired:
		if key not in _held:
			_key(key, true)
	_held = desired

func _press_e() -> void:
	_key(KEY_E, true)
	_key(KEY_E, false)

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = false
	Input.parse_input_event(event)

func _release_keys() -> void:
	for key in _held:
		_key(key, false)
	_held.clear()

func _capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		_failures.append("headless_render")
		return
	DirAccess.make_dir_recursive_absolute(frame_dir)
	var image := get_root().get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("empty_frame")
		return
	var path := frame_dir + "/" + tag + ".png"
	if image.save_png(path) != OK:
		_failures.append("frame_write")
		return
	_frames.append(tag)
	print("FSOD QA LIVE FRAME ", tag, " ", image.get_width(), "x", image.get_height())

func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	printerr("FSOD QA LIVE FAIL: ", message)
	quit(1)
