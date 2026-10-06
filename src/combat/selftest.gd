extends SceneTree
## GRAVEBAG combat selftest (design/game-brief.md bullet-hell slice).
##
## Exercises CombatPatterns math (ring count, spiral rotation, aimed spread
## symmetry), plus bullet flight/curve fields and enemy damage/died/reform,
## with asserts. Prints SELFTEST PASS and quits 0 on success, or
## SELFTEST FAIL lines and quits 1.
##
## Run headless:
##   Godot --headless --path . -s res://src/combat/selftest.gd

const Patterns := preload("res://src/combat/patterns.gd")
const Bullet := preload("res://src/combat/bullet.gd")
const Pool := preload("res://src/combat/bullet_pool.gd")
const Enemy := preload("res://src/combat/enemy.gd")

const EPS := 0.001

var _failures := 0


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
	_test_radial_ring()
	_test_spiral_arms()
	_test_aimed_burst()
	_test_bullet_flight()
	_test_pool_reuse()
	_test_enemy_cycle()
	_test_density_tuning()
	if _failures == 0:
		print("SELFTEST PASS")
	else:
		printerr("SELFTEST FAILURES: %d" % _failures)
	quit(_failures)


func _test_density_tuning() -> void:
	# Combat-density pass: every live enemy fires at least every ~2s with a
	# fair >= 0.4s telegraph, orbs are big and bright, the pool holds the
	# formation without drops, and the leash keeps foes on-screen.
	var foe: Enemy = Enemy.new()
	_check(foe.windup_time >= 0.4, "telegraph >= 0.4s stays dodgeable")
	_check(foe.windup_time + foe.cooldown_time <= 2.05, "fire cycle <= ~2s per enemy")
	_check(foe.bullet_radius >= 12.0, "enemy orbs big and bright")
	_check(foe.ring_count >= 12, "ring volleys stay dense")
	_check(foe.move_speed >= 120.0, "enemies keep up with the player")
	_check(foe.leash_range > foe.preferred_range, "leash holds formation on-screen")
	foe.free()
	var pool: Pool = Pool.new()
	_check(pool.pool_size >= 400, "pool holds the formation without drops")
	pool.free()


func _test_radial_ring() -> void:
	# Arrange + act: 8-ring, no offset.
	var dirs: PackedVector2Array = Patterns.radial_ring(Vector2.ZERO, 8, 0.0)
	# Assert: count, unit length, even spacing.
	_check(dirs.size() == 8, "ring returns 8 directions")
	for i in dirs.size():
		_check(absf(dirs[i].length() - 1.0) < EPS, "ring dir %d unit length" % i)
	for i in range(1, dirs.size()):
		var step: float = absf(wrapf(dirs[i].angle() - dirs[i - 1].angle(), -PI, PI))
		_check(absf(step - TAU / 8.0) < EPS, "ring even spacing at %d" % i)
	# Offset rotates the whole ring.
	var shifted: PackedVector2Array = Patterns.radial_ring(Vector2.ZERO, 8, PI / 8.0)
	_check(
		absf(angle_difference(dirs[0].angle(), shifted[0].angle()) - PI / 8.0) < EPS,
		"ring offset rotates directions"
	)
	# Edge: empty ring never crashes.
	_check(Patterns.radial_ring(Vector2.ZERO, 0).size() == 0, "ring count 0 is empty")
	_check(Patterns.radial_ring(Vector2.ZERO, -3).size() == 0, "ring negative is empty")


func _test_spiral_arms() -> void:
	# Arrange + act: 3 arms aimed +X, rotation 0 vs +0.5.
	var origin := Vector2.ZERO
	var aim := Vector2(100.0, 0.0)
	var a0: PackedVector2Array = Patterns.spiral_arms(origin, aim, 3, 0.0)
	var a1: PackedVector2Array = Patterns.spiral_arms(origin, aim, 3, 0.5)
	# Assert: arm count, unit length, every arm rotated by exactly 0.5.
	_check(a0.size() == 3 and a1.size() == 3, "spiral returns arm_count directions")
	_check(absf(a0[0].angle() - 0.0) < EPS, "spiral first arm on aim bearing")
	for i in 3:
		_check(absf(a0[i].length() - 1.0) < EPS, "spiral arm %d unit length" % i)
		var shift: float = angle_difference(a0[i].angle(), a1[i].angle())
		_check(absf(shift - 0.5) < EPS, "spiral rotation advances arm %d" % i)


