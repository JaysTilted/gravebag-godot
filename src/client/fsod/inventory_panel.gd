# SPDX-License-Identifier: AGPL-3.0-only
# Original GRAVEBAG UI/glyphs; wire slots from FSoD 6fd20aad4a7905b13f25389c68368a942a2b68cb.
# Presentation and requests only. Server snapshots are the only inventory authority.
extends PanelContainer

signal swap_requested(source_object_id: int, source_slot: int, dest_object_id: int, dest_slot: int)
signal use_requested(slot: int)
signal selection_changed(container_slot: int)

const INK := Color("101a2b")
const SLATE := Color("26354b")
const STEEL := Color("8996af")
const PAPER := Color("dce3ef")
const GOLD := Color("efcf7a")
# Original, hand-authored 8x8 silhouettes. No upstream sprite data.
const GLYPHS := {
	"blade": ["......X.", ".....XX.", "....XX..", "...XX...", ".XTX....", "..TX....", ".X..X...", "X......."],
	"staff": ["....TT..", "...TXTT.", "....TT..", "....X...", "...X....", "..X.....", ".X......", "X......."],
	"potion": ["...TT...", "...XX...", "...XX...", "..XTTX..", ".XTTTTX.", ".XTTTTX.", ".XTTTTX.", "..XXXX.."],
	"book": [".XXXXXX.", ".XTTTTX.", ".XTXXTX.", ".XTTTTX.", ".XTXXTX.", ".XTTTTX.", ".XXXXXX.", "..XXXXX."],
	"armor": ["..X..X..", ".XXTTXX.", "XXTTTTXX", "X.XTTX.X", "..XTTX..", "..XTTX..", "..XTTX..", "..XXXX.."],
	"ring": ["...TT...", "..TXTT..", "..X..X..", ".X....X.", ".X....X.", "..X..X..", "...XX...", "........"],
	"pouch": ["..TTTT..", "...XX...", "..XTTX..", ".XTTTTX.", ".XTTXTX.", ".XTTTTX.", ".XTTTTX.", "..XXXX.."],
}

class ItemSlot extends Control:
	var rail: Variant
	var bag: bool = false
	var slot: int = 0
	var caption: Label

	func _init() -> void:
		custom_minimum_size = Vector2(48, 58)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		caption = Label.new()
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.add_theme_font_size_override("font_size", 10)
		add_child(caption)
		resized.connect(_place_caption)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _place_caption() -> void:
		caption.position = Vector2(3, 39)
		caption.size = Vector2(size.x - 6, 16)

	func _draw() -> void:
		var selected: bool = rail._selected.get("bag") == bag and rail._selected.get("slot") == slot
		var occupied: bool = rail._item(bag, slot) >= 0
		draw_style_box(rail._box(Color("1b2a40") if occupied else Color("141f31"), SLATE), Rect2(Vector2.ZERO, size))
		if selected: draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), GOLD, false, 2)
		if has_focus(): draw_rect(Rect2(Vector2(5, 5), size - Vector2(10, 10)), PAPER, false, 1)
		if occupied:
			var glyph: String = rail._glyph(bag, slot)
			var tint: Color = Color("cc8290") if glyph == "potion" else GOLD
			var rows: Array = GLYPHS[glyph]
			var origin := Vector2(floorf((size.x - 24) / 2), 9)
			for y in range(8):
				for x in range(8):
					var pixel: String = rows[y][x]
					if pixel != ".": draw_rect(Rect2(origin + Vector2(x, y) * 3, Vector2(3, 3)), PAPER if pixel == "X" else tint)
		else:
			draw_line(Vector2(size.x / 2 - 4, 22), Vector2(size.x / 2 + 4, 22), STEEL, 1)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			grab_focus()
			rail._activate(bag, slot, event.shift_pressed, event.double_click)
			accept_event()
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				rail._activate(bag, slot, event.shift_pressed, false)
				accept_event()
			elif event.keycode == KEY_ESCAPE:
				rail._clear_selection()
				accept_event()

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if rail._item(bag, slot) < 0: return null
		var preview := Label.new()
		preview.text = rail._item_name(bag, slot)
		preview.add_theme_color_override("font_color", GOLD)
		set_drag_preview(preview)
		return rail._drag_record(bag, slot)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return rail._valid_drag(data, bag, slot)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if rail._valid_drag(data, bag, slot):
			rail._request_swap(data.bag, data.slot, bag, slot)

