# SPDX-License-Identifier: AGPL-3.0-only
# Combat feedback fixtures. Display reads only. No live server, no transport,
# no entry/world/session edits. Headless logic plus optional xvfb frame sequence.
extends SceneTree

const World = preload("res://src/client/fsod/world_view.gd")
const Feedback = preload("res://src/client/fsod/combat_feedback.gd")

var failures := 0
var checks := 0


class MockSession extends Node:
	var state := "playing"
	var player_id := 1
	var player_stats: Dictionary = {0: 100, 1: 100, 7: 1}
	var entity_states: Dictionary = {}
	var metadata: Dictionary = {}
	var send_calls := 0

	func send_fields(_packet_id: Variant = null, _fields: Variant = null) -> void:
		send_calls += 1


class BareEntity extends Node2D:
	var entity_id := 9
	var kind := "enemy"
	var object_type := 900
	var stats: Dictionary = {0: 40, 1: 40}
	var authoritative_position := Vector2(4, 4)


class FakeFront extends Node:
	var entities: Dictionary = {}
	var map_name := "Nexus"
	var player_id := 1
	var descriptors: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _descriptors() -> Dictionary:
	return {"objects": {
		782: {"kind": "player", "name": "Wizard", "class": "Player"},
		900: {"kind": "enemy", "name": "Goblin", "class": "Enemy"},
	}, "tiles": {1: {"color": "#354c40"}}}


func _tiles() -> Array:
	var tiles: Array = []
	for x in 18:
		for y in 12:
			tiles.append({"x": x, "y": y, "tile": 1})
	return tiles


func _world() -> Node2D:
	var world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.set_process_input(false)
	world.set_process_unhandled_input(false)
	world.set_descriptors(_descriptors())
	world.set_player_id(1)
	world.apply_map({"width": 64, "height": 40, "name": "Nexus"})
	world.apply_update({"tiles": _tiles(), "new_objects": [
		{"object_type": 782, "stats": {"id": 1, "position": {"x": 10.0, "y": 10.0}, "stats": {0: 100, 1: 100, 7: 1}}},
		{"object_type": 900, "stats": {"id": 2, "position": {"x": 14.0, "y": 12.0}, "stats": {0: 80, 1: 80}}},
	]})
	return world


func _session() -> MockSession:
	var session := MockSession.new()
	root.add_child(session)
	session.metadata = {"objects": {"900": {"name": "Goblin", "class": "Enemy"}}}
	return session


