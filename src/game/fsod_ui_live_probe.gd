extends SceneTree
## Owned QA helper: instantiates ACTUAL production fsod_entry and drives real
## input/events against a real FSoD session on a private QA backend.
## Never fakes authoritative state, never copies entry, never synthesizes HUD.
## Fail-closed without a normal QA login file. Frame-delta/time sampled
## genuinely (never fixed-rate fake FPS) and persisted to the frame dir.
## Death/offline flows are driven with real mouse InputEvents aimed at the
## production chrome regions from ui_diagnostics (never signal emits).
const ProductionEntry := preload("res://src/game/fsod_entry.gd")

var _profile_path := ""
var _frame_dir := ""
var _mode := "ui-live"
var _deadline_ms := 180000
var _max_frames := 7200
var _entry: Node = null
var _session: Node = null
var _started_ms := 0
var _frames := 0
var _last_ms := -1
var _delta_sum := 0.0
var _delta_min := 1e9
var _delta_max := 0.0
var _deltas: Array = []
var _full_snaps: Array = []
var _light_snaps: Array = []
var _done := false
var _played := false
var _last_state := ""
var _clicked_new := false
var _clicked_reconnect := false
var _shots_saved := 0
var _w_phase := false


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	_started_ms = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fsod-login-file="):
			_profile_path = argument.trim_prefix("--fsod-login-file=")
		elif argument.begins_with("--fsod-deadline-ms="):
			_deadline_ms = clampi(int(argument.trim_prefix("--fsod-deadline-ms=")), 1000, 300000)
		elif argument.begins_with("--fsod-frame-dir="):
			_frame_dir = argument.trim_prefix("--fsod-frame-dir=")
		elif argument.begins_with("--fsod-ui-mode="):
			_mode = argument.trim_prefix("--fsod-ui-mode=")
		elif argument.begins_with("--fsod-max-frames="):
			_max_frames = clampi(int(argument.trim_prefix("--fsod-max-frames=")), 30, 20000)
	if _profile_path.is_empty():
		_fail("profile missing: refusing auth/profile fallback")
		return
	if not FileAccess.file_exists(_profile_path):
		_fail("login file absent: refusing shared STATE")
		return
	if _frame_dir.is_empty():
		_fail("frame dir missing: refusing unrecorded claim")
		return
	if DirAccess.make_dir_recursive_absolute(_frame_dir) != OK:
		_fail("frame dir not writable")
		return
	# Instantiate ACTUAL production entry; never copy its logic here.
	_entry = ProductionEntry.new()
	get_root().add_child(_entry)
	print("FSOD UI LIVE PROBE entry=production fsod_entry login=qa-only mode=" + _mode)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	# Genuine frame-delta/time sampling: real engine ticks, never a fixed-rate fake.
	var now := Time.get_ticks_msec()
	if _last_ms >= 0:
		var frame_delta := float(now - _last_ms) / 1000.0
		_delta_sum += frame_delta
		_delta_min = minf(_delta_min, frame_delta)
		_delta_max = maxf(_delta_max, frame_delta)
		_deltas.append(frame_delta)
	_last_ms = now
	_resolve_session()
	var state := _session_state()
	if state == "playing":
		_played = true
	_drive_real_input(state)
	_snapshot(state, now)
	if _frames >= _max_frames or (now - _started_ms) >= _deadline_ms:
		_report()
	return false


func _resolve_session() -> void:
	if _session != null and is_instance_valid(_session):
		return
	if _entry == null or not is_instance_valid(_entry):
		return
	# Readonly inspection of the production entry's bound session.
	var candidate: Variant = _entry.get("_session")
	if candidate is Node and is_instance_valid(candidate):
		_session = candidate


func _session_state() -> String:
	if _session == null or not is_instance_valid(_session):
		return ""
	return str(_session.get("state"))


func _drive_real_input(state: String) -> void:
	# Real key flow keeps the avatar live; never send_fields/predict/interact.
	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.pressed = _w_phase
	Input.parse_input_event(press)
	_w_phase = not _w_phase
	# Death -> New-character and offline -> Reconnect use REAL mouse input
	# aimed at the production chrome regions, never direct signal emits.
	if state == "dead" and not _clicked_new:
		if _click_action("new_character"):
			_clicked_new = true
			print("FSOD UI LIVE CLICK action=new_character kind=real-mouse")
	elif (state == "offline" or state == "failed") and not _clicked_reconnect:
		if _click_action("reconnect"):
			_clicked_reconnect = true
			print("FSOD UI LIVE CLICK action=reconnect kind=real-mouse")


func _click_action(action: String) -> bool:
	var diag := _diagnostics()
	var regions: Array = diag.get("regions", [])
	var actions: Array = diag.get("actions", [])
	if not (action in actions):
		return false
	for region in regions:
		if not (region is Dictionary):
			continue
		var text := str(region.get("name", "")) + " " + str(region.get("action", ""))
		if action in text.to_lower():
			return _click_rect(region.get("rect", region.get("global_rect", null)))
	return false


