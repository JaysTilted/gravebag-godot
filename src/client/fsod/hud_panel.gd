# SPDX-License-Identifier: AGPL-3.0-only
# Right-rail presentation. Authoritative text jumps. Only bar fills ease, and
# only in this panel's _process. Does not predict, sample hits, or fire actions.
extends Control

const UiTheme = preload("res://src/client/fsod/ui_theme.gd")
const SMOOTH_RATE := 16.0
const HP := 1
const HP_MAX := 0
const MP := 4
const MP_MAX := 3
const XP := 6
const XP_MAX := 5
const LEVEL := 7
const FAME := 57
const POTION_HP := 69
const POTION_MP := 70
const NAME_STAT := 31
# Final totals + included bonus amounts (plans/fsod-inventory-protocol.md:131-135).
# Bonuses are already in the totals; they are shown, never added again.
const STAT_ROWS := [["ATT", 20, 48], ["DEF", 21, 49], ["SPD", 22, 50], ["DEX", 28, 53], ["VIT", 26, 51], ["WIS", 27, 52]]
const MINIMAP_TILE_PX := 6.0 # Integer px per server tile; source cells only, void elsewhere.

var tile_cache_rebuilds: int = 0
var _stats: Dictionary = {}
var _map_name: String = ""
var _minimap: Dictionary = {}
var _cache_revision: int = -1
var _cache_image: Image
var _cache_tex: ImageTexture
var _source_frac: Dictionary = {}
var _display_frac: Dictionary = {}
var _source_text: Dictionary = {}
var _source_value: Dictionary = {}
var _source_max: Dictionary = {}
var _prev_hp: Variant = null
var _hp_flash: float = 0.0
var _minimap_box: Control
var _identity: Label
var _bars: Dictionary = {}
var _potions: Control
var _potion_counts: Dictionary = {}
var _stats_box: Control
var _stat_labels: Dictionary = {}
var _fame: Label
var _host: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	texture_filter = TEXTURE_FILTER_NEAREST
	_build()
	set_process(true)


func inventory_host() -> Control:
	return _host


func set_snapshot(stats: Dictionary, map_name: String, minimap: Dictionary) -> void:
	# Duplicate stats so a later caller mutation cannot change the frozen text.
	# The minimap dict is not copied (tiles can be large) and is never written.
	_stats = stats.duplicate(true)
	_map_name = map_name
	_minimap = minimap
	_sync_sources()
	_sync_labels()
	_rebuild_tile_cache()
	if is_instance_valid(_minimap_box):
		_minimap_box.queue_redraw()
	for kind: String in _bars:
		_bars[kind].queue_redraw()


func displayed_line(stat_id: int) -> String:
	return str(_source_text.get(stat_id, "—"))


func display_fraction(kind: String) -> float:
	return float(_display_frac.get(kind, 0.0))


func source_fraction(kind: String) -> float:
	return float(_source_frac.get(kind, 0.0))


func _process(delta: float) -> void:
	advance_display(delta)


func advance_display(delta: float) -> void:
	var step := 0.0
	if is_finite(delta) and delta > 0.0:
		step = 1.0 - exp(-SMOOTH_RATE * minf(delta, 0.05))
	for kind: String in ["hp", "mp", "xp"]:
		var target: float = float(_source_frac.get(kind, 0.0))
		var shown: float = float(_display_frac.get(kind, 0.0))
		if not is_finite(shown):
			shown = 0.0
		shown = lerpf(shown, target, step)
		if absf(shown - target) < 0.001:
			shown = target
		_display_frac[kind] = shown
		if is_instance_valid(_bars.get(kind)):
			_bars[kind].queue_redraw()
	if _hp_flash > 0.0:
		_hp_flash = maxf(0.0, _hp_flash - maxf(delta, 0.0))
		if is_instance_valid(_bars.get("hp")):
			_bars["hp"].queue_redraw()


