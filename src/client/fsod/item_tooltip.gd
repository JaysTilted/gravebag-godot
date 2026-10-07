# SPDX-License-Identifier: AGPL-3.0-only
# Design inference. Classic and Exalt stills inspected for this goal did not show
# a tooltip. This panel makes the existing eligibility text readable beside the
# slot. It is not a claimed RotMG tooltip. Missing source fields stay "—".
extends Control

const MISSING := "—"
# Stat ids named in plans/fsod-inventory-protocol.md from realm/Stats.cs.
# Unknown ids are not given a made-up name.
const STAT_NAMES := {0: "HP", 3: "MP", 20: "Attack", 21: "Defense", 22: "Speed", 26: "Vitality", 27: "Wisdom", 28: "Dexterity"}

var shown_key: String = ""
var body_text: String = ""
var want: float = 0.0
var _panel: PanelContainer
var _rows: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 2)
	_panel.add_child(_rows)
	modulate.a = 0.0
	visible = false

func apply_chrome(fill: Color, edge: Color, _paper: Color) -> void:
	if _panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)

func is_shown() -> bool:
	return visible and want > 0.0

static func instruction_text(raw: Variant) -> String:
	if not raw is String or (raw as String).is_empty():
		return MISSING
	var text: String = raw
	if text.begins_with("{") and text.ends_with("}") and text.contains("."):
		var inner := text.substr(1, text.length() - 2)
		var dot := inner.find(".")
		if dot < 0:
			return MISSING
		text = inner.substr(dot + 1).replace("_", " ").strip_edges()
		return text if not text.is_empty() else MISSING
	if text.begins_with("{"):
		return MISSING
	return text

static func body(descriptor: Dictionary, context: Dictionary) -> String:
	var lines: PackedStringArray = []
	var item_name := str(context.get("name", MISSING))
	lines.append(item_name if not item_name.is_empty() else MISSING)
	lines.append(_tier_line(descriptor))
	var role := str(context.get("role", MISSING))
	# Player-readable role only; raw wire SlotType codes never reach the panel.
	lines.append(role if not role.is_empty() else MISSING)
	for stat_line in _stat_lines(descriptor):
		lines.append(stat_line)
	var description := instruction_text(descriptor.get("Description", ""))
	if description != MISSING:
		lines.append(description) # No source description: omit, never a bare dash row.
	var eligibility := str(context.get("eligibility", ""))
	if not eligibility.is_empty():
		lines.append(eligibility)
	var hint := str(context.get("hint", ""))
	if not hint.is_empty():
		lines.append(hint)
	return "\n".join(lines)

