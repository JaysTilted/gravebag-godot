# SPDX-License-Identifier: AGPL-3.0-only
# Session chrome for connect / loading / reconnect / offline / death.
# Display and command signals only. No session calls, no profile reads.
# Placement is inference: classic 2012 stills show a flat bottom text bar and
# yellow death lines, not a modal. Exalt's play menu was not watched; the shop
# splash is not copied. Ready play keeps a single nonblocking line.
extends CanvasLayer

signal reconnect_requested
signal new_character_requested

const THEME_SCRIPT := "res://src/client/fsod/ui_theme.gd"
const RAIL_WIDTH := 256.0
const MAX_WIDTH := 360.0
const FADE_RATE := 8.0
const GUIDE_CLEARANCE := 72.0

var _state := ""
var _ready_play := false
var _status := ""
var _error := ""
var _character_name := ""
var _class_name := ""
var _map_name := ""
var _latched_for := ""
var _emitting := false
var _built := false
var _panel_fade := 0.0
var _chip_fade := 0.0
var _last_viewport := Vector2.ZERO
var _tokens: Dictionary = {}

var _panel: Panel
var _column: VBoxContainer
var _name_label: Label
var _class_label: Label
var _map_label: Label
var _status_label: Label
var _error_label: Label
var _action: Button
var _chip: Label


static func fallback_tokens() -> Dictionary:
	# fsod-ui-theme/2 sampled classic dark gray. Aliases match Theme.tokens.
	# Standalone until that script exists; integrated reads it when present.
	return {
		"void": "#1a1a1a",
		"charcoal": "#333333",
		"slot": "#515151",
		"slot_edge": "#2a2a2a",
		"silver": "#d4d4d4",
		"muted": "#9a9a9a",
		"gold": "#efcf7a",
		"hp": "#fc3436",
		"mp": "#648dff",
		"xp": "#5b832b",
		"fame": "#ff8a1a",
		"ink": "#1a1a1a",
		"slate": "#333333",
		"steel": "#9a9a9a",
		"paper": "#d4d4d4",
		"danger": "#fc3436",
	}


static func layout_for(viewport: Vector2, panel_height: float) -> Dictionary:
	var safe := viewport
	if safe.x < 2.0 or safe.y < 2.0:
		safe = Vector2(1280, 720)
	var margin := 16.0 if safe.x >= 900.0 and safe.y >= 500.0 else 8.0
	var font := 16 if safe.x >= 700.0 and safe.y >= 400.0 else 12
	var reserve_rail := safe.x >= 520.0
	var right_limit := safe.x - margin
	if reserve_rail:
		right_limit = minf(right_limit, safe.x - RAIL_WIDTH - margin)
	var max_w := right_limit - margin
	if max_w < 80.0:
		margin = minf(margin, 4.0)
		right_limit = safe.x - 2.0
		max_w = right_limit - margin
	var width := minf(MAX_WIDTH, maxf(max_w, 1.0))
	var x := margin
	if x + width > safe.x - 1.0:
		x = maxf(safe.x - width - 1.0, 0.0)
	var height := maxf(panel_height, 1.0)
	var clipped := false
	var max_h := maxf(safe.y - margin * 2.0, 1.0)
	if height > max_h:
		height = max_h
		clipped = true
	var y := safe.y - margin - height
	if y < margin:
		y = margin
		clipped = true
	var chip_w := minf(width, 280.0)
	var chip_h := float(font) + 8.0
	var chip_y := margin
	if safe.y >= 200.0 and chip_y + chip_h > GUIDE_CLEARANCE:
		chip_h = maxf(GUIDE_CLEARANCE - chip_y, float(font))
	if chip_y + chip_h > y - 4.0:
		chip_h = maxf(y - 4.0 - chip_y, 0.0)
	return {
		"panel_x": x,
		"panel_y": y,
		"panel_w": width,
		"panel_h": height,
		"panel_clipped": clipped,
		"chip_x": x,
		"chip_y": chip_y,
		"chip_w": chip_w,
		"chip_h": chip_h,
		"font": font,
		"margin": margin,
		"right_limit": right_limit,
	}


func _ready() -> void:
	layer = 100
	_build()
	var window := get_tree().root
	if window.has_signal("size_changed") and not window.size_changed.is_connected(_on_resized):
		window.size_changed.connect(_on_resized)
	_present()


func refresh(snapshot: Dictionary) -> void:
	# Full snapshot. Missing keys mean absent. The dictionary is not written.
	var next_state := _string_key(snapshot, "state")
	if _latched_for != "" and next_state != _latched_for:
		_latched_for = ""
	_state = next_state
	var ready_value: Variant = snapshot.get("ready", false)
	_ready_play = ready_value is bool and bool(ready_value)
	_status = _string_key(snapshot, "status")
	_error = _string_key(snapshot, "error")
	_character_name = _string_key(snapshot, "character_name").strip_edges()
	_class_name = _string_key(snapshot, "class_name").strip_edges()
	_map_name = _string_key(snapshot, "map_name").strip_edges()
	_tokens = _resolve_tokens()
	if _built:
		_present()