func _test_aimed_burst() -> void:
	# Arrange + act: 5-wide burst over 0.6 rad aimed +X.
	var origin := Vector2.ZERO
	var aim := Vector2(100.0, 0.0)
	var dirs: PackedVector2Array = Patterns.aimed_burst(origin, aim, 5, 0.6)
	# Assert: count, center shot exact, mirror symmetry, inside the fan.
	_check(dirs.size() == 5, "burst returns count directions")
	_check(dirs[2].is_equal_approx(Vector2.RIGHT), "burst middle shot on aim")
	var signed_sum := 0.0
	for d in dirs:
		var a: float = Vector2.RIGHT.angle_to(d)
		signed_sum += a
		_check(absf(a) <= 0.3 + EPS, "burst shot inside spread")
	_check(absf(signed_sum) < EPS, "burst spread symmetric about aim")
	_check(absf(dirs[0].angle() + dirs[4].angle()) < EPS, "burst outer pair mirrors")
	_check(absf(dirs[1].angle() + dirs[3].angle()) < EPS, "burst inner pair mirrors")
	# Edge: single shot flies the aim bearing; degenerate aim falls back to +X.
	var solo: PackedVector2Array = Patterns.aimed_burst(origin, aim, 1, 0.6)
	_check(solo.size() == 1 and solo[0].is_equal_approx(Vector2.RIGHT), "burst count 1 aims")
	var same: PackedVector2Array = Patterns.aimed_burst(origin, origin, 3, 0.4)
	_check(same.size() == 3 and same[1].is_equal_approx(Vector2.RIGHT), "burst aim==origin falls back")


func _test_bullet_flight() -> void:
	# Arrange: live bullet flying +X.
	var b: Bullet = Bullet.new()
	root.add_child(b)
	b.fire(Vector2(100.0, 100.0), Vector2.RIGHT, 400.0, Bullet.Team.ENEMY, 8.0, 0.0, 10.0)
	# Act: half a second of flight.
	b._physics_process(0.5)
	# Assert: straight-line integration, fields stored.
	_check(b.active, "bullet active after fire")
	_check(b.position.is_equal_approx(Vector2(300.0, 100.0)), "bullet integrates velocity")
	_check(b.team == Bullet.Team.ENEMY and b.radius == 8.0 and b.curve == 0.0, "bullet fields stored")
	# Arrange: curving bullet. Act: half second at PI rad/sec.
	b.fire(Vector2.ZERO, Vector2.RIGHT, 400.0, Bullet.Team.ENEMY, 8.0, PI, 10.0)
	b._physics_process(0.5)
	# Assert: heading bent a quarter turn toward +Y (y-down clockwise).
	_check(absf(angle_difference(b.velocity.angle(), PI * 0.5)) < EPS, "bullet curve bends heading")
	b.deactivate()
	_check(not b.active and not b.visible, "bullet parks on deactivate")
	b.queue_free()


func _test_pool_reuse() -> void:
	# Arrange: tiny pool so exhaustion is reachable.
	var pool: Pool = Pool.new()
	pool.pool_size = 4
	root.add_child(pool)
	# Act: drain it, then one more.
	for i in 4:
		pool.spawn(Vector2.ZERO, Vector2.RIGHT)
	var overflow: Bullet = pool.spawn(Vector2.ZERO, Vector2.RIGHT)
	# Assert: fixed size, no growth, overflow counted.
	_check(pool.active_count() == 4, "pool serves pool_size bullets")
	_check(overflow == null and pool.dropped_shots == 1, "pool drops (never grows) when dry")
	# Act: park one, spawn again. Assert: same instance reused.
	var first: Bullet = pool._bullets[0]
	first.deactivate()
	var again: Bullet = pool.spawn(Vector2.ZERO, Vector2.RIGHT)
	_check(again == first, "pool reuses parked bullet")
	pool.clear_all()
	_check(pool.active_count() == 0, "pool clears")
	pool.queue_free()


func _test_enemy_cycle() -> void:
	# Arrange: enemy with instant timers aimed at a dummy target.
	var foe: Enemy = Enemy.new()
	foe.windup_time = 0.05
	foe.cooldown_time = 0.05
	foe.initial_delay = 0.01
	foe.max_hp = 30.0
	var mark := Node2D.new()
	mark.position = Vector2(300.0, 0.0)
	root.add_child(mark)
	root.add_child(foe)
	foe.global_position = Vector2.ZERO
	foe.target = mark
	var fired := {"count": 0, "dirs": PackedVector2Array()}
	foe.fire_requested.connect(
		func(...args: Array) -> void:
			fired.count += 1
			fired.dirs = args[1]
	)
	var ended := {"died": false}
	foe.died.connect(func(...args: Array) -> void: ended.died = true)
	# Act: walk IDLE -> WINDUP -> fire -> COOLDOWN.
	foe._physics_process(1.0)
	foe._physics_process(1.0)
	# Assert: exactly one volley, ring of ring_count directions.
	_check(fired.count == 1, "enemy fires one volley after windup")
	_check((fired.dirs as PackedVector2Array).size() == foe.ring_count, "enemy volley has ring_count shots")
	# Act: wound, then kill.
	foe.take_damage(10.0)
	_check(absf(foe.hp - 20.0) < EPS and not ended.died, "enemy survives chip damage")
	foe.take_damage(25.0)
	# Assert: died once, hidden, parked.
	_check(ended.died and foe.hp == 0.0, "enemy dies at 0 hp")
	_check(not foe.visible, "corpse hidden until reform")
	# Act: reform. Assert: full hp, visible, firing again.
	foe.reform()
	_check(absf(foe.hp - foe.max_hp) < EPS and foe.visible, "enemy reforms at full hp")
	foe._physics_process(1.0)
	foe._physics_process(1.0)
	_check(fired.count == 2, "reformed enemy fires again")
	mark.queue_free()
	foe.queue_free()
