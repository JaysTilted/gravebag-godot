extends CanvasLayer
## GRAVEBAG right-rail HUD. Standalone, display-only (design/game-brief.md).
##
## Instance hud.tscn anywhere (or run it directly); it never touches the main
## scene or any game state. Feed it plain Dictionaries via [method update_state]
## — it holds no references to player, enemy, or world nodes. All visuals are
## drawn in code (StyleBoxFlat + custom _draw); no external assets.
##
## Layout (right rail, 240px): top minimap, HP / MP bars, XP-or-fame bar,
## 4 gear slots + 8 inventory slots, HP/MP potion stack labels.
## Labels are UPPERCASE and use a monospace-style system font.


## XP fill while leveling (purple 0x8A3DFF).
const XP_COLOR := Color("8a3dff")
## Bar fill once fame takes over at level 20 (orange 0xFF8A1A).
const FAME_COLOR := Color("ff8a1a")
## HP fill (red) and MP fill (blue).
const HP_COLOR := Color("d23b3b")
const MP_COLOR := Color("2f7bff")
## Minimap dots: player yellow, foes red, portal blue, quest skull white.
const PLAYER_DOT := Color("ffe14d")
const FOE_DOT := Color("ff3b30")
const PORTAL_RING := Color("3fa9ff")
const QUEST_SKULL := Color("f2f2f2")
## Loot-bag tier colors (brief: brown/pink public, purple+ soulbound,
## blue potions, white rare).
const TIER_COLORS := {
	"brown": Color("8b5a2b"),
	"pink": Color("ff6ad5"),
	"purple": Color("8a3dff"),
	"blue": Color("3b9bff"),
	"white": Color("ffffff"),
}
## Rail width in pixels.
const RAIL_WIDTH := 240.0
## Minimap square size in pixels.
const MINIMAP_SIZE := 216.0
## Gear / inventory slot counts (brief: 4 + 8).
const GEAR_SLOTS := 4
const INV_SLOTS := 8
## Level at which XP flips to fame (fame latches on; permadeath banks it).
const FAME_LEVEL := 20
## Juice tuning (display-only; all drawn UI, no assets).
const LOW_HP_FRAC := 0.30
const DAMAGE_LIFE := 0.9
const MAX_FLOATERS := 32
const BANNER_LIFE := 2.0
const TOAST_LIFE := 2.5

var _hp := 100.0
var _max_hp := 100.0
var _mp := 50.0
var _max_mp := 50.0
var _level := 1
var _xp_frac := 0.0
var _fame_frac := 0.0
var _fame_mode := false
var _gear: Array = ["", "", "", ""]
var _inv: Array = ["", "", "", "", "", "", "", ""]
var _pot_hp := 0
var _pot_mp := 0
# Minimap state: positions are normalized 0..1 across the realm map.
var _mm_player := Vector2(0.5, 0.5)
var _mm_foes: Array = []
var _mm_bags: Array = []
var _mm_portals: Array = []
var _mm_quest := Vector2.ZERO
var _mm_has_quest := false

var _built := false
var _mono_font: SystemFont
var _minimap: Control
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _xp_bar: ProgressBar
var _hp_title: Label
var _mp_title: Label
var _xp_title: Label
var _gear_labels: Array = []
var _inv_labels: Array = []
var _gear_slots: Array = []
var _inv_slots: Array = []
var _pot_hp_label: Label
var _pot_mp_label: Label
## Juice overlay (all drawn UI, no assets; wiring lands later).
var _overlay: Control
var _vignette: Control
var _banner_label: Label
var _toast_label: Label
var _banner_t := 0.0
var _toast_t := 0.0
var _xp_punch_t := 999.0
var _xp_punch_dur := 0.25
var _xp_punch_amp := 0.0
var _vignette_phase := 0.0
var _floaters: Array = []


func _ready() -> void:
	if _built:
		return
	layer = 10
	_mono_font = SystemFont.new()
	_mono_font.font_names = PackedStringArray(["monospace"])
	_build_rail()
	_build_juice()
	_refresh_all()


## Switch the XP bar to fame mode (orange). Latched: fame never flips back.
func set_fame_mode(enabled: bool) -> void:
	var was := _fame_mode
	_fame_mode = enabled
	if not _built:
		return
	_xp_bar.max_value = 1.0
	if _fame_mode:
		_xp_bar.value = _fame_frac
		_xp_title.text = tr("FAME")
		_xp_bar.add_theme_stylebox_override("fill", _fill_style(FAME_COLOR))
	else:
		_xp_bar.value = _xp_frac
		_xp_title.text = tr("XP LV %d") % _level
		_xp_bar.add_theme_stylebox_override("fill", _fill_style(XP_COLOR))
	if enabled and not was:
		play_fame_flip()


