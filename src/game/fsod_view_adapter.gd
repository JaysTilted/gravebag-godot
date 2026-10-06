extends RefCounted
## Transport/view boundary: source PascalCase + tile vectors -> view snake_case.
## Original backend remains authoritative; this file performs no game simulation.

static func position(value: Variant) -> Dictionary:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		return {"x": float(value.get("x", value.get("X", 0.0))), "y": float(value.get("y", value.get("Y", 0.0)))}
	return {"x": 0.0, "y": 0.0}


static func status(fields: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for pair in fields.get("Stats", []):
		values[int(pair["Type"])] = pair["Value"]
	return {"id": int(fields["Id"]), "position": position(fields["Position"]), "stats": values}


static func map_info(fields: Dictionary) -> Dictionary:
	return {
		"width": int(fields["Width"]), "height": int(fields["Height"]),
		"name": String(fields.get("Name", "")), "difficulty": int(fields.get("Difficulty", 0)),
		"allow_teleport": bool(fields.get("AllowTeleport", false)),
		"client_xml": fields.get("ClientXML", []), "extra_xml": fields.get("ExtraXML", []),
	}


static func update(fields: Dictionary) -> Dictionary:
	var tiles: Array = []
	var objects: Array = []
	for tile in fields.get("Tiles", []):
		tiles.append({"x": int(tile["X"]), "y": int(tile["Y"]), "tile": int(tile["Tile"])})
	for object in fields.get("NewObjects", []):
		objects.append({"object_type": int(object["ObjectType"]), "stats": status(object["Stats"])})
	return {"tiles": tiles, "new_objects": objects, "removed_object_ids": fields.get("RemovedObjectIds", [])}


static func tick(fields: Dictionary) -> Dictionary:
	var statuses: Array = []
	for record in fields.get("UpdateStatuses", []):
		statuses.append(status(record))
	return {"tick_id": int(fields["TickId"]), "tick_time": int(fields["TickTime"]), "update_statuses": statuses}


static func projectile(fields: Dictionary, owner_type: int = -1) -> Dictionary:
	var result := {
		"owner_id": int(fields["OwnerId"]), "bullet_id": int(fields["BulletId"]),
		"position": position(fields.get("Position", fields.get("StartingPos"))),
		"angle": float(fields["Angle"]), "bullet_type": int(fields.get("BulletType", 0)),
		"num_shots": int(fields.get("NumShots", 1)), "angle_inc": float(fields.get("AngleInc", 0.0)),
	}
	# Enemy volleys resolve projectile metadata from owner type; player volleys carry weapon type.
	var container_type := int(fields.get("ContainerType", owner_type))
	if container_type >= 0:
		result["container_type"] = container_type
	return result


static func _descriptor(record: Dictionary) -> Dictionary:
	return record.get("descriptor", record)


static func descriptors(objects: Dictionary, object_descs: Dictionary, projectiles: Dictionary, grounds: Dictionary) -> Dictionary:
	var mapped_objects: Dictionary = {}
	for key in objects:
		var record: Dictionary = objects[key]
		var typed: Dictionary = _descriptor(object_descs.get(key, {}))
		var shots: Array = []
		for shot in projectiles.get(key, []):
			var normalized := {
				"speed": float(shot.get("Speed", 0.0)),
				"lifetime_ms": int(shot.get("LifetimeMS", 0)),
			}
			# Preserve trajectory/condition flags for frontend projection; do not drop original metadata.
			normalized.merge(shot, false)
			shots.append(normalized)
		mapped_objects[String(key)] = {
			"name": String(record.get("id", "")), "class": String(record.get("class", typed.get("Class", ""))),
			"player": bool(typed.get("Player", false)), "enemy": bool(typed.get("Enemy", false)),
			"projectiles": shots, "source_descriptor": typed,
		}
	var tiles: Dictionary = {}
	for key in grounds:
		tiles[String(key)] = {"source_descriptor": _descriptor(grounds[key])}
	return {"objects": mapped_objects, "tiles": tiles}
