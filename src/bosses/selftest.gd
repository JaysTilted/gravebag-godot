extends SceneTree
## Warden selftest: phase thresholds + pattern direction counts.
##
## Headless check for the WARDEN OF THE GATE (no arena, no player, no UI):
##   godot --headless --path . -s res://src/bosses/selftest.gd
## Prints SELFTEST PASS and quits 0 on success, SELFTEST FAIL + quit 1 after
## listing the failed expectation.


func _initialize() -> void:
	var failures: Array[String] = []
	_check_thresholds(failures)
	_check_patterns(failures)
	_check_sprites(failures)
	_check_minions(failures)
	if failures.is_empty():
		print("SELFTEST PASS")
		quit(0)
	else:
		for f in failures:
			printerr("SELFTEST FAIL: ", f)
		printerr("SELFTEST FAIL")
		quit(1)


func _check_thresholds(failures: Array[String]) -> void:
	var Warden := load("res://src/bosses/warden.gd")
	var w = Warden.new()
	w.max_hp = 300.0
	w.hp = 300.0
	w.phase = 1
	w.invuln_left = 0.0
	w.taunt_left = 0.0
	if w.phase_for_hp(300.0) != 1:
		failures.append("full hp is not phase 1")
	w.take_damage(105.0) # 195 left, 65%: crosses the 66% line.
	if w.phase != 2:
		failures.append("66% crossing did not enter phase 2")
	if w.invuln_left <= 0.0:
		failures.append("phase transition granted no invulnerability")
	var held: float = w.hp
	w.take_damage(10.0)
	if w.hp != held:
		failures.append("damage leaked through transition invulnerability")
	w.invuln_left = 0.0
	w.taunt_left = 0.0
	w.take_damage(100.0) # 95 left, ~32%: crosses the 33% line.
	if w.phase != 3:
		failures.append("33% crossing did not enter phase 3 (enrage)")
	w.invuln_left = 0.0
	w.taunt_left = 0.0
	var box := {"grade": -1}
	w.died.connect(func(...args): box["grade"] = args[0])
	w.take_damage(1000.0)
	if w.phase != 0:
		failures.append("lethal damage did not kill the warden")
	if not (box["grade"] is int) or int(box["grade"]) < 2:
		failures.append("died signal carried no loot-grade int")
	w.take_damage(50.0)
	if w.hp != 0.0:
		failures.append("dead warden still takes damage")
	for m in w.adds:
		(m as Node).free()
	w.free()


func _check_patterns(failures: Array[String]) -> void:
	var Patterns := load("res://src/bosses/boss_patterns.gd")
	var ring: Array = Patterns.radial(12)
	if ring.size() != 12:
		failures.append("radial(12) returned %d directions" % ring.size())
	for d in ring:
		if absf((d as Vector2).length() - 1.0) > 0.001:
			failures.append("radial direction not normalized")
			break
	if not Patterns.radial(0).is_empty():
		failures.append("radial(0) was not empty")
	var arms2: Array = Patterns.spiral(0, 2)
	var arms3: Array = Patterns.spiral(7, 3)
	if arms2.size() != 2 or arms3.size() != 3:
		failures.append("spiral arm counts wrong")
	var fan: Array = Patterns.aimed(Vector2.ZERO, Vector2(100, 0), 3, 0.18)
	if fan.size() != 3:
		failures.append("aimed burst returned %d directions" % fan.size())
	else:
		var mid: Vector2 = fan[1]
		if mid.dot(Vector2.RIGHT) < 0.999:
			failures.append("aimed burst center misses the target")
	if not Patterns.aimed(Vector2.ZERO, Vector2.ZERO, 0).is_empty():
		failures.append("aimed(0) was not empty")


func _check_sprites(failures: Array[String]) -> void:
	var Warden := load("res://src/bosses/warden.gd")
	var tex = Warden.make_brute_texture()
	if tex == null:
		failures.append("brute sprite texture is null")
	elif tex.get_size() != Vector2(32, 32):
		failures.append("brute sprite is not 32x32")
	var Minion := load("res://src/bosses/warden_minion.gd")
	var stub = Minion.make_stub_texture()
	if stub == null:
		failures.append("minion sprite texture is null")
	elif stub.get_size() != Vector2(16, 16):
		failures.append("minion sprite is not 16x16")


func _check_minions(failures: Array[String]) -> void:
	var Warden := load("res://src/bosses/warden.gd")
	var w = Warden.new()
	w.max_hp = 300.0
	w.hp = 300.0
	w.phase = 1
	var first: Array = w.spawn_minions()
	if first.size() != 2:
		failures.append("phase-2 spawn produced %d minions, want 2" % first.size())
	var second: Array = w.spawn_minions()
	if not second.is_empty():
		failures.append("minion spawn was not idempotent")
	for m in w.adds:
		(m as Node).free()
	w.free()