func ui_diagnostics() -> Dictionary:
	var viewport := get_viewport_rect().size if is_inside_tree() else size
	var regions: Array = []
	regions.append(UiTheme.region_from_control("minimap", _minimap_box, ""))
	regions.append(UiTheme.region_from_control("identity", _identity, _identity.text if is_instance_valid(_identity) else ""))
	regions.append(_bar_region("hp", displayed_line(HP)))
	regions.append(_bar_region("mp", displayed_line(MP)))
	regions.append(_bar_region("xp", displayed_line(XP)))
	regions.append(_text_region("stats", _stats_box, _stats_text(), _stat_label_list()))
	var potion := _text_region("potions", _potions, "F %s\nV %s" % [displayed_line(POTION_HP), displayed_line(POTION_MP)], _potion_counts.values())
	potion["icons"] = _potion_counts.size()
	regions.append(potion)
	for id: String in ["gear", "inventory", "loot", "tooltip", "guide", "death", "offline"]:
		regions.append(UiTheme.empty_region(id))
	_fill_inventory_regions(regions)
	return {
		"schema": "gravebag.ui_diagnostics.v1",
		"viewport": {"w": viewport.x, "h": viewport.y},
		"regions": regions,
		"bars": {
			"hp": UiTheme.bar_record(_source_value.get(HP), _source_max.get(HP_MAX), displayed_line(HP), display_fraction("hp")),
			"mp": UiTheme.bar_record(_source_value.get(MP), _source_max.get(MP_MAX), displayed_line(MP), display_fraction("mp")),
			"xp": UiTheme.bar_record(_source_value.get(XP), _source_max.get(XP_MAX), displayed_line(XP), display_fraction("xp")),
		},
		"actions": [],
		"focus": _focus_record(),
		"state": "world",
		"minimap_cache": {"rebuilds": tile_cache_rebuilds, "revision": _cache_revision},
	}


# Bar rect plus the measured caption fit: a caption wider/taller than its label
# counts as clipped even when the bar itself sits inside the viewport.
func _bar_region(kind: String, text: String) -> Dictionary:
	var bar: Control = _bars.get(kind)
	var region := UiTheme.region_from_control(kind, bar, text)
	if is_instance_valid(bar):
		var caption: Label = bar.get_node("Caption")
		region["text_fit"] = UiTheme.text_fit(caption)
		if UiTheme.text_overflows(caption):
			region.clipped = true
	return region


func _text_region(id: String, control: Control, text: String, labels: Array) -> Dictionary:
	var region := UiTheme.region_from_control(id, control, text)
	var fits: Array = []
	for label: Variant in labels:
		if not label is Label:
			continue
		fits.append(UiTheme.text_fit(label))
		if UiTheme.text_overflows(label) or not control.get_global_rect().grow(0.5).encloses(label.get_global_rect()):
			region.clipped = true
	region["text_fit"] = fits
	return region


func _stat_label_list() -> Array:
	var out: Array = []
	for key: String in _stat_labels:
		out.append(_stat_labels[key])
	return out


func _stats_text() -> String:
	var lines: PackedStringArray = []
	for row: Array in STAT_ROWS:
		var bonus := _bonus_text(row[2])
		lines.append("%s %s%s" % [row[0], _stat_text(row[1]), (" " + bonus) if not bonus.is_empty() else ""])
	lines.append("Fame %s" % displayed_line(FAME))
	return "\n".join(lines)


func _bonus_text(stat_id: int) -> String:
	var bonus: Variant = _optional_int(stat_id)
	if bonus == null or int(bonus) == 0:
		return ""
	return "(%+d)" % int(bonus)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _build() -> void:
	_minimap_box = Control.new()
	_minimap_box.name = "Minimap"
	_minimap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_box.texture_filter = TEXTURE_FILTER_NEAREST
	_minimap_box.draw.connect(_draw_minimap)
	add_child(_minimap_box)
	_identity = Label.new()
	_identity.name = "Identity"
	_identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply_label(_identity, 14, UiTheme.SILVER)
	add_child(_identity)
	for kind: String in ["hp", "mp", "xp"]:
		var bar := Control.new()
		bar.name = kind.to_upper()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.texture_filter = TEXTURE_FILTER_NEAREST
		bar.draw.connect(_draw_bar.bind(kind))
		var caption := Label.new()
		caption.name = "Caption"
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.apply_label(caption, 13, UiTheme.SILVER)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bar.add_child(caption)
		add_child(bar)
		_bars[kind] = bar
	_stats_box = Control.new()
	_stats_box.name = "Stats"
	_stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stats_box)
	for row: Array in STAT_ROWS:
		for part: String in ["name", "value", "bonus"]:
			var label := Label.new()
			label.name = "%s_%s" % [row[0], part]
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UiTheme.apply_label(label, 12, UiTheme.MUTED if part == "name" else (UiTheme.XP.lightened(0.4) if part == "bonus" else UiTheme.SILVER))
			_stats_box.add_child(label)
			_stat_labels["%s_%s" % [row[0], part]] = label
	_fame = Label.new()
	_fame.name = "Fame"
	_fame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fame.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.apply_label(_fame, 12, UiTheme.FAME)
	add_child(_fame)
	_potions = Control.new()
	_potions.name = "Potions"
	_potions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potions.draw.connect(_draw_potions)
	add_child(_potions)
	for kind: String in ["hp", "mp"]:
		var count := Label.new()
		count.name = "Count_" + kind
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiTheme.apply_label(count, 12, UiTheme.SILVER)
		_potions.add_child(count)
		_potion_counts[kind] = count
	_host = Control.new()
	_host.name = "InventoryHost"
	_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.clip_contents = true
	add_child(_host)
	_layout()