func diagnostics() -> Dictionary:
	return ui_diagnostics()


func ui_diagnostics() -> Dictionary:
	var viewport := _viewport_size()
	var regions: Array = []
	if _built:
		regions = [
			_region("panel", _panel, _status),
			_region("name", _name_label, _name_label.text),
			_region("character_class", _class_label, _class_label.text),
			_region("map", _map_label, _map_label.text),
			_region("status", _status_label, _status_label.text),
			_region("error", _error_label, _error_label.text),
			_region("action", _action, _action.text),
			_region("ready_chip", _chip, _chip.text),
		]
	var owner := ""
	var traps := false
	var viewport_node := get_viewport()
	if viewport_node != null:
		var focused: Control = viewport_node.gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			owner = String(focused.name)
			traps = true
	return {
		"schema": "gravebag.ui_diagnostics.v1",
		"viewport": {"w": viewport.x, "h": viewport.y},
		"regions": regions,
		"actions": _available_actions(),
		"focus": {"owner": owner, "traps_gameplay": traps},
		"state": _state,
		"ready": _ready_play,
		"mouse_ignore": _mouse_ignore(),
	}


func _process(delta: float) -> void:
	if not _built:
		return
	var viewport := _viewport_size()
	if viewport != _last_viewport or _panel_hangs(viewport):
		_last_viewport = viewport
		_layout()
	var panel_target := 1.0 if _wants_panel() else 0.0
	var chip_target := 1.0 if _chip_text() != "" else 0.0
	_panel_fade = _approach(_panel_fade, panel_target, delta)
	_chip_fade = _approach(_chip_fade, chip_target, delta)
	_panel.modulate.a = _panel_fade
	_chip.modulate.a = _chip_fade
	if not _wants_panel() and _panel_fade <= 0.001:
		_panel.visible = false
	if _chip_text() == "" and _chip_fade <= 0.001:
		_chip.visible = false


func _build() -> void:
	if _built:
		return
	_built = true
	_tokens = _resolve_tokens()
	_panel = Panel.new()
	_panel.name = "AccountChromePanel"
	_panel.clip_contents = true
	_panel.focus_mode = Control.FOCUS_NONE
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_column = VBoxContainer.new()
	_column.name = "AccountColumn"
	_column.mouse_filter = Control.MOUSE_FILTER_PASS
	_column.focus_mode = Control.FOCUS_NONE
	_column.add_theme_constant_override("separation", 4)
	_panel.add_child(_column)
	_name_label = _make_label("AccountName")
	_class_label = _make_label("AccountClass")
	_map_label = _make_label("AccountMap")
	_status_label = _make_label("AccountStatus")
	_error_label = _make_label("AccountError")
	_column.add_child(_name_label)
	_column.add_child(_class_label)
	_column.add_child(_map_label)
	_column.add_child(_status_label)
	_column.add_child(_error_label)
	_action = Button.new()
	_action.name = "AccountAction"
	_action.focus_mode = Control.FOCUS_NONE
	_action.mouse_filter = Control.MOUSE_FILTER_STOP
	_action.pressed.connect(_on_action_pressed)
	_column.add_child(_action)
	_chip = _make_label("AccountReadyStatus")
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip)
	set_process(true)


func _present() -> void:
	if not _built:
		return
	_name_label.text = _character_name
	_class_label.text = _class_name
	_map_label.text = _map_name
	_status_label.text = _status
	_error_label.text = _error if _error != _status else ""
	_name_label.visible = _character_name != ""
	_class_label.visible = _class_name != ""
	_map_label.visible = _map_name != ""
	_status_label.visible = _status != ""
	_error_label.visible = _error_label.text != ""
	_sync_action()
	_apply_colors()
	var blocking := _wants_panel()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	_panel.visible = blocking or _panel_fade > 0.001
	_panel.modulate.a = _panel_fade
	_chip.text = _chip_text()
	_chip.visible = _chip.text != "" or _chip_fade > 0.001
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.modulate.a = _chip_fade
	_layout()


func _sync_action() -> void:
	var action_id := _action_id()
	var show := action_id != ""
	_action.visible = show
	if action_id == "new_character":
		_action.text = "New character"
	elif action_id == "reconnect":
		_action.text = "Reconnect"
	else:
		_action.text = ""
	var enabled := show and _latched_for == ""
	_action.disabled = not enabled
	_action.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	_action.mouse_filter = Control.MOUSE_FILTER_STOP if show else Control.MOUSE_FILTER_IGNORE
	if not enabled and _action.has_focus():
		_action.release_focus()