## Push plain data into the HUD. Unknown / missing keys keep their old values.
##
## Accepted keys (all optional, all plain data — no node references):
## hp, max_hp, mp, max_mp (numbers), level (int),
## xp + xp_max (numbers) or xp_frac (0..1), fame + fame_max or fame_frac,
## fame_mode (bool; also auto-latches when level >= 20),
## gear (Array of up to 4 String codes, "" = empty),
## inventory (Array of up to 8 String codes),
## potions (Dictionary with hp / mp counts),
## minimap (Dictionary: player Vector2, foes Array[Vector2],
## bags Array of {pos, tier}, portals Array[Vector2], quest Vector2).
func update_state(d: Dictionary) -> void:
	var old_level := _level
	var old_xp := _xp_frac
	var old_fame := _fame_frac
	_hp = float(d.get("hp", _hp))
	_max_hp = float(d.get("max_hp", _max_hp))
	_mp = float(d.get("mp", _mp))
	_max_mp = float(d.get("max_mp", _max_mp))
	_level = int(d.get("level", _level))
	if d.has("xp_frac"):
		_xp_frac = clampf(float(d.get("xp_frac", 0.0)), 0.0, 1.0)
	elif d.has("xp") and float(d.get("xp_max", 0.0)) > 0.0:
		_xp_frac = clampf(float(d.get("xp", 0.0)) / float(d.get("xp_max", 1.0)), 0.0, 1.0)
	if d.has("fame_frac"):
		_fame_frac = clampf(float(d.get("fame_frac", 0.0)), 0.0, 1.0)
	elif d.has("fame") and float(d.get("fame_max", 0.0)) > 0.0:
		_fame_frac = clampf(float(d.get("fame", 0.0)) / float(d.get("fame_max", 1.0)), 0.0, 1.0)
	if d.has("gear"):
		_gear = _codes(d.get("gear", []), GEAR_SLOTS)
	if d.has("inventory"):
		_inv = _codes(d.get("inventory", []), INV_SLOTS)
	if d.has("potions"):
		var p: Dictionary = d.get("potions", {})
		_pot_hp = maxi(0, int(p.get("hp", _pot_hp)))
		_pot_mp = maxi(0, int(p.get("mp", _pot_mp)))
	if d.has("minimap"):
		_read_minimap(d.get("minimap", {}))
	if d.has("fame_mode"):
		set_fame_mode(bool(d.get("fame_mode", false)))
	elif _level >= FAME_LEVEL:
		set_fame_mode(true)
	_refresh_all()
	if not _built:
		return
	if _level > old_level:
		show_level_up(_level)
	if _xp_frac > old_xp or _fame_frac > old_fame:
		notify_kill()


func _on_minimap_draw() -> void:
	var r := Rect2(Vector2.ZERO, _minimap.size)
	_minimap.draw_rect(r, Color(0.03, 0.04, 0.08, 1.0), true)
	var grid_col := Color(1.0, 1.0, 1.0, 0.06)
	for i in range(1, 4):
		var f := float(i) / 4.0
		_minimap.draw_line(Vector2(r.size.x * f, 0.0), Vector2(r.size.x * f, r.size.y), grid_col, 1.0)
		_minimap.draw_line(Vector2(0.0, r.size.y * f), Vector2(r.size.x, r.size.y * f), grid_col, 1.0)
	for pv in _mm_portals:
		_minimap.draw_circle(_map_pos(_as_vec2(pv)), 6.0, PORTAL_RING, false, 2.0)
	for b in _mm_bags:
		var pos := Vector2(0.5, 0.5)
		var tier := "brown"
		if b is Dictionary:
			pos = _as_vec2((b as Dictionary).get("pos", pos))
			tier = str((b as Dictionary).get("tier", tier)).to_lower()
		else:
			pos = _as_vec2(b)
		var c: Color = TIER_COLORS.get(tier, Color("c9a227"))
		var p := _map_pos(pos)
		_minimap.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), c, true)
	for fv in _mm_foes:
		_minimap.draw_circle(_map_pos(_as_vec2(fv)), 3.0, FOE_DOT, true)
	if _mm_has_quest:
		_draw_skull(_map_pos(_mm_quest))
	_minimap.draw_circle(_map_pos(_mm_player), 4.0, PLAYER_DOT, true)
	_minimap.draw_circle(_map_pos(_mm_player), 4.0, Color(0, 0, 0, 0.6), false, 1.0)
	_minimap.draw_rect(r, Color(0.5, 0.6, 0.9, 0.6), false, 2.0)


