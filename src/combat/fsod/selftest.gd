extends SceneTree
## SPDX-License-Identifier: AGPL-3.0-only
## Tests for the partial FSoD combat port, source revision
## 6fd20aad4a7905b13f25389c68368a942a2b68cb (see integration notes).
const Roster := preload("res://src/combat/fsod/roster.gd")
const Interpreter := preload("res://src/combat/fsod/interpreter.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FSoD: " + label)

func context(id: String, at := Vector2.ZERO, aim := Vector2(2, 0)) -> Dictionary:
	var data := Roster.get_enemy(id)
	return {"has_target": true, "dead": false, "position": at, "target": aim,
		"hp": float(data.max_hp), "max_hp": float(data.max_hp), "projectiles": data.projectiles}

func _initialize() -> void:
	var expected := {"Hobbit Mage": [200, 2, 32.0, 50, 10, 340],
		"Hobbit Archer": [22, 0, 2.2, 60, 8, 2000], "Hobbit Rogue": [26, 0, 2.6, 60, 13, 800],
		"Sumo Master": [340, 5, 56.1, 70, 15, 500], "Lil Sumo": [55, 4, 11.0, 50, 10, 3000]}
	check(Roster.IDS.size() == 5, "five concrete Lowland enemies")
	for id in Roster.IDS:
		var d := Roster.get_enemy(id)
		var e: Array = expected[id]
		check(d.max_hp == e[0] and d.defense == e[1] and is_equal_approx(d.xp_value, e[2]), id + " stats/XP baseline")
		check(d.projectiles[0].speed == e[3] and d.projectiles[0].min_damage == e[4] and d.projectiles[0].lifetime_ms == e[5], id + " projectile")
		var engine := Interpreter.new()
		engine.configure(d.tree, 42)
		for i in 20:
			engine.tick(20, context(id))
	check(Roster.get_enemy("Hobbit Archer").xp_mult == null, "missing XpMult stays explicit")
	check(Roster.get_enemy("not a source enemy").is_empty(), "unknown source id rejected")
	var ring := Roster.shoot(1, {"count": 15, "shoot_angle": 24.0, "fixed_angle": 8.0})
	var dirs := Interpreter.spread(ring, PI / 2)
	check(dirs.size() == 15, "source ring count")
	for i in 15:
		check(dirs[i].is_equal_approx(Vector2.from_angle(deg_to_rad(8 - 168 + 24 * i))), "fixed angle centered, 24 degrees per shot %d" % i)
	var fan := Interpreter.spread(Roster.shoot(10, {"count": 3, "shoot_angle": 14.0}), PI / 2)
	check(fan[0].is_equal_approx(Vector2.from_angle(PI / 2 - deg_to_rad(14))), "spread is adjacent spacing, not total fan width")
	check(Interpreter.spread(Roster.shoot(10, {"count": 4}), 0)[0].is_equal_approx(Vector2.from_angle(-3 * PI / 4)), "default spread 360/count")
	check(is_equal_approx(Interpreter.source_speed(0.75), 4.9025), "GetSpeed conversion")
	_test_shoot()
	_test_states()
	_test_determinism()
	print("FSoD selftest: %d failures (partial interpreter; no enemy adapter)" % failures)
	quit(0 if failures == 0 else 1)