static func _whole(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(float(value), floorf(float(value))):
		return int(value)
	return null

static func _tier_line(descriptor: Dictionary) -> String:
	if not descriptor.has("Tier"):
		return "Tier " + MISSING
	var tier: Variant = _whole(descriptor.get("Tier"))
	if tier == null or int(tier) < 0:
		return "Tier " + MISSING
	return "Tier %d" % int(tier)

static func _stat_lines(descriptor: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var projectiles: Variant = descriptor.get("Projectiles", [])
	if projectiles is Array and not projectiles.is_empty():
		var shown := 0
		for projectile in projectiles:
			if shown >= 3 or not projectile is Dictionary:
				continue
			lines.append(_damage_line(projectile))
			shown += 1
		var shots: Variant = _whole(descriptor.get("NumProjectiles"))
		if shots != null and int(shots) > 1:
			lines.append("Projectiles %d" % int(shots))
		if descriptor.has("RateOfFire") and (descriptor.RateOfFire is int or descriptor.RateOfFire is float) and float(descriptor.RateOfFire) > 0.0:
			lines.append("Rate %s" % _number(descriptor.RateOfFire))
	var mp_cost: Variant = _whole(descriptor.get("MpCost"))
	if mp_cost != null and int(mp_cost) > 0:
		lines.append("MP %d" % int(mp_cost))
	if descriptor.has("Cooldown") and (descriptor.Cooldown is int or descriptor.Cooldown is float) and float(descriptor.Cooldown) > 0.0:
		lines.append("Cooldown %s s" % _number(descriptor.Cooldown))
	var boosts: Variant = descriptor.get("StatsBoost", [])
	if boosts is Array:
		for boost in boosts:
			var amount: Variant = _whole(boost.get("amount")) if boost is Dictionary else null
			if amount == null:
				lines.append(MISSING)
				continue
			var stat_id: Variant = _whole(boost.get("stat"))
			if stat_id == null or not STAT_NAMES.has(int(stat_id)):
				lines.append("%s %+d" % [MISSING, int(amount)])
			else:
				lines.append("%s %+d" % [STAT_NAMES[int(stat_id)], int(amount)])
	var effects: Variant = descriptor.get("ActivateEffects", [])
	if effects is Array:
		for effect in effects:
			if not effect is Dictionary:
				continue
			var effect_name := str(effect.get("EffectName", ""))
			if effect_name == "Heal" or effect_name == "Magic":
				var healed: Variant = _whole(effect.get("Amount"))
				var label := "health" if effect_name == "Heal" else "magic"
				lines.append("Restores %s %s" % [str(int(healed)) if healed != null else MISSING, label])
			elif not effect_name.is_empty() and effect_name != "BulletNova":
				lines.append(effect_name)
	if descriptor.get("Soulbound", false) == true:
		lines.append("Soulbound")
	var doses: Variant = _whole(descriptor.get("Doses"))
	if doses != null and int(doses) > 0:
		lines.append("Doses %d" % int(doses))
	var fame: Variant = _whole(descriptor.get("FameBonus"))
	if fame != null and int(fame) > 0:
		lines.append("Fame %+d" % int(fame))
	return lines

static func _damage_line(projectile: Dictionary) -> String:
	var low: Variant = _whole(projectile.get("MinDamage"))
	var high: Variant = _whole(projectile.get("MaxDamage"))
	if low != null and high != null:
		return "Damage %d–%d" % [int(low), int(high)]
	if low != null:
		return "Damage %d–%s" % [int(low), MISSING]
	if high != null:
		return "Damage %s–%d" % [MISSING, int(high)]
	var flat: Variant = _whole(projectile.get("Damage"))
	if flat != null:
		return "Damage %d" % int(flat)
	return "Damage " + MISSING

static func _number(value: Variant) -> String:
	if value is int or (value is float and is_equal_approx(float(value), floorf(float(value)))):
		return str(int(value))
	return str(value)

func present(key: String, text: String, anchor: Rect2, bounds: Rect2, colors: Dictionary) -> void:
	if _panel == null:
		return
	if key != shown_key:
		shown_key = key
		body_text = text
		_rebuild(text, colors)
		modulate.a = 0.35
	elif text != body_text:
		body_text = text
		_rebuild(text, colors)
	want = 1.0
	visible = true
	_place(anchor, bounds)
	set_process(true)

func dismiss() -> void:
	want = 0.0
	if modulate.a <= 0.01:
		visible = false
		shown_key = ""

func tick(delta: float) -> void:
	var step := maxf(delta, 1.0 / 60.0) * 8.0
	var next := move_toward(modulate.a, want, step)
	if not is_equal_approx(next, modulate.a):
		modulate.a = next
	if want <= 0.0 and modulate.a <= 0.01:
		visible = false
		shown_key = ""
		set_process(false)

func readout(clipped: bool) -> Dictionary:
	var rect := get_global_rect() if is_inside_tree() else Rect2()
	return {
		"id": "tooltip",
		"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
		"visible": is_shown(),
		"clipped": clipped,
		"text": body_text,
		"focusable": false,
		"focused": false,
		"inference": true,
	}

func _rebuild(text: String, colors: Dictionary) -> void:
	apply_chrome(colors.get("void", Color("1a1a1a")), colors.get("muted", Color("9a9a9a")), colors.get("silver", Color("d4d4d4")))
	for child in _rows.get_children():
		child.free()
	var first := true
	for line in text.split("\n"):
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.focus_mode = Control.FOCUS_NONE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		label.text = line
		label.custom_minimum_size.x = 204
		label.add_theme_font_size_override("font_size", 15 if first else 13)
		label.add_theme_color_override("font_color", colors.get("gold", Color("efcf7a")) if first else colors.get("silver", Color("d4d4d4")))
		_rows.add_child(label)
		first = false

func _place(anchor: Rect2, bounds: Rect2) -> void:
	var inner := Rect2(bounds.position + Vector2(2, 2), bounds.size - Vector2(4, 4))
	if inner.size.x < 32.0 or inner.size.y < 32.0:
		inner = bounds
	var width := minf(220.0, inner.size.x)
	for label in _rows.get_children():
		if label is Control:
			label.custom_minimum_size.x = maxf(32.0, width - 16.0)
	var lines := maxi(1, body_text.split("\n").size())
	var height := maxf(_rows.get_combined_minimum_size().y + 16.0, lines * 16.0 + 16.0)
	var x := anchor.position.x - width - 6.0
	if x < inner.position.x:
		x = minf(anchor.end.x + 6.0, inner.end.x - width)
	x = clampf(x, inner.position.x, maxf(inner.position.x, inner.end.x - width))
	var y := clampf(anchor.position.y, inner.position.y, maxf(inner.position.y, inner.end.y - height))
	position = Vector2(x, y)
	size = Vector2(width, height)
