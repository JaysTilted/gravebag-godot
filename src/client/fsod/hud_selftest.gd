# SPDX-License-Identifier: AGPL-3.0-only
# Isolated HUD acceptance. No server, no live usability claim.
extends SceneTree

const UiTheme = preload("res://src/client/fsod/ui_theme.gd")
const Hud = preload("res://src/client/fsod/hud_panel.gd")
const World = preload("res://src/client/fsod/world_view.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD HUD FAIL: " + description)


func _run() -> void:
	_check_theme()
	await _check_panel()
	await _check_world()
	print("FSOD HUD SELFTEST %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)


func _check_theme() -> void:
	_check(UiTheme.CONTRACT == "fsod-ui-theme/2", "theme contract")
	var tokens: Dictionary = UiTheme.tokens()
	_check(tokens.charcoal == Color("333333") and tokens.slate == tokens.charcoal, "charcoal alias")
	_check(tokens.slot == Color("515151") and tokens.slot_edge == Color("2a2a2a"), "slot colors")
	_check(tokens.silver == Color("d4d4d4") and tokens.paper == tokens.silver, "silver alias")
	_check(tokens.muted == Color("9a9a9a") and tokens.steel == tokens.muted, "muted alias")
	_check(tokens.gold == Color("efcf7a"), "gold")
	_check(tokens.hp == Color("fc3436") and tokens.danger == tokens.hp and tokens.potion == tokens.hp, "hp aliases")
	_check(tokens.mp == Color("648dff") and tokens.xp == Color("5b832b") and tokens.fame == Color("ff8a1a"), "bar colors")
	_check(tokens.void == Color("1a1a1a") and tokens.ink == tokens.void, "void alias")
	_check(tokens.player == Color("ffe500") and tokens.enemy == Color("ff3b4a") and tokens.portal == Color("3d8bff"), "markers")
	var panel_a: StyleBoxFlat = UiTheme.panel_style()
	var panel_b: StyleBoxFlat = UiTheme.panel_style()
	_check(panel_a != panel_b and panel_a.get_corner_radius(CORNER_TOP_LEFT) == 0, "panel style is a new square box")
	var slot_a: StyleBoxFlat = UiTheme.slot_style()
	var slot_b: StyleBoxFlat = UiTheme.slot_style()
	_check(slot_a != slot_b and slot_a.bg_color == UiTheme.SLOT, "slot style is a new box")
	var host := UiTheme.inventory_host_rect(Vector2(256, 720))
	_check(host.position.x >= UiTheme.INNER_MARGIN and host.size.y >= 467.0 and host.size.x >= 224.0, "720 host fits measured backpack")
	var strip := UiTheme.potion_strip_rect(Vector2(256, 720))
	_check(strip.position.y >= host.position.y + host.size.y, "potion strip stays outside the host")


func _check_panel() -> void:
	root.size = Vector2i(1280, 720)
	var hud = Hud.new()
	hud.position = Vector2(1024, 0)
	hud.size = Vector2(256, 720)
	root.add_child(hud)
	await process_frame
	var missing: Dictionary = hud.ui_diagnostics()
	_check(missing.schema == "gravebag.ui_diagnostics.v1", "diagnostics schema")
	_check(missing.bars.hp.displayed == "—" and missing.bars.hp.value == null and missing.bars.hp.interpolated == 0.0, "missing HP stays em dash")
	_check(missing.bars.mp.displayed == "—" and missing.bars.xp.displayed == "—", "missing MP and XP")
	var ids := {}
	for region: Variant in missing.regions:
		ids[region.id] = true
	for id: String in UiTheme.REGION_IDS:
		_check(ids.has(id), "region " + id)
	hud.set_snapshot({0: 100, 1: 80, 3: 100, 4: 40, 5: 50, 6: 12, 7: 5, 57: 3, 69: 2, 70: 1}, "Nexus", {"width": 8, "height": 8, "revision": 1, "player": Vector2(3, 3), "cells": {Vector2i(3, 3): Color("c4a574")}})
	var jumped: Dictionary = hud.ui_diagnostics()
	_check(jumped.bars.hp.displayed == "80 / 100" and jumped.bars.hp.value == 80 and jumped.bars.hp.max == 100, "HP text jumps to source")
	_check(hud.displayed_line(4) == "40 / 100" and hud.displayed_line(69) == "2", "MP and potion text are source values")
	var before: float = hud.display_fraction("hp")
	hud.advance_display(0.016)
	var mid: float = hud.display_fraction("hp")
	_check(mid > before and mid < 0.8, "HP fill eases and does not skip to the source")
	var held: float = mid
	hud.set_snapshot({0: 100, 1: 80, 3: 100, 4: 40, 5: 50, 6: 12, 7: 5, 57: 3, 69: 2, 70: 1}, "Nexus", {"width": 8, "height": 8, "revision": 1, "player": Vector2(3, 3)})
	_check(hud.display_fraction("hp") >= held - 0.001, "identical snapshot does not rewind the fill")
	_check(hud.tile_cache_rebuilds == 1, "HP-only refresh does not rebuild the tile cache")
	for _i in 40:
		hud.advance_display(0.05)
	var high: float = hud.display_fraction("hp")
	hud.set_snapshot({0: 100, 1: 0, 3: 100, 4: 40, 5: 50, 6: 12, 7: 5, 57: 3, 69: 2, 70: 1}, "Nexus", {"width": 8, "height": 8, "revision": 1, "player": Vector2(3, 3)})
	hud.advance_display(0.05)
	_check(high > 0.5 and hud.display_fraction("hp") < high, "superseded HP eases toward the new source")
	_check(hud.displayed_line(1) == "0 / 100", "superseded HP text is already the new source")
	var host: Control = hud.inventory_host()
	var expected: Rect2 = UiTheme.inventory_host_rect(hud.size)
	_check(host.get_rect().is_equal_approx(expected), "host control matches inventory_host_rect")
	_check(host.position.x >= UiTheme.INNER_MARGIN and host.position.y >= UiTheme.INNER_MARGIN, "inner host is not flush to the rail")
	var diag: Dictionary = hud.ui_diagnostics()
	var inventory: Dictionary = {}
	for region: Variant in diag.regions:
		if region.id == "inventory":
			inventory = region
	_check(inventory.visible and inventory.rect.w == host.get_global_rect().size.x, "diagnostics use the real inventory rect")
	_check(diag.focus.traps_gameplay == false, "unfocused HUD does not trap gameplay")
	_check(expected.is_equal_approx(Rect2(8, 221, 240, 467)), "canonical v2 main host geometry")
	_check(UiTheme.potion_strip_rect(hud.size).is_equal_approx(Rect2(8, 692, 240, 20)), "canonical potion strip geometry")
	hud.set_snapshot({7: 20, 6: 123, 57: 3, 20: 25, 48: 5, 69: 2, 70: 1}, "NexusPortal.Dragon", {})
	for _i in 40:
		hud.advance_display(0.05)
	var capped: Dictionary = hud.ui_diagnostics()
	_check(capped.bars.xp.max == null and capped.bars.xp.interpolated == 0.0, "level 20 with unknown XP maximum has no invented full fame bar")
	_check(hud._fame.text == "Fame 3" and hud._bars.xp.get_node("Caption").text == "Lv 20  XP 123 / —", "real Fame is text, XP stays source meter")
	_check(hud._stat_labels.ATT_value.text == "25" and hud._stat_labels.ATT_bonus.text == "(+5)", "included bonus is shown without adding it twice")
	_check(hud._stat_labels.DEF_value.text == "—" and hud._stat_labels.DEF_bonus.text == "", "unknown totals stay dash and unknown bonuses stay absent")
	_check(hud._potion_counts.hp.text == "F 2" and hud._potion_counts.mp.text == "V 1", "icon counts show actual F/V actions")
	_check(not hud._identity.get_global_rect().intersects(hud._fame.get_global_rect()), "identity and Fame controls do not overlap")
	_check(not UiTheme.text_overflows(hud._identity) and not UiTheme.text_overflows(hud._fame), "cleaned source realm title and Fame text fit their own rects")
	hud.free()


func _check_world() -> void:
	root.size = Vector2i(1280, 720)
	var world = World.new()
	root.add_child(world)
	await process_frame
	_check(world.RAIL_WIDTH == 256.0, "camera rail constant stays 256")
	_check(is_instance_valid(world._rail) and world._rail.name == "AuthoritativeRail", "legacy rail name")
	_check(world._rail.get_global_rect().position.x >= 1280.0 - 256.0 - 1.0, "rail sits on the right")
	_check(world._rail.get_global_rect().end.x <= 1280.0 + 1.0, "rail right edge is flush")
	_check(world._rail.mouse_filter == Control.MOUSE_FILTER_STOP, "rail stops mouse")
	_check(world.get_node_or_null("HudOverlay/AuthoritativeRail/ScrollContainer") == null, "core inventory is not in a scroll")
	world.set_descriptors({"tiles": {4: {"color": "#c4a574"}}, "objects": {100: {"kind": "player", "name": "Wizard"}}})
	world.set_player_id(7)
	world.apply_map({"name": "Nexus", "width": 16, "height": 16})
	world.apply_update({"tiles": [{"x": 1, "y": 1, "tile": 4}], "new_objects": [
		{"object_type": 100, "stats": {"id": 7, "position": {"x": 2.0, "y": 2.0}, "stats": {0: 100, 1: 80, 7: 5, 57: 3}}},
	]})
	await process_frame
	_check(world._summary.text.contains("HP  80 / 100") and world._summary.text.contains("Level  5"), "legacy summary text")
	_check(world._summary.text.contains("Fame  3"), "legacy fame text")
	var rebuilds: int = world._hud.tile_cache_rebuilds
	world.apply_tick({"tick_time": 100, "update_statuses": [{"id": 7, "position": {"x": 2.0, "y": 2.0}, "stats": {"1": 70}}]})
	_check(world._hud.tile_cache_rebuilds == rebuilds, "physics-free stat tick does not rescan tiles")
	_check(world._hud.displayed_line(1) == "70 / 100", "world snapshot text is authoritative")
	var diag: Dictionary = world.ui_diagnostics()
	_check(diag.schema == "gravebag.ui_diagnostics.v1" and diag.bars.hp.value == 70, "world diagnostics expose source HP")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(960, 540)
	await process_frame
	world._layout_rail()
	await process_frame
	_check(world._rail.get_global_rect().position.x >= -1.0, "small viewport rail stays on screen")
	_check(world._rail.get_global_rect().size.x <= 256.0 and world._rail.get_global_rect().size.x > 0.0, "small viewport rail is not wider than 256")
	root.size = Vector2i(1920, 1080)
	await process_frame
	world._layout_rail()
	await process_frame
	_check(is_equal_approx(world._rail.get_global_rect().size.x, 256.0), "large viewport keeps the 256 rail")
	_check(world._rail.get_global_rect().position.x >= world.get_viewport_rect().size.x - 257.0, "large viewport fight area stays open")
	world.free()