func _on_action_pressed() -> void:
	if _emitting or _latched_for != "" or _action.disabled or not _action.visible:
		return
	var action_id := _action_id()
	if action_id == "":
		return
	_emitting = true
	_latched_for = _state
	_action.disabled = true
	_action.focus_mode = Control.FOCUS_NONE
	if _action.has_focus():
		_action.release_focus()
	if action_id == "new_character":
		new_character_requested.emit()
	elif action_id == "reconnect":
		reconnect_requested.emit()
	_emitting = false


func _panel_hangs(viewport: Vector2) -> bool:
	if not _panel.visible:
		return false
	var rect := _panel.get_global_rect()
	return rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > viewport.x + 1.0 or rect.end.y > viewport.y + 1.0


func _on_resized() -> void:
	if _built:
		_layout()


func _layout() -> void:
	var placed := layout_for(_viewport_size(), _estimate_height())
	var font := int(placed.font)
	_apply_font(_name_label, font)
	_apply_font(_class_label, font - 2)
	_apply_font(_map_label, font - 2)
	_apply_font(_status_label, font)
	_apply_font(_error_label, font - 2)
	_apply_font(_action, font)
	_apply_font(_chip, font)
	var inner := maxf(float(placed.panel_w) - 16.0, 1.0)
	for label in [_name_label, _class_label, _map_label, _status_label, _error_label]:
		label.custom_minimum_size = Vector2(inner, 0)
	_action.custom_minimum_size = Vector2(inner, 28 if font >= 16 else 22)
	var measured := _column.get_combined_minimum_size().y + 16.0
	var content_h := maxf(_estimate_height(), measured)
	var fitted := layout_for(_viewport_size(), content_h)
	_panel.custom_minimum_size = Vector2(fitted.panel_w, 0)
	_panel.position = Vector2(fitted.panel_x, fitted.panel_y)
	_panel.size = Vector2(fitted.panel_w, fitted.panel_h)
	var grown := maxf(_panel.size.y, _panel.get_combined_minimum_size().y)
	if grown > fitted.panel_h + 1.0:
		fitted = layout_for(_viewport_size(), grown)
		_panel.position = Vector2(fitted.panel_x, fitted.panel_y)
		_panel.size = Vector2(fitted.panel_w, fitted.panel_h)
	_column.position = Vector2(8, 8)
	_column.size = Vector2(maxf(float(fitted.panel_w) - 16.0, 1.0), maxf(float(fitted.panel_h) - 16.0, 1.0))
	_chip.position = Vector2(placed.chip_x, placed.chip_y)
	_chip.size = Vector2(placed.chip_w, placed.chip_h)
	_chip.custom_minimum_size = _chip.size
	_last_viewport = _viewport_size()


func _estimate_height() -> float:
	var font := 16.0
	var viewport := _viewport_size()
	if viewport.x < 700.0 or viewport.y < 400.0:
		font = 12.0
	var height := 16.0
	if _character_name != "":
		height += font + 4.0
	if _class_name != "":
		height += font
	if _map_name != "":
		height += font
	if _status != "":
		height += font * 2.0 + 4.0
	if _error != "" and _error != _status:
		height += font * 2.0
	if _action_id() != "":
		height += 36.0
	return maxf(height, 36.0)


func _wants_panel() -> bool:
	if _state == "" or (_state == "playing" and _ready_play):
		return false
	return _action_id() != "" or _status != "" or _error != "" or _character_name != "" or _class_name != "" or _map_name != ""


func _action_id() -> String:
	if _state == "dead":
		return "new_character"
	if _state == "offline" or _state == "failed":
		return "reconnect"
	return ""


func _available_actions() -> Array:
	if _action_id() == "" or _latched_for != "" or not _built or _action.disabled or not _action.visible:
		return []
	return [_action_id()]


func _chip_text() -> String:
	if _state != "playing" or not _ready_play:
		return ""
	var lines: PackedStringArray = []
	if _character_name != "":
		lines.append(_character_name)
	if _class_name != "" and lines.size() < 2:
		lines.append(_class_name)
	if _status != "" and lines.size() < 2 and _status != _character_name and _status != _class_name:
		lines.append(_status)
	return "\n".join(lines)


