extends SceneTree
## GRAVEBAG wave3 foe-variety selftest (dasher / sniper / splitter).
##
## Exercises CombatPatterns helpers (charge_vector, aimed_fan, pick_variant
## weights + distribution), variant stat sanity (telegraph >= 0.4s, fire
## cycle <= ~2s, distinct sprites), dasher lunge + contact damage without
## firing, sniper single fast thin bolt, and splitter death spawning exactly
## 2 live minis. Prints SELFTEST PASS and quits 0 on success, or SELFTEST
## FAIL lines and quits 1.
##
## Run headless:
##   Godot --headless --path . -s res://src/combat/variants/selftest.gd

const Patterns := preload("res://src/combat/patterns.gd")
const Dasher := preload("res://src/combat/variants/dasher.gd")
const Sniper := preload("res://src/combat/variants/sniper.gd")
const Splitter := preload("res://src/combat/variants/splitter.gd")
const Mini := preload("res://src/combat/variants/splitter_mini.gd")

const EPS := 0.001

var _failures := 0


## Minimal victim: GravebagPlayer.damage() stand-in for contact hits.
class StubDiver extends Node2D:
	var hp := 100.0

	func damage(amount: float) -> void:
		hp = maxf(0.0, hp - amount)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("SELFTEST FAIL: ", msg)
	assert(cond, msg)


var _ran := false


## Tests run on the first frame (not _initialize): nodes added during init
## are not inside the tree yet, so _ready and the physics space are missing.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_all()
	return false


func _run_all() -> void:
	_test_charge_vector()
	_test_aimed_fan()
	_test_pick_variant()
	_test_variant_stats()
	_test_dasher_lunge()
	_test_sniper_bolt()
	_test_splitter_split()
	if _failures == 0:
		print("SELFTEST PASS")
	else:
		printerr("SELFTEST FAILURES: %d" % _failures)
	quit(_failures)


func _test_charge_vector() -> void:
	# Arrange + act: +X charge and a diagonal one.
	var straight: Vector2 = Patterns.charge_vector(Vector2.ZERO, Vector2(100, 0))
	var diag: Vector2 = Patterns.charge_vector(Vector2.ZERO, Vector2(30, 40))
	# Assert: unit length, exact bearing.
	_check(straight.is_equal_approx(Vector2.RIGHT), "charge +X bearing")
	_check(absf(diag.length() - 1.0) < EPS, "charge diagonal unit length")
	_check(diag.is_equal_approx(Vector2(0.6, 0.8)), "charge diagonal bearing")
	# Edge: degenerate aim falls back to +X, never NaN.
	var same: Vector2 = Patterns.charge_vector(Vector2(5, 5), Vector2(5, 5))
	_check(same.is_equal_approx(Vector2.RIGHT), "charge aim==origin falls back")


func _test_aimed_fan() -> void:
	# Arrange + act: 5-wide fan over 0.6 rad aimed +X.
	var origin := Vector2.ZERO
	var aim := Vector2(100.0, 0.0)
	var dirs: PackedVector2Array = Patterns.aimed_fan(origin, aim, 5, 0.6)
	# Assert: count, unit length, center on aim, mirror symmetry.
	_check(dirs.size() == 5, "fan returns count directions")
	_check(dirs[2].is_equal_approx(Vector2.RIGHT), "fan middle shot on aim")
	var signed_sum := 0.0
	for d in dirs:
		_check(absf(d.length() - 1.0) < EPS, "fan direction unit length")
		signed_sum += Vector2.RIGHT.angle_to(d)
	_check(absf(signed_sum) < EPS, "fan spread symmetric about aim")
	# Edge: single shot flies the aim bearing; degenerate aim falls back.
	var solo: PackedVector2Array = Patterns.aimed_fan(origin, aim, 1, 0.6)
	_check(solo.size() == 1 and solo[0].is_equal_approx(Vector2.RIGHT), "fan count 1 aims")
	var same: PackedVector2Array = Patterns.aimed_fan(origin, origin, 3, 0.4)
	_check(same.size() == 3 and same[1].is_equal_approx(Vector2.RIGHT), "fan aim==origin falls back")


