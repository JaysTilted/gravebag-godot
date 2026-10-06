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
	_check(panel._player_slots[0].tooltip_text.contains("Cannot use here") and panel._player_slots[0].tooltip_text.contains("Weapon"), "gear role and nonusable tooltip")
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
	panel.free()
	print("FSOD INVENTORY PASS: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await _render(argument.trim_prefix("--capture="), metadata)
	quit(0 if failures == 0 else 1)

func _render(path: String, metadata: Dictionary) -> void:
	root.size = Vector2i(960, 760)
	var background := ColorRect.new()
	background.color = Color("0b1020")
	background.size = Vector2(960, 760)
	root.add_child(background)
	var title := Label.new()
	title.text = "GRAVEBAG    /    Field kit"
	title.position = Vector2(32, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Inventory.GOLD)
	root.add_child(title)
	for index in range(2):
		var heading := Label.new()
		heading.text = "Travel light" if index == 0 else "Backpack equipped"
		heading.position = Vector2(32 + index * 310, 58)
		root.add_child(heading)
		var panel = Inventory.new()
		panel.position = Vector2(32 + index * 310, 88)
		panel.size.x = 256
		root.add_child(panel)
		var stats: Dictionary = _stats(index == 1)
		stats[10] = 2652 # Source Robe of the Neophyte, SlotType 14.
		if index == 1: stats[71] = 2594
		panel.set_snapshot(10, stats, 40, _bag(), metadata)
		if index == 1:
			panel._activate(true, 0)
			panel._player_slots[12].grab_focus()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image.save_png(path) == OK, "save actual rendered PNG")
	print("FSOD INVENTORY RENDER PASS: " + path)
