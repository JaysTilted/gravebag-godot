# SPDX-License-Identifier: AGPL-3.0-only
# Display-only camera/world smoothing checks for the original-FSoD Godot client.
# Deterministic dictionary fixture ONLY, not a live server/game. Verifies the
# smoothed follow in src/client/fsod/world_view.gd: render-rate easing, hard
# snap on map/teleport/discontinuity, displayed-transform mouse mapping, and
# that authoritative state, requests, collision, and trajectories are untouched.
# Advance/hit/predict/MOVE cadence stays in _physics_process by design (hit
# sampling reads semantic Node positions). Must not edit entity_view.gd,
# project.godot, selftest.gd, session, or entry. Run headless for logic; under
# xvfb with --capture-dir=<dir> it also captures two real rendered frames.
extends SceneTree

const World = preload("res://src/client/fsod/world_view.gd")

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var capture_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	var world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.set_descriptors({"objects": {100: {"kind": "player", "name": "Player"}, 200: {"kind": "enemy"}}, "tiles": {1: {"color": "#354c40"}}})
	world.set_player_id(10)
	world.apply_map({"width": 40, "height": 30, "name": "Camera fixture"})
	world.apply_update({"tiles": [{"x": 4, "y": 5, "tile": 1}], "new_objects": [
		{"object_type": 100, "stats": {"id": 10, "position": {"x": 4.0, "y": 5.0}, "stats": {0: 100, 1: 80}}},
		{"object_type": 200, "stats": {"id": 20, "position": {"x": 8.0, "y": 5.0}, "stats": {}}},
	]})
	var player: Variant = world.entities[10]
	var viewport_size: Vector2 = world.get_viewport_rect().size
	_check(viewport_size.x > 0.0 and viewport_size.y > 0.0, "viewport size available")
	# 1. Desired framing math centers the player with the authoritative rail offset.
	var expected_target: Vector2 = Vector2(maxf(0.0, viewport_size.x - 256.0) / 2.0, viewport_size.y / 2.0) - Vector2(128, 160)
	_check(world.desired_camera_position(Vector2(128, 160), viewport_size).is_equal_approx(expected_target), "desired camera centers player with rail offset")
	# 2. First presentation hard-snaps (spawn discontinuity), no slew from origin.
	world.advance_camera_display(1.0 / 60.0)
	_check(world._camera_ready, "first camera presentation snaps ready")
	_check(world._world.position.is_equal_approx(expected_target), "spawn snaps display to target")
	# 3. Small authoritative step does NOT snap: display eases toward the target.
	var tick_target: Vector2 = world.desired_camera_position(Vector2(144, 160), viewport_size)
	world.apply_tick({"tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": 4.5, "y": 5.0}, "stats": {}}]})
	_check(not world._camera_hold_auth, "sub-teleport step keeps smooth follow")
	# Physics cadence first: the local render pose reconciles via prediction, then
	# the render-rate camera eases toward the moved target (engine order mirrored).
	world.predict_motion(Vector2.ZERO, 1.0 / 60.0)
	var before: Vector2 = world._world.position
	world.advance_camera_display(1.0 / 60.0)
	_check(world._world.position != tick_target and world._world.position != before, "small step eases instead of snapping")
	_check(world._world.position.distance_to(tick_target) < before.distance_to(tick_target), "eased display approaches target")
	# 4. Convergence at the same target.
	for i: int in 180:
		world.advance_camera_display(1.0 / 60.0)
	_check(world._world.position.distance_to(world._camera_target) < 0.5, "smoothed display converges to target")
	# 5. Time invariance: 60Hz vs 120Hz over the same simulated second agree.
	world._world.position = world._camera_target + Vector2(200, -120)
	var start: Vector2 = world._world.position
	for i: int in 60:
		world.advance_camera_display(1.0 / 60.0)
	var at_sixty: Vector2 = world._world.position
	world._world.position = start
	for i: int in 120:
		world.advance_camera_display(1.0 / 120.0)
	var at_fast: Vector2 = world._world.position
	_check(at_sixty.distance_to(at_fast) < 1.0, "60Hz and 120Hz smoothing agree over one second")
	# 6. Different framerates both converge given two simulated seconds.
	world._world.position = world._camera_target + Vector2(-160, 90)
	for i: int in 60:
		world.advance_camera_display(1.0 / 30.0)
	var slow_end: Vector2 = world._world.position
	world._world.position = world._camera_target + Vector2(-160, 90)
	for i: int in 240:
		world.advance_camera_display(1.0 / 120.0)
	_check(slow_end.distance_to(world._camera_target) < 1.0 and world._world.position.distance_to(world._camera_target) < 1.0, "30Hz and 120Hz both converge")
	# 7. Degenerate steps leave the display untouched (pure function, no snap).
	var held: Vector2 = world._world.position
	_check(World.smooth_camera_step(held, held + Vector2(50, 50), 0.0).is_equal_approx(held), "zero delta holds display")
	_check(World.smooth_camera_step(held, held + Vector2(50, 50), -0.016).is_equal_approx(held), "negative delta holds display")
	_check(World.smooth_camera_step(held, held + Vector2(50, 50), 0.016, 0.0).is_equal_approx(held), "non-positive rate holds display")
	_check(World.smooth_camera_step(Vector2(INF, 0), Vector2(10, 10), 0.016).x == INF, "non-finite display guarded")
	# 8. Teleport discontinuity hard-snaps to the authoritative landing and holds
	# while the render pose catches up, so the camera never slews across the jump.
	world.apply_tick({"tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": 20.0, "y": 15.0}, "stats": {}}]})
	var landing_target: Vector2 = world.desired_camera_position(Vector2(20, 15) * 32.0, viewport_size)
	_check(world._camera_hold_auth or player.display_position().is_equal_approx(Vector2(20, 15) * 32.0), "teleport holds until display pose lands, or releases after entity instant snap")
	_check(world._world.position.is_equal_approx(landing_target), "teleport snaps display to landing")
	for i: int in 4:
		world.advance_camera_display(1.0 / 60.0)
	_check(world._world.position.is_equal_approx(landing_target), "hold keeps display snapped while pose trails")
	world.predict_motion(Vector2.ZERO, 0.5) # Physics-cadence prediction lands the local pose on _prediction.
	world.advance_camera_display(1.0 / 60.0)
	_check(not world._camera_hold_auth, "hold releases once the render pose lands")
	world.apply_tick({"tick_id": -1, "tick_time": 0, "update_statuses": [{"id": 10, "position": {"x": 20.1, "y": 15.0}, "stats": {}}]})
	_check(world._world.position.is_equal_approx(world.desired_camera_position(Vector2(20.1, 15) * 32.0, viewport_size)), "even sub-tile explicit GOTO snaps camera immediately")
	# 9. Map reset invalidates the camera; the next presentation snaps, not slews.
	world.apply_map({"width": 40, "height": 30, "name": "Camera fixture re-map"})
	_check(not world._camera_ready, "map reset invalidates camera readiness")
	world.apply_update({"new_objects": [
		{"object_type": 100, "stats": {"id": 10, "position": {"x": 6.0, "y": 6.0}, "stats": {0: 100, 1: 80}}},
	]})
	player = world.entities[10] # Map respawn replaces the entity object; re-fetch.
	world.advance_camera_display(1.0 / 60.0)
	_check(world._world.position.is_equal_approx(world._camera_target), "post-map presentation snaps")
	# 10. Mouse mapping follows the DISPLAYED transform, matching the aim/ability path.
	var probe_global: Vector2 = world._world.position + Vector2(96, 64)
	_check(world.screen_to_world_tiles(probe_global).is_equal_approx(Vector2(3, 2)), "screen mapping uses displayed world offset")
	# 11. Smoothing never touches authority, requests, collision, or trajectories.
	var auth_before: Vector2 = player.authoritative_position
	var stats_before: Dictionary = player.stats.duplicate(true)
	var prediction_before: Vector2 = world._prediction
	var tiles_before: int = world.tiles.size()
	world.apply_projectile({"owner_id": 10, "bullet_id": 3, "position": {"x": 6.0, "y": 6.0}, "angle": 0.5, "speed": 150, "lifetime_ms": 600})
	var flight_before: Vector2 = world.projectile_position(world.projectiles["10:3"])
	var moves: Array = []
	var shots: Array = []
	var ground: Array = []
	world.move_requested.connect(func(pos: Dictionary, records: Array): moves.append(pos))
	world.shoot_requested.connect(func(angle: float): shots.append(angle))
	world.ground_damage_requested.connect(func(position: Vector2): ground.append(position))
	world._world.position = world._camera_target + Vector2(120, 80)
	for i: int in 90:
		world._process(1.0 / 60.0)
		world.advance_camera_display(1.0 / 60.0)
	_check(player.authoritative_position.is_equal_approx(auth_before), "smoothing preserves authoritative position")
	_check(player.stats == stats_before, "smoothing preserves authoritative stats")
	_check(world._prediction.is_equal_approx(prediction_before), "smoothing preserves prediction")
	_check(world.tiles.size() == tiles_before, "smoothing preserves streamed tiles")
	_check(world.projectile_position(world.projectiles["10:3"]).is_equal_approx(flight_before), "smoothing preserves source trajectory")
	_check(moves.is_empty() and shots.is_empty() and ground.is_empty(), "camera presentation emits no requests")
	# 12. No camera rounding: fractional offsets survive the ease (no pixel judder).
	world.apply_tick({"tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": 6.33, "y": 6.17}, "stats": {}}]})
	world.predict_motion(Vector2.ZERO, 1.0 / 60.0)
	var step_from: Vector2 = world._world.position
	world.advance_camera_display(1.0 / 60.0)
	var step_target: Vector2 = world._camera_target
	var eased: Vector2 = world._world.position
	_check(not eased.is_equal_approx(eased.round()), "eased display keeps fractional offsets")
	_check(eased.is_equal_approx(World.smooth_camera_step(step_from, step_target, 1.0 / 60.0)), "display step matches pure easing function")
	# 13. Presentation interface stays optional: fallback equals semantic position.
	_check(world._display_player_pixels(player).is_equal_approx(player.position), "camera falls back to semantic position without render-pose interface")
	if capture_dir != "":
		await _render_capture(world, capture_dir)
	world.free()
	await process_frame
	print("FSOD CAMERA SMOOTHING PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _render_capture(world: Node2D, capture_dir: String) -> void:
	world.set_descriptors({"objects": {1: {"kind": "player"}, 2: {"kind": "enemy"}, 300: {"name": "Fixture staff"}}, "tiles": {10: {"color": "#344a44"}, 11: {"color": "#515065"}}})
	world.set_player_id(1)
	world.apply_map({"width": 36, "height": 22, "name": "CAMERA FIXTURE / NOT LIVE"})
	var cells: Array = []
	for y: int in 22:
		for x: int in 36:
			cells.append({"x": x, "y": y, "tile": 11 if x % 12 == 0 or y % 11 == 0 else 10})
	world.apply_update({"tiles": cells, "new_objects": [
		{"object_type": 1, "stats": {"id": 1, "position": {"x": 16, "y": 11}, "stats": {0: 100, 1: 72, 3: 100, 4: 61, 7: 8}}},
		{"object_type": 2, "stats": {"id": 2, "position": {"x": 21, "y": 10}, "stats": {}}},
		{"object_type": 2, "stats": {"id": 3, "position": {"x": 18, "y": 14}, "stats": {}}},
	]})
	world.advance_camera_display(1.0 / 60.0) # Snap to the spawned framing.
	world.entities[1].aim_angle = -0.21
	world.apply_projectile({"owner_id": 1, "bullet_id": 0, "starting_pos": {"x": 17, "y": 11}, "angle": -0.21, "speed": 150, "lifetime_ms": 600})
	world.apply_projectile({"owner_id": 2, "bullet_id": 0, "position": {"x": 20, "y": 10}, "angle": 2.92, "speed": 100, "lifetime_ms": 1000})
	world.entities[1].position += Vector2(48, -24) # Mid-smoothing framing gap, display only.
	world._world.position = world._camera_target + Vector2(60, 30)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame(capture_dir.path_join("camera-frame-0.png"))
	world.advance_visuals(0.13)
	world.advance_camera_display(0.5)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame(capture_dir.path_join("camera-frame-1.png"))
	print("FSOD CAMERA RENDER PASS")


func _save_frame(path: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image.is_empty() or image.get_width() < 1000:
		failures += 1
		push_error("FSOD CAMERA FAIL: renderer did not return real viewport pixels")
		return
	if image.save_png(path) != OK:
		failures += 1
		push_error("FSOD CAMERA FAIL: cannot save rendered fixture frame")
		return
	print("FSOD CAMERA FRAME: %dx%d %s" % [image.get_width(), image.get_height(), path])


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD CAMERA FAIL: " + description)
	assert(condition, description)