func _on_slot_draw(slot: Panel, labels: Array, idx: int) -> void:
	if idx < 0 or idx >= labels.size():
		return
	if str(labels[idx]) != "":
		return
	var r := Rect2(Vector2(5, 5), slot.size - Vector2(10, 10))
	slot.draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
	slot.draw_line(r.position, r.end, Color(1, 1, 1, 0.08), 1.0)
	slot.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(1, 1, 1, 0.08), 1.0)


func _build_rail() -> void:
	var rail := Panel.new()
	rail.name = "RightRail"
	rail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rail.anchor_bottom = 1.0
	rail.offset_left = -RAIL_WIDTH
	rail.offset_right = 0.0
	rail.offset_top = 0.0
	rail.offset_bottom = 0.0
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_theme_stylebox_override("panel", _panel_style(Color(0.043, 0.063, 0.125, 0.92)))
	add_child(rail)

	var margin := MarginContainer.new()
	margin.name = "RailMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	rail.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "RailBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var minimap_title := _make_title(tr("MINIMAP"))
	minimap_title.name = "MinimapTitle"
	box.add_child(minimap_title)
	_minimap = Control.new()
	_minimap.name = "Minimap"
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_on_minimap_draw)
	box.add_child(_minimap)

	_hp_title = _make_title(tr("HP"))
	_hp_title.name = "HPLabel"
	box.add_child(_hp_title)
	_hp_bar = _make_bar(HP_COLOR, 18.0)
	_hp_bar.name = "HPBar"
	box.add_child(_hp_bar)

	_mp_title = _make_title(tr("MP"))
	_mp_title.name = "MPLabel"
	box.add_child(_mp_title)
	_mp_bar = _make_bar(MP_COLOR, 18.0)
	_mp_bar.name = "MPBar"
	box.add_child(_mp_bar)

	_xp_title = _make_title(tr("XP LV 1"))
	_xp_title.name = "XPLabel"
	box.add_child(_xp_title)
	_xp_bar = _make_bar(XP_COLOR, 12.0)
	_xp_bar.name = "XPBar"
	box.add_child(_xp_bar)

	var gear_title := _make_title(tr("GEAR"))
	gear_title.name = "GearTitle"
	box.add_child(gear_title)
	var gear_grid := GridContainer.new()
	gear_grid.name = "GearGrid"
	gear_grid.columns = 4
	gear_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear_grid.add_theme_constant_override("h_separation", 4)
	gear_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(gear_grid)
	for i in range(GEAR_SLOTS):
		var slot := _make_slot("GearSlot%d" % i, _gear_labels, i, true)
		_gear_slots.append(slot)
		gear_grid.add_child(slot)

	var inv_title := _make_title(tr("INVENTORY"))
	inv_title.name = "InvTitle"
	box.add_child(inv_title)
	var inv_grid := GridContainer.new()
	inv_grid.name = "InvGrid"
	inv_grid.columns = 4
	inv_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_grid.add_theme_constant_override("h_separation", 4)
	inv_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(inv_grid)
	for i in range(INV_SLOTS):
		var slot := _make_slot("InvSlot%d" % i, _inv_labels, i, false)
		_inv_slots.append(slot)
		inv_grid.add_child(slot)

	var pot_title := _make_title(tr("POTIONS"))
	pot_title.name = "PotTitle"
	box.add_child(pot_title)
	var pot_row := HBoxContainer.new()
	pot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pot_row.add_theme_constant_override("separation", 4)
	box.add_child(pot_row)
	_pot_hp_label = _make_title(tr("HP POT X0 [F]"))
	_pot_hp_label.name = "PotHpLabel"
	_pot_mp_label = _make_title(tr("MP POT X0 [V]"))
	_pot_mp_label.name = "PotMpLabel"
	pot_row.add_child(_pot_hp_label)
	pot_row.add_child(_pot_mp_label)
	_built = true


func _make_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _mono_font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("cfd6ea"))
	return l


