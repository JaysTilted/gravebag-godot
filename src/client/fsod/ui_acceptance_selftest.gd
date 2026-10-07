# SPDX-License-Identifier: AGPL-3.0-only
# Baseline UI render/geometry/motion/input harness. Live world_view, inventory
# panel and realm guide only. No network, no profile, no entry, no slice HUD.
# Does not claim RotMG target quality. Optional modules are loaded only if the
# integrated tree actually contains them.
extends SceneTree

const World = preload("res://src/client/fsod/world_view.gd")
const Guide = preload("res://src/client/fsod/realm_guide.gd")
const Inventory = preload("res://src/client/fsod/inventory_panel.gd")
const UiTheme = preload("res://src/client/fsod/ui_theme.gd")
# Production Entry/World composition. Only account startup and profile writes
# are disabled in the fixture subclass; production refresh, handlers and signal
# connections are exercised unchanged. No backend/account/profile is opened.
class FixtureEntry extends "res://src/game/fsod_entry.gd":
	func _ready() -> void:
		set_process(false)
	func _save_profile() -> void:
		pass

const OPTIONAL: Array[String] = [
	"res://src/client/fsod/ui_theme.gd",
	"res://src/client/fsod/account_chrome.gd",
	"res://src/client/fsod/combat_feedback.gd",
	"res://src/client/fsod/item_tooltip.gd",
]
const MARGIN := 2.0
const RAIL := 256.0

var failures := 0
var checks := 0
var capture_dir := ""
var frames: Array = []
var gates: Dictionary = {}
var modules: Dictionary = {}
var diagnostics: Array = []
var regions: Array = []
var _owned: Array = []


class FixtureSession extends Node:
	var state: String = "playing"
	var player_id: int = 1
	var pending_position := Vector2(16, 11)
	var entity_states: Dictionary = {}
	var object_types: Dictionary = {}
	var metadata: Dictionary = {}
	var player_stats: Dictionary = {}
	var class_type: int = 782
	var character_id: int = -1
	var retries: int = 0
	var restarts: int = 0
	func retry_connection() -> Error:
		retries += 1
		return OK
	func restart_as_new_character() -> Error:
		restarts += 1
		return OK


func _initialize() -> void:
	# tests/run_all.sh launches every *selftest.gd with --headless and no
	# capture args. Headless has no viewport texture and hangs on window
	# resize. That runner is not render proof. Acceptance is the xvfb test.
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty():
		print("FSOD UI ACCEPTANCE SKIP: headless run_all is not render proof; use tests/layout.test.mjs")
		quit(0)
		return
	call_deferred("_run")


