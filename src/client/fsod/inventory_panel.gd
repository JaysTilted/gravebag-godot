# SPDX-License-Identifier: AGPL-3.0-only
# Original GRAVEBAG UI/glyphs; wire slots from FSoD 6fd20aad4a7905b13f25389c68368a942a2b68cb.
# Presentation and requests only. Server snapshots are the only inventory authority.
extends PanelContainer

signal swap_requested(source_object_id: int, source_slot: int, dest_object_id: int, dest_slot: int)
signal use_requested(slot: int)
signal selection_changed(container_slot: int)

const IconScript = preload("res://src/client/fsod/item_icon.gd")
const TooltipScript = preload("res://src/client/fsod/item_tooltip.gd")
const THEME_PATH := "res://src/client/fsod/ui_theme.gd"
const GOLD := Color("efcf7a")
const MISSING := "—"
const PAD := 4
const GAP := 2
const SLOT_MAX := 48
const SLOT_MIN := 36

var _player_id: int = -1
var _container_id: int = -1
var _player_stats: Dictionary = {}
var _container_stats: Dictionary = {}
var _descriptors: Dictionary = {}
var _selected: Dictionary = {}
var _epoch: int = 0
var _column: VBoxContainer
var _gear: GridContainer
var _inventory: GridContainer
var _backpack: VBoxContainer
var _loot: VBoxContainer
var _hint: Label
var _player_slots: Array = []
var _bag_slots: Array = []
var _hover: Control
var _tooltip: Control
var _tooltip_layer: CanvasLayer
var _slot_style: StyleBox
var _pending: Dictionary = {}
var _last_readback: Dictionary = {"kind": "", "matched": false}
var _colors := {
	"void": Color("1a1a1a"),
	"charcoal": Color("333333"),
	"slot": Color("515151"),
	"slot_edge": Color("2a2a2a"),
	"silver": Color("d4d4d4"),
	"muted": Color("9a9a9a"),
	"gold": Color("efcf7a"),
	"hp": Color("fc3436"),
	"mp": Color("648dff"),
	"xp": Color("5b832b"),
	"fame": Color("ff8a1a"),
}

func _ready() -> void:
	_build()
	_refresh()

func set_snapshot(player_id: int, player_stats: Dictionary, container_id: int, container_stats: Dictionary, descriptors: Dictionary) -> void:
	_epoch += 1
	_player_id = player_id
	_container_id = container_id
	_player_stats = player_stats.duplicate(true)
	_container_stats = container_stats.duplicate(true)
	_descriptors = descriptors.duplicate(true)
	var matched := _pending_matches_current()
	_last_readback = {"kind": str(_pending.get("kind", "")), "matched": matched}
	_pending = {}
	if not _selected.is_empty():
		var bag: bool = _selected.bag
		var slot: int = _selected.slot
		if _object_id(bag) != _selected.object_id or not _valid_slot(bag, slot) or _item(bag, slot) != _selected.item:
			_clear_selection()
	_build()
	_refresh()

static func _v2_tokens() -> Dictionary:
	return {
		"charcoal": "333333", "slot": "515151", "slot_edge": "2a2a2a", "silver": "d4d4d4",
		"muted": "9a9a9a", "gold": "efcf7a", "hp": "fc3436", "mp": "648dff", "xp": "5b832b",
		"fame": "ff8a1a", "player": "ffe500", "enemy": "ff3b4a", "portal": "3d8bff", "void": "1a1a1a",
		"ink": "1a1a1a", "slate": "333333", "steel": "9a9a9a", "paper": "d4d4d4", "danger": "fc3436",
	}

static func _hex(value: Variant) -> String:
	if value is Color:
		return value.to_html(false)
	return str(value).to_lower().replace("#", "").strip_edges()

static func _accept_theme(tokens: Dictionary) -> bool:
	return _hex(tokens.get("slot", "")) == "515151" or _hex(tokens.get("charcoal", "")) == "333333"

