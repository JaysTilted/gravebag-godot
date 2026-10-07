# SPDX-License-Identifier: AGPL-3.0-only
# Display-only combat feedback. No commands, no rule/contact/shoot changes.
# Host attaches this Control and calls initialize(), refresh(session, frontend)
# once per frame, and clear() on a hard reset. This file does not attach itself
# to the entry scene.
#
# Observed stills (not watched motion): small red enemy names and a tiny bar
# only when source metadata/HP exist; center bullets stay unobscured; no
# hit-stop, shake, or blur. Floating HP-delta text and its fade are design
# inference, not a measured video timing.
extends Control

const THEME_PATH := "res://src/client/fsod/ui_theme.gd"
const SCHEMA := "gravebag.ui_diagnostics.v1"
const TILE_PX := 32.0
const TELEPORT_TILES := 4.0 # Same discontinuity fact as world_view CAMERA_TELEPORT_TILES.
const LIFE_S := 0.72
const HOLD_S := 0.12
const RISE_PX := 14.0
const RISE_RATE := 8.0
const FONT_FLOAT := 12
const FONT_NAME := 10
const BAR_W := 22.0
const BAR_H := 3.0
const MARGIN := 8.0
const RAIL_FALLBACK := 256.0
const ORIGIN_CLEARANCE := 16.0
const MAX_PER_ENTITY := 3
const MAX_GLOBAL := 12
const STACK_PX := 10.0
const STAT_MAX_HP := 0
const STAT_HP := 1
const STAT_LEVEL := 7
const STAT_COND_LO := 29
const STAT_COND_HI := 96
const PARALYZED_BIT := 13 # Named in world_view.gd. Stat 29 low word.
const NINJA_SPEEDY_BIT := 15 # Named in fsod_session_selftest.gd. Stat 96 high word.

var _layer: CanvasLayer
var _tokens: Dictionary = {}
var _tokens_from_file := false
var _ready_init := false
var _map := ""
var _player_id := -999999
var _playing := false
var _rail := RAIL_FALLBACK
var _last_reset := ""
var _suppressed := 0
var _last_delta := -1.0
var _integrated := 0.0
var _seq := 0
var _hp: Dictionary = {}
var _level: Variant = null
var _cond_lo: Dictionary = {}
var _cond_hi: Dictionary = {}
var _pose: Dictionary = {}
var _auth: Dictionary = {}
var _pending_hp: Dictionary = {}
var _pending_level := ""
var _pending_status: Array = []
var _plates: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process_input(false)
	set_process_unhandled_input(false)


func _ready() -> void:
	initialize()


func initialize() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process_input(false)
	set_process_unhandled_input(false)
	if _layer != null and is_instance_valid(_layer):
		_ready_init = true
		return
	_layer = CanvasLayer.new()
	_layer.name = "CombatFeedbackLayer"
	_layer.layer = 80
	add_child(_layer)
	_ready_init = true


func clear() -> void:
	_reset_tracking("clear")
	_free_feedback_nodes()


func refresh(session: Variant, frontend: Variant) -> void:
	if not _ready_init:
		initialize()
	if not _is_node(session) or not _is_node(frontend):
		_reset_tracking("missing")
		_free_feedback_nodes()
		return
	var state := _string_prop(session, "state")
	var map := _string_prop(frontend, "map_name")
	var player_id := _int_prop(session, "player_id", _int_prop(frontend, "player_id", -1))
	_rail = _read_rail(frontend)
	if state != "playing":
		# Death, offline, reconnect, loading: drop baselines so the next
		# playing snapshot cannot inherit a stale HP delta.
		_reset_tracking("state")
		_free_floaters()
		_plates = []
		_sync_plates()
		_playing = false
		_map = map
		_player_id = player_id
		return
	if _playing and (map != _map or player_id != _player_id):
		_reset_tracking("map" if map != _map else "player")
		_free_floaters()
		_plates = []
		_sync_plates()
	_playing = true
	_map = map
	_player_id = player_id
	_scan(session, frontend)
	_sync_plates()