func _test_shoot() -> void:
	var engine := Interpreter.new()
	engine.configure(Roster.state("root", [Roster.shoot(10)]))
	var c := context("Hobbit Archer")
	check(engine.tick(100, c).shots.size() == 1, "offset zero fires on first tick")
	for i in 10:
		check(engine.tick(100, c).shots.is_empty(), "cooldown checks before subtraction %d" % i)
	c.target = Vector2(0, 2)
	var shots: Array = engine.tick(100, c).shots
	check(shots.size() == 1 and shots[0].directions[0].is_equal_approx(Vector2.DOWN), "aim recomputed each volley")
	check(shots[0].speed_tiles == 6.0 and shots[0].damage == 8, "source projectile speed/10 and damage")
	engine.configure(Roster.state("root", [Roster.shoot(10, {"offset": 200})]))
	check(engine.tick(100, c).shots.is_empty() and engine.tick(100, c).shots.is_empty(), "coolDownOffset ms")
	check(engine.tick(100, c).shots.size() == 1, "offset fires next tick after zero")
	engine.configure(Roster.get_enemy("Hobbit Rogue").tree)
	c = context("Hobbit Rogue", Vector2.ZERO, Vector2(2, 0))
	var result := engine.tick(20, c)
	check(result.shots.size() == 1 and result.position != c.position, "shooting and following in SAME tick")
	var before: String = engine.current_state
	c.has_target = false
	result = engine.tick(10000, c)
	check(result.shots.is_empty() and result.position == c.position and engine.current_state == before, "null target freezes interpreter")
	c.has_target = true
	c.dead = true
	check(engine.tick(10000, c).shots.is_empty(), "dead context cannot tick")
	c.dead = false
	engine.reset()
	check(engine.tick(20, c).shots.size() == 1, "reset restores initial attack cooldown")

func _test_states() -> void:
	var engine := Interpreter.new()
	engine.configure(Roster.get_enemy("Hobbit Mage").tree)
	var c := context("Hobbit Mage")
	check(engine.current_state == "idle", "first deepest state selected")
	var result := engine.tick(100, c)
	check(engine.current_state == "ring1" and result.shots.is_empty(), "PlayerWithin transitions before OLD behaviors")
	result = engine.tick(100, c)
	check(result.shots.size() == 1 and result.shots[0].directions.size() == 15, "ring1 entry fires, fixedAngle ignores target radius")
	for i in 3:
		engine.tick(100, c)
	check(engine.current_state == "ring1", "400ms subtraction reaches zero without transition")
	engine.tick(100, c)
	check(engine.current_state == "ring2", "TimedTransition checks zero on following tick")
	result = engine.tick(100, c)
	check(result.shots.size() == 1 and result.shots[0].projectile == 1, "ring2 source projectile and state-entry cooldown")
	engine.reset()
	check(engine.current_state == "idle" and engine.storage.is_empty(), "reset clears behavior AND transition storage")
	engine.configure(Roster.get_enemy("Sumo Master").tree)
	c = context("Sumo Master")
	c.hp = 336.6
	engine.tick(20, c)
	check(engine.current_state == "sleeping1", "HpLess 0.99 is STRICT")
	c.hp = 336.0
	engine.tick(20, c)
	check(engine.current_state == "hurt", "HpLess damage wakes sumo")
	result = engine.tick(1000, c)
	check(result.events.filter(func(e: Dictionary) -> bool: return e.kind == "spawn").size() == 2, "hurt initialSpawn truncates 5*0.5 to 2")
	engine.tick(20, c)
	check(engine.current_state == "awake", "hurt timer to awake")
	c.hp = 170.0
	engine.tick(20, c)
	check(engine.current_state == "awake", "rage HP threshold strict")
	c.hp = 169.0
	engine.tick(20, c)
	check(engine.current_state == "shoot", "rage selects nested shoot")
	result = engine.tick(20, c)
	check(result.shots.size() == 1 and result.shots[0].projectile == 1, "nested rage shot source index")
	engine.configure(Roster.get_enemy("Hobbit Archer").tree)
	c = context("Hobbit Archer")
	for i in 5:
		engine.tick(100, c)
	check(engine.current_state == "run2", "archer run1 400ms source timer")
	for i in 7:
		engine.tick(100, c)
	check(engine.current_state == "run3", "archer run2 600ms source timer")
	for i in 5:
		engine.tick(100, c)
	check(engine.current_state == "run1", "archer run3 400ms source timer")

func _test_determinism() -> void:
	var a := Interpreter.new()
	var b := Interpreter.new()
	a.configure(Roster.get_enemy("Hobbit Rogue").tree, 99)
	b.configure(Roster.get_enemy("Hobbit Rogue").tree, 99)
	var ca := context("Hobbit Rogue")
	var cb := ca.duplicate(true)
	for i in 100:
		var ra := a.tick(20, ca)
		var rb := b.tick(20, cb)
		check(ra == rb, "seeded replay tick %d" % i)
		ca.position = ra.position
		cb.position = rb.position
