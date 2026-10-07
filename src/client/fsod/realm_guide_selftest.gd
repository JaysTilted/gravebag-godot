# SPDX-License-Identifier: AGPL-3.0-only
# Realm guide overlay checks: real world_view display reads only, mock session
# snapshots. No live server, no transport writes, no focus/input theft.
# Covers Nexus far/near/unknown/bag-closer/non-realm-nearer/realm/removed/
# busy, viewport small/large clamps, localization cleanup, zero requests, and
# (under xvfb --capture-dir) a real 1280x720 rendered frame with source name
# and E prompt. Must not edit world_view/entity_view/session/entry.
extends SceneTree

const World = preload("res://src/client/fsod/world_view.gd")
const Guide = preload("res://src/client/fsod/realm_guide.gd")

var failures: int = 0
var checks: int = 0


class MockSession extends Node:
	var state: String = "playing"
	var player_id: int = 1
	var pending_position := Vector2.ZERO
	var entity_states: Dictionary = {}
	var object_types: Dictionary = {}
	var metadata: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _metadata() -> Dictionary:
	return {"objects": {
		"782": {"name": "Wizard", "class": "Player"},
		"1810": {"name": "Nexus Portal", "class": "Portal"},
		"1821": {"name": "Portal to Nexus", "class": "Portal"},
		"400": {"name": "Bag", "class": "Container"},
	}}


func _descriptors() -> Dictionary:
	return {"objects": {
		782: {"kind": "player", "name": "Wizard", "class": "Player"},
		1810: {"kind": "portal", "name": "Nexus Portal", "class": "Portal"},
		1821: {"kind": "portal", "name": "Portal to Nexus", "class": "Portal"},
		400: {"kind": "container", "name": "Bag", "class": "Container"},
	}, "tiles": {1: {"color": "#354c40"}}}


func _make_world() -> Node2D:
	var world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.set_descriptors(_descriptors())
	world.set_player_id(1)
	world.apply_map({"width": 60, "height": 40, "name": "Nexus"})
	world.apply_update({"tiles": [{"x": 10, "y": 10, "tile": 1}], "new_objects": [
		{"object_type": 782, "stats": {"id": 1, "position": {"x": 10.0, "y": 10.0}, "stats": {0: 100, 1: 80}}},
	]})
	return world


func _make_session(player_pos: Vector2) -> MockSession:
	var session := MockSession.new()
	root.add_child(session)
	session.metadata = _metadata()
	session.pending_position = player_pos
	session.entity_states[1] = {"position": player_pos, "stats": {}}
	session.object_types[1] = 782
	return session


func _add_portal(session: MockSession, world: Node2D, id: int, object_type: int, pos: Vector2, stats: Dictionary = {}) -> void:
	session.entity_states[id] = {"position": pos, "stats": stats}
	session.object_types[id] = object_type
	world.apply_update({"new_objects": [
		{"object_type": object_type, "stats": {"id": id, "position": {"x": pos.x, "y": pos.y}, "stats": stats}},
	]})


