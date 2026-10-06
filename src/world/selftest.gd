extends SceneTree
## GRAVEBAG world scaffold selftest (src/world only, no wiring).
## Run: godot --headless --path . -s res://src/world/selftest.gd
## Prints SELFTEST PASS and quits 0; on failure prints causes, quits 1.
## Covers: scaling table monotonicity + weights + depth math, realm clamp math.


func _initialize() -> void:
	var failures: Array[String] = []
	var Scaling = load("res://src/world/scaling.gd")
	var Realm = load("res://src/world/realm.gd")
	if Scaling == null:
		failures.append("scaling.gd did not load")
	if Realm == null:
		failures.append("realm.gd did not load")
	if not failures.is_empty():
		_report(failures)
		return
	_check_depth(Scaling, failures)
	_check_monotonic(Scaling, failures)
	_check_weights(Scaling, failures)
	_check_clamp(Realm, failures)
	_report(failures)


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print("SELFTEST PASS")
		quit(0)
	else:
		for f in failures:
			printerr("SELFTEST FAIL: ", f)
		quit(1)


func _check_depth(Scaling, failures: Array[String]) -> void:
	if not is_equal_approx(float(Scaling.depth_from_y(2048.0)), 0.0):
		failures.append("depth_from_y(2048) != 0.0 (south)")
	if not is_equal_approx(float(Scaling.depth_from_y(0.0)), 1.0):
		failures.append("depth_from_y(0) != 1.0 (north)")
	if not is_equal_approx(float(Scaling.depth_from_y(1024.0)), 0.5):
		failures.append("depth_from_y(1024) != 0.5 (middle)")
	if not is_equal_approx(float(Scaling.depth_from_y(5000.0)), 0.0):
		failures.append("depth_from_y past south not clamped to 0.0")
	if not is_equal_approx(float(Scaling.depth_from_y(-500.0)), 1.0):
		failures.append("depth_from_y past north not clamped to 1.0")


func _check_monotonic(Scaling, failures: Array[String]) -> void:
	var prev_diff := -1.0
	var prev_hp := -1.0
	var prev_dmg := -1.0
	var prev_band := -1
	for i in 11:
		var d := float(i) / 10.0
		var diff := float(Scaling.difficulty_for_depth(d))
		var stats: Dictionary = Scaling.stats_for_depth(d)
		var hp := float(stats["hp_mult"])
		var dmg := float(stats["dmg_mult"])
		var band := int(Scaling.band_index_for_depth(d))
		if diff < prev_diff:
			failures.append("difficulty fell at depth %f" % d)
		if hp < prev_hp:
			failures.append("hp_mult fell at depth %f" % d)
		if dmg < prev_dmg:
			failures.append("dmg_mult fell at depth %f" % d)
		if band < prev_band:
			failures.append("band index fell at depth %f" % d)
		prev_diff = diff
		prev_hp = hp
		prev_dmg = dmg
		prev_band = band
	if not float(Scaling.difficulty_for_depth(1.0)) > float(Scaling.difficulty_for_depth(0.0)):
		failures.append("difficulty(1.0) not above difficulty(0.0)")


func _check_weights(Scaling, failures: Array[String]) -> void:
	for i in 11:
		var d := float(i) / 10.0
		var weights: Dictionary = Scaling.spawn_weights_for_depth(d)
		var total := 0.0
		for key in weights:
			var w := float(weights[key])
			if w < 0.0:
				failures.append("negative weight at depth %f" % d)
			total += w
		if not is_equal_approx(total, 1.0):
			failures.append("weights sum %f != 1.0 at depth %f" % [total, d])


func _check_clamp(Realm, failures: Array[String]) -> void:
	if Realm.clamp_to_bounds(Vector2(-50.0, -50.0)) != Vector2.ZERO:
		failures.append("clamp(-50,-50) != (0,0)")
	if Realm.clamp_to_bounds(Vector2(5000.0, 5000.0)) != Vector2(2048.0, 2048.0):
		failures.append("clamp(5000,5000) != (2048,2048)")
	if Realm.clamp_to_bounds(Vector2(100.0, 200.0)) != Vector2(100.0, 200.0):
		failures.append("clamp changed an inside point (100,200)")
	if Realm.clamp_to_bounds(Vector2(2048.0, 0.0)) != Vector2(2048.0, 0.0):
		failures.append("clamp changed a boundary point (2048,0)")