func _apply_theme() -> void:
	var tokens := _v2_tokens()
	_slot_style = null
	var script: Variant = null
	if ResourceLoader.exists(THEME_PATH):
		script = load(THEME_PATH)
	if script != null and script.has_method("tokens"):
		var remote: Variant = script.tokens()
		if remote is Dictionary and _accept_theme(remote):
			tokens = remote
			_slot_style = _theme_style(script, "slot_style")
			var panel_style: StyleBox = _theme_style(script, "panel_style")
			add_theme_stylebox_override("panel", panel_style if panel_style != null else _panel_style(tokens))
		else:
			add_theme_stylebox_override("panel", _panel_style(tokens))
	else:
		add_theme_stylebox_override("panel", _panel_style(tokens))
	for key in _colors.keys():
		_colors[key] = _token_color(tokens, key, _colors[key])

static func _theme_style(script: Variant, method: String) -> StyleBox:
	if script == null or not script.has_method(method):
		return null
	if script is GDScript:
		for info in script.get_script_method_list():
			if str(info.get("name", "")) == method and (info.get("args", []) as Array).size() != 0:
				return null
	var style: Variant = script.call(method)
	return style if style is StyleBox else null

static func _token_color(tokens: Dictionary, key: String, fallback: Color) -> Color:
	var aliases := {"void": "ink", "charcoal": "slate", "muted": "steel", "silver": "paper", "hp": "danger"}
	var value: Variant = tokens.get(key, null)
	if value == null and aliases.has(key):
		value = tokens.get(aliases[key], null)
	if value == null:
		for alias in aliases:
			if aliases[alias] == key and tokens.has(alias):
				value = tokens[alias]
				break
	if value is Color:
		return value
	if value is String and not value.is_empty():
		return Color("#" + value.replace("#", ""))
	return fallback

func _panel_style(tokens: Dictionary) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _token_color(tokens, "charcoal", _colors.charcoal)
	style.border_color = _token_color(tokens, "slot_edge", _colors.slot_edge)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(PAD)
	return style

func _build() -> void:
	if _column != null:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_apply_theme()
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", GAP)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_gear = _grid("Gear")
	_inventory = _grid("Inventory")
	_column.add_child(_gear)
	_column.add_child(_inventory)
	for slot in range(0, 4):
		_add_slot(_gear, false, slot)
	for slot in range(4, 12):
		_add_slot(_inventory, false, slot)
	_backpack = _labeled("Backpack", "Pack")
	_loot = _labeled("Loot", "Loot")
	_column.add_child(_backpack)
	_column.add_child(_loot)
	for slot in range(12, 20):
		_add_slot(_backpack.get_node("Grid"), false, slot)
	for slot in range(0, 8):
		_add_slot(_loot.get_node("Grid"), true, slot)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", _colors.muted)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_hint)
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 80
	add_child(_tooltip_layer)
	_tooltip = TooltipScript.new()
	_tooltip_layer.add_child(_tooltip)
	_apply_metrics()