func _run() -> void:
	_static_checks()
	await _far_near_unknown()
	await _bag_closer_nonrealm()
	await _realm_removed_busy()
	await _smoothed_camera_labels()
	_viewport_clamps()
	await _zero_requests()
	var capture_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	if capture_dir != "":
		await _render_capture(capture_dir)
	_cleanup()
	await process_frame
	print("FSOD REALM GUIDE PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _static_checks() -> void:
	_check(Guide.is_realm_type(1810), "0x0712 is the realm type")
	_check(not Guide.is_realm_type(1821), "other portals are not the realm type")
	_check(Guide.is_guide_portal(_metadata(), 1810), "realm portal recognized by number")
	_check(Guide.is_guide_portal(_metadata(), 1821), "dungeon portal recognized by class")
	_check(not Guide.is_guide_portal(_metadata(), 782), "player is not a portal")
	_check(Guide.type_name(_metadata(), 1810) == "Nexus Portal", "typeName preserved verbatim")
	_check(Guide.clean_world_name("Dragon") == "Dragon", "plain WorldName kept")
	_check(Guide.clean_world_name("{objects.Dragon}") == "Dragon", "braced WorldName cleaned")
	_check(Guide.clean_world_name("{realm.Dragon_Realm}") == "Dragon Realm", "underscore WorldName spaced")
	_check(Guide.clean_world_name("NexusPortal.Dragon") == "Dragon", "source realm id keeps the realm segment")
	_check(Guide.clean_world_name("NexusPortal.Cube") == "Cube", "source Cube realm id cleaned")
	_check(Guide.portal_label(_metadata(), 1810, {31: "NexusPortal.Dragon"}) == "Dragon", "0x0712 label uses cleaned source Name")
	_check(Guide.clean_world_name("") == "", "empty WorldName stays empty")
	_check(Guide.clean_world_name(42) == "", "non-string WorldName never fabricated")
	_check(Guide.portal_label(_metadata(), 1810, {31: "Dragon"}) == "Dragon", "realm prefers source WorldName")
	_check(Guide.portal_label(_metadata(), 1810, {}) == "Nexus Portal", "realm without WorldName falls back to typeName")
	_check(Guide.portal_label(_metadata(), 1821, {31: "Ignored"}) == "Portal to Nexus", "non-realm keeps typeName over WorldName")
	_check(Guide.portal_label({"objects": {}}, 1810, {}) == "", "unknown realm metadata never invents a name")
	_check(Guide.compass(Vector2(5, 0)) == "east", "compass east")
	_check(Guide.compass(Vector2(-5, 0.1)) == "west", "compass west")
	_check(Guide.compass(Vector2(0, -5)) == "north", "compass north (-y)")
	_check(Guide.compass(Vector2(0, 5)) == "south", "compass south (+y)")
	_check(Guide.compass(Vector2(5, -5)) == "north-east", "compass diagonal")
	_check(Guide.format_distance(10.4) == "10 tiles", "distance rounds to tiles")
	_check(Guide.format_distance(0.2) == "1 tile", "sub-tile distance floors to 1 tile")


func _far_near_unknown() -> void:
	var world := _make_world()
	var guide = Guide.new()
	root.add_child(guide)
	var session := _make_session(Vector2(10, 10))
	_add_portal(session, world, 50, 1810, Vector2(20, 10), {31: "Dragon"})
	world.interaction_target_id = -1
	guide.refresh(session, world)
	_check(guide.is_guide_visible(), "far Nexus shows the guide")
	_check(guide.guide_direction_text().contains("Dragon"), "far direction names the source realm")
	_check(guide.guide_direction_text().contains("east"), "far direction points east to the streamed portal")
	_check(guide.guide_direction_text().contains("10 tile"), "far direction carries real tile distance")
	_check(guide.guide_prompt_text() == "", "far out-of-range shows no E prompt")
	_check(guide.guide_hint_text().contains("Stand closer"), "far out-of-range shows stand-closer hint")
	_check(guide.guide_hint_text().contains("Dragon"), "far hint names the realm portal")
	_check(guide.visible_portal_count() >= 1, "far on-screen portal gets a floating source label")
	# Forged session pending next to the portal; avatar node stays at spawn (10, 10).
	# (20.5 - 10) * 32 = 336px. Direction must follow the sprite, not that lead.
	# E prompt still follows the forced interaction target, because that is what E sends.
	session.pending_position = Vector2(20, 10)
	session.entity_states[1].position = Vector2(20, 10)
	world.interaction_target_id = 50
	guide.refresh(session, world)
	_check(guide.guide_prompt_text() == "E · Enter realm Dragon", "E prompt follows interaction_target even if the sprite has not arrived")
	_check(not guide.guide_direction_text().contains("here"), "forged session pending must not claim here while the avatar is still at spawn")
	_check(guide.guide_direction_text().contains("east"), "direction follows the displayed avatar, east of spawn")
	_check(guide.guide_hint_text() == "", "actual portal E target clears the stand-closer hint")
	# Move the avatar onto the session pose. Half a tile from the ring is 16px, not 336px.
	_sync_player(world, session, Vector2(20, 10))
	guide.refresh(session, world)
	_check(guide.guide_prompt_text() == "E · Enter realm Dragon", "near E prompt uses source WorldName")
	_check(guide.guide_hint_text() == "", "near in-range clears the stand-closer hint")
	_check(guide.guide_direction_text().contains("Dragon"), "near direction keeps the realm label")
	_check(guide.guide_direction_text().contains("here"), "synced avatar next to the ring may say here")
	var synced_gap: float = _sprite_gap(world, 1, 50)
	_check(synced_gap < 48.0, "synced avatar is within 1.5 tiles of the ring (got %.1f px)" % synced_gap)
	# Unknown WorldName: fall back to typeName, never fabricate.
	session.entity_states[50].stats = {}
	world.interaction_target_id = 50
	guide.refresh(session, world)
	_check(guide.guide_prompt_text() == "E · Enter realm Nexus Portal", "unknown WorldName falls back to Nexus Portal")
	_check(guide.guide_direction_text().contains("Nexus Portal"), "unknown direction falls back to typeName")
	session.free()
	guide.free()
	world.free()
	await process_frame


func _sync_player(world: Node2D, session: MockSession, pos: Vector2) -> void:
	session.pending_position = pos
	session.entity_states[1]["position"] = pos
	var player: Variant = world.entities.get(1)
	if player != null and player.has_method("predict_position"):
		player.predict_position(pos)
	world._prediction = pos
	if world._world != null and player != null and player.has_method("display_position"):
		var view_size: Vector2 = world.get_viewport_rect().size
		if not view_size.is_finite() or view_size.x < 100.0 or view_size.y < 100.0:
			view_size = Vector2(1280, 720)
		world._camera_target = world.desired_camera_position(player.display_position(), view_size)
		world.snap_camera_to_target()


func _sprite_gap(world: Node2D, player_id: int, portal_id: int) -> float:
	var player: Variant = world.entities.get(player_id)
	var portal: Variant = world.entities.get(portal_id)
	if not player is Node2D or not portal is Node2D:
		return INF
	return (player as Node2D).get_global_position().distance_to((portal as Node2D).get_global_position())


func _guide_viewport(node: Node) -> Vector2:
	var size: Vector2 = node.get_viewport().get_visible_rect().size if node.get_viewport() != null else Vector2.ZERO
	if not size.is_finite() or size.x < 100.0 or size.y < 100.0:
		return Vector2(1280, 720)
	return size


func _bag_closer_nonrealm() -> void:
	var world := _make_world()
	var guide = Guide.new()
	root.add_child(guide)
	var session := _make_session(Vector2(20, 10))
	_sync_player(world, session, Vector2(20, 10))
	_add_portal(session, world, 50, 1810, Vector2(21, 10), {31: "Dragon"})
	_add_portal(session, world, 60, 400, Vector2(20.2, 10), {8: 100})
	# Bag is the actual E target: prompt must NOT offer the realm portal.
	world.interaction_target_id = 60
	guide.refresh(session, world)
	_check(guide.is_guide_visible(), "bag-closer keeps the guide visible")
	_check(not guide.guide_prompt_text().contains("Dragon"), "bag E target never offers the realm portal")
	_check(guide.guide_prompt_text() == "", "bag E target shows no E prompt for a container")
	_check(guide.guide_hint_text().contains("Stand closer"), "bag-closer keeps the realm stand-closer hint")
	_check(guide.guide_direction_text().contains("Dragon"), "bag-closer direction still targets the realm")
	# Non-realm portal nearer than the realm: labels both, direction stays realm.
	_add_portal(session, world, 70, 1821, Vector2(20.5, 10), {})
	world.interaction_target_id = 70
	guide.refresh(session, world)
	_check(guide.guide_prompt_text() == "E · Enter Portal to Nexus", "E prompt reflects the actual non-realm E target")
	_check(guide.guide_direction_text().contains("Dragon"), "direction still targets 0x0712 when another portal is nearer")
	_check(guide.visible_portal_count() >= 2, "both source portal labels are shown")
	session.free()
	guide.free()
	world.free()
	await process_frame


func _realm_removed_busy() -> void:
	var world := _make_world()
	var guide = Guide.new()
	root.add_child(guide)
	var session := _make_session(Vector2(10, 10))
	_add_portal(session, world, 50, 1810, Vector2(20, 10), {31: "Dragon"})
	world.interaction_target_id = -1
	guide.refresh(session, world)
	_check(guide.is_guide_visible(), "Nexus baseline visible before leave/remove")
	# Leaving Nexus hides the overlay.
	world.apply_map({"width": 40, "height": 40, "name": "Realm"})
	guide.refresh(session, world)
	_check(not guide.is_guide_visible(), "realm map hides the Nexus guide")
	_check(guide.guide_prompt_text() == "", "hidden guide carries no E prompt")
	# Back in Nexus with the portal removed: explore line, labels cleared.
	world.apply_map({"width": 60, "height": 40, "name": "Nexus"})
	world.apply_update({"tiles": [{"x": 10, "y": 10, "tile": 1}], "new_objects": [
		{"object_type": 782, "stats": {"id": 1, "position": {"x": 10.0, "y": 10.0}, "stats": {0: 100, 1: 80}}},
	]})
	session.entity_states.erase(50)
	session.object_types.erase(50)
	world.remove_entity(50)
	world.interaction_target_id = -1
	guide.refresh(session, world)
	_check(guide.is_guide_visible(), "empty Nexus still shows the explore line")
	_check(guide.guide_direction_text() == "Explore Nexus to find a realm portal", "no streamed portal shows the explore line, never a guessed north")
	_check(guide.guide_prompt_text() == "" and guide.guide_hint_text() == "", "no portal means no E prompt and no stand-closer")
	_check(guide.visible_portal_count() == 0, "removed portal clears floating labels")
	# Busy/offline states hide without requests.
	session.state = "offline"
	guide.refresh(session, world)
	_check(not guide.is_guide_visible(), "offline hides the guide")
	session.state = "connecting"
	guide.refresh(session, world)
	_check(not guide.is_guide_visible(), "connecting hides the guide")
	session.state = "playing"
	session.player_id = -1
	guide.refresh(session, world)
	_check(not guide.is_guide_visible(), "missing player hides the guide")
	session.free()
	guide.free()
	world.free()
	await process_frame


func _smoothed_camera_labels() -> void:
	# Walking-smoothed camera on this HEAD moves _world.position; it does not
	# change tile poses. A lagged camera must move the floating label with the
	# portal's global display pose, not leave it at raw tile*32.
	var world := _make_world()
	var guide = Guide.new()
	root.add_child(guide)
	var session := _make_session(Vector2(10, 10))
	_add_portal(session, world, 50, 1810, Vector2(12, 10), {31: "NexusPortal.Dragon"})
	_sync_player(world, session, Vector2(10, 10))
	world.interaction_target_id = -1
	var lag := Vector2(120, -70)
	world._world.position += lag
	guide.refresh(session, world)
	var portal: Node2D = world.entities[50]
	var anchor: Vector2 = portal.get_global_position()
	if portal.has_method("display_position"):
		var pose: Vector2 = portal.display_position()
		if pose.is_finite():
			anchor += pose - portal.position
	var viewport: Vector2 = _guide_viewport(guide)
	var expected: Vector2 = Guide.clamp_label(anchor, viewport)
	var actual: Vector2 = guide.portal_label_position(50)
	_check(actual.is_finite() and actual.distance_to(expected) <= 1.0, "floating label tracks smoothed-camera global pose (got %s expected %s)" % [actual, expected])
	var raw: Vector2 = Guide.clamp_label(Vector2(12, 10) * 32.0, viewport)
	_check(actual.distance_to(raw) > 8.0, "label is not raw tile*32; camera offset is applied (got %s raw %s)" % [actual, raw])
	_check(guide.guide_direction_text().contains("Dragon"), "source realm id NexusPortal.Dragon cleans to Dragon")
	_check(not guide.guide_direction_text().contains("here"), "avatar two tiles west is not here")
	_check(guide.guide_direction_text().contains("east"), "smoothed camera does not change tile compass")
	_check(guide.guide_prompt_text() == "", "out-of-range 0x0712 shows no E prompt")
	session.free()
	guide.free()
	world.free()
	await process_frame


func _viewport_clamps() -> void:
	var small := Guide.clamp_label(Vector2(100, 100), Vector2(640, 360))
	_check(small.x <= 640.0 - 256.0 and small.y <= 360.0, "small viewport stays on screen")
	_check(small.x >= 4.0 and small.y >= 84.0, "small viewport respects top HUD offset")
	var large := Guide.clamp_label(Vector2(1800, 900), Vector2(1920, 1080))
	_check(large.x <= 1920.0 - 256.0 - 100.0 + 0.01 and large.y <= 1080.0 - 30.0 + 0.01, "large viewport stays left of the rail")
	_check(large.x >= 4.0, "large viewport clamps inside the left edge")
	var rail := Guide.clamp_label(Vector2(1250, 400), Vector2(1280, 720))
	_check(rail.x <= 1280.0 - 256.0 - 100.0 + 0.01, "1280x720 label never slides under HP/inventory rail")


func _zero_requests() -> void:
	var world := _make_world()
	var guide = Guide.new()
	root.add_child(guide)
	var session := _make_session(Vector2(10, 10))
	_add_portal(session, world, 50, 1810, Vector2(20, 10), {31: "Dragon"})
	var moves: Array = []
	var shots: Array = []
	var interacts: Array = []
	var abilities: Array = []
	var potions: Array = []
	world.move_requested.connect(func(pos: Dictionary, records: Array): moves.append(pos))
	world.shoot_requested.connect(func(angle: float): shots.append(angle))
	world.interact_requested.connect(func(entity: int, slot: int): interacts.append(entity))
	world.ability_requested.connect(func(position: Vector2): abilities.append(position))
	world.potion_requested.connect(func(kind: String): potions.append(kind))
	world.interaction_target_id = 50
	for i: int in 5:
		guide.refresh(session, world)
	_check(moves.is_empty() and shots.is_empty() and interacts.is_empty() and abilities.is_empty() and potions.is_empty(), "overlay refresh emits no gameplay requests")
	session.free()
	guide.free()
	world.free()
	await process_frame


func _render_capture(capture_dir: String) -> void:
	var world := _make_world()
	var guide = Guide.new()
	root.add_child(guide)
	var session := _make_session(Vector2(20, 10))
	_add_portal(session, world, 50, 1810, Vector2(20.5, 10), {31: "NexusPortal.Dragon"})
	_sync_player(world, session, Vector2(20, 10))
	world.interaction_target_id = 50
	guide.refresh(session, world)
	var gap: float = _sprite_gap(world, 1, 50)
	print("FSOD REALM GUIDE GAP_PX: %.1f" % gap)
	_check(gap < 48.0, "rendered avatar is within 1.5 tiles of the ring, not a 336px fixture desync (got %.1f px)" % gap)
	_check(guide.guide_prompt_text() == "E · Enter realm Dragon", "rendered frame carries the source E prompt")
	_check(guide.guide_direction_text().contains("here"), "synced render may say here only because the avatar is on the ring")
	_check(guide.visible_portal_count() >= 1, "rendered frame carries a floating source label")
	for i: int in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.is_empty() or image.get_width() < 1000:
		_check(false, "renderer did not return real viewport pixels")
		return
	_check(image.get_width() == 1280 and image.get_height() == 720, "rendered frame is the real 1280x720 viewport")
	var path: String = capture_dir.path_join("realm-guide-frame-0.png")
	if image.save_png(path) != OK:
		_check(false, "cannot save rendered realm guide frame")
		return
	print("FSOD REALM GUIDE FRAME: %dx%d %s" % [image.get_width(), image.get_height(), path])
	session.free()
	guide.free()
	world.free()
	await process_frame


func _cleanup() -> void:
	pass


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD REALM GUIDE FAIL: " + description)
	assert(condition, description)