func _run() -> void:
	var report_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	if capture_dir.is_empty() or report_path.is_empty():
		push_error("FSOD UI ACCEPTANCE FAIL: need --capture-dir and --report")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	_scan_modules()
	await _set_viewport(1280, 720)
	_check(absf(_logical().x - 1280.0) <= 1.0 and absf(_logical().y - 720.0) <= 1.0, "logical viewport resized to 1280x720 (got %s)" % _logical())
	_static_contracts()
	await _capture_states()
	await _missing_stats()
	await _viewport_sweep()
	await _letterbox()
	await _temporal()
	await _minimap_invalidation()
	await _input_authority()
	await _optional_modules()
	_write_report(report_path)
	print("FSOD UI ACCEPTANCE TARGET: checks=%d failures=%d target_claimed=false" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _scan_modules() -> void:
	modules = {
		"world_view": "present",
		"inventory_panel": "present",
		"realm_guide": "present",
		"slice_hud": "excluded",
		"entry": "production_handlers_fixture_io_disabled",
	}
	for path in OPTIONAL:
		var rel: String = path.trim_prefix("res://")
		modules[rel.get_file().get_basename()] = "present" if FileAccess.file_exists(path) or ResourceLoader.exists(path) else "absent"


func _static_contracts() -> void:
	var small := Guide.clamp_label(Vector2(100, 100), Vector2(640, 360))
	_check(small.x >= 4.0 and small.y >= 84.0 and small.x <= 640.0 - RAIL, "640x360 clamp_label stays on screen")
	var mid := Guide.clamp_label(Vector2(1250, 400), Vector2(1280, 720))
	_check(mid.x <= 1280.0 - RAIL - 100.0 + 0.01, "1280x720 clamp_label stays left of the rail")
	var large := Guide.clamp_label(Vector2(1800, 900), Vector2(1920, 1080))
	_check(large.x <= 1920.0 - RAIL - 100.0 + 0.01 and large.y <= 1080.0 - 30.0 + 0.01, "1920x1080 clamp_label stays left of the rail")
	var center := World.new().desired_camera_position(Vector2.ZERO, Vector2(1280, 720))
	_check(is_equal_approx(center.x, (1280.0 - RAIL) / 2.0) and is_equal_approx(center.y, 360.0), "playfield center reserves the 256 rail")


func _capture_states() -> void:
	await _state_nexus()
	await _state_realm()
	await _state_combat()
	await _state_inventory(false)
	await _state_inventory(true)
	await _state_tooltip()
	await _state_session("offline")
	await _state_session("dead")


func _state_nexus() -> void:
	var built := await _build("Nexus", true, false, false)
	var session := _session("playing", built.world)
	built.guide.refresh(session, built.world)
	await process_frame
	_check(built.guide.is_guide_visible(), "Nexus playing shows the live guide")
	_check(built.guide.guide_direction_text().contains("Explore"), "Nexus guide text comes from the live overlay")
	_measure_rail(built.world, "nexus" if _logical() == Vector2(1280, 720) else "%dx%d" % [_logical().x, _logical().y], true)
	await _grab(built, "1280x720-nexus.png", "nexus", "apply_map Nexus + guide.refresh playing, no enemy")
	_release(built, session)


func _state_realm() -> void:
	var built := await _build("NexusPortal.Dragon", true, false, false)
	var session := _session("playing", built.world)
	built.guide.refresh(session, built.world)
	_check(not built.guide.is_guide_visible(), "realm map hides the Nexus guide")
	_check(built.guide.guide_direction_text() == "", "realm frame has no explore line")
	await _grab(built, "1280x720-realm.png", "realm", "apply_map NexusPortal.Dragon, guide.refresh, no projectile")
	_release(built, session)


func _state_combat() -> void:
	var built := await _build("NexusPortal.Dragon", true, true, false)
	_check(built.world.entities.has(2), "combat fixture spawned an enemy entity")
	_check(not built.world.projectiles.is_empty(), "combat fixture spawned a projectile")
	var session := _session("playing", built.world)
	built.guide.refresh(session, built.world)
	_check(not built.guide.is_guide_visible(), "combat realm does not show the Nexus guide")
	await _grab(built, "1280x720-combat.png", "combat", "apply_update enemy id 2 + apply_projectile owner 2")
	_release(built, session)


func _state_inventory(loot: bool) -> void:
	var built := await _build("Nexus", true, false, loot)
	var panel = built.world._inventory_panel
	_check(panel is Inventory, "live inventory panel is hosted by world_view")
	_check(panel._player_slots.size() >= 12, "live panel has the core slots")
	var visible_core := 0
	for slot in range(12):
		if panel._player_slots[slot].is_visible_in_tree():
			visible_core += 1
	_check(visible_core == 12, "core 12 slot nodes are visible flags")
	if loot:
		_check(panel._loot.visible, "nearby container opens the live loot section")
		await _grab(built, "1280x720-loot.png", "loot", "container within 1.5 tiles, set_snapshot via _refresh_rail")
	else:
		_check(not panel._loot.visible, "inventory state has no nearby bag")
		await _grab(built, "1280x720-inventory.png", "inventory", "player stats 8-19, no container in range")
	_release(built, null)


func _state_tooltip() -> void:
	var built := await _build("Nexus", true, false, true)
	var panel = built.world._inventory_panel
	var slot: Control = panel._player_slots[4]
	_check(slot.tooltip_text.contains("Health Potion"), "tooltip text is the live slot property")
	_check(slot.tooltip_text.contains("Double-click to use"), "tooltip keeps the consumable eligibility string")
	slot.grab_focus()
	await process_frame
	_check(slot.has_focus(), "inventory slot accepts focus")
	var motion := InputEventMouseMotion.new()
	motion.position = slot.get_global_rect().get_center()
	root.push_input(motion)
	if _logical() == Vector2(1280, 720):
		for i in 3:
			await _grab(built, "tooltip-fade-%d.png" % i, "tooltip-fade", "separate hover fade sample %d" % i)
	await create_timer(0.7).timeout
	_check(panel._tooltip.modulate.a >= 0.99, "tooltip legibility capture is fully settled")
	var hovered := root.gui_get_hovered_control()
	var tooltip_panel := false
	var node: Node = root
	var stack: Array = [root]
	while not stack.is_empty():
		node = stack.pop_back()
		if node is PopupPanel or String(node.name).to_lower().contains("tooltip"):
			if node is CanvasItem and (node as CanvasItem).visible:
				tooltip_panel = true
		for child in node.get_children():
			stack.append(child)
	frames.append({
		"note": "tooltip_panel_rendered",
		"value": tooltip_panel,
		"hovered": String(hovered.name) if hovered != null else "",
		"tooltip_text": slot.tooltip_text,
	})
	await _grab(built, "1280x720-tooltip.png", "tooltip", "live tooltip_text on Health Potion slot; engine popup recorded separately")
	_release(built, null)


func _state_session(mode: String) -> void:
	var built := await _build("Nexus", true, false, false)
	var session := _session(mode, built.world)
	built.guide.refresh(session, built.world)
	_check(not built.guide.is_guide_visible(), "%s hides the guide" % mode)
	var diag: Dictionary = built.world.ui_diagnostics()
	var hp_line: String = str(diag.bars.hp.displayed)
	_check(_region(diag, "hp").get("visible", false), "%s still shows the live HP bar" % mode)
	var file := "1280x720-death.png" if mode == "dead" else "1280x720-offline.png"
	var state := "death" if mode == "dead" else "offline"
	if mode == "dead":
		_check(hp_line == "0 / 100", "death shows authoritative HP 0, not a stand-in banner (%s)" % hp_line)
	_present_fixture(built, session)
	await process_frame
	_check(_visible_button_text(built.chrome) == ("New character" if mode == "dead" else "Reconnect"), "composed %s chrome action" % mode)
	var action := "new_character" if mode == "dead" else "reconnect"
	_check(built.entry.ui_diagnostics().actions == [action], "production Entry advertises the actual %s action" % action)
	_check(not built.entry._status.visible and not built.entry._action.visible and built.entry._action.disabled, "production Entry hides and disables legacy controls")
	await _grab(built, file, state, "session.state=%s via production Entry state/READY/refresh handlers; profile IO disabled" % mode)
	_press_visible_button(built.chrome)
	_press_visible_button(built.chrome)
	_check(session.restarts == (1 if mode == "dead" else 0) and session.retries == (1 if mode == "offline" else 0), "composed production signal routes one action to the fixture session")
	_release(built, session)


func _viewport_sweep() -> void:
	for size in [Vector2i(800, 600), Vector2i(640, 360), Vector2i(1920, 1080)]:
		var measured := await _set_viewport(size.x, size.y)
		_check(absf(measured.logical.w - float(size.x)) <= 1.0 and absf(measured.logical.h - float(size.y)) <= 1.0, "logical viewport is %d x %d" % [size.x, size.y])
		await _capture_states() # All eight states at every short/large logical size.


func _letterbox() -> void:
	var measured := await _set_viewport(1280, 720, Vector2i(1920, 1080))
	_check(absf(measured.logical.w - 1280.0) <= 1.0 and absf(measured.logical.h - 720.0) <= 1.0, "letterbox keeps logical 1280x720")
	_check(measured.window.w >= 1900.0 and measured.window.h >= 1060.0, "letterbox window is the physical 1920x1080 size")
	var built := await _build("Nexus", true, false, false)
	_measure_rail(built.world, "letterbox-1280", true)
	var frame := await _grab(built, "letterbox-1920x1080.png", "nexus", "window 1920x1080, content scale 1280x720 keep", true)
	frame["letterbox"] = true
	frame["viewport"] = measured
	_gate("letterbox_not_larger_hud", true, measured)
	_release(built, null)


func _temporal() -> void:
	await _set_viewport(1280, 720)
	var built := await _build("NexusPortal.Dragon", true, true, false)
	var world = built.world
	await create_timer(0.6).timeout # Settle chrome before measured, no-wait temporal steps.
	world._camera_ready = true
	world._camera_hold_auth = false
	var player = world._player()
	_check(player != null, "temporal sample has a player")
	var target: Vector2 = world.desired_camera_position(player.position, _logical())
	world._world.position = target + Vector2(140, 36)
	world.apply_tick({"tick_time": 100, "tick_id": 2, "update_statuses": [{"id": 1, "stats": {1: 40, 4: 20, 6: 30}}]})
	var deltas: Array = []
	var positions: Array = []
	var files: Array = []
	var bar_samples: Array = []
	var prior: Dictionary = world.ui_diagnostics().bars
	for i in 4:
		var delta := 1.0 / 60.0
		var started := Time.get_ticks_usec()
		world.advance_camera_display(delta)
		world._hud.advance_display(delta)
		var current: Dictionary = world.ui_diagnostics().bars
		for kind in ["hp", "mp", "xp"]:
			var fill_target := float(current[kind].value) / float(current[kind].max)
			var previous := float(prior[kind].interpolated)
			var shown := float(current[kind].interpolated)
			_check(shown >= minf(previous, fill_target) - 0.0001 and shown <= maxf(previous, fill_target) + 0.0001 and absf(shown - previous) > 0.00001, "%s fill eases monotonically between source and prior frame" % kind)
		_check(current.hp.displayed == "40 / 100" and current.mp.displayed == "20 / 100" and current.xp.displayed == "30 / 50", "stat captions jump to tick source")
		bar_samples.append(current)
		prior = current
		if world.entities.has(2):
			world.entities[2].advance_presentation(delta)
		deltas.append(delta)
		positions.append(world._world.position.x)
		var frame := await _grab(built, "temporal-%d.png" % i, "combat", "advance_camera_display + advance_presentation delta=1/60")
		files.append(frame.file)
		var elapsed := Time.get_ticks_usec() - started
		_check(elapsed < 500000, "temporal step did not insert a multi-frame delay")
	var moved := absf(float(positions[3]) - float(positions[0])) > 1.0
	_check(moved, "render-rate camera sample moved the display (%.2f -> %.2f)" % [positions[0], positions[3]])
	var hz := 60.0
	_gate("render_rate_samples", moved, {"deltas": deltas, "files": files, "sample_hz": hz, "positions": positions, "bars": bar_samples, "derived_from": "harness 1/60 steps, not a UI constant"})
	_release(built, null)


func _minimap_invalidation() -> void:
	await _set_viewport(1280, 720)
	var built := await _build("Nexus", true, false, false)
	var world = built.world
	var draws := {"n": 0}
	world._hud._minimap_box.draw.connect(func() -> void: draws.n += 1)
	world._redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var before := await _crop_minimap(world, "minimap-before.png")
	var draws_before: int = draws.n
	# Real tile path: apply_update bumps the revision the HUD cache keys on.
	world.apply_update({"tiles": [{"x": 14, "y": 9, "tile": 3}, {"x": 15, "y": 9, "tile": 3}, {"x": 14, "y": 10, "tile": 3}]})
	world._redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var after := await _crop_minimap(world, "minimap-after.png")
	var changed: bool = before.checksum != after.checksum and not str(before.checksum).is_empty() and not str(after.checksum).is_empty()
	_check(changed, "minimap pixels change after a tile write and redraw")
	_gate("minimap_invalidates_on_tile_change", changed, {"before": before, "after": after, "draws_after_tile": draws.n - draws_before})
	var physics_draws := 0
	draws.n = 0
	world.advance_visuals(1.0 / 60.0)
	await process_frame
	physics_draws = draws.n
	_gate("minimap_cache_skips_unchanged_physics", physics_draws == 0, {"draws_on_advance_visuals": physics_draws, "note": "measured; unmet means the live rail still redraws from the physics path"})
	_release(built, null)


func _input_authority() -> void:
	await _set_viewport(1280, 720)
	var built := await _build("Nexus", true, false, true)
	var world = built.world
	var panel = world._inventory_panel
	var swaps: Array = []
	var uses: Array = []
	var shots: Array = []
	var potions: Array = []
	var interacts: Array = []
	var abilities: Array = []
	world.inventory_swap_requested.connect(func(a: int, b: int, c: int, d: int) -> void: swaps.append([a, b, c, d]))
	world.item_use_requested.connect(func(slot: int) -> void: uses.append(slot))
	world.shoot_requested.connect(func(angle: float) -> void: shots.append(angle))
	world.potion_requested.connect(func(kind: String) -> void: potions.append(kind))
	world.interact_requested.connect(func(entity: int, slot: int) -> void: interacts.append(entity))
	world.ability_requested.connect(func(position: Vector2) -> void: abilities.append(position))
	var before_item: int = panel._item(false, 0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var started := Time.get_ticks_usec()
	panel._player_slots[0]._gui_input(click)
	panel._player_slots[4]._gui_input(click)
	var swap_us := Time.get_ticks_usec() - started
	_check(swaps.size() == 1, "two live clicks emit one swap through world_view")
	_check(swap_us < 20000, "swap is synchronous (no cosmetic delay), %d us" % swap_us)
	_check(panel._item(false, 0) == before_item, "swap does not mutate the local item")
	click.double_click = true
	started = Time.get_ticks_usec()
	panel._player_slots[4]._gui_input(click)
	var use_us := Time.get_ticks_usec() - started
	_check(uses == [4], "double-click consumable emits use once")
	_check(use_us < 20000, "use is synchronous, %d us" % use_us)
	var rail_click := InputEventMouseButton.new()
	rail_click.button_index = MOUSE_BUTTON_LEFT
	rail_click.pressed = true
	rail_click.position = world._rail.get_global_rect().get_center()
	root.push_input(rail_click)
	await process_frame
	_check(shots.is_empty(), "rail click does not emit shoot")
	var field := InputEventMouseButton.new()
	field.button_index = MOUSE_BUTTON_LEFT
	field.pressed = true
	field.position = Vector2(80, 80)
	started = Time.get_ticks_usec()
	root.push_input(field)
	var shoot_us := Time.get_ticks_usec() - started
	_check(shots.size() == 1, "playfield click emits shoot")
	_check(shoot_us < 20000, "shoot has no added delay, %d us" % shoot_us)
	world.interaction_target_id = 9
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	started = Time.get_ticks_usec()
	root.push_input(key)
	var interact_us := Time.get_ticks_usec() - started
	_check(interacts == [9], "E emits interact immediately")
	_check(interact_us < 20000, "E has no cosmetic delay, %d us" % interact_us)
	key.keycode = KEY_F
	key.physical_keycode = KEY_F
	root.push_input(key)
	_check(potions == ["health"], "F emits the health potion request immediately")
	var select := InputEventMouseButton.new()
	select.button_index = MOUSE_BUTTON_LEFT
	select.pressed = true
	panel._player_slots[0]._gui_input(select)
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	panel._player_slots[4]._gui_input(enter)
	_check(swaps.size() == 2, "Enter still activates a focused swap")
	panel._player_slots[4].grab_focus()
	await process_frame
	var space := InputEventKey.new()
	space.pressed = true
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	root.push_input(space)
	await process_frame
	var space_reaches: bool = abilities.size() == 1
	_gate("space_passthrough_while_slot_focused", space_reaches, {"ability_signals": abilities.size(), "owner": "inventory writer"})
	_gate("input_authority", true, {"swap_us": swap_us, "use_us": use_us, "shoot_us": shoot_us, "interact_us": interact_us})
	_release(built, null)


func _optional_modules() -> void:
	await _set_viewport(1280, 720)
	await _theme_probe()
	await _chrome_probe()
	await _feedback_probe()
	_tooltip_module_probe()


func _theme_probe() -> void:
	var path := "res://src/client/fsod/ui_theme.gd"
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_gate("theme_tokens", false, {"status": "not_integrated"})
		_gate("inventory_host_rect", false, {"status": "not_integrated"})
		return
	var script: Script = load(path)
	_check(script != null, "ui_theme.gd loads")
	if script == null:
		return
	var tokens: Dictionary = {}
	if script.has_method("tokens"):
		var raw: Variant = script.call("tokens")
		if raw is Dictionary:
			tokens = raw
	_gate("theme_tokens", not tokens.is_empty(), {"present": not tokens.is_empty(), "keys": tokens.keys()})
	if script.has_method("inventory_host_rect"):
		var built := await _build("Nexus", true, false, false)
		var rail: Control = built.world._rail
		var panel: Control = built.world._inventory_panel
		var host: Variant = script.call("inventory_host_rect", rail.size)
		var relative := Rect2(panel.get_global_rect().position - rail.get_global_rect().position, panel.get_global_rect().size)
		var matched := false
		if host is Rect2:
			matched = relative.position.distance_to((host as Rect2).position) <= 2.0 and relative.size.distance_to((host as Rect2).size) <= 2.0
			_gate("inventory_host_rect", matched, {"function": _rect(host), "measured": _rect(relative), "hardcoded": false})
		else:
			_gate("inventory_host_rect", false, {"status": "unexpected_return"})
		_release(built, null)
	else:
		_gate("inventory_host_rect", false, {"status": "method_absent"})


func _chrome_probe() -> void:
	var path := "res://src/client/fsod/account_chrome.gd"
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_gate("chrome_ready_hides", false, {"status": "not_integrated"})
		_gate("chrome_actions_once", false, {"status": "not_integrated"})
		return
	var script: Script = load(path)
	var chrome = script.new()
	_own(chrome)
	await process_frame
	_consume_diagnostics(chrome, "account_chrome")
	if chrome.has_method("refresh"):
		chrome.refresh({"state": "playing", "ready": true, "status": "GRAVEBAG", "character_name": "Proof"})
		await process_frame
		_check(_visible_button_text(chrome) == "", "READY playing hides the blocking action")
		_gate("chrome_ready_hides", _visible_button_text(chrome) == "", {"button": _visible_button_text(chrome)})
		var created: Array = []
		var reconnected: Array = []
		if chrome.has_signal("new_character_requested"):
			chrome.new_character_requested.connect(func() -> void: created.append(1))
		if chrome.has_signal("reconnect_requested"):
			chrome.reconnect_requested.connect(func() -> void: reconnected.append(1))
		chrome.refresh({"state": "dead", "ready": false, "status": "YOU DIED"})
		await process_frame
		_press_visible_button(chrome)
		_press_visible_button(chrome)
		chrome.refresh({"state": "offline", "ready": false, "status": "offline"})
		await process_frame
		_press_visible_button(chrome)
		_press_visible_button(chrome)
		var once: bool = created.size() == 1 and reconnected.size() == 1
		_check(once, "chrome emits each genuine action once")
		_gate("chrome_actions_once", once, {"new_character": created.size(), "reconnect": reconnected.size()})
		var dead_diag: Dictionary = chrome.ui_diagnostics() if chrome.has_method("ui_diagnostics") else {}
		_bounds_skip_hidden(dead_diag, "account_chrome")
	chrome.queue_free()


func _feedback_probe() -> void:
	var path := "res://src/client/fsod/combat_feedback.gd"
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_gate("feedback_no_false_first_damage", false, {"status": "not_integrated"})
		_gate("feedback_no_commands", false, {"status": "not_integrated"})
		return
	var script: Script = load(path)
	var feedback = script.new()
	_own(feedback)
	await process_frame
	if feedback is CanvasLayer:
		_gate("feedback_layer_80", int(feedback.layer) == 80, {"layer": feedback.layer})
	var banned := ["shoot_requested", "move_requested", "interact_requested", "ability_requested", "potion_requested", "inventory_swap_requested", "item_use_requested"]
	var leaked: Array = []
	for entry in feedback.get_signal_list():
		if banned.has(String(entry.name)):
			leaked.append(String(entry.name))
	_check(leaked.is_empty(), "feedback exposes no gameplay command signals")
	_gate("feedback_no_commands", leaked.is_empty(), {"leaked": leaked})
	if feedback.has_method("initialize"):
		feedback.initialize()
	var world_built := await _build("Nexus", true, true, false)
	var session := _session("playing", world_built.world)
	session.player_stats = {0: 100, 1: 80, 5: 50, 6: 10, 7: 4}
	var first := _feedback_count(feedback)
	if feedback.has_method("refresh"):
		feedback.refresh(session, world_built.world)
		await process_frame
	var after_first := _feedback_count(feedback)
	var observable: bool = first >= 0 and after_first >= 0
	if observable:
		var clean := after_first <= first
		_check(clean, "first feedback snapshot does not invent damage")
		_gate("feedback_no_false_first_damage", clean, {"before": first, "after": after_first})
		session.player_stats = {0: 100, 1: 80, 5: 50, 6: 10, 7: 4}
		world_built.world.apply_map({"width": 40, "height": 30, "name": "NexusPortal.Cube"})
		if feedback.has_method("clear"):
			feedback.clear()
		if feedback.has_method("refresh"):
			feedback.refresh(session, world_built.world)
		await process_frame
		var after_reset := _feedback_count(feedback)
		_gate("feedback_map_reset_clean", after_reset <= 0 or after_reset <= after_first, {"after_reset": after_reset})
	else:
		_gate("feedback_no_false_first_damage", false, {"status": "not_observable"})
		_gate("feedback_map_reset_clean", false, {"status": "not_observable"})
	_consume_diagnostics(feedback, "combat_feedback")
	_release(world_built, session)
	feedback.queue_free()


func _tooltip_module_probe() -> void:
	var path := "res://src/client/fsod/item_tooltip.gd"
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_gate("item_tooltip_module", false, {"status": "not_integrated"})
		return
	var script: Script = load(path)
	var tip = script.new()
	_own(tip)
	await process_frame
	_consume_diagnostics(tip, "item_tooltip")
	_gate("item_tooltip_module", true, {"loaded": true})
	tip.queue_free()


func _build(map_name: String, player: bool, combat: bool, loot: bool) -> Dictionary:
	var world = World.new()
	_own(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.set_descriptors(_descriptors())
	world.set_player_id(1)
	var cells: Array = []
	for y in 8:
		for x in 12:
			cells.append({"x": x + 10, "y": y + 8, "tile": 1 if (x + y) % 5 else 2})
	world.apply_map({"width": 48, "height": 36, "name": map_name})
	var objects: Array = []
	if player:
		var stats := _player_stats()
		if map_name == "death-pending":
			stats[1] = 0
		objects.append({"object_type": 782, "stats": {"id": 1, "position": {"x": 16.0, "y": 11.0}, "stats": stats}})
	if combat:
		objects.append({"object_type": 500, "stats": {"id": 2, "position": {"x": 20.0, "y": 11.0}, "stats": {0: 40, 1: 40}}})
	if loot:
		objects.append({"object_type": 400, "stats": {"id": 40, "position": {"x": 16.4, "y": 11.0}, "stats": {8: 2594, 9: -1, 10: -1, 11: -1, 12: -1, 13: -1, 14: -1, 15: -1}}})
	world.apply_update({"tiles": cells, "new_objects": objects})
	if combat:
		world.apply_projectile({"owner_id": 2, "bullet_id": 3, "position": {"x": 20.0, "y": 11.0}, "angle": 3.1, "speed": 80, "lifetime_ms": 1200, "bullet_type": 0})
	world._hud.set_process(false)
	for _i in 20:
		world._hud.advance_display(0.05)
	var session := _session("playing", world)
	var entry := FixtureEntry.new()
	_own(entry)
	entry.session = session
	entry._frontend = world
	entry._status = Label.new()
	entry._action = Button.new()
	entry.add_child(entry._status)
	entry.add_child(entry._action)
	entry._realm_guide = Guide.new()
	entry.add_child(entry._realm_guide)
	entry._attach_optional_hosts()
	var built := {"world": world, "entry": entry, "guide": entry._realm_guide, "chrome": entry._account_chrome, "feedback": entry._combat_feedback, "session": session}
	_check(built.chrome != null and built.feedback != null, "production Entry attaches delivered chrome and feedback")
	_present_fixture(built, session)
	await process_frame
	await process_frame
	return built


func _present_fixture(built: Dictionary, session: FixtureSession) -> void:
	built.entry.session = session
	built.entry._on_state(session.state)
	if session.state == "playing":
		built.entry._on_packet_readback(0, {}) # Existing READY predicate, not a fixture pass flag.
	built.entry._process(1.0 / 60.0) # Real readonly snapshot and feedback refresh paths.


func _session(mode: String, world) -> FixtureSession:
	var session := FixtureSession.new()
	_own(session)
	session.state = "dead" if mode == "dead" else ("offline" if mode == "offline" else "playing")
	session.pending_position = Vector2(16, 11)
	session.metadata = {"objects": {"1810": {"name": "Nexus Portal", "class": "Portal"}}}
	session.player_stats = _player_stats()
	if mode == "dead":
		session.player_stats[1] = 0
		world.apply_tick({"tick_time": 100, "tick_id": 1, "update_statuses": [{"id": 1, "stats": {1: 0}}]})
	return session


func _player_stats() -> Dictionary:
	var stats := {0: 100, 1: 80, 3: 100, 4: 40, 5: 50, 6: 12, 7: 4, 20: 25, 21: 5, 22: 30, 26: 20, 27: 30, 28: 32, 48: 5, 53: 2, 57: 3, 69: 2, 70: 1}
	for slot in range(12):
		stats[8 + slot] = -1
	stats[8] = 2711
	stats[12] = 2594
	return stats


func _descriptors() -> Dictionary:
	return {
		"objects": {
			782: {"kind": "player", "name": "Wizard", "class": "Player", "player": true},
			500: {"kind": "enemy", "name": "Pirate", "class": "Enemy", "enemy": true, "projectiles": [{"bullet_type": 0, "speed": 80, "lifetime_ms": 1200}]},
			400: {"kind": "container", "name": "Brown Bag", "class": "Container"},
			1810: {"kind": "portal", "name": "Nexus Portal", "class": "Portal"},
		},
		"tiles": {1: {"color": "#354c40"}, 2: {"color": "#6a7a3a"}},
		"items": {
			"2711": {"ObjectId": "Energy Staff", "SlotType": 17, "Usable": false},
			"2594": {"ObjectId": "Health Potion", "Consumable": true, "Potion": true, "Usable": false},
		},
	}


func _measure_rail(world, tag: String, require_flush: bool) -> void:
	var rail: Control = world._rail
	var rect := rail.get_global_rect()
	var vp := _logical()
	var flush := absf(rect.end.x - vp.x) <= 1.0
	var width_ok := absf(rect.size.x - RAIL) <= 1.0
	var left_ok := rect.position.x >= -0.5
	_check(rect.size.x > 8.0 and rect.size.y > 8.0, "%s rail has a real laid-out rect (%s)" % [tag, rect])
	_check(left_ok, "%s rail left edge is on screen (%s)" % [tag, rect])
	if require_flush:
		_gate("rail_offset_256", is_equal_approx(rail.offset_left, -RAIL), {"offset_left": rail.offset_left, "laid_out_width": rect.size.x})
	var center: Vector2 = world.desired_camera_position(Vector2.ZERO, vp)
	var center_ok := is_equal_approx(center.x, maxf(0.0, vp.x - RAIL) / 2.0)
	_gate("rail_%s" % tag, flush and width_ok and left_ok and center_ok, {"rect": _rect(rect), "viewport": {"w": vp.x, "h": vp.y}, "flush": flush, "width": rect.size.x, "center_x": center.x})
	_push_region("dock", rail, false, "world_view")
	var hud = world._hud
	_gate("hud_host_no_overlap_%s" % tag, hud._stats_box.get_global_rect().end.y <= hud._host.get_global_rect().position.y, {"stats": _rect(hud._stats_box.get_global_rect()), "host": _rect(hud._host.get_global_rect())})
	_push_region("identity", hud._identity, true, "hud_panel")
	_push_region("minimap", hud._minimap_box, true, "hud_panel")
	_push_region("potions", hud._potions, true, "hud_panel")
	var diag: Dictionary = world.ui_diagnostics()
	var potion_region := _region(diag, "potions")
	# Fixture wire stats 69=2, 70=1: both counts must render in a visible, unclipped potion strip.
	var potions: bool = bool(potion_region.get("visible", false)) and not bool(potion_region.get("clipped", true)) and str(potion_region.get("text", "")).contains("2") and str(potion_region.get("text", "")).contains("1") and int(potion_region.get("icons", 0)) == 2
	if tag == "nexus" or tag == "1280x720":
		_gate("potions_69_70_displayed", potions, {"region": potion_region})
		var bars_ok := true
		var fits: Dictionary = {}
		for id in ["hp", "mp", "xp"]:
			var r := _region(diag, id)
			fits[id] = r.get("text_fit", {})
			var fit: Dictionary = r.get("text_fit", {})
			if not bool(r.get("visible", false)) or bool(r.get("clipped", true)) or float(fit.get("font_size", 0)) < 12.0 or float(r.rect.h) < float(fit.get("line_height", 999.0)):
				bars_ok = false
		_gate("bars_readable_unclipped", bars_ok, {"fits": fits})
		var stats_region := _region(diag, "stats")
		_gate("six_stats_rows", bool(stats_region.get("visible", false)) and not bool(stats_region.get("clipped", true)) and str(stats_region.get("text", "")).split("\n").size() >= 6, {"region": stats_region})
		var mm := _region(diag, "minimap")
		_gate("minimap_readable", bool(mm.get("visible", false)) and float(mm.rect.w) >= 200.0 and float(mm.rect.h) >= 96.0, {"region": mm})
	_measure_core(world, tag)
	var essential := _essential_violations(world)
	if tag == "nexus":
		_gate("essential_inner_2px_1280", essential.is_empty(), {"violations": essential, "margin": MARGIN, "dock_excluded": true})


func _measure_core(world, tag: String) -> void:
	var panel = world._inventory_panel
	var scroll := _find_scroll(world._rail)
	var outside: Array = []
	var scroll_y := 0
	if scroll != null:
		scroll_y = scroll.scroll_vertical
	for slot in range(12):
		var tile: Control = panel._player_slots[slot]
		var rect := tile.get_global_rect()
		var vp := _logical()
		var past := rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > vp.x + 1.0 or rect.end.y > vp.y + 1.0
		var scrolled := false
		var ancestor := tile.get_parent()
		while ancestor != null:
			if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().grow(0.5).encloses(rect):
				scrolled = true
			ancestor = ancestor.get_parent()
		if not tile.is_visible_in_tree():
			scrolled = true
		if scroll != null:
			var visible := scroll.get_global_rect()
			scrolled = scrolled or rect.end.y > visible.end.y + 1.0 or rect.position.y < visible.position.y - 1.0
		if past or scrolled:
			outside.append({"slot": slot, "rect": _rect(rect), "scrolled": scrolled})
	var met := outside.is_empty() and scroll_y == 0
	_gate("core_4_plus_8_%s" % tag, met, {"outside": outside, "scroll_vertical": scroll_y, "tag": tag})


func _essential_violations(world) -> Array:
	var vp := _logical()
	var bad: Array = []
	var controls: Array = [world._hud._identity, world._hud._minimap_box, world._hud._potions]
	for kind in ["hp", "mp", "xp"]:
		controls.append(world._hud._bars[kind])
	for slot in range(4):
		controls.append(world._inventory_panel._player_slots[slot])
	for control in controls:
		if not control is Control or not (control as Control).is_visible_in_tree():
			continue
		var rect: Rect2 = (control as Control).get_global_rect()
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			bad.append({"name": String(control.name), "reason": "empty"})
			continue
		var inside := rect.position.x >= MARGIN - 0.5 and rect.position.y >= MARGIN - 0.5 and rect.end.x <= vp.x - MARGIN + 0.5 and rect.end.y <= vp.y - MARGIN + 0.5
		if not inside:
			bad.append({"name": String(control.name), "rect": _rect(rect)})
		elif control is Label and UiTheme.text_overflows(control):
			bad.append({"name": String(control.name), "reason": "text overflows", "fit": UiTheme.text_fit(control)})
	return bad


func _missing_stats() -> void:
	await _set_viewport(1280, 720)
	var built := await _build("Awaiting server", false, false, false)
	var diag: Dictionary = built.world.ui_diagnostics()
	var shown: bool = str(diag.bars.hp.displayed) == "—" and str(diag.bars.mp.displayed) == "—" and str(diag.bars.xp.displayed) == "—" and float(diag.bars.xp.interpolated) == 0.0
	_check(shown, "absent stats render an em dash, not a guessed number")
	_gate("missing_stat_emdash", shown, {"bars": diag.bars})
	_release(built, null)


func _grab(built: Dictionary, file: String, state: String, source: String, allow_scale: bool = false) -> Dictionary:
	if file.begins_with("1280x720-"):
		file = "%dx%d-%s" % [_logical().x, _logical().y, file.trim_prefix("1280x720-")]
	if state != "tooltip-fade" and not file.begins_with("temporal-"):
		await create_timer(0.6).timeout # Fully settled chrome/tooltip legibility, separate from fade samples.
		var surface: Control = built.chrome.get_node("AccountChromePanel" if built.entry.session.state in ["dead", "offline"] else "AccountReadyStatus")
		_check(surface.modulate.a >= 0.99, "%s composed chrome fully settled" % file)
	_measure_core(built.world, "%dx%d" % [_logical().x, _logical().y])
	var header = built.world._hud
	_gate("identity_fame_nonoverlap", not header._identity.get_global_rect().intersects(header._fame.get_global_rect()) and not UiTheme.text_overflows(header._identity) and not UiTheme.text_overflows(header._fame), {"name": {"rect": _rect(header._identity.get_global_rect()), "text": header._identity.text, "fit": UiTheme.text_fit(header._identity)}, "fame": {"rect": _rect(header._fame.get_global_rect()), "text": header._fame.text, "fit": UiTheme.text_fit(header._fame)}})
	var current_diag: Dictionary = built.world.ui_diagnostics()
	for region: Dictionary in current_diag.regions:
		if bool(region.get("visible", false)):
			_check(not bool(region.get("clipped", true)), "%s %s actual region %s is unclipped" % [file, state, region.id])
	await process_frame
	await RenderingServer.frame_post_draw
	if state == "nexus":
		var guide = built.guide
		var style: StyleBoxFlat = guide._panel.get_theme_stylebox("panel")
		_gate("guide_charcoal_compact", style.bg_color.is_equal_approx(UiTheme.CHARCOAL) and guide._panel.size.y <= guide._direction_label.size.y + 9.0, {"color": style.bg_color.to_html(false), "panel": _rect(guide._panel.get_global_rect()), "direction": _rect(guide._direction_label.get_global_rect()), "text": guide._direction_label.text})
	var image := await _viewport_image()
	var path := capture_dir.path_join(file)
	_check(image != null and not image.is_empty(), "viewport texture for %s" % file)
	if image == null or image.is_empty():
		return {}
	_check(image.save_png(path) == OK, "save %s" % file)
	var colors := _sample_colors(image)
	_check(colors >= 4, "%s is a rendered frame (%d sampled colors)" % [file, colors])
	var logical := _logical()
	var window := DisplayServer.window_get_size()
	var frame := {
		"file": file,
		"state": state,
		"state_source": source,
		"logical_w": logical.x,
		"logical_h": logical.y,
		"png_w": image.get_width(),
		"png_h": image.get_height(),
		"window_w": window.x,
		"window_h": window.y,
		"sample_colors": colors,
		"transform": _transform(),
		"diagnostics": {"entry": built.entry.ui_diagnostics(), "world": built.world.ui_diagnostics(), "chrome": built.chrome.ui_diagnostics(), "feedback": built.feedback.ui_diagnostics()},
	}
	if not allow_scale:
		_check(absf(float(image.get_width()) - logical.x) <= 2.0 and absf(float(image.get_height()) - logical.y) <= 2.0, "%s png matches logical viewport" % file)
	frames.append(frame)
	return frame


func _crop_minimap(world, file: String) -> Dictionary:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := await _viewport_image()
	if image == null or image.is_empty():
		return {"checksum": "", "file": file}
	var rect: Rect2 = world._hud._minimap_box.get_global_rect()
	var scale := _pixel_scale(image)
	var origin := _pixel_origin()
	var pixel := Rect2i(Vector2i(origin + rect.position * scale), Vector2i(rect.size * scale))
	pixel.position.x = clampi(pixel.position.x, 0, image.get_width() - 1)
	pixel.position.y = clampi(pixel.position.y, 0, image.get_height() - 1)
	pixel.size.x = clampi(pixel.size.x, 1, image.get_width() - pixel.position.x)
	pixel.size.y = clampi(pixel.size.y, 1, image.get_height() - pixel.position.y)
	var crop := image.get_region(pixel)
	var path := capture_dir.path_join(file)
	crop.save_png(path)
	return {"checksum": _checksum(crop), "file": file, "rect": _rect(rect), "pixel": {"x": pixel.position.x, "y": pixel.position.y, "w": pixel.size.x, "h": pixel.size.y}}


func _viewport_image() -> Image:
	for _i in 3:
		var tex := root.get_texture()
		if tex != null:
			var image := tex.get_image()
			if image != null and not image.is_empty():
				return image
		await process_frame
		await RenderingServer.frame_post_draw
	return null


func _set_viewport(w: int, h: int, window_override: Vector2i = Vector2i.ZERO) -> Dictionary:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	var window_size := Vector2i(w, h) if window_override == Vector2i.ZERO else window_override
	root.size = window_size
	DisplayServer.window_set_size(window_size)
	await process_frame
	await process_frame
	var logical := _logical()
	var window := DisplayServer.window_get_size()
	return {
		"logical": {"w": logical.x, "h": logical.y},
		"window": {"w": window.x, "h": window.y},
		"content_scale": {"w": w, "h": h},
		"transform": _transform(),
	}


func _logical() -> Vector2:
	var size := root.get_visible_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return Vector2(root.size)
	return size


func _transform() -> Dictionary:
	var screen := root.get_screen_transform()
	var scale := screen.get_scale()
	return {
		"origin": [screen.origin.x, screen.origin.y],
		"scale": [scale.x, scale.y],
		"coordinate_space": "viewport",
	}


func _pixel_scale(image: Image) -> Vector2:
	var logical := _logical()
	if logical.x < 1.0 or logical.y < 1.0:
		return Vector2.ONE
	return Vector2(float(image.get_width()) / logical.x, float(image.get_height()) / logical.y)


func _pixel_origin() -> Vector2:
	var screen := root.get_screen_transform()
	return screen.origin


func _sample_colors(image: Image) -> int:
	var seen := {}
	var step_x := maxi(1, image.get_width() / 24)
	var step_y := maxi(1, image.get_height() / 24)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			seen[image.get_pixel(x, y).to_html(false)] = true
	return seen.size()


func _checksum(image: Image) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(image.get_data())
	return ctx.finish().hex_encode()


func _consume_diagnostics(node: Node, module: String) -> void:
	if node == null or not node.has_method("ui_diagnostics"):
		diagnostics.append({"module": module, "status": "absent"})
		return
	var raw: Variant = node.call("ui_diagnostics")
	if not raw is Dictionary:
		_check(false, "%s ui_diagnostics did not return a Dictionary" % module)
		return
	var payload: Dictionary = raw
	_check(String(payload.get("schema", "")) == "gravebag.ui_diagnostics.v1", "%s diagnostics schema" % module)
	var vp: Variant = payload.get("viewport", {})
	if vp is Dictionary:
		var logical := _logical()
		_check(absf(float(vp.get("w", -1)) - logical.x) <= 1.0 and absf(float(vp.get("h", -1)) - logical.y) <= 1.0, "%s diagnostics viewport matches get_visible_rect" % module)
	if String(payload.get("coordinate_space", "viewport")) != "viewport":
		_check(false, "%s coordinate_space must be viewport" % module)
	_bounds_skip_hidden(payload, module)
	payload["module"] = module
	payload["source"] = "production"
	diagnostics.append(payload)


func _bounds_skip_hidden(payload: Dictionary, module: String) -> void:
	if payload.is_empty():
		return
	var vp := _logical()
	var regions_raw: Variant = payload.get("regions", [])
	if not regions_raw is Array:
		return
	for region in regions_raw:
		if not region is Dictionary:
			continue
		if not bool(region.get("visible", false)):
			continue
		var rect: Variant = region.get("rect", {})
		if not rect is Dictionary:
			continue
		var x := float(rect.get("x", 0))
		var y := float(rect.get("y", 0))
		var w := float(rect.get("w", 0))
		var h := float(rect.get("h", 0))
		var id := String(region.get("id", ""))
		if id == "dock" or id == "rail":
			continue
		var inside := x >= -1.0 and y >= -1.0 and x + w <= vp.x + 1.0 and y + h <= vp.y + 1.0
		_check(inside, "%s visible region %s stays in the logical viewport" % [module, id])


func _feedback_count(node: Node) -> int:
	if node.has_method("ui_diagnostics"):
		var raw: Variant = node.call("ui_diagnostics")
		if raw is Dictionary:
			if raw.get("state") is Dictionary and raw.state.has("floater_count"):
				return int(raw.state.floater_count)
			for key in ["floater_count", "damage_events", "floaters"]:
				if raw.has(key) and (raw[key] is int or raw[key] is float):
					return int(raw[key])
				if raw.has(key) and raw[key] is Array:
					return (raw[key] as Array).size()
	return -1


func _visible_button_text(node: Node) -> String:
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Button and (current as Button).visible and (current as Button).is_visible_in_tree():
			return (current as Button).text
		for child in current.get_children():
			stack.append(child)
	return ""


func _press_visible_button(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Button and (current as Button).visible and not (current as Button).disabled:
			(current as Button).emit_signal("pressed")
			return
		for child in current.get_children():
			stack.append(child)


func _push_region(id: String, control: Control, essential: bool, module: String) -> void:
	if control == null:
		return
	var rect := control.get_global_rect()
	var vp := _logical()
	var visible := control.is_visible_in_tree()
	var inside := rect.position.x >= -1.0 and rect.position.y >= -1.0 and rect.end.x <= vp.x + 1.0 and rect.end.y <= vp.y + 1.0
	regions.append({
		"id": id,
		"source": "harness_measure",
		"module": module,
		"visible": visible,
		"essential": essential,
		"clipped": visible and not inside,
		"rect": _rect(rect),
		"text": control.text if control is Label else "",
		"coordinate_space": "viewport",
	})


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll(child)
		if found != null:
			return found
	return null


func _region(diag: Dictionary, id: String) -> Dictionary:
	for item in diag.get("regions", []):
		if item is Dictionary and str(item.get("id", "")) == id:
			return item
	return {}


func _rect(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _gate(id: String, met: bool, measured: Dictionary) -> void:
	gates[id] = {"met": met, "measured": measured}
	_check(met, "target gate %s: %s" % [id, JSON.stringify(measured)])


func _own(node: Node) -> Node:
	root.add_child(node)
	_owned.append(node)
	return node


func _release(built: Dictionary, session: Node) -> void:
	if session != null and is_instance_valid(session):
		session.free()
	for key in ["entry", "session", "world"]:
		if built.has(key) and is_instance_valid(built[key]):
			built[key].free()


func _write_report(path: String) -> void:
	var unmet: Array = []
	for id in gates.keys():
		if not bool(gates[id].met):
			unmet.append(id)
	var report := {
		"kind": "gravebag.ui_geometry.v1",
		"acceptance": "target_geometry",
		"target_quality_claimed": false,
		"final_acceptance": false,
		"reference_motion_matched": false,
		"reference_comparison": "not_applied",
		"research_video_watched": false,
		"slice_hud_used_as_acceptance": false,
		"live_subject": "world_view",
		"backend_live": false,
		"reason": "binding source-derived geometry/input/stat/motion fixture gates; independent reference approval and original-backend live proof remain separate",
		"modules": modules,
		"diagnostics": diagnostics,
		"regions": regions,
		"frames": frames,
		"gates": gates,
		"unmet": unmet,
		"checks": checks,
		"failures": failures,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FSOD UI ACCEPTANCE FAIL: cannot write report")
		failures += 1
		return
	file.store_string(JSON.stringify(report))
	file.close()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD UI ACCEPTANCE FAIL: " + description)