func _layout() -> void:
	if not is_instance_valid(_host):
		return
	var host := UiTheme.inventory_host_rect(size)
	var strip := UiTheme.potion_strip_rect(size)
	var inset := UiTheme.INNER_MARGIN
	var width := maxf(0.0, size.x - inset * 2.0)
	var line_h := 15.0 # Font 12 line height fits; measured by text_fit in diagnostics.
	var bar_h := 18.0 # Caption font 13 fits inside; readable, still compact.
	var stats_h := line_h * 3.0
	var below := 2.0 + (bar_h + 2.0) * 3.0 + stats_h + 2.0
	_identity.position = Vector2(inset + 2.0, inset)
	_identity.size = Vector2(width - 4.0, 18.0)
	_fame.position = _identity.position
	_fame.size = _identity.size
	var top := _identity.position.y + 19.0
	var minimap_h := maxf(48.0, host.position.y - top - below)
	_minimap_box.position = Vector2(inset, top)
	_minimap_box.size = Vector2(width, minimap_h)
	var y := top + minimap_h + 2.0
	for kind: String in ["hp", "mp", "xp"]:
		var bar: Control = _bars[kind]
		bar.position = Vector2(inset, y)
		bar.size = Vector2(width, bar_h)
		var caption: Label = bar.get_node("Caption")
		caption.position = Vector2(4, 0)
		caption.size = Vector2(maxf(0.0, bar.size.x - 8.0), bar.size.y)
		y += bar_h + 2.0
	_stats_box.position = Vector2(inset + 2.0, y)
	_stats_box.size = Vector2(width - 4.0, stats_h)
	var col_w := (_stats_box.size.x) / 2.0
	for i in STAT_ROWS.size():
		var row: Array = STAT_ROWS[i]
		var origin := Vector2((i % 2) * col_w, floorf(i / 2.0) * line_h)
		_stat_labels[row[0] + "_name"].position = origin
		_stat_labels[row[0] + "_name"].size = Vector2(32.0, line_h)
		_stat_labels[row[0] + "_value"].position = origin + Vector2(32.0, 0)
		_stat_labels[row[0] + "_value"].size = Vector2(36.0, line_h)
		_stat_labels[row[0] + "_bonus"].position = origin + Vector2(68.0, 0)
		_stat_labels[row[0] + "_bonus"].size = Vector2(maxf(0.0, col_w - 70.0), line_h)
	_host.position = host.position
	_host.size = host.size
	_potions.position = strip.position
	_potions.size = strip.size
	var half := strip.size.x / 2.0
	for i in 2:
		var count: Label = _potion_counts["hp" if i == 0 else "mp"]
		count.position = Vector2(i * half + 22.0, 0)
		count.size = Vector2(maxf(0.0, half - 24.0), strip.size.y)
	_minimap_box.queue_redraw()
	_potions.queue_redraw()


func _sync_sources() -> void:
	var next_hp: Variant = _optional_int(HP)
	if _prev_hp != null and next_hp != null and int(next_hp) < int(_prev_hp):
		_hp_flash = 0.18
	_prev_hp = next_hp
	_pair("hp", HP, HP_MAX)
	_pair("mp", MP, MP_MAX)
	_pair("xp", XP, XP_MAX)
	_source_text[LEVEL] = _stat_text(LEVEL)
	_source_text[FAME] = _stat_text(FAME)
	_source_text[POTION_HP] = _stat_text(POTION_HP)
	_source_text[POTION_MP] = _stat_text(POTION_MP)
	_source_text[NAME_STAT] = _name_text()