func _process(delta: float) -> void:
	if not _ready_init:
		initialize()
	_present_pending()
	if is_finite(delta) and delta > 0.0:
		_last_delta = delta
		_integrated += delta
		_advance(delta)
	_layout()


func ui_diagnostics() -> Dictionary:
	var viewport := _viewport_size()
	return {
		"schema": SCHEMA,
		"viewport": {"w": viewport.x, "h": viewport.y},
		"regions": _regions(),
		"motion": _motion(),
		"supported_actions": [],
		"focus": {"owner": _focus_owner(), "traps_gameplay": false},
		"state": {
			"session_playing": _playing,
			"map": _map,
			"player_id": _player_id,
			"last_reset": _last_reset,
			"suppressed": _suppressed,
			"baseline_count": _hp.size(),
			"floater_count": _floater_nodes().size(),
			"name_count": _nodes_named("name_").size(),
			"bar_count": _nodes_named("bar_").size(),
			"pending": _pending_rows(),
		},
	}


static func fade_alpha(age: float) -> float:
	if not is_finite(age) or age <= HOLD_S:
		return 1.0
	if age >= LIFE_S:
		return 0.0
	return clampf(1.0 - (age - HOLD_S) / (LIFE_S - HOLD_S), 0.0, 1.0)


static func rise_offset(age: float) -> float:
	if not is_finite(age) or age <= 0.0:
		return 0.0
	return RISE_PX * (1.0 - exp(-RISE_RATE * age))


func _scan(session: Variant, frontend: Variant) -> void:
	var seen: Dictionary = {}
	var plates: Array = []
	var entities: Variant = frontend.get("entities")
	if entities is Dictionary:
		for key in entities.keys():
			var entity: Variant = entities[key]
			if not _is_node(entity):
				continue
			var id := _entity_id(entity, key)
			if id < 0:
				continue
			seen[id] = true
			var screen: Variant = _screen_pose(entity)
			var jumped := _discontinuity(id, entity, screen)
			_remember_pose(id, entity, screen)
			if id == _player_id or entity.get("is_local_player") == true:
				_track_player(session, id, screen, jumped)
			elif _kind(entity) == "enemy":
				_track_enemy(session, frontend, entity, id, screen, jumped, plates)
	_drop_unseen(seen)
	_plates = plates


func _track_player(session: Variant, id: int, screen: Variant, jumped: bool) -> void:
	var stats: Variant = session.get("player_stats")
	if not stats is Dictionary or (stats as Dictionary).is_empty():
		_hp.erase(id)
		_level = null
		_cond_lo.erase(id)
		_cond_hi.erase(id)
		_pending_hp.erase(id)
		_pending_level = ""
		return
	var known: Dictionary = stats
	_note_hp(id, _stat_int(known, STAT_HP), screen, not jumped)
	_note_level(_stat_int(known, STAT_LEVEL), screen, not jumped)
	_note_condition(id, known, STAT_COND_LO, PARALYZED_BIT, "Paralyzed", screen, not jumped)
	_note_condition(id, known, STAT_COND_HI, NINJA_SPEEDY_BIT, "NinjaSpeedy", screen, not jumped)


func _track_enemy(session: Variant, frontend: Variant, entity: Variant, id: int, screen: Variant, jumped: bool, plates: Array) -> void:
	var stats := _enemy_stats(session, entity)
	_note_hp(id, _stat_int(stats, STAT_HP), screen, not jumped)
	_note_condition(id, stats, STAT_COND_LO, PARALYZED_BIT, "Paralyzed", screen, not jumped)
	_note_condition(id, stats, STAT_COND_HI, NINJA_SPEEDY_BIT, "NinjaSpeedy", screen, not jumped)
	if not screen is Vector2:
		return
	var name := _type_name(frontend, session, entity)
	var max_hp: Variant = _stat_int(stats, STAT_MAX_HP)
	var hp: Variant = _stat_int(stats, STAT_HP)
	var has_bar := max_hp is int and hp is int and int(max_hp) > 0
	if name == "" and not has_bar:
		return
	plates.append({
		"id": id,
		"name": name,
		"has_bar": has_bar,
		"hp": hp if hp is int else 0,
		"max_hp": max_hp if max_hp is int else 0,
		"screen": screen,
	})


