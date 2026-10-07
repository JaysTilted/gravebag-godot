# SPDX-License-Identifier: AGPL-3.0-only
# Entity render-pose smoothing + edge-polish selftest (frontend-only, no backend).
# Proves: baseline contact track bit-identical linear, render pose smooth and
# FPS-stable, discontinuity snaps render only, sourceSize fidelity, no authority
# mutation. Run: Godot_v4.6 --headless --path <root> -s src/client/fsod/entity_smoothing_selftest.gd
extends SceneTree
const EntityView = preload("res://src/client/fsod/entity_view.gd")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(is_equal_approx(EntityView.TILE_PIXELS, 32.0), "32 pixels per source tile unchanged")
	_check(is_equal_approx(EntityView.PIXEL, 3.0), "crisp texel PIXEL 3.0 unchanged")
	_check(EntityView.PLAYER_FRAMES.size() == 2 and EntityView.ENEMY_FRAMES.size() == 2, "two sprite frames kept")
	_check(EntityView.PLAYER_FRAMES[0] != EntityView.PLAYER_FRAMES[1], "two distinct player pixel frames")
	_check(EntityView.ENEMY_FRAMES[0] != EntityView.ENEMY_FRAMES[1], "two distinct enemy pixel frames")
	_check(is_equal_approx(EntityView.PRESENT_RATE, 20.0) and is_equal_approx(EntityView.SNAP_PIXELS, 256.0), "presentation tuning constants present")
	var probe = EntityView.new()
	_check(probe.has_method("advance_visual") and probe.has_method("advance_presentation") and probe.has_method("display_position"), "matching advance(delta) interface plus optional render pass")
	var script_methods: Array = []
	for entry: Dictionary in probe.get_script().get_script_method_list():
		script_methods.append(entry.get("name", ""))
	_check(not script_methods.has("_process") and not script_methods.has("_physics_process"), "no entity _process/_physics_process (camera worker owns cadence, no double-step)")
	probe.free()
	var source := FileAccess.open("res://src/client/fsod/entity_view.gd", FileAccess.READ)
	_check(source != null, "entity source readable for fidelity audit")
	if source != null:
		var text: String = source.get_as_text()
		_check(text.contains("antialiased") and text.contains("advance_presentation") and text.contains("_render_offset"), "AA decorations plus render pose present")
		_check(not text.contains("CanvasItemMaterial") and not text.contains("ShaderMaterial") and not text.contains("TextureFilter"), "no blanket blur/material/filter nodes")
		_check(not text.contains("round(_visual_size)") and not text.contains("snapped"), "no integer scale forcing")
	var sized = EntityView.new()
	root.add_child(sized)
	sized.configure(1, 100, {"kind": "enemy", "name": "Fixture", "source_descriptor": {"MinSize": 100}})
	_check(is_equal_approx(sized._visual_size, 1.0), "descriptor MinSize 100 maps to 1.0")
	sized.apply_status({"position": {"x": 0.0, "y": 0.0}, "stats": {2: 150}})
	_check(is_equal_approx(sized._visual_size, 1.5), "wire stat 2 drives exact source size")
	sized.apply_status({"position": {"x": 0.0, "y": 0.0}, "stats": {2: 133}})
	_check(is_equal_approx(sized._visual_size, 1.33), "fractional source size kept, not integer-snapped")
	sized.configure(2, 100, {"kind": "enemy", "name": "Big", "source_descriptor": {"MinSize": 500}})
	_check(is_equal_approx(sized._visual_size, 3.0), "size clamp upper bound kept")
	sized.configure(3, 100, {"kind": "enemy", "name": "Small", "source_descriptor": {"MinSize": 10}})
	_check(is_equal_approx(sized._visual_size, 0.5), "size clamp lower bound kept")
	_check(sized.position == Vector2.ZERO and sized._render_offset == Vector2.ZERO, "fresh view has zero render offset")
	sized.free()
	var remote = EntityView.new()
	root.add_child(remote)
	remote.configure(20, 200, {"kind": "enemy", "name": "Runner"})
	remote.apply_status({"position": {"x": 4.0, "y": 3.0}, "stats": {}})
	_check(remote.position == Vector2(128, 96), "spawn snaps contact track to target")
	_check(remote.display_position() == Vector2(128, 96), "spawn initializes render pose at target")
	remote.apply_status({"position": {"x": 6.0, "y": 3.0}, "stats": {}}, 0.2)
	_check(remote.authoritative_position == Vector2(6, 3), "authority tracks latest target")
	_check(remote.position == Vector2(128, 96), "new tick restarts contact from presentation (baseline)")
	remote.advance_visual(0.1)
	_check(remote.position == Vector2(160, 96), "halfway linear contact preserved for hit sampling")
	var in_flight: Vector2 = remote.position
	remote.apply_status({"position": {"x": 6.0, "y": 3.0}, "stats": {}}, 0.2)
	_check(remote.position == in_flight, "duplicate tick causes no contact jump")
	remote.advance_visual(0.1)
	_check(remote.position == Vector2(176, 96), "duplicate tick restarts baseline linear clock")
	remote.advance_visual(0.1)
	_check(remote.position == Vector2(192, 96), "endpoint contact preserved for hit sampling")
	var smooth = EntityView.new()
	root.add_child(smooth)
	smooth.configure(21, 200, {"kind": "enemy", "name": "Glider"})
	smooth.apply_status({"position": {"x": 0.0, "y": 0.0}, "stats": {}})
	smooth.apply_status({"position": {"x": 4.0, "y": 0.0}, "stats": {}}, 0.2)
	_check(smooth._render_offset == Vector2.ZERO, "render offset starts at zero (baseline-identical)")
	smooth.advance_presentation(0.05)
	_check(smooth._render_offset.x > 0.0 and smooth._render_offset.x < 128.0, "render pose eases toward target behind it")
	var first_render: Vector2 = smooth._render_pos
	smooth.advance_presentation(0.05)
	_check(smooth._render_pos.x > first_render.x and smooth._render_pos.x < 128.0, "render pose converges monotonically without overshoot")
	for i in 20:
		smooth.advance_presentation(0.1)
	_check(smooth._render_pos.distance_to(Vector2(128, 0)) < 1.0, "render pose settles on target")
	var view_a = EntityView.new()
	var view_b = EntityView.new()
	root.add_child(view_a)
	root.add_child(view_b)
	for view: Variant in [view_a, view_b]:
		view.configure(22, 200, {"kind": "enemy", "name": "Cadence"})
		view.apply_status({"position": {"x": 0.0, "y": 0.0}, "stats": {}})
		view.apply_status({"position": {"x": 4.0, "y": 0.0}, "stats": {}}, 0.2)
	for i in 10:
		view_a.advance_presentation(0.02)
	view_b.advance_presentation(0.2)
	_check(view_a._render_pos.distance_to(view_b._render_pos) < 0.001, "render pose is FPS-stable: 10x20ms equals 1x200ms")
	_check(view_a._render_offset == view_a._render_pos - view_a.position, "render offset always equals pose minus contact")
	view_a.free()
	view_b.free()
	smooth.free()
	var jumper = EntityView.new()
	root.add_child(jumper)
	jumper.configure(23, 200, {"kind": "enemy", "name": "Blink"})
	jumper.apply_status({"position": {"x": 6.0, "y": 3.0}, "stats": {}})
	jumper.apply_status({"position": {"x": 6.0, "y": 3.0}, "stats": {}}, 0.2)
	jumper.advance_visual(0.2)
	_check(jumper.position == Vector2(192, 96), "settled contact before teleport")
	jumper.apply_status({"position": {"x": 100.0, "y": 3.0}, "stats": {}}, 0.2)
	_check(jumper.position == Vector2(192, 96), "teleport keeps baseline contact evolution (no contact change)")
	_check(jumper._render_pos == Vector2(3200, 96), "teleport snaps render pose, never slides")
	_check(jumper.display_position() == Vector2(3200, 96), "display pose exposes snapped target")
	jumper.apply_status({"position": {"x": 100.5, "y": 3.0}, "stats": {}}, 0.0)
	_check(jumper._render_pos == Vector2(3216, 96), "GOTO zero-tick snaps render pose")
	jumper.free()
	var local = EntityView.new()
	root.add_child(local)
	local.configure(10, 100, {"kind": "player", "name": "Self", "player": true})
	local.is_local_player = true
	local.apply_status({"position": {"x": 2.5, "y": 3.0}, "stats": {0: 100, 1: 80}}, 0.2)
	var before_stats: Dictionary = local.stats.duplicate(true)
	var before_authority: Vector2 = local.authoritative_position
	local.predict_position(Vector2(2.7, 3.0))
	local.advance_visual(0.05)
	local.advance_presentation(0.05)
	_check(local.stats == before_stats and local.authoritative_position == before_authority, "prediction/presentation never mutate authority")
	_check(local._render_offset == Vector2.ZERO and local.display_position() == local.position, "local render stays tight on prediction")
	_check(local.position == Vector2(2.7, 3.0) * 32.0, "local contact follows prediction only")
	local.free()
	var framed = EntityView.new()
	root.add_child(framed)
	framed.configure(24, 200, {"kind": "enemy", "name": "Frame"})
	framed.apply_status({"position": {"x": 1.0, "y": 1.0}, "stats": {}})
	framed.apply_status({"position": {"x": 3.0, "y": 1.0}, "stats": {}}, 0.2)
	var contact_before: Vector2 = framed.position
	var render_before: Vector2 = framed._render_pos
	framed.advance_visual(1.0 / 60.0)
	framed.advance_presentation(1.0 / 60.0)
	_check(framed.position.x > contact_before.x and framed.position.x <= 96.0, "contact advances toward target within segment")
	_check(framed._render_pos.x >= render_before.x and framed._render_pos.x <= 96.0, "render advances toward target without overshoot")
	_check(framed.position.is_finite() and framed._render_pos.is_finite(), "frame step stays finite")
	_check(framed.authoritative_position == Vector2(3, 1), "frame step keeps authority")
	framed.free()
	remote.free()
	await process_frame
	print("FSOD SMOOTHING PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD SMOOTHING FAIL: " + description)
	assert(condition, description)