func _test_pick_variant() -> void:
	# Arrange: bands 0 (shallow) through 2 (deep).
	for band in [0, 1, 2]:
		var w: Dictionary = Patterns.variant_weights(band)
		var total := 0.0
		for key in ["dasher", "sniper", "splitter"]:
			var v := float(w.get(key, 0.0))
			_check(v > 0.0, "band %d weights %s above zero" % [band, key])
			total += v
		_check(absf(total - 1.0) < EPS, "band %d weights sum to 1" % band)
	# Act: 300 seeded rolls per band. Assert: every band covers all three.
	for band in [0, 1, 2]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + band
		var seen := {}
		for i in 300:
			seen[Patterns.pick_variant(band, rng)] = true
		_check(seen.has(&"dasher"), "band %d rolls dashers" % band)
		_check(seen.has(&"sniper"), "band %d rolls snipers" % band)
		_check(seen.has(&"splitter"), "band %d rolls splitters" % band)
	# Pure: same seed replays the same sequence; negative bands stay valid.
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var b := RandomNumberGenerator.new()
	b.seed = 42
	var replay := true
	for i in 20:
		if Patterns.pick_variant(1, a) != Patterns.pick_variant(1, b):
			replay = false
	_check(replay, "pick_variant replays on same seed")
	var edge_rng := RandomNumberGenerator.new()
	edge_rng.seed = 7
	var edge: StringName = Patterns.pick_variant(-5, edge_rng)
	_check(edge == &"dasher" or edge == &"sniper" or edge == &"splitter", "negative band stays valid")


func _stat_foe(script: Script) -> CharacterBody2D:
	var foe := script.new() as CharacterBody2D
	root.add_child(foe)
	return foe


func _test_variant_stats() -> void:
	# Arrange: one fresh foe of each kind (defaults, unmodified).
	var d := _stat_foe(Dasher)
	var n := _stat_foe(Sniper)
	var s := _stat_foe(Splitter)
	var m := _stat_foe(Mini)
	# Assert: Enemy contract fields sane on every variant.
	for foe in [d, n, s, m]:
		_check(float(foe.get("max_hp")) > 0.0, "variant max_hp positive")
		_check(float(foe.get("move_speed")) > 0.0, "variant move_speed positive")
		_check(float(foe.get("windup_time")) >= 0.4, "variant telegraph >= 0.4s")
		_check(float(foe.get("windup_time")) + float(foe.get("cooldown_time")) <= 2.05, "variant fire cycle <= ~2s")
		_check(foe.has_signal("died"), "variant keeps died signal")
	# Assert: roles read in the numbers (fast lunger / slow tank / weak mini).
	_check(float(d.get("move_speed")) > float(s.get("move_speed")), "dasher outruns splitter")
	_check(float(s.get("max_hp")) > float(d.get("max_hp")), "splitter out-tanks dasher")
	_check(float(s.get("move_speed")) <= 90.0, "splitter slow")
	_check(float(n.get("windup_time")) >= 0.8, "sniper long windup")
	_check(float(n.get("bullet_speed")) >= 450.0, "sniper fast bolt")
	_check(float(n.get("bullet_radius")) <= 8.0, "sniper thin bolt")
	_check(float(d.get("contact_damage")) > 0.0, "dasher contact hits")
	_check(int(s.get("mini_count")) == 2, "splitter splits in two")
	_check(float(m.get("max_hp")) <= 15.0, "minis fragile")
	# Assert: code-drawn sprites exist and differ (silhouette + color).
	var td: Texture2D = Dasher.make_texture()
	var tn: Texture2D = Sniper.make_texture()
	var ts: Texture2D = Splitter.make_texture()
	var tm: Texture2D = Mini.make_texture()
	for t in [td, tn, ts, tm]:
		_check(t != null and t.get_size().x > 0.0, "variant sprite generated")
	var centers: Array = []
	for t in [td, tn, ts, tm]:
		centers.append((t as ImageTexture).get_image().get_pixel(int(t.get_size().x / 2), int(t.get_size().y / 2)))
	for i in centers.size():
		_check((centers[i] as Color).a > 0.0, "variant sprite %d opaque center" % i)
		for j in range(i + 1, centers.size()):
			_check(not (centers[i] as Color).is_equal_approx(centers[j] as Color), "sprites %d/%d differ" % [i, j])
	for foe in [d, n, s, m]:
		foe.queue_free()


