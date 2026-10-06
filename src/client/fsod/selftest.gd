# SPDX-License-Identifier: AGPL-3.0-only
# Tests original GRAVEBAG frontend against FSoD 6fd20aa plain dictionary semantics.
extends SceneTree
const World = preload("res://src/client/fsod/world_view.gd")
var failures: int = 0
var checks: int = 0
var moves: Array = []
var shots: Array = []
var hits: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_descriptors({"objects": {100: {"kind": "player", "name": "Player"}, 200: {"kind": "enemy", "projectiles": [{"id": 0, "speed": 150, "lifetime_ms": 600}]}, 300: {"name": "Source weapon"}}, "tiles": {1: {"color": "#354c40"}}})
	world.set_player_id(10)
	world.apply_map({"width": 20, "height": 20, "name": "Fixture"})
	_check(world.entities.is_empty() and world.projectiles.is_empty(), "map clears old state")
	_check(world._summary.text.contains("HP  — / —"), "missing authority never fabricated")
	world.apply_update({"tiles": [{"x": 1, "y": 2, "tile": 1}, {"x": -1, "y": 0, "tile": 1}], "new_objects": [
		{"object_type": 100, "stats": {"id": 10, "position": {"x": 2.0, "y": 3.0}, "stats": {0: 100, 1: 80, 3: 50, 4: 40, 7: 5, 8: 300, 9: -1}}},
		{"object_type": 200, "stats": {"id": 20, "position": {"x": 4.0, "y": 3.0}, "stats": {}}},
	]})
	_check(world.entities.size() == 2 and world.tiles.size() == 1, "update objects and sparse bounded tiles")
	_check(world.entities[10].position == Vector2(64, 96), "32 pixels per source tile")
	_check(world.entities[10].is_local_player, "player identity set before spawn")
	_check(world._summary.text.contains("HP  80 / 100") and world._summary.text.contains("Level  5"), "authoritative rail")
	_check(world._inventory.text.contains("Source weapon") and world._inventory.text.contains("empty"), "source inventory descriptor names")
	world.apply_tick({"tick_time": 200, "update_statuses": [
		{"id": 10, "position": {"x": 2.5, "y": 3.0}, "stats": {"1": 70}},
		{"id": 20, "position": {"x": 6.0, "y": 3.0}, "stats": [{"type": 1, "value": 23}]},
		{"id": 999, "position": {"x": 1, "y": 1}, "stats": {}},
	]})
	_check(world.entities[10].stats[0] == 100 and world.entities[10].stats[1] == 70, "stat delta merges string wire keys")
	_check(not world.entities.has(999), "unknown tick cannot invent type")
	world.entities[10].apply_status({"stats": [{"type": "not-a-wire-id", "value": 999}, {"type": -1, "value": 999}], "position": {"x": 1e38, "y": 0}})
	_check(world.entities[10].stats[0] == 100 and world.entities[10].authoritative_position == Vector2(2.5, 3), "invalid wire IDs and overflow coordinates do not fabricate authority")
	world.advance_visuals(0.1)
	_check(world.entities[20].position == Vector2(160, 96), "halfway authoritative interpolation")
	_check(world.entities[20].stats[1] == 23, "list stats supported")
	world.advance_visuals(0.1)
	_check(world.entities[20].position == Vector2(192, 96), "interpolation endpoint")
	_check(world.entities[20].animation_frame == 1, "actual alternate movement frame")
	_check(world.entities[20].ENEMY_FRAMES[0] != world.entities[20].ENEMY_FRAMES[1], "two distinct enemy pixel frames")
	_check(world.entities[10].PLAYER_FRAMES[0] != world.entities[10].PLAYER_FRAMES[1], "two distinct player pixel frames")
	world.entities[10].aim_angle = 0.317
	world.prediction_speed_tiles = 4.0 # Explicit fixture injection, not runtime default.
	world.clock_ms = func(): return 1234
	world.move_requested.connect(func(pos: Dictionary, records: Array): moves.append({"pos": pos, "records": records}))
	world.shoot_requested.connect(func(angle: float): shots.append(angle))
	world.predict_motion(Vector2(1, 1), 0.1)
	_check(moves.size() == 1 and moves[0]["records"][0]["time"] == 1234, "outbound move records supplied clock")
	_check(is_equal_approx(world._prediction.distance_to(Vector2(2.5, 3)), 0.4), "normalized independent prediction")
	_check(world.entities[10].authoritative_position == Vector2(2.5, 3), "prediction never overwrites server position")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	world._unhandled_input(click)
	_check(shots.size() == 1 and is_equal_approx(shots[0], 0.317), "unsnapped source-radian shot request")
	world.predict_motion(Vector2.RIGHT, 0.1)
	_check(moves.size() == 2, "movement continues while firing held")
	world.apply_projectile({"owner_id": 20, "bullet_id": 1, "angle": 0, "position": {"x": 6, "y": 3}})
	_check(world.projectiles.size() == 1, "visible source descriptor projectile")
	world.advance_visuals(0.2)
	_check(world.projectile_position(world.projectiles["20:1"]) == Vector2(9, 3), "XML speed / 10 tiles per second")
	world.apply_projectile({"owner_id": 20, "bullet_id": 1, "angle": 0, "position": {"x": 6, "y": 3}, "num_shots": 2, "angle_inc": 0.5})
	_check(world.projectiles.size() == 2, "repeat bullet replaces, multishot visible")
	world.advance_visuals(0.7)
	_check(world.projectiles.is_empty(), "source lifetime removes visuals only")
	world.apply_projectile({"owner_id": 999, "bullet_id": 1, "angle": 0, "position": {"x": 1, "y": 1}})
	_check(world.projectiles.is_empty(), "missing descriptors do not invent projectile lifetime")
	world.projectile_hit_requested.connect(func(owner: int, bullet: int, target: int, kind: String): hits.append([owner, bullet, target, kind]))
	world.apply_projectile({"owner_id": 10, "bullet_id": 5, "position": {"x": 2.5, "y": 3}, "angle": 0, "speed": 150, "lifetime_ms": 600})
	world.advance_visuals(0.25)
	_check(hits.is_empty(), "missing source geometry never invents hit radius")
	world.projectiles.clear()
	var geometry: Dictionary = world.descriptors.duplicate(true)
	geometry["objects"][200]["hit_radius_tiles"] = 0.2 # Synthetic geometry only for this test.
	geometry["objects"][200]["projectiles"] = [{"BulletType": 7, "Speed": 100, "LifetimeMS": 1000, "Boomerang": true}, {"BulletType": 2, "Speed": 180, "LifetimeMS": 475, "Amplitude": 0.5, "Frequency": 2}]
	world.set_descriptors(geometry)
	world.apply_projectile({"owner_id": 10, "bullet_id": 5, "position": {"x": 2.5, "y": 3}, "angle": 0, "speed": 150, "lifetime_ms": 600})
	world.advance_visuals(0.25)
	_check(hits == [[10, 5, 20, "enemy"]], "swept hit request only with explicit injected geometry")
	_check(world.entities[20].stats[1] == 23, "hit request never applies damage")
	world.advance_visuals(0.01)
	_check(hits.size() == 1, "hit requests deduped per bullet target")
	world.projectiles.clear()
	world.apply_projectile({"owner_id": 20, "bullet_id": 6, "bullet_type": 2, "position": {"x": 6, "y": 3}, "angle": 0})
	var curved: Dictionary = world.projectiles["20:6"]
	_check(curved["speed"] == 18.0 and is_equal_approx(curved["lifetime"], 0.475), "source BulletType resolved not array index")
	curved["age"] = 0.11875
	_check(world.projectile_position(curved).is_equal_approx(Vector2(8.1375, 3)), "source amplitude sinusoid phase endpoint")
	curved["age"] = 0.059375
	_check(world.projectile_position(curved).is_equal_approx(Vector2(7.06875, 3.5)), "source amplitude sinusoid midpoint")
	world.apply_projectile({"owner_id": 20, "bullet_id": 7, "bullet_type": 7, "position": {"x": 6, "y": 3}, "angle": 0})
	var returning: Dictionary = world.projectiles["20:7"]
	returning["age"] = 0.75
	_check(world.projectile_position(returning).is_equal_approx(Vector2(8.5, 3)), "source boomerang returns after half lifetime")
	returning["descriptor"] = {"parametric": true, "magnitude": 3.0}
	returning["age"] = 0.25
	_check(world.projectile_position(returning).is_equal_approx(Vector2(9, 3)), "source parametric parity signs and magnitude")
	returning["descriptor"] = {"wavy": true}
	returning["age"] = 0.25
	_check(world.projectile_position(returning).is_equal_approx(Vector2(8.5, 3)), "source wavy integer elapsed seconds behavior")
	world.entities[20].free()
	world.apply_tick({"update_statuses": [{"id": 20, "position": {"x": 1, "y": 1}}]})
	_check(not world.entities.has(20), "externally freed entity safe")
	world.apply_update({"new_objects": [{"object_type": 200, "stats": {"id": 20, "position": {"x": 4, "y": 4}, "stats": {}}}]})
	world.entities[20].queue_free()
	world.apply_update({"new_objects": [{"object_type": 200, "stats": {"id": 20, "position": {"x": 5, "y": 5}, "stats": {}}}]})
	_check(is_instance_valid(world.entities[20]) and not world.entities[20].is_queued_for_deletion(), "queued entity replacement safe")
	world.apply_update({"removed_object_ids": [20, 20]})
	_check(not world.entities.has(20), "idempotent removal")
	world.entities[10].queue_free()
	world.advance_visuals(0.1)
	world.predict_motion(Vector2.RIGHT, 0.1)
	_check(not world.entities.has(10), "freed player input safe")
	world.apply_map({"width": NAN, "height": -3})
	world.apply_update({"tiles": "bad", "new_objects": [null, {}], "removed_object_ids": null})
	world.apply_tick({"tick_time": INF, "update_statuses": null})
	world.apply_projectile({"position": {"x": NAN, "y": 0}})
	_check(world.entities.is_empty() and world.tiles.is_empty(), "malformed input finite/bounded")
	world.free()
	await process_frame
	print("FSOD FRONTEND PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD FRONTEND FAIL: " + description)
	assert(condition, description)