func _apply_colors() -> void:
	var ink := _color("ink")
	var slate := _color("slate")
	var steel := _color("steel")
	var paper := _color("paper")
	var gold := _color("gold")
	var hp := _color("hp")
	var dead := _state == "dead"
	var panel_box := _box(ink, hp if dead else ink, 2 if dead else 0)
	if dead:
		panel_box.border_width_left = 2
		panel_box.border_width_top = 0
		panel_box.border_width_right = 0
		panel_box.border_width_bottom = 0
		panel_box.border_color = hp
	_panel.add_theme_stylebox_override("panel", panel_box)
	_name_label.add_theme_color_override("font_color", gold)
	_class_label.add_theme_color_override("font_color", steel)
	_map_label.add_theme_color_override("font_color", steel)
	_status_label.add_theme_color_override("font_color", gold if dead else paper)
	_error_label.add_theme_color_override("font_color", paper)
	_chip.add_theme_color_override("font_color", gold if _character_name != "" else paper)
	_chip.add_theme_color_override("font_outline_color", ink)
	_chip.add_theme_constant_override("outline_size", 1)
	_action.add_theme_color_override("font_color", paper)
	_action.add_theme_color_override("font_disabled_color", steel)
	_action.add_theme_stylebox_override("normal", _box(slate, slate, 0))
	_action.add_theme_stylebox_override("hover", _box(slate.lightened(0.08), gold, 1))
	_action.add_theme_stylebox_override("pressed", _box(ink, gold, 1))
	_action.add_theme_stylebox_override("disabled", _box(ink, ink, 0))
	_action.add_theme_stylebox_override("focus", _box(slate, gold, 1))


func _box(fill: Color, border: Color, border_px: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_px)
	box.set_corner_radius_all(0)
	box.shadow_size = 0
	box.shadow_offset = Vector2.ZERO
	box.set_content_margin_all(8)
	return box


func _make_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = 3
	return label


func _apply_font(control: Control, size: int) -> void:
	control.add_theme_font_size_override("font_size", maxi(size, 10))


func _resolve_tokens() -> Dictionary:
	var tokens := fallback_tokens()
	if not ResourceLoader.exists(THEME_SCRIPT):
		return tokens
	var loaded: Variant = load(THEME_SCRIPT)
	if not loaded is Script:
		return tokens
	var theme_script := loaded as Script
	if not theme_script.has_method("tokens"):
		return tokens
	var provided: Variant = theme_script.call("tokens")
	if not provided is Dictionary:
		return tokens
	for key in (provided as Dictionary).keys():
		var value: Variant = (provided as Dictionary)[key]
		if value is String and Color.html_is_valid(value):
			tokens[key] = value
		elif value is Color:
			tokens[key] = "#" + (value as Color).to_html(false)
	return _alias_tokens(tokens, provided as Dictionary)


func _alias_tokens(tokens: Dictionary, provided: Dictionary) -> Dictionary:
	# Theme keys win over the standalone fallback, including alias pairs.
	var pairs := [["ink", "void"], ["slate", "charcoal"], ["steel", "muted"], ["paper", "silver"], ["danger", "hp"]]
	for pair in pairs:
		var alias := String(pair[0])
		var canon := String(pair[1])
		if _valid_color(provided.get(alias)):
			tokens[alias] = provided[alias]
			tokens[canon] = provided[alias]
		elif _valid_color(provided.get(canon)):
			tokens[canon] = provided[canon]
			tokens[alias] = provided[canon]
	return tokens


func _valid_color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)


func _color(key: String) -> Color:
	var raw: Variant = _tokens.get(key, fallback_tokens().get(key, "#1a1a1a"))
	if raw is String and Color.html_is_valid(raw):
		return Color(raw)
	return Color("#1a1a1a")


func _mouse_ignore() -> Dictionary:
	return {
		"outside": true,
		"panel": not _built or _panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"action": not _built or _action.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"ready_chip": true,
		"name": true,
		"status": true,
		"error": true,
	}


func _region(id: String, control: Control, text: String) -> Dictionary:
	var rect := control.get_global_rect()
	if rect.size == Vector2.ZERO:
		rect = Rect2(control.position, control.size)
	var viewport := _viewport_size()
	var inside := rect.position.x >= -1.0 and rect.position.y >= -1.0 and rect.end.x <= viewport.x + 1.0 and rect.end.y <= viewport.y + 1.0
	return {
		"id": id,
		"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
		"visible": control.visible,
		"clipped": control.visible and not inside,
		"text": text,
		"focusable": control.focus_mode != Control.FOCUS_NONE,
		"focused": control.has_focus(),
	}


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(1280, 720)
	var size := viewport.get_visible_rect().size
	if size.x < 2.0 or size.y < 2.0:
		return Vector2(1280, 720)
	return size


func _string_key(snapshot: Dictionary, key: String) -> String:
	var value: Variant = snapshot.get(key, "")
	return value if value is String else ""


func _approach(current: float, target: float, delta: float) -> float:
	if is_equal_approx(current, target):
		return target
	var step := minf(FADE_RATE * delta, 0.08)
	if current < target:
		return minf(current + step, target)
	return maxf(current - step, target)
