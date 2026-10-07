# SPDX-License-Identifier: AGPL-3.0-only
# Realm entry overlay for the original-FSoD Godot frontend.
# Display ONLY: labels streamed portals + actionable E prompt + Nexus
# direction/distance. Emits no gameplay/transport requests, mutates no
# authority, touches no input/focus. Walkingwriter owns world_view,
# entity_view and session: this file NEVER writes them.
# Display reads use ONLY named existing world fields/get methods (entities,
# interaction_target_id, map_name, get_global_position(), display_position(),
# position, get_viewport().get_visible_rect()); rail/palette/clamp are local
# layout helpers. Session reads are readonly snapshots (state, player_id,
# pending_position, entity_states, object_types, metadata), single pass per
# refresh (called once per frame from entry _process).
extends CanvasLayer

const REALM_PORTAL_TYPE: int = 1810 # 0x0712 Nexus Portal, bound-realm use.
const INTERACT_RANGE_TILES: float = 1.0 # Matches session _update_interaction_target.
const TILE_PIXELS: float = 32.0 # Matches world_view.TILE_PIXELS. Display read only.
const RAIL_WIDTH: float = 256.0 # Layout helper mirroring world_view.RAIL_WIDTH.
const MAX_PORTAL_LABELS: int = 8
const LABEL_TRUNC: int = 28
const PANEL_POS := Vector2(16, 80) # Below entry status(16,16)/button(16,48).
const THEME_SCRIPT := "res://src/client/fsod/ui_theme.gd"
var _palette: Dictionary = {}

var _panel: PanelContainer
var _direction_label: Label
var _prompt_label: Label
var _hint_label: Label
var _portal_labels: Dictionary = {} # entity id -> Label.
var _ready_built: bool = false


func _ready() -> void:
	layer = 90
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _ready_built:
		return
	_ready_built = true
	if ResourceLoader.exists(THEME_SCRIPT):
		var theme: Variant = load(THEME_SCRIPT)
		if theme.has_method("tokens"):
			_palette = theme.tokens()
	_panel = PanelContainer.new()
	_panel.name = "RealmGuidePanel"
	_panel.position = PANEL_POS
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = _color("charcoal", Color("333333"))
	style.set_corner_radius_all(0)
	style.set_content_margin_all(4.0)
	_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_direction_label = Label.new()
	_direction_label.add_theme_color_override("font_color", _color("silver", Color("d4d4d4")))
	_direction_label.add_theme_font_size_override("font_size", 14)
	_direction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_direction_label.focus_mode = Control.FOCUS_NONE
	column.add_child(_direction_label)
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", _color("gold", Color("efcf7a")))
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.focus_mode = Control.FOCUS_NONE
	column.add_child(_prompt_label)
	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_color", _color("muted", Color("9a9a9a")))
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.focus_mode = Control.FOCUS_NONE
	column.add_child(_hint_label)
	add_child(_panel)
	_panel.visible = false


func _color(key: String, fallback: Color) -> Color:
	var value: Variant = _palette.get(key, fallback)
	return value if value is Color else (Color(value) if value is String else fallback)


static func is_realm_type(object_type: int) -> bool:
	return object_type == REALM_PORTAL_TYPE


static func type_record(metadata: Dictionary, object_type: int) -> Dictionary:
	var objects: Variant = metadata.get("objects", {})
	if not objects is Dictionary:
		return {}
	var result: Variant = objects.get(str(object_type), objects.get(object_type, {}))
	return result if result is Dictionary else {}


static func is_portal_class(metadata: Dictionary, object_type: int) -> bool:
	var record: Dictionary = type_record(metadata, object_type)
	var cls: String = String(record.get("class", record.get("kind", ""))).to_lower()
	return cls == "portal"


static func is_guide_portal(metadata: Dictionary, object_type: int) -> bool:
	# Numeric 0x0712 is always a realm portal even when descriptor metadata is
	# sparse (object_descriptors lacks 1810); other types need Portal class.
	return is_realm_type(object_type) or is_portal_class(metadata, object_type)


static func type_name(metadata: Dictionary, object_type: int) -> String:
	# TypeName is never altered: no localization cleanup here.
	return String(type_record(metadata, object_type).get("name", ""))