func _pair(kind: String, cur_id: int, max_id: int) -> void:
	var cur: Variant = _optional_int(cur_id)
	var maximum: Variant = _optional_int(max_id)
	_source_value[cur_id] = cur
	_source_max[max_id] = maximum
	if cur == null or maximum == null:
		_source_text[cur_id] = "—"
		_source_frac[kind] = 0.0
		if not _display_frac.has(kind):
			_display_frac[kind] = 0.0
		return
	_source_text[cur_id] = "%s / %s" % [cur, maximum]
	var max_f := float(maximum)
	_source_frac[kind] = 0.0 if max_f <= 0.0 else clampf(float(cur) / max_f, 0.0, 1.0)
	if not _display_frac.has(kind):
		_display_frac[kind] = 0.0


func _sync_labels() -> void:
	if not is_instance_valid(_identity):
		return
	var who := _name_text()
	var world := _map_name if not _map_name.is_empty() else "—"
	_identity.text = "%s · %s" % [who, world]
	_fame.text = "Fame %s" % displayed_line(FAME)
	_bars["hp"].get_node("Caption").text = "HP  %s" % displayed_line(HP)
	_bars["mp"].get_node("Caption").text = "MP  %s" % displayed_line(MP)
	_bars["xp"].get_node("Caption").text = "Lv %s  XP %s" % [_stat_text(LEVEL), displayed_line(XP)]
	for row: Array in STAT_ROWS:
		_stat_labels[row[0] + "_name"].text = row[0]
		_stat_labels[row[0] + "_value"].text = _stat_text(row[1])
		_stat_labels[row[0] + "_bonus"].text = _bonus_text(row[2])
	_potion_counts["hp"].text = displayed_line(POTION_HP)
	_potion_counts["mp"].text = displayed_line(POTION_MP)
	if is_instance_valid(_potions):
		_potions.queue_redraw()


func _draw_bar(kind: String) -> void:
	var bar: Control = _bars[kind]
	var track := Rect2(Vector2.ZERO, bar.size)
	bar.draw_rect(track, UiTheme.VOID)
	var frac := display_fraction(kind) # Source cur/max only; unknown max stays empty.
	var fill := UiTheme.HP if kind == "hp" else UiTheme.MP if kind == "mp" else UiTheme.XP
	if frac > 0.0:
		bar.draw_rect(Rect2(track.position, Vector2(track.size.x * frac, track.size.y)), fill)
	bar.draw_rect(track, UiTheme.SLOT_EDGE, false, 1.0)
	if kind == "hp" and _hp_flash > 0.0:
		bar.draw_rect(track, UiTheme.SILVER, false, 1.0)


func _draw_minimap() -> void:
	var box := _minimap_box
	box.draw_rect(Rect2(Vector2.ZERO, box.size), UiTheme.VOID)
	box.draw_rect(Rect2(Vector2.ZERO, box.size), UiTheme.SLOT_EDGE, false, 1.0)
	var player: Vector2 = _minimap.get("player", Vector2.ZERO)
	var inner := box.size - Vector2(2, 2)
	var span := inner.x / MINIMAP_TILE_PX
	if _cache_tex != null and box.size.x > 4.0 and box.size.y > 4.0:
		var window := Rect2(player - inner / MINIMAP_TILE_PX * 0.5, inner / MINIMAP_TILE_PX)
		box.draw_texture_rect_region(_cache_tex, Rect2(Vector2(1, 1), inner), window)
	var aim := float(_minimap.get("aim", -PI / 2.0))
	var center := box.size * 0.5
	var tip := center + Vector2(cos(aim), sin(aim)) * 6.0
	var left := center + Vector2(cos(aim + 2.4), sin(aim + 2.4)) * 4.0
	var right := center + Vector2(cos(aim - 2.4), sin(aim - 2.4)) * 4.0
	box.draw_colored_polygon(PackedVector2Array([tip, left, right]), UiTheme.PLAYER)
	var scale := box.size.x / span
	for marker: Variant in _minimap.get("markers", []):
		if not marker is Dictionary or str(marker.get("kind", "")) == "player":
			continue
		var pos: Vector2 = marker.get("pos", Vector2.ZERO)
		var local := center + (pos - player) * scale
		if not Rect2(Vector2.ZERO, box.size).grow(-2).has_point(local):
			continue
		var color := UiTheme.ENEMY
		if str(marker.get("kind", "")) == "portal":
			color = UiTheme.PORTAL
		elif str(marker.get("kind", "")) == "container":
			color = UiTheme.GOLD
		box.draw_rect(Rect2(local - Vector2(1, 1), Vector2(3, 3)), color)