func _make_bar(fill: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _fill_style(Color(0, 0, 0, 0.65)))
	bar.add_theme_stylebox_override("fill", _fill_style(fill))
	return bar


func _make_slot(slot_name: String, labels: Array, idx: int, is_gear: bool) -> Panel:
	var slot := Panel.new()
	slot.name = slot_name
	slot.custom_minimum_size = Vector2(48, 48)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := Color("7a5cff") if is_gear else Color("4a5878")
	var bg := _panel_style(Color(0.09, 0.12, 0.2, 1.0))
	bg.border_color = edge
	bg.set_border_width_all(2)
	slot.add_theme_stylebox_override("panel", bg)
	var code := Label.new()
	code.set_anchors_preset(Control.PRESET_FULL_RECT)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code.add_theme_font_override("font", _mono_font)
	code.add_theme_font_size_override("font_size", 13)
	code.add_theme_color_override("font_color", Color("ffe9a8"))
	slot.add_child(code)
	labels.append(code)
	slot.draw.connect(_on_slot_draw.bind(slot, labels, idx))
	return slot


func _panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	return s


func _fill_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(3)
	return s


func _refresh_all() -> void:
	if not _built:
		return
	_hp_bar.max_value = maxf(_max_hp, 1.0)
	_hp_bar.value = clampf(_hp, 0.0, maxf(_max_hp, 1.0))
	_hp_title.text = "%s %d/%d" % [tr("HP"), int(_hp), int(_max_hp)]
	_mp_bar.max_value = maxf(_max_mp, 1.0)
	_mp_bar.value = clampf(_mp, 0.0, maxf(_max_mp, 1.0))
	_mp_title.text = "%s %d/%d" % [tr("MP"), int(_mp), int(_max_mp)]
	set_fame_mode(_fame_mode)
	for i in range(mini(_gear.size(), _gear_labels.size())):
		(_gear_labels[i] as Label).text = str(_gear[i]).to_upper()
	for i in range(mini(_inv.size(), _inv_labels.size())):
		(_inv_labels[i] as Label).text = str(_inv[i]).to_upper()
	_pot_hp_label.text = "%s X%d [F]" % [tr("HP POT"), _pot_hp]
	_pot_mp_label.text = "%s X%d [V]" % [tr("MP POT"), _pot_mp]
	for s in _gear_slots:
		(s as Control).queue_redraw()
	for s in _inv_slots:
		(s as Control).queue_redraw()
	_minimap.queue_redraw()


func _read_minimap(m: Dictionary) -> void:
	_mm_player = _as_vec2(m.get("player", _mm_player))
	_mm_foes = []
	for fv in m.get("foes", []):
		_mm_foes.append(_as_vec2(fv))
	_mm_bags = []
	for b in m.get("bags", []):
		if b is Dictionary:
			var bd: Dictionary = b
			_mm_bags.append({"pos": _as_vec2(bd.get("pos", Vector2(0.5, 0.5))), "tier": str(bd.get("tier", "brown"))})
		else:
			_mm_bags.append({"pos": _as_vec2(b), "tier": "brown"})
	_mm_portals = []
	for pv in m.get("portals", []):
		_mm_portals.append(_as_vec2(pv))
	if m.has("quest"):
		_mm_quest = _as_vec2(m.get("quest", Vector2.ZERO))
		_mm_has_quest = true
	else:
		_mm_has_quest = false


func _as_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return (v as Vector2).clamp(Vector2.ZERO, Vector2.ONE)
	if v is Array and (v as Array).size() >= 2:
		var a: Array = v
		return Vector2(float(a[0]), float(a[1])).clamp(Vector2.ZERO, Vector2.ONE)
	return Vector2(0.5, 0.5)


func _map_pos(n: Vector2) -> Vector2:
	return Vector2(n.x * _minimap.size.x, n.y * _minimap.size.y)


func _draw_skull(p: Vector2) -> void:
	_minimap.draw_circle(p + Vector2(0, -1), 5.0, QUEST_SKULL, true)
	_minimap.draw_rect(Rect2(p + Vector2(-3, 2), Vector2(6, 4)), QUEST_SKULL, true)
	var dark := Color(0.05, 0.05, 0.08, 1.0)
	_minimap.draw_circle(p + Vector2(-2, -1), 1.4, dark, true)
	_minimap.draw_circle(p + Vector2(2, -1), 1.4, dark, true)