func _feedback() -> Control:
	var feedback = Feedback.new()
	root.add_child(feedback)
	feedback.set_process(false)
	feedback.initialize()
	return feedback


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_static_contract()
	await _first_and_coalesce()
	await _fade_is_rate_independent()
	await _removal_map_teleport_offline()
	await _unknown_and_unplaced()
	await _status_level_and_name()
	await _clamp_and_origin()
	await _input_and_diagnostics()
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--capture-dir="):
			capture_dir = str(arg).trim_prefix("--capture-dir=")
	if capture_dir != "":
		await _capture(capture_dir)
	print("FSOD COMBAT FEEDBACK PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _static_contract() -> void:
	_check(Feedback.fade_alpha(0.0) == 1.0, "fade holds at the start")
	_check(Feedback.fade_alpha(0.72) == 0.0, "fade ends at life")
	_check(is_equal_approx(Feedback.fade_alpha(0.5), 1.0 - (0.5 - 0.12) / (0.72 - 0.12)), "fade is a function of age")
	_check(is_equal_approx(Feedback.rise_offset(0.0), 0.0), "rise starts at the sprite")
	var script := FileAccess.get_file_as_string("res://src/client/fsod/combat_feedback.gd")
	_check(script.contains("func refresh("), "refresh is the bind")
	_check(script.contains("gravebag.ui_diagnostics.v1"), "diagnostics schema is v1")
	_check(not script.contains("shoot_requested"), "no shoot request")
	_check(not script.contains("send_fields"), "no transport send")
	_check(not script.contains("set_theme_tokens"), "no invented theme setter")
	_check(script.contains("#fc3436") and script.contains("#ff3b4a") and script.contains("#1a1a1a"), "fallback uses the frozen theme map")


func _first_and_coalesce() -> void:
	var world := _world()
	var session := _session()
	var feedback := _feedback()
	await process_frame
	var before: Dictionary = session.player_stats.duplicate(true)
	feedback.refresh(session, world)
	_check(session.player_stats == before, "refresh does not mutate player stats")
	_check(session.send_calls == 0, "refresh sends no command")
	var first: Dictionary = feedback.ui_diagnostics()
	_check(int(first.state.floater_count) == 0, "first snapshot does not invent a hit")
	_check(first.state.pending.is_empty(), "first snapshot queues nothing")
	_check(not _has_amount(first), "first snapshot has no damage text")
	session.player_stats[1] = 90
	feedback.refresh(session, world)
	session.player_stats[1] = 80
	feedback.refresh(session, world)
	var pending: Dictionary = feedback.ui_diagnostics()
	_check(pending.state.pending.size() == 1 and int(pending.state.pending[0].amount) == -20, "HP updates before present coalesce to -20")
	_check(int(pending.state.floater_count) == 0, "coalesced update is not drawn twice before present")
	feedback._process(0.0)
	var shown: Dictionary = feedback.ui_diagnostics()
	_check(int(shown.state.floater_count) == 1, "present emits one floater")
	_check(_has_text(shown, "-20"), "coalesced text is the net verified delta")
	_check(shown.state.pending.is_empty(), "present consumes the pending delta")
	feedback.refresh(session, world)
	feedback._process(0.0)
	var again: Dictionary = feedback.ui_diagnostics()
	_check(int(again.state.floater_count) == 1, "identical snapshot does not spawn another floater")
	world.entities[2].stats[1] = 75
	session.player_stats[1] = 70
	feedback.refresh(session, world)
	var both: Dictionary = feedback.ui_diagnostics()
	_check(both.state.pending.size() == 2, "two entities do not coalesce into one amount")
	_free(feedback, session, world)


func _fade_is_rate_independent() -> void:
	var world := _world()
	var left_session := _session()
	var right_session := _session()
	var left := _feedback()
	var right := _feedback()
	await process_frame
	left.refresh(left_session, world)
	right.refresh(right_session, world)
	left_session.player_stats[1] = 90
	right_session.player_stats[1] = 90
	left.refresh(left_session, world)
	right.refresh(right_session, world)
	left._process(0.0)
	right._process(0.0)
	left._process(0.5)
	for _i in 4:
		right._process(0.125)
	var a: Dictionary = left.ui_diagnostics().motion.samples[0]
	var b: Dictionary = right.ui_diagnostics().motion.samples[0]
	_check(is_equal_approx(float(a.age_s), 0.5), "one step records the actual delta sum")
	_check(is_equal_approx(float(b.age_s), 0.5), "four steps record the same age")
	_check(is_equal_approx(float(a.alpha), float(b.alpha)), "fade alpha matches across step sizes")
	_check(absf(float(a.rise_px) - float(b.rise_px)) < 0.05, "rise matches across step sizes")
	_check(float(a.alpha) < 1.0 and float(a.alpha) > 0.0, "mid-life sample is actually fading")
	_check(left.ui_diagnostics().motion.last_delta_s == 0.5, "motion reports the actual last delta")
	_check(not str(left.ui_diagnostics().motion).contains("fps"), "motion does not guess a frame rate")
	_free(left, left_session, world)
	right.queue_free()
	right_session.queue_free()


func _removal_map_teleport_offline() -> void:
	var world := _world()
	var session := _session()
	var feedback := _feedback()
	await process_frame
	feedback.refresh(session, world)
	session.player_stats[1] = 90
	world.entities[2].stats[1] = 70
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(int(feedback.ui_diagnostics().state.floater_count) == 2, "player and enemy both show verified deltas")
	world.remove_entity(2)
	feedback.refresh(session, world)
	var removed: Dictionary = feedback.ui_diagnostics()
	_check(int(removed.state.floater_count) == 1, "removed entity drops its floater")
	_check(int(removed.state.name_count) == 0, "removed entity drops its name")
	world.apply_map({"width": 64, "height": 40, "name": "SpriteWorld"})
	world.apply_update({"new_objects": [
		{"object_type": 782, "stats": {"id": 1, "position": {"x": 10.0, "y": 10.0}, "stats": {0: 100, 1: 40, 7: 9}}},
	]})
	session.player_stats = {0: 100, 1: 40, 7: 9}
	feedback.refresh(session, world)
	feedback._process(0.0)
	var mapped: Dictionary = feedback.ui_diagnostics()
	_check(int(mapped.state.floater_count) == 0, "map reset does not turn the new HP into a hit")
	_check(not _has_text(mapped, "Level 9"), "map reset does not announce a level")
	_check(str(mapped.state.last_reset) == "map", "map reset is recorded")
	session.player_stats[1] = 39
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(_has_text(feedback.ui_diagnostics(), "-1"), "a later verified hit still shows after rebaseline")
	_free(feedback, session, world)

	world = _world()
	session = _session()
	feedback = _feedback()
	await process_frame
	feedback.refresh(session, world)
	world.apply_tick({"tick_id": 3, "tick_time": 100, "update_statuses": [
		{"id": 1, "position": {"x": 20.0, "y": 10.0}, "stats": {1: 70}},
	]})
	session.player_stats[1] = 70
	feedback.refresh(session, world)
	feedback._process(0.0)
	var jumped: Dictionary = feedback.ui_diagnostics()
	_check(int(jumped.state.floater_count) == 0, "teleport does not queue a stale hit")
	_check(int(jumped.state.suppressed) >= 1, "teleport suppression is counted")
	world.apply_tick({"tick_id": 4, "tick_time": 100, "update_statuses": [
		{"id": 1, "position": {"x": 20.2, "y": 10.0}, "stats": {1: 69}},
	]})
	session.player_stats[1] = 69
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(_has_text(feedback.ui_diagnostics(), "-1"), "post-teleport verified hit still shows")
	session.state = "offline"
	session.player_stats[1] = 1
	feedback.refresh(session, world)
	var offline: Dictionary = feedback.ui_diagnostics()
	_check(int(offline.state.floater_count) == 0, "offline clears floaters")
	_check(int(offline.state.baseline_count) == 0, "offline drops baselines")
	_check(not _has_amount(offline), "offline does not invent a hit")
	session.state = "dead"
	session.player_stats[1] = 0
	feedback.refresh(session, world)
	_check(not _has_text(feedback.ui_diagnostics(), "0"), "death does not print a fake zero")
	_check(int(feedback.ui_diagnostics().state.floater_count) == 0, "death does not queue a hit")
	session.state = "playing"
	session.player_stats = {0: 100, 1: 100, 7: 1}
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(int(feedback.ui_diagnostics().state.floater_count) == 0, "return to play baselines instead of replaying old damage")
	_free(feedback, session, world)


func _unknown_and_unplaced() -> void:
	var world := _world()
	var session := _session()
	var feedback := _feedback()
	await process_frame
	session.player_stats = {0: 100, 7: 1}
	feedback.refresh(session, world)
	session.player_stats[0] = 90
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(int(feedback.ui_diagnostics().state.floater_count) == 0, "missing HP stat does not become zero")
	_check(not _has_text(feedback.ui_diagnostics(), "0"), "missing HP does not render 0")
	_check(not _has_text(feedback.ui_diagnostics(), "-10"), "missing HP does not render a delta")
	session.player_stats[1] = 1.5
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(int(feedback.ui_diagnostics().state.floater_count) == 0, "non-integer HP is unknown, not rounded into a hit")
	_free(feedback, session, world)

	var bare := BareEntity.new()
	var front := FakeFront.new()
	root.add_child(front)
	root.add_child(bare)
	front.entities[9] = bare
	front.descriptors = _descriptors()
	var ghost_session := _session()
	ghost_session.player_id = 1
	ghost_session.player_stats = {}
	var ghost := _feedback()
	ghost.refresh(ghost_session, front)
	bare.set("stats", {0: 40, 1: 20})
	ghost.refresh(ghost_session, front)
	ghost._process(0.0)
	var unplaced: Dictionary = ghost.ui_diagnostics()
	_check(int(unplaced.state.floater_count) == 0, "no display_position means no screen guess")
	_check(int(unplaced.state.name_count) == 0, "nameplate is not placed from authoritative tiles")
	_check(ghost_session.send_calls == 0, "unplaced refresh still sends nothing")
	_free(ghost, ghost_session, front)
	bare.queue_free()


func _status_level_and_name() -> void:
	var world := _world()
	var session := _session()
	var feedback := _feedback()
	await process_frame
	feedback.refresh(session, world)
	feedback._process(0.0)
	var named: Dictionary = feedback.ui_diagnostics()
	_check(_has_text(named, "Goblin"), "enemy name uses source metadata")
	_check(int(named.state.bar_count) == 1, "enemy bar appears only with known HP and max")
	_check(not _has_text(named, "Wizard"), "player name is not floated over the avatar")
	session.player_stats.erase(29)
	feedback.refresh(session, world)
	session.player_stats[29] = 1 << 13
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(not _has_text(feedback.ui_diagnostics(), "Paralyzed"), "first condition word is a baseline, not a fake rising edge")
	session.player_stats[29] = 0
	feedback.refresh(session, world)
	session.player_stats[29] = 1 << 13
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(_has_text(feedback.ui_diagnostics(), "Paralyzed"), "named paralysis bit cues on a real rising edge")
	var count := 0
	for row in feedback.ui_diagnostics().regions:
		if str(row.text) == "Paralyzed":
			count += 1
	feedback.refresh(session, world)
	feedback._process(0.0)
	var still := 0
	for row in feedback.ui_diagnostics().regions:
		if str(row.text) == "Paralyzed":
			still += 1
	_check(still == count, "held status does not queue another label")
	session.player_stats[7] = 2
	feedback.refresh(session, world)
	feedback._process(0.0)
	_check(_has_text(feedback.ui_diagnostics(), "Level 2"), "verified level increase cues once")
	var label := _find_label(feedback, "-")
	if label == null:
		label = _find_label(feedback, "Level 2")
	if label is Label:
		_check((label as Label).get_theme_color("font_color") == Color("fc3436") or (label as Label).get_theme_color("font_color") == Color("efcf7a"), "label color comes from the frozen theme")
	var level := _find_label(feedback, "Level 2")
	_check(level is Label and (level as Label).get_theme_color("font_color") == Color("efcf7a"), "level cue uses gold")
	var goblin := _find_label(feedback, "Goblin")
	_check(goblin is Label and (goblin as Label).get_theme_color("font_color") == Color("ff3b4a"), "enemy name uses the enemy token")
	_free(feedback, session, world)

	world = _world()
	session = _session()
	feedback = _feedback()
	await process_frame
	world.entities[2].stats.erase(0)
	world.entities[2].stats.erase(1)
	feedback.refresh(session, world)
	_check(int(feedback.ui_diagnostics().state.bar_count) == 0, "unknown enemy HP draws no bar and no fake zero")
	_check(_has_text(feedback.ui_diagnostics(), "Goblin"), "name still shows when the descriptor exists")
	_free(feedback, session, world)


func _clamp_and_origin() -> void:
	var world := _world()
	var session := _session()
	var feedback := _feedback()
	await process_frame
	feedback.refresh(session, world)
	session.player_stats[1] = 80
	feedback.refresh(session, world)
	feedback._process(0.0)
	await process_frame
	var diag: Dictionary = feedback.ui_diagnostics()
	var player: Variant = world.entities[1]
	var pose: Vector2 = player.get_parent().to_global(player.display_position())
	var floater: Dictionary = _region_with(diag, "-20")
	_check(not floater.is_empty(), "verified player delta has a region")
	if not floater.is_empty():
		var rect := Rect2(float(floater.rect.x), float(floater.rect.y), float(floater.rect.w), float(floater.rect.h))
		_check(not rect.has_point(pose), "floater does not cover the display origin")
		var node := feedback.get_node_or_null("CombatFeedbackLayer/" + str(floater.id))
		_check(node is Control, "region id matches a live control")
		if node is Control:
			var live: Rect2 = (node as Control).get_global_rect()
			_check(is_equal_approx(live.position.x, float(floater.rect.x)), "region x is get_global_rect")
			_check(is_equal_approx(live.position.y, float(floater.rect.y)), "region y is get_global_rect")
			_check(is_equal_approx(live.size.x, float(floater.rect.w)), "region w is get_global_rect")
			_check(is_equal_approx(live.size.y, float(floater.rect.h)), "region h is get_global_rect")
			_check((node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "floater ignores the mouse")
			_check((node as Control).focus_mode == Control.FOCUS_NONE, "floater is not focusable")
	_free(feedback, session, world)

	world = _world()
	session = _session()
	feedback = _feedback()
	world.apply_update({"new_objects": [
		{"object_type": 900, "stats": {"id": 8, "position": {"x": 38.0, "y": 4.0}, "stats": {0: 20, 1: 20}}},
	]})
	await process_frame
	feedback.refresh(session, world)
	feedback._process(0.0)
	await process_frame
	var edge: Dictionary = feedback.ui_diagnostics()
	var name_row := _region_with(edge, "Goblin")
	# The edge goblin and the center goblin share the type name. Pick the clipped one.
	var clipped := false
	var inside := false
	var rail := 256.0
	var limit := float(edge.viewport.w) - rail - 8.0
	for row in edge.regions:
		if str(row.text) != "Goblin":
			continue
		if bool(row.clipped):
			clipped = true
			inside = float(row.rect.x) + float(row.rect.w) <= limit + 0.6
	_check(clipped, "edge name is marked clipped")
	_check(inside, "clipped name stays inside the playfield, off the rail")
	_check(not name_row.is_empty() or clipped, "a source name region exists")
	_free(feedback, session, world)


func _click_at(button: Button, at: Vector2) -> bool:
	var bag := {"hit": false}
	var on_down := func() -> void: bag["hit"] = true
	button.button_down.connect(on_down)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	root.push_input(press)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	release.button_mask = 0
	root.push_input(release)
	await process_frame
	if button.button_down.is_connected(on_down):
		button.button_down.disconnect(on_down)
	var hovered := root.gui_get_hovered_control()
	return bool(bag["hit"]) or hovered == button


func _input_and_diagnostics() -> void:
	var button := Button.new()
	button.position = Vector2(20, 220)
	button.size = Vector2(90, 28)
	button.text = "ping"
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(button)
	await process_frame
	var alone := await _click_at(button, Vector2(40, 232))
	_check(alone or DisplayServer.get_name() == "headless", "fixture click reaches a button before the overlay exists")
	var feedback := _feedback()
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var covered := await _click_at(button, Vector2(40, 232))
	if DisplayServer.get_name() == "headless":
		_check(feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "headless overlay ignores the mouse")
	else:
		_check(alone and covered, "overlay does not eat a click meant for a control under it")
	_check(feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "root control ignores the mouse")
	_check(feedback.focus_mode == Control.FOCUS_NONE, "root control takes no focus")
	var diag: Dictionary = feedback.ui_diagnostics()
	_check(str(diag.schema) == "gravebag.ui_diagnostics.v1", "schema name is v1")
	_check(diag.supported_actions.is_empty(), "supported actions stay empty")
	_check(diag.focus.traps_gameplay == false, "focus does not trap gameplay")
	_check(str(diag.focus.owner) == "", "nothing in the overlay is focused")
	_check(diag.viewport.w == 1280 and diag.viewport.h == 720, "viewport is the real window size")
	var again: Dictionary = feedback.ui_diagnostics()
	_check(int(again.state.floater_count) == int(diag.state.floater_count), "diagnostics read does not change cues")
	feedback.clear()
	_check(int(feedback.ui_diagnostics().state.floater_count) == 0, "clear drops cues and keeps the node")
	_check(is_instance_valid(feedback.get_node("CombatFeedbackLayer")), "clear keeps the layer")
	feedback.initialize()
	_check(feedback.get_child_count() == 1, "initialize is idempotent")
	button.queue_free()
	feedback.queue_free()


func _capture(capture_dir: String) -> void:
	var world := _world()
	var session := _session()
	var feedback := _feedback()
	await process_frame
	feedback.refresh(session, world)
	session.player_stats[1] = 80
	feedback.refresh(session, world)
	feedback._process(0.0)
	var sequence: Array = []
	var steps: Array = [0.0, 0.125, 0.25, 0.4]
	for index in steps.size():
		if float(steps[index]) > 0.0:
			feedback._process(float(steps[index]))
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		_check(not image.is_empty() and image.get_width() == 1280 and image.get_height() == 720, "capture frame is 1280x720")
		if image.is_empty():
			return
		var diag: Dictionary = feedback.ui_diagnostics()
		var path := capture_dir.path_join("combat-feedback-frame-%d.png" % index)
		_check(image.save_png(path) == OK, "capture frame saves")
		var alpha := 0.0
		var rise := 0.0
		if diag.motion.samples.size() > 0:
			alpha = float(diag.motion.samples[0].alpha)
			rise = float(diag.motion.samples[0].rise_px)
		var red := _red_in_floater(image, diag)
		print("FSOD COMBAT FEEDBACK FRAME: %dx%d age=%.3f alpha=%.3f rise=%.2f red=%s %s" % [image.get_width(), image.get_height(), float(diag.motion.integrated_s), alpha, rise, str(red), path])
		sequence.append({"frame": index, "alpha": alpha, "rise_px": rise, "red": red, "diagnostics": diag})
	_check(bool(sequence[0].red), "first rendered frame shows the damage color in the floater rect")
	_check(float(sequence[0].alpha) > float(sequence[2].alpha), "rendered sequence fades")
	var motion_path := capture_dir.path_join("combat-feedback-motion.json")
	var file := FileAccess.open(motion_path, FileAccess.WRITE)
	_check(file != null, "motion log opens")
	if file != null:
		file.store_string(JSON.stringify({"schema": "gravebag.ui_diagnostics.v1", "frames": sequence}))
		file.close()
	_free(feedback, session, world)


func _red_in_floater(image: Image, diag: Dictionary) -> bool:
	var row := _region_with(diag, "-20")
	if row.is_empty():
		return false
	var x0 := int(floor(float(row.rect.x)))
	var y0 := int(floor(float(row.rect.y)))
	var x1 := int(ceil(float(row.rect.x) + float(row.rect.w)))
	var y1 := int(ceil(float(row.rect.y) + float(row.rect.h)))
	for y in range(maxi(y0, 0), mini(y1, image.get_height())):
		for x in range(maxi(x0, 0), mini(x1, image.get_width())):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.72 and pixel.r > pixel.g + 0.25 and pixel.r > pixel.b + 0.25:
				return true
	return false


func _region_with(diag: Dictionary, text: String) -> Dictionary:
	for row in diag.regions:
		if str(row.text) == text or (text == "-" and str(row.text).begins_with("-")):
			return row
	return {}


func _find_label(feedback: Control, text: String) -> Label:
	var layer := feedback.get_node_or_null("CombatFeedbackLayer")
	if layer == null:
		return null
	for child in layer.get_children():
		if child is Label and (str(child.text) == text or (text == "-" and str(child.text).begins_with("-"))):
			return child
	return null


func _has_text(diag: Dictionary, text: String) -> bool:
	for row in diag.regions:
		if str(row.text) == text:
			return true
	return false


func _has_amount(diag: Dictionary) -> bool:
	for row in diag.regions:
		var text := str(row.text)
		if text.begins_with("-") or text.begins_with("+"):
			return true
	return false


func _free(a: Node, b: Node, c: Node) -> void:
	if is_instance_valid(a):
		a.free()
	if is_instance_valid(b):
		b.free()
	if is_instance_valid(c):
		c.free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD COMBAT FEEDBACK FAIL: " + description)
	assert(condition, description)