var _player_id: int = -1
var _container_id: int = -1
var _player_stats: Dictionary = {}
var _container_stats: Dictionary = {}
var _descriptors: Dictionary = {}
var _selected: Dictionary = {}
var _epoch: int = 0
var _column: VBoxContainer
var _backpack: VBoxContainer
var _loot: VBoxContainer
var _hint: Label
var _player_slots: Array = []
var _bag_slots: Array = []

func _ready() -> void:
	_build()
	_refresh()

func set_snapshot(player_id: int, player_stats: Dictionary, container_id: int,
		container_stats: Dictionary, descriptors: Dictionary) -> void:
	_epoch += 1
	_player_id = player_id
	_container_id = container_id
	_player_stats = player_stats.duplicate(true)
	_container_stats = container_stats.duplicate(true)
	_descriptors = descriptors.duplicate(true)
	if not _selected.is_empty():
		var bag: bool = _selected.bag
		var slot: int = _selected.slot
		if _object_id(bag) != _selected.object_id or not _valid_slot(bag, slot) or _item(bag, slot) != _selected.item:
			_clear_selection()
	_build()
	_refresh()

func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func _build() -> void:
	if _column != null: return
	custom_minimum_size.x = 224
	add_theme_stylebox_override("panel", _box(INK, SLATE))
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	margin.add_child(_column)
	_section("Equipment", 0, 4, false)
	_section("Inventory", 4, 12, false)
	_backpack = _section("Backpack", 12, 20, false)
	_loot = _section("Nearby loot", 0, 8, true)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", STEEL)
	_column.add_child(_hint)

func _section(title: String, start: int, end: int, bag: bool) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	_column.add_child(section)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", PAPER)
	section.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	section.add_child(grid)
	for slot in range(start, end):
		var tile := ItemSlot.new()
		tile.rail = self
		tile.bag = bag
		tile.slot = slot
		tile.name = ("Loot" if bag else "Item") + str(slot)
		grid.add_child(tile)
		if bag: _bag_slots.append(tile)
		else: _player_slots.append(tile)
	return section

func _stat(stats: Dictionary, id: int) -> Variant:
	return stats.get(id, stats.get(str(id)))

func _has_backpack() -> bool:
	var value: Variant = _stat(_player_stats, 79)
	return (value is bool and value) or (value is int and value == 1)

func _valid_slot(bag: bool, slot: int) -> bool:
	return _object_id(bag) >= 0 and _object_id(bag) <= 2147483647 and slot >= 0 and slot < (8 if bag else (20 if _has_backpack() else 12))

func _object_id(bag: bool) -> int:
	return _container_id if bag else _player_id

# -2 means unknown, not empty. Never pick up into a stat absent from the snapshot.
func _item(bag: bool, slot: int) -> int:
	if not _valid_slot(bag, slot): return -2
	var wire: int = slot + 8 if slot < 12 else slot + 59
	var value: Variant = _stat(_container_stats if bag else _player_stats, wire)
	if not value is int: return -2
	if value == -1 or value == 65535: return -1
	return value if value >= 0 and value < 65535 else -2

func _descriptor(bag: bool, slot: int) -> Dictionary:
	var items: Variant = _descriptors.get("items", {})
	if not items is Dictionary: return {}
	var item: int = _item(bag, slot)
	var descriptor: Variant = items.get(item, items.get(str(item), {}))
	return descriptor if descriptor is Dictionary else {}

func _item_name(bag: bool, slot: int) -> String:
	var item: int = _item(bag, slot)
	if item == -2: return "Unavailable"
	if item == -1: return "Empty"
	var descriptor: Dictionary = _descriptor(bag, slot)
	if descriptor.has("ObjectId"): return str(descriptor.ObjectId)
	var objects: Variant = _descriptors.get("objects", {})
	if objects is Dictionary:
		var object: Variant = objects.get(item, objects.get(str(item), {}))
		if object is Dictionary: return str(object.get("name", object.get("id", "Unknown item")))
	return "Unknown item"

func _role(bag: bool, slot: int) -> String:
	if bag: return "Loot"
	if slot >= 12: return "Backpack"
	if slot >= 4: return "Inventory"
	var roles := ["Weapon", "Ability", "Armor", "Ring"]
	return roles[slot]

func _can_use(bag: bool, slot: int) -> bool:
	if bag or _item(bag, slot) < 0: return false
	var descriptor: Dictionary = _descriptor(bag, slot)
	return descriptor.get("Consumable", false) == true or descriptor.get("Usable", false) == true