static func clean_world_name(value: Variant) -> String:
	# WorldName (wire stat 31) cleanup ONLY. TypeName is never passed here.
	# Source bound realms are Name=world.Name, e.g. NexusPortal.Dragon, or a
	# braced localization key {ns.Name}. Both keep the last segment only.
	if not value is String:
		return ""
	var text: String = value.strip_edges()
	if text.is_empty():
		return ""
	if text.begins_with("{") and text.ends_with("}"):
		text = text.substr(1, text.length() - 2).strip_edges()
	var dot: int = text.rfind(".")
	if dot >= 0:
		text = text.substr(dot + 1)
	text = text.replace("_", " ").strip_edges()
	if text.is_empty():
		return ""
	return text.left(LABEL_TRUNC).strip_edges()


static func portal_label(metadata: Dictionary, object_type: int, stats: Dictionary) -> String:
	var world: String = clean_world_name(stats.get(31, ""))
	var typed: String = type_name(metadata, object_type)
	if is_realm_type(object_type):
		if not world.is_empty():
			return world
		if not typed.is_empty():
			return typed.left(LABEL_TRUNC)
		return ""
	if not typed.is_empty():
		return typed.left(LABEL_TRUNC)
	if not world.is_empty():
		return world
	return ""


static func compass(delta: Vector2) -> String:
	var ew: String = ""
	var ns: String = ""
	if delta.x > 0.5:
		ew = "east"
	elif delta.x < -0.5:
		ew = "west"
	if delta.y > 0.5:
		ns = "south" # Tile +y is screen-south.
	elif delta.y < -0.5:
		ns = "north"
	if not ns.is_empty() and not ew.is_empty():
		return ns + "-" + ew
	if not ns.is_empty():
		return ns
	if not ew.is_empty():
		return ew
	return "here"


static func format_distance(tiles: float) -> String:
	if not is_finite(tiles) or tiles < 0.0:
		return "?. tiles"
	var whole: int = maxi(1, roundi(tiles))
	return "%d tile%s" % [whole, "" if whole == 1 else "s"]


static func clamp_label(screen: Vector2, viewport: Vector2) -> Vector2:
	var x_max: float = maxf(4.0, viewport.x - RAIL_WIDTH - 100.0)
	var y_max: float = maxf(84.0, viewport.y - 30.0)
	return Vector2(clampf(screen.x - 40.0, 4.0, x_max), clampf(screen.y - 34.0, 84.0, y_max))


func is_guide_visible() -> bool:
	return _ready_built and is_instance_valid(_panel) and _panel.visible


func guide_prompt_text() -> String:
	return _prompt_label.text if _ready_built and is_instance_valid(_prompt_label) else ""


func guide_direction_text() -> String:
	return _direction_label.text if _ready_built and is_instance_valid(_direction_label) else ""


func guide_hint_text() -> String:
	return _hint_label.text if _ready_built and is_instance_valid(_hint_label) else ""


func visible_portal_count() -> int:
	var total: int = 0
	for id in _portal_labels:
		var label: Variant = _portal_labels[id]
		if label is Label and is_instance_valid(label) and (label as Label).visible:
			total += 1
	return total


func portal_label_position(entity_id: int) -> Vector2:
	var label: Variant = _portal_labels.get(entity_id)
	if label is Label and is_instance_valid(label) and (label as Label).visible:
		return (label as Label).position
	return Vector2(INF, INF)


static func is_nexus_map(map_value: Variant) -> bool:
	# The original hub world is named exactly Nexus. A substring match treats
	# NexusPortal.Sprite / NexusPortal.Dragon as the hub and leaves the explore
	# line up after a real realm entry.
	if not map_value is String:
		return false
	return (map_value as String).strip_edges().to_lower() == "nexus"


func _set_visible(value: bool) -> void:
	_ensure_nodes()
	_panel.visible = value
	if not value:
		_direction_label.text = ""
		_prompt_label.text = ""
		_hint_label.text = ""
		_prompt_label.visible = false
		_hint_label.visible = false
		for id in _portal_labels:
			var label: Variant = _portal_labels[id]
			if label is Label and is_instance_valid(label):
				(label as Label).visible = false


func _display_global(view: Variant) -> Variant:
	# Display transform via named Node2D methods/fields only: never reads
	# private _world/_camera state. Prefers the render pose when exposed.
	if not is_instance_valid(view) or not (view is Node2D):
		return null
	var node: Node2D = view
	if not node.is_inside_tree():
		return null
	var base: Vector2 = node.get_global_position()
	if not base.is_finite():
		return null
	if view.has_method("display_position"):
		var pose: Variant = view.call("display_position")
		if pose is Vector2 and (pose as Vector2).is_finite() and node.position.is_finite():
			var offset: Vector2 = (pose as Vector2) - node.position
			if offset.is_finite() and offset.length() < 512.0:
				base += offset
	return base


