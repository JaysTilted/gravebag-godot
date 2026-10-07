# SPDX-License-Identifier: AGPL-3.0-only
# Isolated SceneTree acceptance + actual renderer, no server or global project imports.
extends SceneTree
const Inventory = preload("res://src/client/fsod/inventory_panel.gd")
var failures: int = 0
var checks: int = 0
var swaps: Array = []
var uses: Array = []
var selections: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD INVENTORY FAIL: " + description)

func _stats(backpack: bool = false) -> Dictionary:
	var stats: Dictionary = {79: 1 if backpack else 0}
	for slot in range(12): stats[slot + 8] = -1
	for slot in range(8): stats[slot + 71] = -1
	stats[8] = 2711 # Source Energy Staff.
	stats[9] = 2606 # Source Fire Spray Spell.
	stats[12] = 2594 # Source Health Potion (Consumable true, Usable false).
	return stats

func _bag() -> Dictionary:
	var stats: Dictionary = {}
	for slot in range(8): stats[slot + 8] = -1
	stats[8] = 2594
	stats[15] = 2711
	return stats

func _metadata() -> Dictionary:
	return {"items": JSON.parse_string(FileAccess.get_file_as_string("res://src/data/fsod/items.json")),
		"objects": JSON.parse_string(FileAccess.get_file_as_string("res://src/data/fsod/objects.json")),
		"SlotTypes": [17, 11, 14, 9, 0, 0, 0, 0, 0, 0, 0, 0]}

