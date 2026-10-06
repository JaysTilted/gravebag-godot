# SPDX-License-Identifier: AGPL-3.0-only
# Synthetic dictionary fixture ONLY, not a live server/game or source stat defaults.
# Produces real GL-rendered frames of original GRAVEBAG frontend placeholder art.
extends SceneTree
const Frontend = preload("res://src/client/fsod/frontend.tscn")


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
	if output.is_empty():
		push_error("render fixture needs --capture-dir=<absolute path>")
		quit(1)
		return
	var view = Frontend.instantiate()
	root.add_child(view)
	view.set_physics_process(false)
	view.set_descriptors({"objects": {1: {"kind": "player"}, 2: {"kind": "enemy"}, 300: {"name": "Fixture staff"}}, "tiles": {10: {"color": "#344a44"}, 11: {"color": "#515065"}}})
	view.set_player_id(1)
	view.apply_map({"width": 36, "height": 22, "name": "RENDER FIXTURE / NOT LIVE"})
	var cells: Array = []
	for y: int in 22:
		for x: int in 36:
			cells.append({"x": x, "y": y, "tile": 11 if x % 12 == 0 or y % 11 == 0 else 10})
	view.apply_update({"tiles": cells, "new_objects": [
		{"object_type": 1, "stats": {"id": 1, "position": {"x": 16, "y": 11}, "stats": {0: 100, 1: 72, 3: 100, 4: 61, 7: 8, 8: 300, 9: -1, 10: -1, 11: -1, 12: -1, 13: -1, 14: -1, 15: -1, 16: -1, 17: -1, 18: -1, 19: -1}}},
		{"object_type": 2, "stats": {"id": 2, "position": {"x": 21, "y": 10}, "stats": {}}},
		{"object_type": 2, "stats": {"id": 3, "position": {"x": 18, "y": 14}, "stats": {}}},
		{"object_type": 900, "stats": {"id": 4, "position": {"x": 13, "y": 8}, "stats": {}}},
	]})
	view._world.position = Vector2(0, 8)
	view.entities[1].aim_angle = -0.21
	view.entities[1]._moving = true
	view.entities[2]._moving = true
	view.entities[3]._moving = true
	view.apply_projectile({"owner_id": 1, "bullet_id": 0, "starting_pos": {"x": 17, "y": 11}, "angle": -0.21, "speed": 150, "lifetime_ms": 600})
	view.apply_projectile({"owner_id": 2, "bullet_id": 0, "position": {"x": 20, "y": 10}, "angle": 2.92, "speed": 100, "lifetime_ms": 1000})
	for frame: int in 2:
		if frame == 1: view.advance_visuals(0.13)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image.is_empty() or image.get_width() < 1000:
			push_error("renderer did not return real viewport pixels")
			quit(1)
			return
		var path: String = output.path_join("frontend-frame-%d.png" % frame)
		if image.save_png(path) != OK:
			push_error("cannot save rendered fixture frame")
			quit(1)
			return
		print("FSOD RENDER FRAME %d: %dx%d" % [frame, image.get_width(), image.get_height()])
	view.free()
	await process_frame
	print("FSOD RENDER PASS")
	quit(0)