func _displayed_player_tiles(frontend: Node, player_id: int) -> Variant:
	# Local/remote render pose is in the same pixel space as Node2D.position
	# (tile * 32). Camera smoothing moves _world, not this tile pose, so
	# compass distance stays in source tiles while labels use global pixels.
	var views_raw: Variant = frontend.get("entities")
	if not views_raw is Dictionary:
		return null
	var views: Dictionary = views_raw
	var view: Variant = views.get(player_id, views.get(str(player_id)))
	if not is_instance_valid(view) or not (view is Node2D):
		return null
	var node: Node2D = view
	var pixels: Vector2 = node.position
	if view.has_method("display_position"):
		var pose: Variant = view.call("display_position")
		if pose is Vector2 and (pose as Vector2).is_finite():
			pixels = pose
	if not pixels.is_finite():
		return null
	return pixels / TILE_PIXELS


func _viewport_size() -> Vector2:
	var fallback := Vector2(1280, 720)
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return fallback
	var size: Vector2 = viewport.get_visible_rect().size
	if not size.is_finite() or size.x < 100.0 or size.y < 100.0:
		return fallback
	return size


## Readonly single-pass poll. Called once per frame from entry _process.
## Never emits signals, never writes session/frontend/transport.
func refresh(session: Node, frontend: Node) -> void:
	_ensure_nodes()
	if session == null or frontend == null:
		_set_visible(false)
		return
	if not is_instance_valid(session) or not is_instance_valid(frontend):
		_set_visible(false)
		return
	if String(session.get("state")) != "playing":
		_set_visible(false)
		return
	var map_value: Variant = frontend.get("map_name")
	# Hub only. Bound realms are named NexusPortal.Sprite / Dragon / etc.
	if not is_nexus_map(map_value):
		_set_visible(false)
		return
	var player_raw: Variant = session.get("player_id")
	if not (player_raw is int or player_raw is float) or int(player_raw) < 0:
		_set_visible(false)
		return
	var pending_raw: Variant = session.get("pending_position")
	if not pending_raw is Vector2 or not (pending_raw as Vector2).is_finite():
		_set_visible(false)
		return
	var pending: Vector2 = pending_raw
	var states_raw: Variant = session.get("entity_states")
	var types_raw: Variant = session.get("object_types")
	var meta_raw: Variant = session.get("metadata")
	if not states_raw is Dictionary or not types_raw is Dictionary or not meta_raw is Dictionary:
		_set_visible(false)
		return
	var states: Dictionary = states_raw
	var types: Dictionary = types_raw
	var metadata: Dictionary = meta_raw
	var target_raw: Variant = frontend.get("interaction_target_id")
	var interaction_target: int = -1
	if target_raw is int or target_raw is float:
		interaction_target = int(target_raw)
	# Single pass: collect streamed portals from authoritative snapshots.
	var portals: Array = []
	var by_id: Dictionary = {}
	for id in states:
		var eid: int = int(id)
		var type_raw: Variant = types.get(eid, types.get(str(eid), -1))
		if not (type_raw is int or type_raw is float):
			continue
		var object_type: int = int(type_raw)
		if not is_guide_portal(metadata, object_type):
			continue
		var record: Variant = states[id]
		if not record is Dictionary:
			continue
		var pos_raw: Variant = (record as Dictionary).get("position")
		if not pos_raw is Vector2 or not (pos_raw as Vector2).is_finite():
			continue
		var stats_raw: Variant = (record as Dictionary).get("stats", {})
		var stats: Dictionary = stats_raw if stats_raw is Dictionary else {}
		var label: String = portal_label(metadata, object_type, stats)
		var entry: Dictionary = {
			"id": eid, "type": object_type, "pos": pos_raw,
			"stats": stats, "label": label,
			"is_realm": is_realm_type(object_type),
		}
		portals.append(entry)
		by_id[eid] = entry
	# Direction uses the rendered avatar tile pose when the frontend has one.
	# Session pending_position is what E's hidden target was computed from, and
	# a fixture (or a prediction lead) can put that next to a portal while the
	# sprite is still tiles away. "here" must match the sprite, not that lead.
	var anchor: Vector2 = pending
	var displayed: Variant = _displayed_player_tiles(frontend, int(player_raw))
	if displayed is Vector2 and (displayed as Vector2).is_finite():
		anchor = displayed
	for portal in portals:
		portal["dist"] = anchor.distance_to(portal["pos"])
	# Nearest streamed REALM (0x0712 only); other portals never steer direction.
	var nearest: Dictionary = {}
	for portal in portals:
		if not bool(portal.get("is_realm", false)):
			continue
		if nearest.is_empty() or float(portal["dist"]) < float(nearest["dist"]):
			nearest = portal
	var viewport: Vector2 = _viewport_size()
	var direction_text: String
	var prompt_text: String = ""
	var hint_text: String = ""
	if nearest.is_empty():
		direction_text = "Explore Nexus to find a realm portal"
	else:
		var delta: Vector2 = (nearest["pos"] as Vector2) - anchor
		var realm_label: String = String(nearest.get("label", ""))
		if realm_label.is_empty():
			realm_label = "Realm portal"
		direction_text = "%s · %s %s" % [realm_label, compass(delta), format_distance(float(nearest["dist"]))]
		if by_id.has(interaction_target):
			var actual: Dictionary = by_id[interaction_target]
			var actual_label: String = String(actual.get("label", ""))
			if bool(actual.get("is_realm", false)):
				prompt_text = "E · Enter realm %s" % actual_label if not actual_label.is_empty() else "E · Enter realm"
			else:
				prompt_text = "E · Enter %s" % actual_label if not actual_label.is_empty() else "E · Enter portal"
		elif interaction_target >= 0:
			# Actual E target is a bag/container (or unknown): E will not use the
			# realm portal, so show stand-closer instead of an E realm prompt.
			var realm_short: String = String(nearest.get("label", ""))
			if realm_short.is_empty():
				realm_short = "the realm portal"
			hint_text = "Stand closer to %s, then press E" % realm_short
		else:
			var realm_short2: String = String(nearest.get("label", ""))
			if realm_short2.is_empty():
				realm_short2 = "the realm portal"
			hint_text = "Stand closer to %s, then press E" % realm_short2
	_direction_label.text = direction_text.left(64)
	_prompt_label.text = prompt_text.left(48)
	_prompt_label.visible = not prompt_text.is_empty()
	_hint_label.text = hint_text.left(72)
	_hint_label.visible = not hint_text.is_empty()
	_panel.position = PANEL_POS
	_panel.visible = true
	# Container minimum sizes update after the visibility changes. Shrink stale
	# empty rows instead of retaining the initial three-label card height.
	_panel.call_deferred("reset_size")
	# Floating SOURCE labels for on-screen portals only; off-screen portals keep
	# direction-line guidance with no guessed coordinates.
	var views_raw: Variant = frontend.get("entities")
	var views: Dictionary = views_raw if views_raw is Dictionary else {}
	var ranked: Array = portals.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	var shown: Dictionary = {}
	var placed: int = 0
	for portal in ranked:
		if placed >= MAX_PORTAL_LABELS:
			break
		var label_text: String = String(portal.get("label", ""))
		if label_text.is_empty():
			continue
		var view: Variant = views.get(int(portal["id"]), views.get(str(portal["id"])))
		var screen: Variant = _display_global(view)
		if not screen is Vector2 or not (screen as Vector2).is_finite():
			continue
		var point: Vector2 = screen
		if point.x < -64.0 or point.y < -64.0 or point.x > viewport.x + 64.0 or point.y > viewport.y + 64.0:
			continue
		var node: Label = _portal_labels.get(int(portal["id"]))
		if not is_instance_valid(node):
			node = Label.new()
			node.add_theme_color_override("font_color", Color("f9de86"))
			node.add_theme_color_override("font_shadow_color", _color("void", Color("1a1a1a")))
			node.add_theme_constant_override("shadow_offset_x", 1)
			node.add_theme_constant_override("shadow_offset_y", 1)
			node.add_theme_font_size_override("font_size", 13)
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.focus_mode = Control.FOCUS_NONE
			add_child(node)
			_portal_labels[int(portal["id"])] = node
		node.text = label_text
		node.position = clamp_label(point, viewport)
		node.visible = true
		shown[int(portal["id"])] = true
		placed += 1
	for id in _portal_labels.keys():
		if not shown.has(id):
			var stale: Variant = _portal_labels[id]
			if stale is Label and is_instance_valid(stale):
				(stale as Label).visible = false