func _click(tile: Control, shift: bool = false, double: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = shift
	event.double_click = double
	tile._gui_input(event)

func _run() -> void:
	var player: Dictionary = _stats()
	var bag: Dictionary = _bag()
	var metadata: Dictionary = _metadata()
	var originals: Array = [player.duplicate(true), bag.duplicate(true), metadata.duplicate(true)]
	var panel = Inventory.new()
	panel.set_snapshot(10, player, 40, bag, metadata) # pre-ready contract
	root.add_child(panel)
	panel.swap_requested.connect(func(a: int, b: int, c: int, d: int): swaps.append([a, b, c, d]))
	panel.use_requested.connect(func(slot: int): uses.append(slot))
	panel.selection_changed.connect(func(slot: int): selections.append(slot))
	await process_frame
	_check(panel is PanelContainer, "public PanelContainer")
	_check(panel._player_slots.size() == 20 and panel._bag_slots.size() == 8, "complete source and bag nodes")
	_check(not panel._backpack.visible and panel._loot.visible, "default layout has twelve player positions and eight bag positions")
	var visible_count: int = 0
	for tile: Control in panel._player_slots:
		if tile.is_visible_in_tree(): visible_count += 1
	_check(visible_count == 12, "exactly twelve player slots visible without backpack")
	_check(panel._item_name(false, 0) == "Energy Staff", "exported source name")
	_check(panel._player_slots[4].tooltip_text.contains("Double-click to use"), "consumable eligibility tooltip")
	_check(panel._player_slots[0].tooltip_text.contains("Equipped") and panel._player_slots[0].tooltip_text.contains("Weapon"), "gear role and equipped tooltip")
	_click(panel._bag_slots[0], true)
	_check(swaps == [[40, 0, 10, 5]], "shift loot uses first empty inventory, not empty equipment")
	_check(panel._item(true, 0) == 2594 and panel._item(false, 5) == -1, "pickup never removes or inserts item locally")
	_click(panel._bag_slots[7])
	_check(selections.back() == 7, "bag selection callback")
	_click(panel._player_slots[4])
	_check(swaps.back() == [40, 7, 10, 4], "two click occupied-to-occupied source swap")
	_check(panel._selected.is_empty() and selections.back() == -1, "swap clears selection")
	_click(panel._player_slots[4])
	_click(panel._player_slots[4], false, true)
	_check(uses == [4], "doubleclick consumable emits exact player slot")
	_click(panel._player_slots[1], false, true)
	_check(uses == [4, 1], "source usable ability requests use without consumption")
	_click(panel._player_slots[0], false, true)
	_click(panel._player_slots[5], false, true)
	_click(panel._bag_slots[0], false, true)
	_check(uses == [4, 1], "nonusable gear, empty slot and bag never emit use")
	_check(panel._item(false, 4) == 2594 and panel._item(false, 1) == 2606, "use never consumes or equips locally")
	_click(panel._bag_slots[7])
	var drag: Dictionary = panel._drag_record(true, 7)
	_check(panel._player_slots[6]._can_drop_data(Vector2.ZERO, drag), "valid drag destination")
	panel._player_slots[6]._drop_data(Vector2.ZERO, drag)
	_check(swaps.back() == [40, 7, 10, 6], "drop emits same source swap callback")
	_check(panel._selected.is_empty(), "drag swap clears prior click selection")
	_check(not panel._bag_slots[7]._can_drop_data(Vector2.ZERO, drag), "self drag rejected")
	_check(not panel._valid_drag({}, false, 5), "foreign malformed drag rejected")
	_check(not panel._valid_drag(panel._drag_record(false, 5), true, 0), "empty source drag rejected")
	panel.set_snapshot(10, player, 40, bag, metadata)
	_check(not panel._valid_drag(drag, false, 5), "drag invalidated by subsequent authority")
	_check([player, bag, metadata] == originals, "all caller snapshots and descriptors deeply readonly after requests")
	player[12] = 2711
	metadata.items["2594"].ObjectId = "External mutation"
	_check(panel._item(false, 4) == 2594 and panel._item_name(false, 4) == "Health Potion", "copied snapshots insulated from external mutation")
	player = originals[0].duplicate(true)
	metadata = originals[2].duplicate(true)
	# Authoritative server update, not optimistic UI, changes items.
	var server: Dictionary = player.duplicate(true)
	server[13] = 2594
	var server_bag: Dictionary = bag.duplicate(true)
	server_bag[8] = -1
	panel.set_snapshot(10, server, 40, server_bag, metadata)
	_check(panel._item(false, 5) == 2594 and panel._item(true, 0) == -1, "only new server snapshot updates slot contents")
	var full: Dictionary = _stats()
	for slot in range(4, 12): full[slot + 8] = 2711
	panel.set_snapshot(10, full, 40, bag, metadata)
	var before: int = swaps.size()
	_click(panel._bag_slots[0], true)
	_check(swaps.size() == before and panel._item(true, 0) == 2594, "full inventory emits nothing and loses no loot")
	_check(panel._hint.text.contains("Loot stays"), "full inventory readable feedback")
	# Disabled backpack contents are ignored, even if stat values are present.
	full[71] = -1
	panel.set_snapshot(10, full, 40, bag, metadata)
	_click(panel._bag_slots[0], true)
	_check(swaps.size() == before and not panel._valid_slot(false, 12), "disabled backpack never a destination")
	full[79] = 1
	full[71] = 65535
	panel.set_snapshot(10, full, 40, bag, metadata)
	await process_frame
	visible_count = 0
	for tile: Control in panel._player_slots:
		if tile.is_visible_in_tree(): visible_count += 1
	_check(visible_count == 20, "exactly twenty player slots with authoritative backpack")
	_check(panel._backpack.visible and panel._item(false, 12) == -1, "backpack stat71 and unsigned empty mapping")
	_click(panel._bag_slots[0], true)
	_check(swaps.back() == [40, 0, 10, 12], "pickup into enabled first empty backpack slot")
	full[78] = 2594
	panel.set_snapshot(10, full, 40, bag, metadata)
	_check(panel._item(false, 19) == 2594, "last backpack stat78 maps to slot19")
	_click(panel._player_slots[19], false, true)
	_check(uses.back() == 19, "backpack use callback preserves source slot")
	var packed: Dictionary = full.duplicate(true)
	for wire in range(71, 79): packed[wire] = 2711
	panel.set_snapshot(10, packed, 40, bag, metadata)
	before = swaps.size()
	_click(panel._bag_slots[0], true)
	_check(swaps.size() == before and panel._item(true, 0) == 2594, "full enabled backpack also emits nothing and preserves loot")
	_click(panel._bag_slots[7])
	panel.set_snapshot(10, full, -1, {}, metadata)
	_check(panel._selected.is_empty() and selections.back() == -1 and not panel._loot.visible, "container disappears and resets selection")
	_check(not panel._valid_drag(drag, false, 5), "vanished bag drag rejected")
	panel.set_snapshot(10, player, 40, bag, metadata)
	_click(panel._bag_slots[0])
	panel.set_snapshot(10, player, 41, bag, metadata)
	_check(panel._selected.is_empty() and selections.back() == -1, "different container identity invalidates selection")
	_click(panel._bag_slots[7])
	server_bag = bag.duplicate(true)
	server_bag[15] = -1
	panel.set_snapshot(10, player, 41, server_bag, metadata)
	_check(panel._selected.is_empty(), "selected item disappears resets selection")
	panel.set_snapshot(10, player, 40, bag, metadata)
	_click(panel._player_slots[4])
	panel.set_snapshot(11, player, 40, bag, metadata)
	_check(panel._selected.is_empty(), "player identity change invalidates player selection")
	panel.set_snapshot(10, full, 40, bag, metadata)
	_click(panel._player_slots[19])
	full[79] = 0
	panel.set_snapshot(10, full, 40, bag, metadata)
	_check(panel._selected.is_empty(), "backpack removal invalidates its selection")
	# Missing stats never look like capacity. Invalid IDs and malformed values emit nothing.
	panel.set_snapshot(10, {}, 40, bag, metadata)
	before = swaps.size()
	_click(panel._bag_slots[0], true)
	_check(swaps.size() == before and panel._item(false, 4) == -2, "unknown player stats never empty capacity")
	panel._activate(false, -1)
	panel._activate(false, 20)
	panel._activate(true, 8)
	_check(swaps.size() == before, "out of range callbacks suppressed")
	for flag: Variant in [2, "1", null]:
		panel.set_snapshot(10, {79: flag}, 40, bag, metadata)
		_check(not panel._backpack.visible, "backpack requires authoritative enabled value")
	var string_stats: Dictionary = {}
	for key: Variant in player: string_stats[str(key)] = player[key]
	panel.set_snapshot(10, string_stats, 40, bag, metadata)
	_check(panel._item(false, 4) == 2594, "numeric-string wire keys")
	# Exercise the real keyboard and mouse route, not just request methods.
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	panel._bag_slots[7]._gui_input(key)
	_check(panel._selected.get("slot") == 7, "keyboard selects loot")
	panel._player_slots[5]._gui_input(key)
	_check(swaps.back() == [40, 7, 10, 5], "keyboard two-slot swap")
	key.shift_pressed = true
	panel._bag_slots[0]._gui_input(key)
	_check(swaps.back() == [40, 0, 10, 5], "shift keyboard pickup")
	_click(panel._bag_slots[0])
	key.keycode = KEY_ESCAPE
	panel._bag_slots[0]._gui_input(key)
	_check(panel._selected.is_empty(), "escape clears selection")
	# Known equipment mismatch is a server decision, never a pretend client equip.
	_click(panel._player_slots[4])
	_click(panel._player_slots[0])
	_check(swaps.back() == [10, 4, 10, 0] and panel._item(false, 0) == 2711, "gear mismatch requested without local equip")
	panel.set_snapshot(10, player, 10, bag, metadata)
	before = swaps.size()
	_click(panel._bag_slots[0])
	_click(panel._player_slots[0])
	_check(swaps.size() == before, "same object and slot never emit invalid self swap")
	panel.set_snapshot(2147483648, player, -1, {}, metadata)
	_check(not panel._valid_slot(false, 0), "wire object ID range guarded")
	panel.set_snapshot(-1, player, -1, {}, metadata)
	before = uses.size()
	_click(panel._player_slots[4], false, true)
	_check(uses.size() == before and not panel._valid_slot(false, 4), "no authority identity means no use")
	_check(Inventory._accept_theme({"slot": "#515151", "charcoal": "#333333"}), "v2 theme accepted")
	_check(not Inventory._accept_theme({"ink": "#171717", "slate": "#343434"}), "v1 rollback rejected")
	_check(panel._colors.slot.is_equal_approx(Color("515151")), "painted slot is sampled v2")
	_check(panel._colors.charcoal.is_equal_approx(Color("333333")), "painted rail is sampled v2")
	_check(panel.find_children("*", "ScrollContainer", true, false).is_empty(), "core grid has no internal scroll")
	await _check_space(panel, uses)
	await _check_source_tooltip(panel, metadata)
	await _check_host_fit(metadata)
	panel.free()
	print("FSOD INVENTORY PASS: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await _render(argument.trim_prefix("--capture="), metadata)
	quit(0 if failures == 0 else 1)

func _check_space(panel: Inventory, uses: Array) -> void:
	var probe := AbilityProbe.new()
	root.add_child(probe)
	panel._player_slots[1].grab_focus()
	await process_frame
	_check(panel._player_slots[1].has_focus(), "ability slot can take focus")
	var before := uses.size()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	space.echo = false
	panel.get_viewport().push_input(space)
	await process_frame
	_check(probe.spaces == 1, "focused slot does not consume Space")
	_check(uses.size() == before, "Space does not also emit inventory use")
	_check(panel.ui_diagnostics().focus.traps_gameplay == false, "focus does not trap gameplay")
	probe.free()

func _check_source_tooltip(panel: Inventory, metadata: Dictionary) -> void:
	panel.set_snapshot(10, _stats(), 40, _bag(), metadata)
	panel._hover_slot(panel._player_slots[0], true)
	await process_frame
	var staff: String = panel._tooltip_body(false, 0)
	_check(staff.contains("Energy Staff") and staff.contains("Tier 0"), "staff name and tier from source")
	_check(staff.contains("magical wooden staff") and staff.contains("Damage 10"), "staff instruction and damage from source")
	_check(staff.contains("Equipped") and not staff.contains("Cannot use"), "staff shows its equip state, not a blocked-use claim")
	for jargon in ["slot type", "Server validates", "server validates", "Cannot use here"]:
		_check(not staff.contains(jargon), "staff tooltip has no wire/backend jargon: " + jargon)
	_check(not staff.contains("Energy S…"), "tooltip is not the clipped tile caption")
	var potion: String = panel._tooltip_body(false, 4)
	_check(potion.contains("Health Potion") and potion.contains("Tier 1") and potion.contains("Restores 100"), "potion tier and heal amount from source")
	_check(potion.contains("Double-click to use"), "potion use instruction")
	var bare := metadata.duplicate(true)
	bare.items["9999"] = {"ObjectId": "Bare Relic", "SlotType": 1, "StatsBoost": [{"stat": 99, "amount": 4}]}
	var stats := _stats()
	stats[16] = 9999
	panel.set_snapshot(10, stats, -1, {}, bare)
	var relic: String = panel._tooltip_body(false, 8)
	_check(relic.contains("Bare Relic") and relic.contains("Tier —") and relic.contains("— +4"), "missing tier and unknown stat stay em dash")
	_check(not relic.contains("Luck") and not relic.contains("Damage 0"), "no fabricated stat name or zero damage")
	var diag: Dictionary = panel.ui_diagnostics()
	_check(diag.schema == "gravebag.ui_diagnostics.v1", "diagnostics schema")
	_check(diag.focus.traps_gameplay == false, "diagnostics focus does not trap gameplay")
	_check(not str(diag).contains("potion_count"), "potion counts stay out of this panel")
	panel.set_snapshot(10, _stats(), -1, {}, metadata)

func _check_host_fit(metadata: Dictionary) -> void:
	var host := Control.new()
	host.name = "InventoryHost"
	host.position = Vector2(24, 36)
	host.size = Vector2(252, 440)
	root.add_child(host)
	var panel := Inventory.new()
	host.add_child(panel)
	panel.position = Vector2.ZERO
	panel.size = host.size
	panel.set_snapshot(10, _stats(), 40, _bag(), metadata)
	await process_frame
	await process_frame
	var host_rect := host.get_global_rect()
	var diag: Dictionary = panel.ui_diagnostics()
	_check(diag.regions.size() >= 3, "gear inventory and loot regions")
	for region in diag.regions:
		if str(region.id) not in ["gear", "inventory", "loot"]:
			continue
		var node_name := "Column/Gear" if region.id == "gear" else "Column/Inventory" if region.id == "inventory" else "Column/Loot"
		var live: Rect2 = (panel.get_node(node_name) as Control).get_global_rect()
		_check(is_equal_approx(float(region.rect.x), live.position.x) and is_equal_approx(float(region.rect.w), live.size.x), region.id + " rect is the live control")
		_check(float(region.rect.x) >= host_rect.position.x - 0.5 and float(region.rect.y) >= host_rect.position.y - 0.5, region.id + " inside host")
		_check(float(region.rect.x) + float(region.rect.w) <= host_rect.end.x + 0.5, region.id + " width inside host")
		_check(float(region.rect.y) + float(region.rect.h) <= host_rect.end.y + 0.5, region.id + " height inside host")
		if panel.get_viewport().get_visible_rect().size.y >= 720.0:
			_check(region.clipped == false, region.id + " not clipped")
		_check(str(region.text).contains("Energy Staff") or str(region.text).contains("Health Potion"), region.id + " text is a source name")
	var slot: Control = panel._player_slots[0]
	_check(slot.size.x >= 40.0 and absf(slot.size.x - slot.size.y) < 1.0, "core slots are square and legible")
	_check(slot.get_node("Label").text.is_valid_int(), "tile shows a tier digit, not a clipped name")
	_check(panel.get_combined_minimum_size().y <= host.size.y, "core and loot fit the host control")
	panel._player_slots[0].grab_focus()
	panel._hover_slot(panel._player_slots[0], true)
	await process_frame
	var tip: Dictionary = {}
	for region in panel.ui_diagnostics().regions:
		if region.id == "tooltip":
			tip = region
	var view: Rect2 = panel.get_viewport().get_visible_rect()
	_check(not tip.is_empty(), "tooltip region while hovered")
	if view.size.y >= 720.0:
		_check(float(tip.rect.x) >= view.position.x + 2.0 and float(tip.rect.y) >= view.position.y + 2.0, "tooltip inset from viewport")
		_check(float(tip.rect.x) + float(tip.rect.w) <= view.end.x - 2.0 and float(tip.rect.y) + float(tip.rect.h) <= view.end.y - 2.0, "tooltip clamped inside viewport")
	_check(str(tip.text).contains("Energy Staff") and tip.inference == true, "tooltip text is source data and marked inference")
	panel.free()
	host.free()

func _render(path: String, metadata: Dictionary) -> void:
	root.size = Vector2i(1280, 720)
	var background := ColorRect.new()
	background.color = Color("1a1a1a")
	background.size = Vector2(1280, 720)
	root.add_child(background)
	var rail := ColorRect.new()
	rail.color = Color("333333")
	rail.position = Vector2(1024, 0)
	rail.size = Vector2(256, 720)
	root.add_child(rail)
	var host := Control.new()
	host.name = "InventoryHost"
	host.position = Vector2(1028, 180)
	host.size = Vector2(248, 460)
	root.add_child(host)
	var panel := Inventory.new()
	host.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stats := _stats()
	stats[10] = 2652
	panel.set_snapshot(10, stats, 40, _bag(), metadata)
	panel._hover_slot(panel._player_slots[0], true)
	var note := Label.new()
	note.text = "fixture 1280x720, not live"
	note.position = Vector2(24, 16)
	note.add_theme_color_override("font_color", Inventory.GOLD)
	root.add_child(note)
	for _i in 10:
		await process_frame
	var shown: Dictionary = {}
	for region in panel.ui_diagnostics().regions:
		if region.id == "tooltip":
			shown = region
		if str(region.id) in ["gear", "inventory", "loot"]:
			_check(region.clipped == false, "render " + region.id + " not clipped")
	var view: Rect2 = panel.get_viewport().get_visible_rect()
	_check(not shown.is_empty() and float(shown.rect.x) >= 2.0 and float(shown.rect.y) >= 2.0, "render tooltip inset")
	_check(float(shown.rect.x) + float(shown.rect.w) <= view.end.x - 2.0 and float(shown.rect.y) + float(shown.rect.h) <= view.end.y - 2.0, "render tooltip clamped")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image.save_png(path) == OK, "save actual rendered PNG")
	print("FSOD INVENTORY RENDER PASS: " + path)

class AbilityProbe extends Node:
	var spaces: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
			spaces += 1
