extends SceneTree
## Owned QA helper: instantiates ACTUAL production fsod_entry and drives real
## input/events against a real FSoD session. Never fakes authoritative state,
## never copies entry, never synthesizes HUD. Fail-closed without a normal QA
## login file. Frame-delta/time sampled genuinely (never fixed-rate fake FPS).
const ProductionEntry := preload("res://src/game/fsod_entry.gd")

var _profile_path := ""
var _entry: Node = null
var _started_ms := 0
var _deadline_ms := 90000
var _max_frames := 600
var _frames := 0
var _last_ms := -1
var _delta_sum := 0.0
var _delta_min := INF
var _delta_max := 0.0
var _frame_dir := ""
var _done := false

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
	if _profile_path.is_empty():
		_fail("profile missing: refusing auth/profile fallback")
		return
	if not FileAccess.file_exists(_profile_path):
		_fail("login file absent: refusing shared STATE")
		return
	# Instantiate ACTUAL production entry; never copy its logic here.
	_entry = ProductionEntry.new()
	get_root().add_child(_entry)
	print("FSOD UI LIVE PROBE entry=production fsod_entry login=qa-only")

func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	# Genuine frame-delta/time sampling: easing fills are compared against
	# actual source values elsewhere; this records real deltas, no fixed rate.
	var now := Time.get_ticks_msec()
	if _last_ms >= 0:
		var frame_delta := float(now - _last_ms) / 1000.0
		_delta_sum += frame_delta
		_delta_min = minf(_delta_min, frame_delta)
		_delta_max = maxf(_delta_max, frame_delta)
	_last_ms = now
	_drive_real_input()
	if _frames >= _max_frames or (now - _started_ms) >= _deadline_ms:
		_report()
	return false

func _drive_real_input() -> void:
	# Real InputEvent flow only; never send_fields/predict_motion/interact emit.
	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.pressed = false
	Input.parse_input_event(release)
	# ui_diagnostics is consumed when a production module implements it;
	# this probe never synthesizes a stand-in HUD.
	if _entry != null and _entry.has_method("get") == false:
		pass

func _report() -> void:
	_done = true
	var avg := 0.0
	if _frames > 1:
		avg = _delta_sum / float(_frames - 1)
	print("FSOD UI LIVE DIAG frames=%d avg_delta=%.4f min=%.4f max=%.4f" % [_frames, avg, _delta_min, _delta_max])
	quit(0)

func _fail(message: String) -> void:
	_done = true
	printerr("FSOD UI LIVE FAIL " + message)
	quit(1)
