extends SceneTree
const Probe := preload("res://src/game/fsod_live_probe.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var checks := 0
	assert(Probe.navigation_keys(Vector2(0.19, 0)).has(KEY_D), "0.19-tile remainder must not idle outside 0.18 arrival radius")
	checks += 1
	for radius in [0.181, 0.19, 0.2, 0.25, 1.0]:
		for step in range(360):
			var offset := Vector2.from_angle(float(step) * TAU / 360.0) * float(radius)
			assert(not Probe.navigation_keys(offset).is_empty(), "non-arrived waypoint has at least one movement key")
			checks += 1
	assert(Probe.navigation_keys(Vector2.ZERO).is_empty(), "arrived bot releases keys")
	checks += 1
	print("FSOD PROBE NAVIGATION PASS: %d checks" % checks)
	quit(0)