func _glyph(bag: bool, slot: int) -> String:
	var descriptor: Dictionary = _descriptor(bag, slot)
	if descriptor.get("Potion", false) == true: return "potion"
	var type: int = int(descriptor.get("SlotType", 0))
	if type == 9: return "ring"
	if type in [6, 7, 14]: return "armor"
	if type in [11, 4, 5, 12, 13, 15, 16, 18, 19, 20, 21, 22, 23]: return "book"
	if type in [8, 17]: return "staff"
	if type in [1, 2, 3]: return "blade"
	return "pouch"

func _refresh() -> void:
	if _column == null: return
	_backpack.visible = _has_backpack()
	_loot.visible = _container_id >= 0
	for tile: ItemSlot in _player_slots + _bag_slots:
		var item: int = _item(tile.bag, tile.slot)
		var role: String = _role(tile.bag, tile.slot)
		tile.caption.text = _item_name(tile.bag, tile.slot) if item != -1 else (role if not tile.bag and tile.slot < 4 else "Empty")
		tile.caption.add_theme_color_override("font_color", PAPER if item >= 0 else STEEL)
		var eligibility: String = "Double-click to use" if _can_use(tile.bag, tile.slot) else "Cannot use here"
		var slot_types: Variant = _descriptors.get("SlotTypes", [])
		if not tile.bag and tile.slot < 4 and slot_types is Array and slot_types.size() > tile.slot:
			role += " (source equipment slot)"
		tile.tooltip_text = "%s\n%s · position %d\n%s\n%s" % [_item_name(tile.bag, tile.slot), role, tile.slot + 1, eligibility,
			"Shift-click to take; click or drag to swap" if tile.bag else "Click or drag to swap; server validates equipment"]
		tile.queue_redraw()
	_hint.text = "Click two slots or drag to swap.\nDouble-click to use. Shift-click loot to take." if _container_id >= 0 else "Click two slots or drag to swap.\nDouble-click to use. No nearby loot."

func _clear_selection() -> void:
	var had_selection: bool = not _selected.is_empty()
	_selected = {}
	if had_selection: selection_changed.emit(-1)
	_refresh()

func _activate(bag: bool, slot: int, shift: bool = false, double: bool = false) -> void:
	if not _valid_slot(bag, slot) or _item(bag, slot) == -2: return
	if double:
		_clear_selection()
		if _can_use(bag, slot):
			use_requested.emit(slot)
			_hint.text = "Use requested. Waiting for server."
		return
	if shift and bag:
		_clear_selection()
		if _item(bag, slot) < 0: return
		for dest in range(4, 20 if _has_backpack() else 12):
			if _item(false, dest) == -1:
				_request_swap(true, slot, false, dest)
				return
		_hint.text = "Inventory full or unavailable. Loot stays in the bag."
		return
	if not _selected.is_empty():
		var source: Dictionary = _selected.duplicate()
		_clear_selection()
		_request_swap(source.bag, source.slot, bag, slot)
	elif _item(bag, slot) >= 0:
		_selected = {"bag": bag, "slot": slot, "object_id": _object_id(bag), "item": _item(bag, slot)}
		selection_changed.emit(slot if bag else -1)
		_refresh()
		_hint.text = "%s selected. Choose a destination." % _item_name(bag, slot)

func _request_swap(source_bag: bool, source_slot: int, dest_bag: bool, dest_slot: int) -> void:
	if not _valid_slot(source_bag, source_slot) or not _valid_slot(dest_bag, dest_slot): return
	if _item(source_bag, source_slot) < 0 or _item(dest_bag, dest_slot) == -2: return
	if _object_id(source_bag) == _object_id(dest_bag) and source_slot == dest_slot: return
	_clear_selection()
	swap_requested.emit(_object_id(source_bag), source_slot, _object_id(dest_bag), dest_slot)
	_hint.text = "Swap requested. Waiting for server."

func _drag_record(bag: bool, slot: int) -> Dictionary:
	return {"rail": self, "epoch": _epoch, "bag": bag, "slot": slot, "item": _item(bag, slot)}

func _valid_drag(data: Variant, bag: bool, slot: int) -> bool:
	if not data is Dictionary or not data.has_all(["rail", "epoch", "bag", "slot", "item"]): return false
	if data.rail != self or data.epoch != _epoch or not data.bag is bool or not data.slot is int: return false
	return _valid_slot(data.bag, data.slot) and _valid_slot(bag, slot) and _item(data.bag, data.slot) >= 0 and _item(data.bag, data.slot) == data.item and _item(bag, slot) != -2 and not (_object_id(data.bag) == _object_id(bag) and data.slot == slot)