func _codes(v: Variant, count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append("")
	if v is Array:
		var a: Array = v
		for i in range(mini(a.size(), count)):
			out[i] = str(a[i]).to_upper()
	return out


## ── HUD juice: additive display-only APIs (wiring lands later) ──
## All drawn UI, no assets. update_state()/set_fame_mode() behavior above
## is unchanged; these effects only add motion on top.


## Spawn a floating damage number at a world position. Converts to screen
## via the viewport canvas transform; safe to call before layout (no-op
## until _ready has built the overlay). Color tints the number.
func spawn_damage(world_pos: Vector2, amount: Variant, color: Color = Color.WHITE) -> void:
	if not _built:
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var screen := world_pos
	var vp := get_viewport()
	if vp != null:
		screen = vp.get_canvas_transform() * world_pos
	var txt := str(amount)
	if amount is float:
		txt = str(int(round(float(amount))))
	elif amount is int:
		txt = str(amount)
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _mono_font)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 5)
	_overlay.add_child(lbl)
	var jitter := Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0))
	var base := screen + jitter
	lbl.position = base
	_floaters.append({"label": lbl, "age": 0.0, "life": DAMAGE_LIFE, "base": base})
	while _floaters.size() > MAX_FLOATERS:
		var old: Dictionary = _floaters.pop_front()
		var old_lbl: Variant = old.get("label")
		if old_lbl is Label and is_instance_valid(old_lbl):
			(old_lbl as Label).queue_free()


## Flash the center-screen level-up banner for the given level.
## Auto-called by update_state() when level rises; wiring may call it too.
func show_level_up(level: int) -> void:
	if not _built:
		return
	if _banner_label == null or not is_instance_valid(_banner_label):
		return
	_banner_label.text = "LEVEL UP! LV %d" % level
	_banner_t = BANNER_LIFE
	_banner_label.visible = true
	_banner_label.modulate.a = 0.0


## Scale-punch the XP/fame bar for a kill. Auto-called when xp/fame frac
## rises; wiring may call it directly on kills. Never squashes a bigger
## fame-flip punch already playing.
func notify_kill() -> void:
	if not _built:
		return
	if _xp_bar == null or not is_instance_valid(_xp_bar):
		return
	if _xp_punch_t < _xp_punch_dur and _xp_punch_amp > 0.18:
		return
	_xp_punch_dur = 0.25
	_xp_punch_amp = 0.18
	_xp_punch_t = 0.0


## Show a one-line toast (bag pickups). Replaces the current line and
## restarts its fade; wiring passes the bag tier/name as the label.
func show_toast(text: String) -> void:
	if not _built:
		return
	if _toast_label == null or not is_instance_valid(_toast_label):
		return
	_toast_label.text = text
	_toast_t = TOAST_LIFE
	_toast_label.visible = true
	_toast_label.modulate.a = 0.0


## Bag-pickup toast line: "PICKED UP  <LABEL>" (uppercase, HUD style).
func notify_bag_pickup(bag_label: String) -> void:
	show_toast("PICKED UP  %s" % bag_label.to_upper())


## Fame-flip punch on the XP bar (bigger/longer than kill-pop).
## Auto-called once when set_fame_mode() latches at 20.
func play_fame_flip() -> void:
	if not _built:
		return
	if _xp_bar == null or not is_instance_valid(_xp_bar):
		return
	_xp_punch_dur = 0.6
	_xp_punch_amp = 0.45
	_xp_punch_t = 0.0


func _process(delta: float) -> void:
	if not _built:
		return
	_tick_juice(delta)


func _build_juice() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = Control.new()
	_overlay.name = "JuiceOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette = Control.new()
	_vignette.name = "LowHpVignette"
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	_overlay.add_child(_vignette)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.draw.connect(_on_vignette_draw)
	_banner_label = Label.new()
	_banner_label.name = "LevelBanner"
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_override("font", _mono_font)
	_banner_label.add_theme_font_size_override("font_size", 34)
	_banner_label.add_theme_color_override("font_color", Color("ffd94d"))
	_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner_label.add_theme_constant_override("outline_size", 8)
	_banner_label.modulate.a = 0.0
	_banner_label.visible = false
	_overlay.add_child(_banner_label)
	_banner_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_label = Label.new()
	_toast_label.name = "BagToast"
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_override("font", _mono_font)
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast_label.add_theme_color_override("font_color", Color("ffe9a8"))
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast_label.add_theme_constant_override("outline_size", 4)
	_toast_label.modulate.a = 0.0
	_toast_label.visible = false
	_overlay.add_child(_toast_label)
	_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast_label.offset_left = 0.0
	_toast_label.offset_right = 0.0
	_toast_label.offset_top = -56.0
	_toast_label.offset_bottom = -16.0


