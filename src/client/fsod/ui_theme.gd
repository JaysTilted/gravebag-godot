# SPDX-License-Identifier: AGPL-3.0-only
# Shared FSoD UI tokens. RefCounted on purpose: callers preload the script and
# read static tokens(). No Node, no autoload, no second palette.
extends RefCounted

const CONTRACT := "fsod-ui-theme/2"
const RAIL_WIDTH := 256.0
const INNER_MARGIN := 2.0
const INVENTORY_MIN_SIZE := Vector2(224, 309)
const INVENTORY_BACKPACK_MIN_SIZE := Vector2(224, 467)
const POTION_STRIP_HEIGHT := 20.0
const REGION_IDS: PackedStringArray = ["minimap", "identity", "hp", "mp", "xp", "gear", "inventory", "loot", "tooltip", "guide", "death", "offline"]

# Sampled classic dock + GRAVEBAG sprite gold. One palette.
const CHARCOAL := Color("333333")
const SLOT := Color("515151")
const SLOT_EDGE := Color("2a2a2a")
const SILVER := Color("d4d4d4")
const MUTED := Color("9a9a9a")
const GOLD := Color("efcf7a")
const HP := Color("fc3436")
const MP := Color("648dff")
const XP := Color("5b832b")
const FAME := Color("ff8a1a")
const PLAYER := Color("ffe500")
const ENEMY := Color("ff3b4a")
const PORTAL := Color("3d8bff")
const VOID := Color("1a1a1a")
# v1 names are aliases of the same colors, not a second palette.
const INK := VOID
const SLATE := CHARCOAL
const STEEL := MUTED
const PAPER := SILVER
const DANGER := HP
const POTION := HP

static var _font: Font


static func tokens() -> Dictionary:
	return {
		"charcoal": CHARCOAL, "slot": SLOT, "slot_edge": SLOT_EDGE, "silver": SILVER,
		"muted": MUTED, "gold": GOLD, "hp": HP, "mp": MP, "xp": XP, "fame": FAME,
		"player": PLAYER, "enemy": ENEMY, "portal": PORTAL, "void": VOID,
		"ink": INK, "slate": SLATE, "steel": STEEL, "paper": PAPER, "danger": DANGER,
		"potion": POTION,
	}


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CHARCOAL
	style.border_color = SLOT_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(0)
	style.anti_aliasing = false
	return style


static func slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT
	style.border_color = SLOT_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(int(INNER_MARGIN))
	style.anti_aliasing = false
	return style


# Rail-local rect of the inventory host. Same numbers the live control uses.
# At 256x720 this is the measured backpack block under a 2px inner margin,
# with the potion strip kept outside the host. Proof reads the control rect.
static func inventory_host_rect(rail_size: Vector2) -> Rect2:
	var inset := INNER_MARGIN
	var width := maxf(0.0, rail_size.x - inset * 2.0)
	var strip := POTION_STRIP_HEIGHT
	var gap := INNER_MARGIN
	var host_h := INVENTORY_BACKPACK_MIN_SIZE.y
	var y := rail_size.y - inset - strip - gap - host_h
	if y < 96.0:
		y = 72.0
		host_h = maxf(64.0, rail_size.y - y - inset - strip - gap)
	return Rect2(inset, y, width, host_h)


static func potion_strip_rect(rail_size: Vector2) -> Rect2:
	var host := inventory_host_rect(rail_size)
	return Rect2(host.position.x, host.position.y + host.size.y + INNER_MARGIN, host.size.x, POTION_STRIP_HEIGHT)


static func pixel_font() -> Font:
	if _font != null:
		return _font
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "monospace"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	_font = font
	return font


static func apply_label(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_override("font", pixel_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	label.clip_text = true
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func empty_region(id: String) -> Dictionary:
	return {
		"id": id, "rect": {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0},
		"visible": false, "clipped": false, "text": "", "focusable": false, "focused": false,
	}


static func region_from_control(id: String, control: Control, text: String = "") -> Dictionary:
	if not is_instance_valid(control):
		return empty_region(id)
	var rect := control.get_global_rect() if control.is_inside_tree() else Rect2()
	var clipped := false
	if control.is_inside_tree():
		var viewport := control.get_viewport_rect()
		clipped = not viewport.encloses(rect)
		var parent := control.get_parent()
		if parent is Control and parent.clip_contents and not parent.get_global_rect().encloses(rect):
			clipped = true
	return {
		"id": id,
		"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
		"visible": control.is_visible_in_tree(),
		"clipped": clipped,
		"text": text,
		"focusable": control.focus_mode != Control.FOCUS_NONE,
		"focused": control.has_focus(),
	}


static func bar_record(value: Variant, maximum: Variant, displayed: String, interpolated: float) -> Dictionary:
	return {"value": value, "max": maximum, "displayed": displayed, "interpolated": interpolated}
