extends "res://src/game/fsod_live_probe.gd"
## Acceptance-only loot driver. Same probe as the shipped bot, except the
## request waits until the avatar is inside the original server pickup radius
## (0.55 tiles). The shipped 1-tile approach can emit a swap the server drops.

var _loot_diag_at: int = 0


func _drive_loot() -> bool:
	if not _loot_request.is_empty():
		var wire: int = 8 + int(_loot_request.destination_slot)
		var have: int = int(session.player_stats.get(wire, -1))
		if have == int(_loot_request.type):
			_release_keys()
			_capture("06-original-loot")
			_done = true
			print("FSOD LIVE LOOT PASS original_server_item=%d inventory_slot=%d source_bag=%d" % [_loot_request.type, _loot_request.destination_slot, _loot_request.source_id])
			quit(0)
		var waited: float = session.pending_position.distance_to(_bag_position(int(_loot_request.source_id)))
		_loot_diag("WAIT bag=%d distance=%.2f wire=%d have=%d want=%d" % [int(_loot_request.source_id), waited, wire, have, int(_loot_request.type)])
		return true
	var nearest := -1
	var nearest_distance := INF
	var item_slot := -1
	for id in session.entity_states:
		if session._class_for(id) != "Container": continue
		var stats: Dictionary = session.entity_states[id].get("stats", {})
		var nonempty := -1
		for slot in range(8):
			if int(stats.get(8 + slot, -1)) >= 0:
				nonempty = slot
				break
		if nonempty < 0: continue
		var distance: float = session.pending_position.distance_to(session.entity_states[id].position)
		if distance < nearest_distance:
			nearest = id
			nearest_distance = distance
			item_slot = nonempty
	if nearest < 0: return false
	if nearest_distance >= 0.55:
		_loot_diag("APPROACH bag=%d distance=%.2f" % [nearest, nearest_distance])
		_navigate(session.entity_states[nearest].position)
		return true
	_release_keys()
	var destination_slot := -1
	for slot in range(4, 12):
		if int(session.player_stats.get(8 + slot, -1)) < 0:
			destination_slot = slot
			break
	if destination_slot < 0:
		_fail("source inventory full: no destructive loot request")
		return true
	var type: int = int(session.entity_states[nearest].stats.get(8 + item_slot, -1))
	var result: int = session.swap_slots(nearest, item_slot, session.player_id, destination_slot)
	if result != OK:
		_fail("original loot request refused")
		return true
	_loot_request = {"source_id": nearest, "source_slot": item_slot, "destination_slot": destination_slot, "type": type}
	print("FSOD LIVE LOOT REQUEST source_bag=%d type=%d destination_slot=%d distance=%.2f; awaiting actual server snapshot" % [nearest, type, destination_slot, nearest_distance])
	return true


func _bag_position(bag_id: int) -> Vector2:
	var state: Variant = session.entity_states.get(bag_id, {})
	if state is Dictionary and (state as Dictionary).get("position") is Vector2:
		return (state as Dictionary).position
	return session.pending_position


func _loot_diag(line: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _loot_diag_at < 1000:
		return
	_loot_diag_at = now
	print("FSOD LIVE LOOT %s" % line)