func _grid(node_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return grid

func _labeled(node_name: String, title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = node_name
	section.visible = false
	section.add_theme_constant_override("separation", GAP)
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", _colors.muted)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(label)
	section.add_child(_grid("Grid"))
	return section

func _add_slot(grid: GridContainer, bag: bool, slot: int) -> void:
	var tile := ItemSlot.new()
	tile.rail = self
	tile.bag = bag
	tile.slot = slot
	tile.name = ("Loot" if bag else "Item") + str(slot)
	grid.add_child(tile)
	if bag:
		_bag_slots.append(tile)
	else:
		_player_slots.append(tile)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_metrics()

func _apply_metrics() -> void:
	if _player_slots.is_empty():
		return
	var width := _column.size.x if _column != null and _column.size.x > 32.0 else size.x - PAD * 2.0
	if width < 64.0:
		width = 200.0
	var side := clampi(int(floor((width - GAP * 3.0) / 4.0)), SLOT_MIN, SLOT_MAX)
	for tile in _player_slots + _bag_slots:
		if tile.custom_minimum_size.x != side:
			tile.custom_minimum_size = Vector2(side, side)

func _process(delta: float) -> void:
	if _tooltip != null:
		_tooltip.tick(delta)
	set_process(false)

func _stat(stats: Dictionary, id: int) -> Variant:
	return stats.get(id, stats.get(str(id)))

func _has_backpack() -> bool:
	var value: Variant = _stat(_player_stats, 79)
	return (value is bool and value) or (value is int and value == 1)

func _valid_slot(bag: bool, slot: int) -> bool:
	return _object_id(bag) >= 0 and _object_id(bag) <= 2147483647 and slot >= 0 and slot < (8 if bag else (20 if _has_backpack() else 12))

func _object_id(bag: bool) -> int:
	return _container_id if bag else _player_id

func _item(bag: bool, slot: int) -> int:
	if not _valid_slot(bag, slot):
		return -2
	var wire: int = slot + 8 if slot < 12 else slot + 59
	var value: Variant = _stat(_container_stats if bag else _player_stats, wire)
	if not value is int:
		return -2
	if value == -1 or value == 65535:
		return -1
	return value if value >= 0 and value < 65535 else -2

func _descriptor(bag: bool, slot: int) -> Dictionary:
	var items: Variant = _descriptors.get("items", {})
	if not items is Dictionary:
		return {}
	var item: int = _item(bag, slot)
	var descriptor: Variant = items.get(item, items.get(str(item), {}))
	return descriptor if descriptor is Dictionary else {}

func _item_name(bag: bool, slot: int) -> String:
	var item: int = _item(bag, slot)
	if item == -2:
		return "Unavailable"
	if item == -1:
		return "Empty"
	var descriptor: Dictionary = _descriptor(bag, slot)
	if descriptor.has("ObjectId"):
		return str(descriptor.ObjectId)
	var objects: Variant = _descriptors.get("objects", {})
	if objects is Dictionary:
		var object: Variant = objects.get(item, objects.get(str(item), {}))
		if object is Dictionary:
			return str(object.get("name", object.get("id", "Unknown item")))
	return "Unknown item"

func _role(bag: bool, slot: int) -> String:
	if bag:
		return "Loot"
	if slot >= 12:
		return "Backpack"
	if slot >= 4:
		return "Inventory"
	var roles := ["Weapon", "Ability", "Armor", "Ring"]
	return roles[slot]

func _can_use(bag: bool, slot: int) -> bool:
	if bag or _item(bag, slot) < 0:
		return false
	var descriptor: Dictionary = _descriptor(bag, slot)
	return descriptor.get("Consumable", false) == true or descriptor.get("Usable", false) == true

func _glyph(bag: bool, slot: int) -> String:
	return IconScript.glyph_for(_descriptor(bag, slot))

func _refresh() -> void:
	if _column == null:
		return
	_backpack.visible = _has_backpack()
	_loot.visible = _container_id >= 0
	for tile in _player_slots + _bag_slots:
		tile.refresh()
	_hint.text = "Click two slots or drag to swap.\nDouble-click to use. Shift-click loot to take." if _container_id >= 0 else "Click two slots or drag to swap.\nDouble-click to use. No nearby loot."
	_hint.add_theme_color_override("font_color", _colors.muted)
	_apply_metrics()
	_sync_tooltip()

func _clear_selection() -> void:
	var had_selection: bool = not _selected.is_empty()
	_selected = {}
	if had_selection:
		selection_changed.emit(-1)
	_refresh()

func _activate(bag: bool, slot: int, shift: bool = false, double: bool = false) -> void:
	if not _valid_slot(bag, slot) or _item(bag, slot) == -2:
		return
	if double:
		_clear_selection()
		if _can_use(bag, slot):
			_pending = {"kind": "use", "slot": slot, "item": _item(bag, slot)}
			_flash(_slot_node(bag, slot))
			use_requested.emit(slot)
			_hint.text = "Use requested. Waiting for server."
		return
	if shift and bag:
		_clear_selection()
		if _item(bag, slot) < 0:
			return
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
	if not _valid_slot(source_bag, source_slot) or not _valid_slot(dest_bag, dest_slot):
		return
	if _item(source_bag, source_slot) < 0 or _item(dest_bag, dest_slot) == -2:
		return
	if _object_id(source_bag) == _object_id(dest_bag) and source_slot == dest_slot:
		return
	_pending = {
		"kind": "swap",
		"source_bag": source_bag,
		"source_slot": source_slot,
		"dest_bag": dest_bag,
		"dest_slot": dest_slot,
		"source_item": _item(source_bag, source_slot),
		"dest_item": _item(dest_bag, dest_slot),
	}
	_clear_selection()
	_flash(_slot_node(source_bag, source_slot))
	_flash(_slot_node(dest_bag, dest_slot))
	swap_requested.emit(_object_id(source_bag), source_slot, _object_id(dest_bag), dest_slot)
	_hint.text = "Swap requested. Waiting for server."

func _drag_record(bag: bool, slot: int) -> Dictionary:
	return {"rail": self, "epoch": _epoch, "bag": bag, "slot": slot, "item": _item(bag, slot)}

func _valid_drag(data: Variant, bag: bool, slot: int) -> bool:
	if not data is Dictionary or not data.has_all(["rail", "epoch", "bag", "slot", "item"]):
		return false
	if data.rail != self or data.epoch != _epoch or not data.bag is bool or not data.slot is int:
		return false
	return _valid_slot(data.bag, data.slot) and _valid_slot(bag, slot) and _item(data.bag, data.slot) >= 0 and _item(data.bag, data.slot) == data.item and _item(bag, slot) != -2 and not (_object_id(data.bag) == _object_id(bag) and data.slot == slot)

func _pending_matches_current() -> bool:
	if str(_pending.get("kind", "")) != "swap":
		return false
	return _item(bool(_pending.get("source_bag", false)), int(_pending.get("source_slot", -1))) == int(_pending.get("dest_item", -999)) and _item(bool(_pending.get("dest_bag", false)), int(_pending.get("dest_slot", -1))) == int(_pending.get("source_item", -999))

func _flash(tile: Control) -> void:
	if tile != null:
		tile.flash_until = Time.get_ticks_msec() + 180
		tile.set_process(true)

func _slot_node(bag: bool, slot: int) -> Control:
	var slots: Array = _bag_slots if bag else _player_slots
	return slots[slot] if slot >= 0 and slot < slots.size() else null

func _hover_slot(tile: Control, inside: bool) -> void:
	if inside:
		_hover = tile
		tile.hover_target = 1.0
	elif _hover == tile:
		_hover = null
		tile.hover_target = 0.0
	tile.set_process(true)
	_sync_tooltip()

func _sync_tooltip() -> void:
	if _tooltip == null or not _tooltip.has_method("present"):
		return
	if _hover == null or not is_instance_valid(_hover) or not _hover.is_visible_in_tree():
		_tooltip.dismiss()
		set_process(true)
		return
	var bag: bool = _hover.bag
	var slot: int = _hover.slot
	var bounds := get_viewport().get_visible_rect() if is_inside_tree() else Rect2(Vector2.ZERO, Vector2(1280, 720))
	_tooltip.present("%s:%s:%s" % [bag, slot, _item(bag, slot)], _tooltip_body(bag, slot), _hover.get_global_rect(), bounds, _colors)
	set_process(true)

func _tooltip_body(bag: bool, slot: int) -> String:
	return TooltipScript.body(_descriptor(bag, slot), {
		"name": _item_name(bag, slot),
		"role": _role(bag, slot),
		"eligibility": "Double-click to use" if _can_use(bag, slot) else "Cannot use here",
		"hint": "Shift-click to take; click or drag to swap" if bag else "Click or drag to swap; server validates equipment",
	})

func _tint(descriptor: Dictionary) -> Color:
	var heal := false
	var magic := false
	var effects: Variant = descriptor.get("ActivateEffects", [])
	if effects is Array:
		for effect in effects:
			if effect is Dictionary and str(effect.get("EffectName", "")) == "Heal":
				heal = true
			if effect is Dictionary and str(effect.get("EffectName", "")) == "Magic":
				magic = true
	if magic and not heal:
		return _colors.mp
	if descriptor.get("Potion", false) == true or heal:
		return _colors.hp
	return _colors.gold

func _tier_text(descriptor: Dictionary) -> String:
	var tier: Variant = descriptor.get("Tier", null)
	if tier is float and is_equal_approx(float(tier), floorf(float(tier))):
		tier = int(tier)
	return str(int(tier)) if tier is int and int(tier) >= 0 else ""

func _available_actions() -> Array:
	var actions: Array = []
	if _occupied_somewhere():
		actions.append("swap")
	var focused := _focused_slot()
	if not focused.is_empty() and not bool(focused.bag) and _can_use(false, int(focused.slot)):
		actions.append("use")
	if _container_id >= 0:
		for slot in range(8):
			if _item(true, slot) >= 0:
				actions.append("take")
				break
	return actions

func _occupied_somewhere() -> bool:
	for slot in range(20 if _has_backpack() else 12):
		if _item(false, slot) >= 0:
			return true
	if _container_id >= 0:
		for slot in range(8):
			if _item(true, slot) >= 0:
				return true
	return false

func _focused_slot() -> Dictionary:
	if not is_inside_tree():
		return {}
	var focused := get_viewport().gui_get_focus_owner()
	if focused is ItemSlot and focused.rail == self:
		return {"bag": focused.bag, "slot": focused.slot}
	return {}

func _focus_owner() -> String:
	var focused := _focused_slot()
	if focused.is_empty():
		return ""
	if bool(focused.bag):
		return "loot"
	if int(focused.slot) < 4:
		return "gear"
	return "inventory"

func ui_diagnostics() -> Dictionary:
	var viewport_size := Vector2.ZERO
	if is_inside_tree():
		viewport_size = get_viewport().get_visible_rect().size
	var regions: Array = []
	if _gear != null:
		regions.append(_region("gear", _gear, _names_for(false, 0, 4)))
	if _inventory != null:
		regions.append(_region("inventory", _inventory, _names_for(false, 4, 12)))
	if _loot != null and _loot.visible:
		regions.append(_region("loot", _loot, _names_for(true, 0, 8)))
	if _tooltip != null and _tooltip.has_method("is_shown") and _tooltip.is_shown():
		regions.append(_tooltip.readout(_control_clipped(_tooltip)))
	return {
		"schema": "gravebag.ui_diagnostics.v1",
		"viewport": {"w": viewport_size.x, "h": viewport_size.y},
		"regions": regions,
		"actions": _available_actions(),
		"focus": {"owner": _focus_owner(), "traps_gameplay": false},
		"state": {
			"pending": {
				"active": not _pending.is_empty(),
				"kind": str(_pending.get("kind", "")),
				"authoritative": false,
				"request": _pending.duplicate(true),
				"authoritative_values": {"player": _player_stats.duplicate(true), "container": _container_stats.duplicate(true)},
			},
			"last_readback": _last_readback.duplicate(true),
			"names": _names_for(false, 0, 20),
			"backpack_visible": _backpack != null and _backpack.visible,
			"container_id": _container_id,
		},
	}

func _names_for(bag: bool, first: int, last: int) -> String:
	var names: PackedStringArray = []
	for slot in range(first, last):
		if _item(bag, slot) >= 0:
			names.append(_item_name(bag, slot))
	return "\n".join(names) if not names.is_empty() else MISSING

func _region(id: String, control: Control, text: String) -> Dictionary:
	var rect := control.get_global_rect() if control.is_inside_tree() else Rect2()
	var focused := false
	var focusable := false
	for child in control.find_children("*", "Control", true, false):
		if child is ItemSlot and child.rail == self:
			focusable = true
			if child.has_focus():
				focused = true
	return {
		"id": id,
		"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
		"visible": control.is_visible_in_tree(),
		"clipped": _control_clipped(control),
		"text": text,
		"focusable": focusable,
		"focused": focused,
	}

func _control_clipped(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	if not get_viewport().get_visible_rect().grow(0.5).encloses(rect):
		return true
	var node: Node = control.get_parent()
	while node != null:
		if node is Control and node.clip_contents and not node.get_global_rect().grow(0.5).encloses(rect):
			return true
		node = node.get_parent()
	return false

class ItemSlot extends Control:
	const IconScript = preload("res://src/client/fsod/item_icon.gd")
	var rail: Variant
	var bag: bool = false
	var slot: int = 0
	var icon: Control
	var tier: Label
	var hover_target: float = 0.0
	var hover_shown: float = 0.0
	var flash_until: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		icon = IconScript.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		add_child(icon)
		tier = Label.new()
		tier.name = "Label"
		tier.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tier.focus_mode = Control.FOCUS_NONE
		tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tier.add_theme_font_size_override("font_size", 9)
		tier.custom_minimum_size = Vector2(16, 11)
		add_child(tier)
		mouse_entered.connect(func() -> void:
			if rail != null:
				rail._hover_slot(self, true)
		)
		mouse_exited.connect(func() -> void:
			if rail != null:
				rail._hover_slot(self, false)
		)

	func _make_custom_tooltip(_for_text: String) -> Object:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2.ZERO
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return blank

	func refresh() -> void:
		var item: int = rail._item(bag, slot)
		var descriptor: Dictionary = rail._descriptor(bag, slot)
		var role: String = rail._role(bag, slot)
		var eligibility: String = "Double-click to use" if rail._can_use(bag, slot) else "Cannot use here"
		var slot_types: Variant = rail._descriptors.get("SlotTypes", [])
		if not bag and slot < 4 and slot_types is Array and slot_types.size() > slot:
			role += " (source equipment slot)"
		var next_tip := "%s\n%s · position %d\n%s\n%s" % [rail._item_name(bag, slot), role, slot + 1, eligibility, "Shift-click to take; click or drag to swap" if bag else "Click or drag to swap; server validates equipment"]
		if item < 0:
			next_tip = "Unavailable" if item == -2 else ""
		if tooltip_text != next_tip:
			tooltip_text = next_tip
		var next_tier: String = rail._tier_text(descriptor) if item >= 0 else ""
		if tier.text != next_tier:
			tier.text = next_tier
		tier.add_theme_color_override("font_color", rail._colors.silver)
		tier.position = Vector2(maxi(0, size.x - 18), maxi(0, size.y - 12))
		tier.size = Vector2(16, 11)
		icon.present(rail._glyph(bag, slot) if item >= 0 else "", rail._tint(descriptor), rail._colors.void, rail._colors.silver, item >= 0)
		queue_redraw()

	func _process(delta: float) -> void:
		var next := move_toward(hover_shown, hover_target, maxf(delta, 1.0 / 60.0) * 10.0)
		var flashing := Time.get_ticks_msec() < flash_until
		if not is_equal_approx(next, hover_shown) or flashing:
			hover_shown = next
			queue_redraw()
		elif not flashing:
			set_process(false)

	func _draw() -> void:
		var fill: Color = rail._colors.slot.lerp(rail._colors.silver, hover_shown * 0.16)
		if rail._slot_style != null and hover_shown <= 0.01:
			draw_style_box(rail._slot_style, Rect2(Vector2.ZERO, size))
		else:
			draw_rect(Rect2(Vector2.ZERO, size), fill)
		draw_rect(Rect2(Vector2.ZERO, size), rail._colors.slot_edge, false, 1.0)
		var selected: bool = rail._selected.get("bag") == bag and rail._selected.get("slot") == slot
		if selected:
			draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), rail._colors.gold, false, 2.0)
		if has_focus():
			draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), rail._colors.silver, false, 1.0)
		if Time.get_ticks_msec() < flash_until:
			draw_rect(Rect2(Vector2.ZERO, size), Color(rail._colors.gold, float(flash_until - Time.get_ticks_msec()) / 180.0 * 0.35))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			grab_focus()
			rail._activate(bag, slot, event.shift_pressed, event.double_click)
			accept_event()
		elif event is InputEventKey and event.pressed and not event.echo and _is_enter(event):
			rail._activate(bag, slot, event.shift_pressed, false)
			accept_event()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			rail._clear_selection()
			accept_event()

	func _is_enter(event: InputEventKey) -> bool:
		return event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.physical_keycode == KEY_ENTER

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if rail._item(bag, slot) < 0:
			return null
		var preview := HBoxContainer.new()
		var mark := IconScript.new()
		mark.custom_minimum_size = Vector2(32, 32)
		mark.present(rail._glyph(bag, slot), rail._tint(rail._descriptor(bag, slot)), rail._colors.void, rail._colors.silver, true)
		preview.add_child(mark)
		var label := Label.new()
		label.text = rail._item_name(bag, slot)
		preview.add_child(label)
		set_drag_preview(preview)
		return rail._drag_record(bag, slot)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return rail._valid_drag(data, bag, slot)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if rail._valid_drag(data, bag, slot):
			rail._request_swap(data.bag, data.slot, bag, slot)