func _rebuild_tile_cache() -> void:
	var revision := int(_minimap.get("revision", -1))
	if not _minimap.has("cells") or revision == _cache_revision:
		return
	_cache_revision = revision
	tile_cache_rebuilds += 1
	var width := maxi(int(_minimap.get("width", 0)), 1)
	var height := maxi(int(_minimap.get("height", 0)), 1)
	if width > 4096 or height > 4096:
		width = mini(width, 4096)
		height = mini(height, 4096)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(UiTheme.VOID)
	var cells: Variant = _minimap.get("cells", {})
	if cells is Dictionary:
		for cell: Variant in cells:
			if not cell is Vector2i:
				continue
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				continue
			var color: Variant = cells[cell]
			if color is Color:
				image.set_pixel(cell.x, cell.y, color)
	_cache_image = image
	_cache_tex = ImageTexture.create_from_image(image)


func _fill_inventory_regions(regions: Array) -> void:
	var host_region := UiTheme.region_from_control("inventory", _host, "")
	for i in regions.size():
		if str(regions[i].get("id", "")) == "inventory":
			regions[i] = host_region
	var panel := _host.get_child(0) if _host.get_child_count() > 0 else null
	if panel != null and panel.has_method("ui_diagnostics"):
		var child: Variant = panel.call("ui_diagnostics")
		if child is Dictionary:
			_merge_regions(regions, child.get("regions", []))


func _merge_regions(regions: Array, extra: Array) -> void:
	for item: Variant in extra:
		if not item is Dictionary or not item.has("id"):
			continue
		var replaced := false
		for i in regions.size():
			if str(regions[i].get("id", "")) == str(item["id"]):
				regions[i] = item
				replaced = true
				break
		if not replaced:
			regions.append(item)


func _focus_record() -> Dictionary:
	var owner := ""
	var traps := false
	if is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			owner = str(focused.name)
			var rail := get_global_rect()
			traps = focused.mouse_filter == Control.MOUSE_FILTER_STOP and not rail.encloses(focused.get_global_rect())
	return {"owner": owner, "traps_gameplay": traps}


func _draw_potions() -> void:
	var strip := _potions
	strip.draw_rect(Rect2(Vector2.ZERO, strip.size), UiTheme.CHARCOAL)
	var half := strip.size.x / 2.0
	for i in 2:
		var cell := Rect2(Vector2(i * half + 1.0, 1.0), Vector2(18.0, maxf(0.0, strip.size.y - 2.0)))
		strip.draw_rect(cell, UiTheme.SLOT)
		strip.draw_rect(cell, UiTheme.SLOT_EDGE, false, 1.0)
		_draw_flask(strip, cell, UiTheme.HP if i == 0 else UiTheme.MP)


# Authored solid 6x8 flask, 2px pixels. Source stats 69/70 decide only the count.
func _draw_flask(target: Control, cell: Rect2, liquid: Color) -> void:
	var rows := ["..XX..", "..XX..", ".XLLX.", "XLLLLX", "XLLLLX", "XLLLLX", ".XXXX."]
	var px := 2.0
	var origin := (cell.position + (cell.size - Vector2(6, rows.size()) * px) * 0.5).floor()
	for y in rows.size():
		for x in 6:
			var c: String = rows[y][x]
			if c == ".":
				continue
			target.draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px, px)), liquid if c == "L" else UiTheme.SILVER)


func _name_text() -> String:
	var named: Variant = _lookup(NAME_STAT)
	if named is String and not named.is_empty():
		return named
	var passed: Variant = _minimap.get("player_name", "")
	if passed is String and not passed.is_empty():
		return passed
	return "—"


func _stat_text(stat_id: int) -> String:
	var value: Variant = _lookup(stat_id)
	return "—" if value == null else str(value)


func _optional_int(stat_id: int) -> Variant:
	var value: Variant = _lookup(stat_id)
	if value == null or value is String or value is bool:
		return null
	return int(value)


func _lookup(stat_id: int) -> Variant:
	if _stats.has(stat_id):
		return _stats[stat_id]
	if _stats.has(str(stat_id)):
		return _stats[str(stat_id)]
	return null
