# SPDX-License-Identifier: AGPL-3.0-only
# Deterministic held-WASD walking-stutter reproduce + regression guard.
# Dictionary fixture ONLY, no live server/game/input injection. Compares the
# GOTO working path (tick_id -1 hard snap, correct) against the NEW_TICK broken
# path (per-tick auth rebase discarding unacked prediction). Held RIGHT at
# physics cadence with delayed + quantized server snapshots every 100ms and
# 20Hz MOVE batching mirrors the live pipeline. Run headless:
# Godot_v4.6 --headless --path <root> -s src/client/fsod/walking_selftest.gd
extends SceneTree

const World = preload("res://src/client/fsod/world_view.gd")

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.set_descriptors({"objects": {100: {"kind": "player", "name": "Player"}}, "tiles": {1: {"color": "#354c40"}}})
	world.set_player_id(10)
	world.apply_map({"width": 40, "height": 30, "name": "Walking fixture"})
	var cells: Array = []
	for x in range(0, 40):
		for y in range(2, 9):
			cells.append({"x": x, "y": y, "tile": 1})
	world.apply_update({"tiles": cells, "new_objects": [
		{"object_type": 100, "stats": {"id": 10, "position": {"x": 4.0, "y": 5.0}, "stats": {0: 100, 1: 80}}},
	]})
	var player: Variant = world.entities[10]
	world.prediction_speed_tiles = 4.0 # Explicit fixture injection, not runtime default.
	var clock_ms := {"t": 0}
	world.clock_ms = func(): return clock_ms.t
	var moves: Array = []
	world.move_requested.connect(func(pos: Dictionary, records: Array): moves.append({"pos": pos, "records": records}))
	# H1: held RIGHT 1.0s at 60Hz physics; server NEW_TICK every 100ms carries
	# the delayed + quantized echo (one tick behind, 0.01 tile quantization).
	var dt := 1.0 / 60.0
	var pred_path: Array = []
	var disp_path: Array = []
	var rewinds := 0
	var rewind_total := 0.0
	var backward_steps := 0
	var elapsed := 0.0
	var tick_idx := 0
	for i in 60:
		world.predict_motion(Vector2.RIGHT, dt)
		world.advance_visuals(dt)
		clock_ms.t += int(dt * 1000.0)
		elapsed += dt
		pred_path.append(world._prediction.x)
		disp_path.append(player.display_position().x / 32.0)
		if i % 6 == 5:
			tick_idx += 1
			var auth_x: float = snappedf(4.0 + 4.0 * float(tick_idx - 1) * 0.1, 0.01)
			var before: float = world._prediction.x
			world.apply_tick({"tick_id": tick_idx, "tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": auth_x, "y": 5.0}, "stats": {}}]})
			var after: float = world._prediction.x
			if after < before - 0.05:
				rewinds += 1
				rewind_total += before - after
	for i in range(1, disp_path.size()):
		if disp_path[i] < disp_path[i - 1] - 0.001:
			backward_steps += 1
	var total_disp: float = disp_path[disp_path.size() - 1] - disp_path[0]
	print("WALKING HELD BASELINE: rewinds=%d rewind_total=%.3f backward_steps=%d total_disp=%.3f moves=%d" % [rewinds, rewind_total, backward_steps, total_disp, moves.size()])
	_check(rewinds == 0, "held NEW_TICK causes zero prediction rewinds (got %d, %.3f tiles)" % [rewinds, rewind_total])
	_check(backward_steps == 0, "held display never steps backward (got %d)" % backward_steps)
	_check(absf(total_disp - 4.0 * 59.0 / 60.0) < 0.25, "held 1s covers ~speed*time without speed pause (got %.3f)" % total_disp)
	_check(moves.size() >= 18 and moves.size() <= 22, "source MOVE samples stay at 20Hz physics cadence (got %d)" % moves.size())
	_check(player.authoritative_position.x < world._prediction.x, "auth trails prediction while held (delayed server, not snapped)")
	# Release: 0.5s idle, server catches up to the stopped point. No snap-back.
	var held_end: float = world._prediction.x
	for i in 30:
		world.predict_motion(Vector2.ZERO, dt)
		world.advance_visuals(dt)
		clock_ms.t += int(dt * 1000.0)
		elapsed += dt
		if i % 6 == 5:
			tick_idx += 1
			var catch: float = minf(held_end, snappedf(4.0 + 4.0 * float(tick_idx - 1) * 0.1, 0.01))
			world.apply_tick({"tick_id": tick_idx, "tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": catch, "y": 5.0}, "stats": {}}]})
	_check(absf(world._prediction.x - held_end) < 0.06, "release holds prediction (no snap-back, got %.3f vs %.3f)" % [world._prediction.x, held_end])
	_check(absf(player.display_position().x / 32.0 - held_end) < 0.08, "release display stays (got %.3f)" % (player.display_position().x / 32.0))
	# GOTO working path (reference): explicit GOTO hard-snaps immediately.
	world.apply_tick({"tick_id": -1, "tick_time": 0, "update_statuses": [{"id": 10, "position": {"x": 20.0, "y": 15.0}, "stats": {}}]})
	world.predict_motion(Vector2.ZERO, dt)
	_check(world._prediction.is_equal_approx(Vector2(20, 15)), "genuine GOTO still hard-snaps prediction")
	_check((player.position / 32.0).distance_to(Vector2(20, 15)) < 0.05, "genuine GOTO snaps display")
	_check(player.authoritative_position.is_equal_approx(Vector2(20, 15)), "authority tracks GOTO landing")
	# Cross-FPS: same 0.5s hold at 60Hz vs 144Hz step sizes agrees.
	world.apply_tick({"tick_id": -1, "tick_time": 0, "update_statuses": [{"id": 10, "position": {"x": 4.0, "y": 5.0}, "stats": {}}]})
	world.predict_motion(Vector2.ZERO, dt)
	var fps60: Array = []
	for i in 30:
		world.predict_motion(Vector2.RIGHT, 1.0 / 60.0)
		fps60.append(world._prediction.x)
	world.apply_tick({"tick_id": -1, "tick_time": 0, "update_statuses": [{"id": 10, "position": {"x": 4.0, "y": 5.0}, "stats": {}}]})
	world.predict_motion(Vector2.ZERO, 1.0 / 60.0)
	var fps144_end := 0.0
	for i in 72:
		world.predict_motion(Vector2.RIGHT, 1.0 / 144.0)
		fps144_end = world._prediction.x
	_check(absf(fps60[fps60.size() - 1] - fps144_end) < 0.05, "60Hz vs 144Hz holds agree (%.3f vs %.3f)" % [fps60[fps60.size() - 1], fps144_end])
	# Mouse mapping follows the displayed transform with no drift.
	world.advance_camera_display(1.0 / 60.0)
	var probe_global: Vector2 = world._world.position + Vector2(96, 64)
	var tiles: Vector2 = world.screen_to_world_tiles(probe_global)
	var roundtrip: Vector2 = world._world.to_global(tiles * 32.0)
	_check(roundtrip.distance_to(probe_global) < 0.01, "screen mapping round-trips through displayed transform")
	_check(world._display_player_pixels(player).is_equal_approx(player.display_position()), "camera reads the render pose, not the contact box")
	_check(player.position.distance_to(player.authoritative_position * 32.0) < 1.0, "contact position stays on the server echo")
	# Blocking colliders / NoWalk preserved: wall ahead clips, never entered.
	var walled: Dictionary = world.descriptors.duplicate(true)
	walled["tiles"][2] = {"source_descriptor": {"NoWalk": true}}
	world.set_descriptors(walled)
	world.tiles[Vector2i(10, 5)] = 2
	_check(not world._can_walk(Vector2(10.2, 5.0)), "source NoWalk tile still blocks")
	world.apply_tick({"tick_id": -1, "tick_time": 0, "update_statuses": [{"id": 10, "position": {"x": 8.0, "y": 5.0}, "stats": {}}]})
	world.predict_motion(Vector2.ZERO, dt)
	for i in 120:
		world.predict_motion(Vector2.RIGHT, dt)
		world.advance_visuals(dt)
		if i % 6 == 5:
			world.apply_tick({"tick_id": 100 + i, "tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": world._prediction.x, "y": 5.0}, "stats": {}}]})
	_check(world._prediction.x < 10.0, "prediction clips at NoWalk wall (got %.3f)" % world._prediction.x)
	_check(world.entities[10].stats.get(0, 100) == 100, "prediction never rewrites backend HP")
	_turns_and_thresholds(world, player, dt)
	_contact_stays_on_echo(world, player)
	world.free()
	await process_frame
	print("FSOD WALKING PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _reset(world, player, pos: Vector2) -> void:
	if world.entities.has(40):
		world.remove_entity(40)
	if world.tiles.has(Vector2i(10, 5)):
		world.tiles[Vector2i(10, 5)] = 1
	world.apply_tick({"tick_id": -1, "tick_time": 0, "update_statuses": [{"id": 10, "position": {"x": pos.x, "y": pos.y}, "stats": {29: 0}}]})
	world.predict_motion(Vector2.ZERO, 1.0 / 60.0)
	player.stats[29] = 0

func _echo_sent(world, x: float, y: float, tick: int) -> void:
	world.apply_tick({"tick_id": tick, "tick_time": 100, "update_statuses": [{"id": 10, "position": {"x": x, "y": y}, "stats": {29: int(world.entities[10].stats.get(29, 0))}}]})

func _turns_and_thresholds(world, player, dt: float) -> void:
	# Reverse: delayed echoes of sent samples must not yank the return.
	_reset(world, player, Vector2(8, 5))
	var sent: Array = []
	world.move_requested.connect(func(pos: Dictionary, _records: Array): sent.append(Vector2(float(pos.x), float(pos.y))))
	var backward := 0
	var prev: float = player.display_position().x
	for i in 30:
		world.predict_motion(Vector2.RIGHT, dt)
		if i % 6 == 5 and sent.size() > 1:
			_echo_sent(world, sent[maxi(0, sent.size() - 2)].x, 5.0, 200 + i)
		var shown: float = player.display_position().x
		if shown < prev - 0.001:
			backward += 1
		prev = shown
	var far_sample: Vector2 = sent[sent.size() - 1]
	for i in 30:
		world.predict_motion(Vector2.LEFT, dt)
		if i % 6 == 5 and sent.size() > 1:
			var sample: Vector2 = sent[maxi(0, sent.size() - 2)]
			_echo_sent(world, sample.x, sample.y, 300 + i)
		var shown: float = player.display_position().x
		if shown > prev + 0.001:
			backward += 1
		prev = shown
	_check(absf(world._prediction.x - 8.0) < 0.15, "reverse finishes near the start (got %.3f)" % world._prediction.x)
	_check(backward == 0, "reverse display steps only with the command (got %d)" % backward)
	var before_yank: float = world._prediction.x
	_echo_sent(world, far_sample.x, far_sample.y, 390)
	_check(absf(world._prediction.x - before_yank) < 0.02, "echo of the far point does not yank the return")
	# Perpendicular.
	_reset(world, player, Vector2(4, 4))
	var origin: Vector2 = world._prediction
	for i in 30:
		world.predict_motion(Vector2.RIGHT, dt)
		if i % 6 == 5:
			var sample: Vector2 = world._sent_moves[maxi(0, world._sent_moves.size() - 2)]
			_echo_sent(world, sample.x, sample.y, 400 + i)
	for i in 30:
		world.predict_motion(Vector2.DOWN, dt)
		if i % 6 == 5:
			var sample: Vector2 = world._sent_moves[maxi(0, world._sent_moves.size() - 2)]
			_echo_sent(world, sample.x, sample.y, 500 + i)
	var expected: float = 4.0 * 0.5
	_check(absf(world._prediction.x - origin.x - expected) < 0.05, "perpendicular x covers speed*time")
	_check(absf(world._prediction.y - origin.y - expected) < 0.05, "perpendicular y covers speed*time")
	# Off-path. 0.20 off the current pose is noise. Anything outside that dead
	# zone that is not a sent echo snaps, including 0.30. 0.50 is the same rule,
	# not a separate threshold.
	_reset(world, player, Vector2(6, 6))
	world.predict_motion(Vector2.RIGHT, dt)
	var pose: Vector2 = world._prediction
	_echo_sent(world, pose.x + 0.20, pose.y, 600)
	_check(world._prediction.is_equal_approx(pose), "0.20 off the current pose does not snap")
	_reset(world, player, Vector2(6, 6))
	world.predict_motion(Vector2.RIGHT, dt)
	var pose30: Vector2 = world._prediction
	_echo_sent(world, pose30.x, pose30.y + 0.30, 603)
	_check(world._prediction.is_equal_approx(Vector2(pose30.x, pose30.y + 0.30)), "0.30 off-trail non-echo snaps")
	_check(world._sent_moves.size() == 1, "0.30 off-trail snap clears sent history")
	_reset(world, player, Vector2(6, 6))
	world.predict_motion(Vector2.RIGHT, dt)
	pose = world._prediction
	_echo_sent(world, pose.x, pose.y + 0.50, 601)
	_check(world._prediction.is_equal_approx(Vector2(pose.x, pose.y + 0.50)), "0.50 off the trail snaps")
	_check(world._sent_moves.size() == 1, "off-path snap clears sent history")
	_reset(world, player, Vector2(6, 6))
	_echo_sent(world, 11.0, 6.0, 602)
	_check(world._prediction.is_equal_approx(Vector2(11, 6)), "distance over 4 tiles snaps")
	_check(world._sent_moves.size() == 1, "teleport snap clears sent history")
	# Paralysis hard-corrects a freeze on the trail, including inside the 0.20 dead zone.
	_reset(world, player, Vector2(4, 5))
	for i in 40:
		world.predict_motion(Vector2.RIGHT, dt)
	var lead: Vector2 = world._prediction
	player.stats[29] = 1 << 13
	_echo_sent(world, lead.x - 0.60, lead.y, 700)
	_check(absf(world._prediction.x - (lead.x - 0.60)) < 0.02, "paralysis 0.6 tiles back hard-corrects")
	_reset(world, player, Vector2(4, 5))
	for i in 40:
		world.predict_motion(Vector2.RIGHT, dt)
	lead = world._prediction
	player.stats[29] = 1 << 13
	_echo_sent(world, lead.x - 0.20, lead.y, 701)
	_check(absf(world._prediction.x - (lead.x - 0.20)) < 0.02, "paralysis 0.2 tiles back hard-corrects")
	player.stats[29] = 0
	# OccupySquare overlap must not rewind an echo of the pre-overlap pose.
	_reset(world, player, Vector2(4, 5))
	for i in 18:
		world.predict_motion(Vector2.RIGHT, dt)
	var pre_overlap: Vector2 = world._sent_moves[0]
	for i in 24:
		world.predict_motion(Vector2.RIGHT, dt)
	var occupied: Dictionary = world.descriptors.duplicate(true)
	occupied["objects"][200] = {"kind": "enemy", "source_descriptor": {"OccupySquare": true}}
	world.set_descriptors(occupied)
	world.apply_update({"new_objects": [{"object_type": 200, "stats": {"id": 40, "position": {"x": world._prediction.x, "y": world._prediction.y}}}]})
	var overlap_rewinds := 0
	for i in 12:
		var before: float = world._prediction.x
		world.predict_motion(Vector2.RIGHT, dt)
		_echo_sent(world, pre_overlap.x, pre_overlap.y, 800 + i)
		if world._prediction.x < before - 0.05:
			overlap_rewinds += 1
	_check(overlap_rewinds == 0, "OccupySquare overlap echo does not rewind (got %d)" % overlap_rewinds)
	# Delayed echo older than the 64 sent-sample ring snaps.
	_reset(world, player, Vector2(2, 7))
	var aged: float = world._sent_moves[0].x
	for i in 720:
		world.predict_motion(Vector2.RIGHT, 1.0 / 144.0)
	_check(world._sent_moves.size() == 64, "sent ring stays capped at 64 (got %d)" % world._sent_moves.size())
	var aged_out: bool = true
	for point in world._sent_moves:
		if point is Vector2 and absf(point.x - aged) <= 0.02:
			aged_out = false
	_check(aged_out, "144Hz hold ages the first sent sample out of the ring")
	var before_age: Vector2 = world._prediction
	_echo_sent(world, aged, 7.0, 900)
	_check(world._prediction.is_equal_approx(Vector2(aged, 7.0)), "echo older than the sent ring snaps")
	_check(before_age.distance_to(world._prediction) > 0.5, "aged echo is a real correction, not a no-op")

func _contact_stays_on_echo(world, player) -> void:
	_reset(world, player, Vector2(4, 5))
	player.present_prediction(Vector2(5.4, 5.0))
	_check(player.position.is_equal_approx(Vector2(4, 5) * 32.0), "contact box stays on the echo")
	_check(player.display_position().is_equal_approx(Vector2(5.4, 5.0) * 32.0), "render pose carries the lead")
	var described: Dictionary = world.descriptors.duplicate(true)
	described["objects"][100]["hit_radius_tiles"] = 0.5
	described["objects"][300] = {"kind": "enemy", "hit_radius_tiles": 0.5, "projectiles": [{"bullet_type": 0, "speed": 10.0, "lifetime_ms": 1000}]}
	world.set_descriptors(described)
	world.apply_update({"new_objects": [{"object_type": 300, "stats": {"id": 77, "position": {"x": 1.0, "y": 1.0}}}]})
	var hits: Array = []
	world.projectile_hit_requested.connect(func(owner: int, bullet: int, target: int, kind: String): hits.append({"owner": owner, "bullet": bullet, "target": target, "kind": kind}))
	world.apply_projectile({"owner_id": 77, "bullet_id": 1, "position": {"x": 4.0, "y": 5.0}, "speed": 10.0, "lifetime_ms": 1000, "angle": 0.0})
	world.advance_visuals(1.0 / 60.0)
	_check(hits.size() == 1 and hits[0].kind == "player" and hits[0].target == 10, "bullet on the echo fires PLAYERHIT")
	hits.clear()
	world.apply_projectile({"owner_id": 77, "bullet_id": 2, "position": {"x": 5.4, "y": 5.0}, "speed": 10.0, "lifetime_ms": 1000, "angle": 0.0})
	world.advance_visuals(1.0 / 60.0)
	_check(hits.is_empty(), "bullet on the prediction lead does not fire PLAYERHIT")
	# Mouse aim uses the lagged displayed transform, not the unsmoothed target.
	world._camera_target = world._world.position
	world._world.position = world._camera_target + Vector2(40, 0)
	var screen: Vector2 = world._world.to_global(player.display_position() + Vector2(64, 0))
	var aim: Vector2 = world.screen_to_world_tiles(screen) - world._display_player_pixels(player) / 32.0
	_check(absf(rad_to_deg(aim.angle())) < 1.0, "aim matches the displayed cursor within 1 degree (got %.2f)" % rad_to_deg(aim.angle()))

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD WALKING FAIL: " + description)
	assert(condition, description)