func _note_hp(id: int, hp: Variant, screen: Variant, allow_cue: bool) -> void:
	if not hp is int:
		_hp.erase(id)
		_pending_hp.erase(id)
		return
	if not _hp.has(id):
		_hp[id] = int(hp)
		return
	var delta := int(hp) - int(_hp[id])
	_hp[id] = int(hp)
	if delta == 0 or not allow_cue:
		if not allow_cue:
			_pending_hp.erase(id)
			if delta != 0:
				_suppressed += 1
		return
	if not screen is Vector2:
		_suppressed += 1
		return
	var row: Dictionary = _pending_hp.get(id, {"amount": 0, "screen": screen})
	row["amount"] = int(row.get("amount", 0)) + delta
	row["screen"] = screen
	if int(row["amount"]) == 0:
		_pending_hp.erase(id)
	else:
		_pending_hp[id] = row


func _note_level(level: Variant, screen: Variant, allow_cue: bool) -> void:
	if not level is int:
		_level = null
		_pending_level = ""
		return
	if not _level is int:
		_level = int(level)
		return
	var previous := int(_level)
	_level = int(level)
	if int(level) <= previous or not allow_cue:
		if not allow_cue and int(level) != previous:
			_pending_level = ""
			_suppressed += 1
		return
	if not screen is Vector2:
		_suppressed += 1
		return
	_pending_level = "Level %d" % int(level)
	_pose["level_screen"] = screen


func _note_condition(id: int, stats: Dictionary, stat_id: int, bit: int, label: String, screen: Variant, allow_cue: bool) -> void:
	var store: Dictionary = _cond_lo if stat_id == STAT_COND_LO else _cond_hi
	var value: Variant = _stat_int(stats, stat_id)
	if not value is int:
		store.erase(id)
		return
	var mask := 1 << bit
	var now := int(value) & mask
	if not store.has(id):
		store[id] = int(value)
		return
	var was := int(store[id]) & mask
	store[id] = int(value)
	if was != 0 or now == 0 or not allow_cue:
		return
	if not screen is Vector2:
		_suppressed += 1
		return
	_pending_status.append({"id": id, "text": label, "screen": screen})


func _discontinuity(id: int, entity: Variant, screen: Variant) -> bool:
	var jumped := false
	if screen is Vector2 and _pose.has(id) and _pose[id] is Vector2:
		if (_pose[id] as Vector2).distance_to(screen) > TELEPORT_TILES * TILE_PX:
			jumped = true
	var auth: Variant = entity.get("authoritative_position")
	if auth is Vector2 and (auth as Vector2).is_finite() and _auth.has(id) and _auth[id] is Vector2:
		if (_auth[id] as Vector2).distance_to(auth) > TELEPORT_TILES:
			jumped = true
	return jumped


func _remember_pose(id: int, entity: Variant, screen: Variant) -> void:
	if screen is Vector2:
		_pose[id] = screen
	var auth: Variant = entity.get("authoritative_position")
	if auth is Vector2 and (auth as Vector2).is_finite():
		_auth[id] = auth


func _present_pending() -> void:
	for id in _pending_hp.keys():
		var row: Dictionary = _pending_hp[id]
		var amount := int(row.get("amount", 0))
		var screen: Variant = row.get("screen")
		if amount != 0 and screen is Vector2:
			_spawn_floater(int(id), amount, "heal" if amount > 0 else "damage", _amount_text(amount), screen)
	_pending_hp.clear()
	if _pending_level != "" and _pose.get("level_screen") is Vector2:
		_spawn_floater(_player_id, 0, "level", _pending_level, _pose["level_screen"])
	_pending_level = ""
	for item in _pending_status:
		if item is Dictionary and item.get("screen") is Vector2:
			_spawn_floater(int(item.get("id", -1)), 0, "status", str(item.get("text", "")), item["screen"])
	_pending_status.clear()
	_cap_floaters()