func _on_vignette_draw() -> void:
	if _vignette == null or not is_instance_valid(_vignette):
		return
	var sz := _vignette.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_vignette_phase)
	var edge := 26.0
	var a := 0.28 + 0.22 * pulse
	var col := Color(1.0, 0.12, 0.12, a)
	_vignette.draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, edge)), col, true)
	_vignette.draw_rect(Rect2(Vector2(0, sz.y - edge), Vector2(sz.x, edge)), col, true)
	_vignette.draw_rect(Rect2(Vector2.ZERO, Vector2(edge, sz.y)), col, true)
	_vignette.draw_rect(Rect2(Vector2(sz.x - edge, 0), Vector2(edge, sz.y)), col, true)
	var inner := Color(1.0, 0.2, 0.2, a * 0.5)
	_vignette.draw_rect(Rect2(Vector2.ZERO, sz), inner, false, 2.0)


func _tick_juice(delta: float) -> void:
	if _vignette != null and is_instance_valid(_vignette):
		var frac := 1.0
		if _max_hp > 0.0:
			frac = clampf(_hp / maxf(_max_hp, 1.0), 0.0, 1.0)
		var low := frac < LOW_HP_FRAC
		_vignette.visible = low
		if low:
			_vignette_phase += delta * 6.0
			_vignette.queue_redraw()
	if _banner_label != null and is_instance_valid(_banner_label):
		if _banner_t > 0.0:
			_banner_t = maxf(_banner_t - delta, 0.0)
			var elapsed := BANNER_LIFE - _banner_t
			var ba := 1.0
			if elapsed < 0.15:
				ba = elapsed / 0.15
			elif _banner_t < 0.6:
				ba = maxf(_banner_t / 0.6, 0.0)
			_banner_label.modulate.a = clampf(ba, 0.0, 1.0)
			var bp := clampf(elapsed / 0.4, 0.0, 1.0)
			var bs := 1.35 - 0.35 * bp
			_banner_label.pivot_offset = _banner_label.size * 0.5
			_banner_label.scale = Vector2(bs, bs)
			if _banner_t <= 0.0:
				_banner_label.visible = false
				_banner_label.scale = Vector2.ONE
	if _toast_label != null and is_instance_valid(_toast_label):
		if _toast_t > 0.0:
			_toast_t = maxf(_toast_t - delta, 0.0)
			var telapsed := TOAST_LIFE - _toast_t
			var ta := 1.0
			if telapsed < 0.2:
				ta = telapsed / 0.2
			elif _toast_t < 0.8:
				ta = maxf(_toast_t / 0.8, 0.0)
			_toast_label.modulate.a = clampf(ta, 0.0, 1.0)
			if _toast_t <= 0.0:
				_toast_label.visible = false
	if _xp_bar != null and is_instance_valid(_xp_bar):
		if _xp_punch_t < _xp_punch_dur:
			_xp_punch_t += delta
			var p := clampf(_xp_punch_t / _xp_punch_dur, 0.0, 1.0)
			var s := 1.0 + _xp_punch_amp * sin(PI * p)
			_xp_bar.pivot_offset = _xp_bar.size * 0.5
			_xp_bar.scale = Vector2(s, s)
		elif _xp_bar.scale != Vector2.ONE:
			_xp_bar.scale = Vector2.ONE
	for i in range(_floaters.size() - 1, -1, -1):
		var f: Dictionary = _floaters[i]
		var lbl: Variant = f.get("label")
		if not (lbl is Label and is_instance_valid(lbl)):
			_floaters.remove_at(i)
			continue
		var label := lbl as Label
		var age := float(f.get("age", 0.0)) + delta
		f["age"] = age
		var life := float(f.get("life", DAMAGE_LIFE))
		var base: Vector2 = f.get("base", Vector2.ZERO)
		var k := clampf(age / life, 0.0, 1.0)
		label.position = base + Vector2(0, -56.0 * k)
		label.modulate.a = 1.0 - k
		if age >= life:
			_floaters.remove_at(i)
			if is_instance_valid(label):
				label.queue_free()