func _test_dasher_lunge() -> void:
	# Arrange: dasher aimed at a stub diver, fast timers, volley counting.
	var diver := StubDiver.new()
	diver.position = Vector2(300.0, 0.0)
	root.add_child(diver)
	var d := Dasher.new()
	d.initial_delay = 0.01
	root.add_child(d)
	d.global_position = Vector2.ZERO
	d.target = diver
	var fired := {"count": 0}
	d.fire_requested.connect(func(...args: Array) -> void: fired.count += 1)
	var lunges := {"count": 0}
	(d as Dasher).lunged.connect(func(...args: Array) -> void: lunges.count += 1)
	# Act: walk IDLE -> WINDUP -> lunge trigger.
	d._physics_process(1.0)
	d._physics_process(1.0)
	# Assert: telegraphed, lunged, never shot.
	_check(lunges.count == 1, "dasher lunges after telegraph")
	_check(fired.count == 0, "dasher never fires bullets")
	_check((d as Dasher).is_dashing(), "dasher carrying after trigger")
	# Act: park the diver on the lunge lane, carry one frame.
	diver.global_position = d.global_position + Vector2(30.0, 0.0)
	d._physics_process(0.016)
	# Assert: exactly one contact hit, then no more per lunge.
	_check(diver.hp < 100.0, "dasher contact damages")
	var after_first: float = diver.hp
	d._physics_process(0.016)
	_check(absf(diver.hp - after_first) < EPS, "one hit per lunge")
	diver.queue_free()
	d.queue_free()


func _test_sniper_bolt() -> void:
	# Arrange: sniper aimed at a stub diver, fast timers, volley capture.
	var diver := StubDiver.new()
	diver.position = Vector2(400.0, 0.0)
	root.add_child(diver)
	var n := Sniper.new()
	n.initial_delay = 0.01
	n.windup_time = 0.05
	root.add_child(n)
	n.global_position = Vector2.ZERO
	n.target = diver
	var got := {"count": 0, "dirs": PackedVector2Array(), "speed": 0.0}
	n.fire_requested.connect(
		func(...args: Array) -> void:
			got.count += 1
			got.dirs = args[1]
			got.speed = args[2]
	)
	# Act: walk IDLE -> WINDUP -> volley.
	n._physics_process(1.0)
	n._physics_process(1.0)
	# Assert: exactly one thin bolt on the aim bearing, fast.
	_check(got.count == 1, "sniper fires one volley after windup")
	var dirs := got.dirs as PackedVector2Array
	_check(dirs.size() == 1, "sniper volley is a single bolt")
	_check(absf(dirs[0].length() - 1.0) < EPS, "sniper bolt unit length")
	_check(absf(dirs[0].angle()) < 0.05, "sniper bolt aimed at diver")
	_check(float(got.speed) >= 450.0, "sniper bolt fast")
	diver.queue_free()
	n.queue_free()


func _test_splitter_split() -> void:
	# Arrange: splitter parented to a holder, death watched.
	var holder := Node2D.new()
	root.add_child(holder)
	var s := Splitter.new()
	holder.add_child(s)
	s.global_position = Vector2(100.0, 100.0)
	var diver := StubDiver.new()
	diver.position = Vector2(500.0, 0.0)
	root.add_child(diver)
	s.target = diver
	var ended := {"died": false}
	s.died.connect(func(...args: Array) -> void: ended.died = true)
	var splits := {"minis": []}
	(s as Splitter).split_spawned.connect(func(minis: Array) -> void: splits.minis = minis)
	# Act: lethal hit.
	s.take_damage(9999.0)
	# Assert: died once, exactly 2 live minis beside the corpse, wired target.
	_check(ended.died, "splitter dies at 0 hp")
	_check((s as Splitter).spawned_minis.size() == 2, "splitter records 2 minis")
	_check((splits.minis as Array).size() == 2, "splitter emits 2 minis")
	var minis: Array = []
	for c in holder.get_children():
		if c.get_script() == Mini:
			minis.append(c)
	_check(minis.size() == 2, "2 minis join the tree")
	for mini in minis:
		_check(float((mini as Node).get("hp")) > 0.0, "mini spawns alive")
		_check((mini as Node2D).visible, "mini spawns visible")
		_check((mini as Node).get("target") == diver, "mini inherits target")
	# Act: a mini telegraphs and fires its ring.
	var mini0 := minis[0] as CharacterBody2D
	mini0.set("initial_delay", 0.01)
	mini0.set("windup_time", 0.05)
	var shots := {"count": 0, "dirs": PackedVector2Array()}
	(mini0 as Mini).fire_requested.connect(
		func(...args: Array) -> void:
			shots.count += 1
			shots.dirs = args[1]
	)
	mini0._physics_process(1.0)
	mini0._physics_process(1.0)
	_check(shots.count == 1, "mini fires after windup")
	_check((shots.dirs as PackedVector2Array).size() == 6, "mini volley is a 6-ring")
	diver.queue_free()
	holder.queue_free()