func _spawn_floater(id: int, amount: int, kind: String, text: String, screen: Vector2) -> void:
	if text == "":
		return
	_seq += 1
	var stack := _count_for(id)
	var region_id := "%s_%d_%d" % [kind, id, _seq]
	var label := _make_label(region_id, text, FONT_FLOAT, _floater_color(kind))
	_layer.add_child(label)
	label.set_meta("kind", kind)
	label.set_meta("entity_id", id)
	label.set_meta("amount", amount)
	label.set_meta("age", 0.0)
	label.set_meta("stack", stack)
	label.set_meta("screen", screen)
	label.set_meta("floater", true)
	var origin := _floater_origin(screen, text, stack)
	_place(label, origin, text, FONT_FLOAT)
	label.set_meta("base_y", label.position.y)


func _advance(delta: float) -> void:
	var stale: Array = []
	for label in _floater_nodes():
		var age := float(label.get_meta("age", 0.0)) + delta
		label.set_meta("age", age)
		label.modulate.a = fade_alpha(age)
		if age >= LIFE_S:
			stale.append(label)
	for label in stale:
		_free_node(label)


func _layout() -> void:
	var play := _playfield()
	for label in _floater_nodes():
		var age := float(label.get_meta("age", 0.0))
		var screen: Variant = label.get_meta("screen")
		if not screen is Vector2:
			continue
		var origin: Vector2 = _floater_origin(screen, label.text, int(label.get_meta("stack", 0)))
		origin.y -= rise_offset(age)
		_place_at(label, origin, label.text, FONT_FLOAT, play)
		label.modulate.a = fade_alpha(age)
	_layout_plates(play)


func _sync_plates() -> void:
	if _layer == null or not is_instance_valid(_layer):
		return
	var keep: Dictionary = {}
	for plate in _plates:
		if not plate is Dictionary:
			continue
		var id := int(plate.get("id", -1))
		var screen: Variant = plate.get("screen")
		if id < 0 or not screen is Vector2:
			continue
		var name := str(plate.get("name", ""))
		if name != "":
			var name_id := "name_%d" % id
			keep[name_id] = true
			var name_label := _ensure_label(name_id, name, FONT_NAME, _color_of("enemy"))
			name_label.set_meta("floater", false)
			name_label.set_meta("screen", screen)
			name_label.visible = true
		if plate.get("has_bar") == true:
			var bar_id := "bar_%d" % id
			keep[bar_id] = true
			var bar := _ensure_bar(bar_id, int(plate.get("hp", 0)), int(plate.get("max_hp", 1)))
			bar.set_meta("screen", screen)
			bar.visible = true
	var drop: Array = []
	for child in _layer.get_children():
		if not child is Control:
			continue
		var node := child as Control
		if bool(node.get_meta("floater", false)):
			continue
		if not keep.has(node.name):
			drop.append(node)
	for node in drop:
		_free_node(node)


func _layout_plates(play: Rect2) -> void:
	for child in _layer.get_children():
		if not child is Control or bool(child.get_meta("floater", false)):
			continue
		var screen: Variant = child.get_meta("screen", null)
		if not screen is Vector2:
			continue
		var control := child as Control
		if str(control.name).begins_with("name_"):
			var origin := (screen as Vector2) + Vector2(-8.0, -28.0)
			_place_at(control, origin, control.text if control is Label else "", FONT_NAME, play)
		elif str(control.name).begins_with("bar_"):
			var origin := (screen as Vector2) + Vector2(-8.0, -14.0)
			_place_at(control, origin, "", FONT_NAME, play)


func _place(label: Control, origin: Vector2, text: String, font_size: int) -> void:
	_place_at(label, origin, text, font_size, _playfield())