func _click_rect(rect: Variant) -> bool:
	var center := Vector2(-1, -1)
	if rect is Array and rect.size() == 4:
		center = Vector2(float(rect[0]) + float(rect[2]) / 2.0, float(rect[1]) + float(rect[3]) / 2.0)
	elif rect is Dictionary and rect.has("x"):
		center = Vector2(float(rect["x"]) + float(rect.get("w", 0)) / 2.0, float(rect["y"]) + float(rect.get("h", 0)) / 2.0)
	elif rect is Rect2:
		center = rect.get_center()
	if center.x < 0.0:
		return false
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = center
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = center
	up.pressed = false
	Input.parse_input_event(up)
	return true


func _diagnostics() -> Dictionary:
	if _entry == null or not is_instance_valid(_entry):
		return {}
	if not _entry.has_method("ui_diagnostics"):
		return {}
	var value: Variant = _entry.call("ui_diagnostics")
	return value if value is Dictionary else {}


func _snapshot(state: String, now: int) -> void:
	_light_snaps.append({"f": _frames, "t": now, "st": state})
	var changed := state != _last_state
	_last_state = state
	if _frames % 15 == 0 or changed or _frames == 1:
		var diag := _diagnostics()
		_full_snaps.append({"f": _frames, "t": now, "st": state, "diag": diag})
	if _frames % 120 == 0 and _shots_saved < 6:
		_save_frame()


func _save_frame() -> void:
	var viewport := get_root()
	if viewport == null:
		return
	var image: Image = viewport.get_texture().get_image()
	var path := _frame_dir.path_join("ui-live-%06d.png" % _frames)
	if image.save_png(path) == OK:
		_shots_saved += 1


func _viewport_info() -> Dictionary:
	var viewport := get_root()
	var size := Vector2.ZERO
	var camera := ""
	if viewport != null:
		size = viewport.get_visible_rect().size
		var cam: Camera2D = viewport.get_camera_2d()
		if cam != null and is_instance_valid(cam):
			camera = str(cam.get_path()) + " zoom=" + str(cam.zoom)
	return {"w": size.x, "h": size.y, "camera": camera}


func _persist() -> void:
	var avg := 0.0
	if _frames > 1:
		avg = _delta_sum / float(_frames - 1)
	var deltas_path := _frame_dir.path_join("frame-deltas.json")
	var deltas_file := FileAccess.open(deltas_path, FileAccess.WRITE)
	if deltas_file != null:
		deltas_file.store_string(JSON.stringify({"frames": _frames, "avg_delta": avg, "min_delta": _delta_min, "max_delta": _delta_max, "deltas": _deltas}))
		deltas_file.close()
	var diag_path := _frame_dir.path_join("ui-diagnostics.jsonl")
	var diag_file := FileAccess.open(diag_path, FileAccess.WRITE)
	if diag_file != null:
		for snap in _full_snaps:
			diag_file.store_string(JSON.stringify(snap) + "\n")
		diag_file.close()
	var meta := {
		"pid": OS.get_process_id(),
		"mode": _mode,
		"frames": _frames,
		"played": _played,
		"clicked_new_character": _clicked_new,
		"clicked_reconnect": _clicked_reconnect,
		"png_saved": _shots_saved,
		"viewport": _viewport_info(),
		"profile": _profile_path.get_file(),
	}
	var meta_file := FileAccess.open(_frame_dir.path_join("ui-live-meta.json"), FileAccess.WRITE)
	if meta_file != null:
		meta_file.store_string(JSON.stringify(meta))
		meta_file.close()


func _report() -> void:
	_done = true
	_persist()
	var avg := 0.0
	if _frames > 1:
		avg = _delta_sum / float(_frames - 1)
	print("FSOD UI LIVE DIAG mode=%s frames=%d avg_delta=%.4f min=%.4f max=%.4f played=%s png=%d" % [_mode, _frames, avg, _delta_min, _delta_max, str(_played), _shots_saved])
	var diag := _diagnostics()
	if _frames < 30 or avg <= 0.0:
		_fail("no genuine frame sampling")
		return
	if not _played:
		_fail("production session never reached playing")
		return
	if str(diag.get("schema", "")) != "gravebag.ui_diagnostics.v1":
		_fail("ui_diagnostics schema missing; refusing stand-in HUD")
		return
	if _shots_saved < 1:
		_fail("no readable frame captured")
		return
	print("FSOD UI LIVE PASS mode=%s frames=%d avg_delta=%.4f png=%d clicked_new=%s clicked_reconnect=%s" % [_mode, _frames, avg, _shots_saved, str(_clicked_new), str(_clicked_reconnect)])
	quit(0)


func _fail(message: String) -> void:
	_done = true
	printerr("FSOD UI LIVE FAIL " + message)
	quit(1)