func _place_at(control: Control, origin: Vector2, text: String, font_size: int, play: Rect2) -> void:
	var size := control.size
	if control is Label:
		size = _text_size(text, font_size)
	elif size.x < 1.0:
		size = Vector2(BAR_W, BAR_H)
	control.size = size
	control.custom_minimum_size = size
	var clamped := _clamp_pos(origin, size, play)
	control.position = clamped
	var desired := Rect2(origin, size)
	var moved := clamped.distance_to(origin) > 0.5
	var outside := play.size.x < 1.0 or play.size.y < 1.0 or not play.encloses(Rect2(clamped, size))
	control.set_meta("clipped", moved or outside)
	control.visible = true


func _regions() -> Array:
	var rows: Array = []
	if _layer == null or not is_instance_valid(_layer):
		return rows
	for child in _layer.get_children():
		if not child is Control or not is_instance_valid(child) or not child.visible:
			continue
		var control := child as Control
		var rect := control.get_global_rect()
		var text: String = control.text if control is Label else ""
		rows.append({
			"id": str(control.name),
			"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
			"visible": control.visible,
			"clipped": bool(control.get_meta("clipped", false)),
			"text": text,
			"focusable": control.focus_mode != Control.FOCUS_NONE,
			"focused": control.has_focus(),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return rows


func _motion() -> Dictionary:
	var samples: Array = []
	for label in _floater_nodes():
		var base_y := float(label.get_meta("base_y", label.position.y))
		samples.append({
			"id": str(label.name),
			"age_s": float(label.get_meta("age", 0.0)),
			"alpha": label.modulate.a,
			"x": label.position.x,
			"y": label.position.y,
			"rise_px": base_y - label.position.y,
		})
	return {
		"time_source": "process_delta",
		"last_delta_s": _last_delta if _last_delta >= 0.0 else null,
		"integrated_s": _integrated,
		"fade_hold_s": HOLD_S,
		"fade_life_s": LIFE_S,
		"rise_px": RISE_PX,
		"rise_rate": RISE_RATE,
		"samples": samples,
	}


func _focus_owner() -> String:
	if _layer == null or not is_instance_valid(_layer):
		return ""
	for child in _layer.get_children():
		if child is Control and (child as Control).has_focus():
			return str(child.name)
	if has_focus():
		return str(name)
	return ""


func _pending_rows() -> Array:
	var rows: Array = []
	for id in _pending_hp.keys():
		rows.append({"id": int(id), "amount": int(_pending_hp[id].get("amount", 0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return rows


func _floater_nodes() -> Array:
	var found: Array = []
	if _layer == null or not is_instance_valid(_layer):
		return found
	for child in _layer.get_children():
		if child is Label and bool(child.get_meta("floater", false)) and is_instance_valid(child):
			found.append(child)
	return found


func _nodes_named(prefix: String) -> Array:
	var found: Array = []
	if _layer == null or not is_instance_valid(_layer):
		return found
	for child in _layer.get_children():
		if child is Control and str(child.name).begins_with(prefix) and child.visible:
			found.append(child)
	return found


func _cap_floaters() -> void:
	var by_entity: Dictionary = {}
	for label in _floater_nodes():
		var id := int(label.get_meta("entity_id", -1))
		if not by_entity.has(id):
			by_entity[id] = []
		(by_entity[id] as Array).append(label)
	for id in by_entity.keys():
		var group: Array = by_entity[id]
		while group.size() > MAX_PER_ENTITY:
			_free_node(group.pop_front())
	var all := _floater_nodes()
	while all.size() > MAX_GLOBAL:
		_free_node(all.pop_front())


func _count_for(id: int) -> int:
	var count := 0
	for label in _floater_nodes():
		if int(label.get_meta("entity_id", -1)) == id:
			count += 1
	return count


func _floater_origin(screen: Vector2, text: String, stack: int) -> Vector2:
	var size := _text_size(text, FONT_FLOAT)
	return screen + Vector2(8.0, -ORIGIN_CLEARANCE - size.y - float(stack) * STACK_PX)


func _make_label(region_id: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = region_id
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.clip_text = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", _color_of("ink"))
	label.add_theme_constant_override("outline_size", 1)
	label.modulate.a = 1.0
	var size := _text_size(text, font_size)
	label.size = size
	label.custom_minimum_size = size
	return label


func _ensure_label(region_id: String, text: String, font_size: int, color: Color) -> Label:
	var existing := _layer.get_node_or_null(region_id)
	if existing is Label:
		var label := existing as Label
		label.text = text
		label.add_theme_color_override("font_color", color)
		return label
	var label := _make_label(region_id, text, font_size, color)
	label.set_meta("floater", false)
	_layer.add_child(label)
	return label


func _ensure_bar(region_id: String, hp: int, max_hp: int) -> ColorRect:
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
	var existing := _layer.get_node_or_null(region_id)
	var track: ColorRect
	if existing is ColorRect:
		track = existing as ColorRect
	else:
		track = ColorRect.new()
		track.name = region_id
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.focus_mode = Control.FOCUS_NONE
		track.color = _color_of("slate")
		track.size = Vector2(BAR_W, BAR_H)
		track.custom_minimum_size = Vector2(BAR_W, BAR_H)
		track.set_meta("floater", false)
		var fill := ColorRect.new()
		fill.name = "fill"
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.focus_mode = Control.FOCUS_NONE
		fill.color = _color_of("hp")
		track.add_child(fill)
		_layer.add_child(track)
	track.color = _color_of("slate")
	var fill_node := track.get_node_or_null("fill")
	if fill_node is ColorRect:
		var fill := fill_node as ColorRect
		fill.color = _color_of("hp")
		fill.position = Vector2.ZERO
		fill.size = Vector2(BAR_W * ratio, BAR_H)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return track


func _floater_color(kind: String) -> Color:
	if kind == "heal":
		return _color_of("paper")
	if kind == "level":
		return _color_of("gold")
	if kind == "status":
		return _color_of("steel")
	return _color_of("hp")


func _color_of(key: String) -> Color:
	var tokens := _theme_tokens()
	var value: Variant = tokens.get(key, null)
	if not _is_color_value(value) and _alias_of(key) != "":
		value = tokens.get(_alias_of(key), null)
	var parsed: Variant = _parse_color(value)
	if parsed is Color:
		return parsed
	var fallback: Variant = _parse_color(_fallback_tokens().get(key, "#d4d4d4"))
	return fallback if fallback is Color else Color("#d4d4d4")


func _theme_tokens() -> Dictionary:
	if _tokens_from_file and not _tokens.is_empty():
		return _tokens
	var path := THEME_PATH
	if ResourceLoader.exists(path):
		var loaded: Variant = load(path)
		if loaded is GDScript:
			var instance: Variant = (loaded as GDScript).new()
			var value: Variant = null
			if instance != null and instance.has_method("tokens"):
				value = instance.call("tokens")
			if instance is Node:
				(instance as Node).free()
			if value is Dictionary:
				_tokens = _normalize_tokens(value)
				_tokens_from_file = true
				return _tokens
	if _tokens.is_empty():
		_tokens = _fallback_tokens()
	return _tokens


func _normalize_tokens(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	for pair in [["ink", "void"], ["slate", "charcoal"], ["steel", "muted"], ["paper", "silver"], ["danger", "hp"]]:
		if out.has(pair[0]) and not out.has(pair[1]):
			out[pair[1]] = out[pair[0]]
		elif out.has(pair[1]) and not out.has(pair[0]):
			out[pair[0]] = out[pair[1]]
	var fallback := _fallback_tokens()
	for key in fallback.keys():
		if not out.has(key):
			out[key] = fallback[key]
	return out


func _fallback_tokens() -> Dictionary:
	# Final fsod-ui-theme/2 contract. Used only when ui_theme.gd is absent.
	return {
		"charcoal": "#333333", "slot": "#515151", "slot_edge": "#2a2a2a",
		"silver": "#d4d4d4", "muted": "#9a9a9a", "gold": "#efcf7a",
		"hp": "#fc3436", "mp": "#648dff", "xp": "#5b832b", "fame": "#ff8a1a",
		"player": "#ffe500", "enemy": "#ff3b4a", "portal": "#3d8bff", "void": "#1a1a1a",
		"ink": "#1a1a1a", "slate": "#333333", "steel": "#9a9a9a", "paper": "#d4d4d4",
		"danger": "#fc3436", "corners": 0,
	}


func _alias_of(key: String) -> String:
	match key:
		"ink": return "void"
		"slate": return "charcoal"
		"steel": return "muted"
		"paper": return "silver"
		"danger": return "hp"
		"void": return "ink"
		"charcoal": return "slate"
		"muted": return "steel"
		"silver": return "paper"
		"hp": return "danger"
		_: return ""


func _parse_color(value: Variant) -> Variant:
	if value is Color:
		return value
	if value is String:
		var text: String = (value as String).strip_edges()
		if text == "":
			return null
		if not text.begins_with("#"):
			text = "#" + text
		if Color.html_is_valid(text):
			return Color(text)
	return null


func _is_color_value(value: Variant) -> bool:
	return _parse_color(value) is Color


func _screen_pose(entity: Variant) -> Variant:
	if not _is_node(entity) or not entity.has_method("display_position"):
		return null
	var pose: Variant = entity.call("display_position")
	if not pose is Vector2 or not (pose as Vector2).is_finite():
		return null
	var parent: Node = entity.get_parent()
	if not parent is Node2D:
		return null
	var global: Vector2 = (parent as Node2D).to_global(pose)
	if not global.is_finite():
		return null
	return global


func _enemy_stats(session: Variant, entity: Variant) -> Dictionary:
	var merged: Dictionary = {}
	var local: Variant = entity.get("stats")
	if local is Dictionary:
		merged = (local as Dictionary).duplicate()
	var states: Variant = session.get("entity_states")
	if not states is Dictionary:
		return merged
	var id: Variant = entity.get("entity_id")
	var snap: Variant = (states as Dictionary).get(id, (states as Dictionary).get(str(id), {}))
	if snap is Dictionary and (snap as Dictionary).get("stats") is Dictionary:
		var extra: Dictionary = (snap as Dictionary)["stats"]
		for key in extra.keys():
			if not merged.has(key):
				merged[key] = extra[key]
	return merged


func _type_name(frontend: Variant, session: Variant, entity: Variant) -> String:
	var object_type: Variant = entity.get("object_type")
	if not (object_type is int or object_type is float):
		return ""
	var type := int(object_type)
	for source in [frontend.get("descriptors"), session.get("metadata")]:
		if not source is Dictionary:
			continue
		var objects: Variant = (source as Dictionary).get("objects", {})
		if not objects is Dictionary:
			continue
		var record: Variant = (objects as Dictionary).get(type, (objects as Dictionary).get(str(type), {}))
		if record is Dictionary:
			var name := str((record as Dictionary).get("name", (record as Dictionary).get("id", ""))).strip_edges()
			if name != "":
				return name
	return ""


func _stat_int(stats: Dictionary, id: int) -> Variant:
	var value: Variant = null
	if stats.has(id):
		value = stats[id]
	elif stats.has(str(id)):
		value = stats[str(id)]
	else:
		return null
	if not (value is int or value is float) or not is_finite(float(value)):
		return null
	if not is_equal_approx(float(value), round(float(value))):
		return null
	return int(round(float(value)))


func _amount_text(delta: int) -> String:
	return str(delta) if delta < 0 else "+%d" % delta


func _text_size(text: String, font_size: int) -> Vector2:
	var font := ThemeDB.fallback_font
	if font == null:
		return Vector2(maxf(8.0, float(text.length()) * 7.0), float(font_size) + 2.0)
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(maxf(measured.x + 2.0, 4.0), maxf(measured.y + 2.0, float(font_size)))


func _playfield() -> Rect2:
	var viewport := _viewport_size()
	var rail := _rail_width()
	var right := viewport.x - rail - MARGIN
	var bottom := viewport.y - MARGIN
	return Rect2(MARGIN, MARGIN, maxf(0.0, right - MARGIN), maxf(0.0, bottom - MARGIN))


func _clamp_pos(origin: Vector2, size: Vector2, play: Rect2) -> Vector2:
	if play.size.x < 1.0 or play.size.y < 1.0:
		return origin
	var max_x := play.position.x
	var max_y := play.position.y
	if size.x < play.size.x:
		max_x = play.end.x - size.x
	if size.y < play.size.y:
		max_y = play.end.y - size.y
	return Vector2(clampf(origin.x, play.position.x, max_x), clampf(origin.y, play.position.y, max_y))


func _rail_width() -> float:
	return _rail if is_finite(_rail) and _rail >= 0.0 else RAIL_FALLBACK


func _read_rail(frontend: Variant) -> float:
	var value: Variant = null
	var script: Variant = frontend.get_script() if frontend is Object else null
	if script is Script:
		var constants: Dictionary = (script as Script).get_script_constant_map()
		if constants.has("RAIL_WIDTH"):
			value = constants["RAIL_WIDTH"]
	if not (value is int or value is float):
		value = frontend.get("RAIL_WIDTH")
	if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0:
		return float(value)
	return RAIL_FALLBACK


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var rect := vp.get_visible_rect()
	if not rect.size.is_finite() or rect.size.x < 2.0 or rect.size.y < 2.0:
		return Vector2.ZERO
	return rect.size


func _reset_tracking(reason: String) -> void:
	_hp.clear()
	_level = null
	_cond_lo.clear()
	_cond_hi.clear()
	_pose.clear()
	_auth.clear()
	_pending_hp.clear()
	_pending_level = ""
	_pending_status.clear()
	_plates = []
	_suppressed = 0
	_last_reset = reason
	_playing = false


func _drop_unseen(seen: Dictionary) -> void:
	for id in _hp.keys():
		if not seen.has(id):
			_hp.erase(id)
			_pending_hp.erase(id)
			_cond_lo.erase(id)
			_cond_hi.erase(id)
			_pose.erase(id)
			_auth.erase(id)
	var stale: Array = []
	for label in _floater_nodes():
		if not seen.has(int(label.get_meta("entity_id", -1))):
			stale.append(label)
	for label in stale:
		_free_node(label)


func _free_floaters() -> void:
	for label in _floater_nodes():
		_free_node(label)


func _free_feedback_nodes() -> void:
	if _layer == null or not is_instance_valid(_layer):
		return
	var children: Array = _layer.get_children()
	for child in children:
		_free_node(child)


func _free_node(node: Variant) -> void:
	if not node is Node or not is_instance_valid(node):
		return
	var item := node as Node
	if item is CanvasItem:
		(item as CanvasItem).visible = false
	var parent := item.get_parent()
	if parent != null:
		parent.remove_child(item)
	item.queue_free()


func _entity_id(entity: Variant, key: Variant) -> int:
	var from_entity: Variant = entity.get("entity_id")
	if from_entity is int and int(from_entity) >= 0:
		return int(from_entity)
	if from_entity is float and is_finite(float(from_entity)) and int(from_entity) >= 0:
		return int(from_entity)
	if key is int:
		return int(key)
	if key is float and is_finite(float(key)):
		return int(key)
	if key is String and (key as String).is_valid_int():
		return int(key)
	return -1


func _kind(entity: Variant) -> String:
	var kind: Variant = entity.get("kind")
	return str(kind).to_lower() if kind is String else ""


func _is_node(value: Variant) -> bool:
	return is_instance_valid(value) and value is Node


func _string_prop(node: Variant, key: String) -> String:
	var value: Variant = node.get(key)
	return str(value) if value != null else ""


func _int_prop(node: Variant, key: String, fallback: int) -> int:
	var value: Variant = node.get(key)
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return int(value)
