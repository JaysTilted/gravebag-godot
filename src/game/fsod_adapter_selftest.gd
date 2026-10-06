extends SceneTree
const Adapter := preload("res://src/game/fsod_view_adapter.gd")

func _init() -> void:
	var wire_status := {
		"Id": 1234, "Position": Vector2(12.5, -3.25),
		"Stats": [{"Type": 1, "Value": 87}, {"Type": 31, "Value": "Gravebag"}, {"Type": 38, "Value": "42"}],
	}
	var converted := Adapter.status(wire_status)
	assert(converted.id == 1234)
	assert(converted.position == {"x": 12.5, "y": -3.25})
	assert(converted.stats[1] == 87 and converted.stats[38] == "42")
	assert(wire_status.Stats[0].Type == 1, "adapter never mutates source records")
	var wire_update := {
		"Tiles": [{"X": 12, "Y": 9, "Tile": 72}],
		"NewObjects": [{"ObjectType": 782, "Stats": wire_status}], "RemovedObjectIds": [44, 45],
	}
	var update := Adapter.update(wire_update)
	assert(update.tiles[0] == {"x": 12, "y": 9, "tile": 72})
	assert(update.new_objects[0].object_type == 782)
	assert(update.removed_object_ids == [44, 45])
	var tick := Adapter.tick({"TickId": 7, "TickTime": 200, "UpdateStatuses": [wire_status]})
	assert(tick.tick_time == 200 and tick.tick_id == 7 and tick.update_statuses[0].id == 1234)
	var map := Adapter.map_info({"Width": 100, "Height": 80, "Name": "Nexus", "ClientXML": ["<Objects/>"]})
	assert(map.width == 100 and map.height == 80 and map.client_xml == ["<Objects/>"])
	var shot := Adapter.projectile({"OwnerId": 1234, "BulletId": 2, "StartingPos": Vector2(2, 3), "ContainerType": 100, "Angle": 0.27})
	assert(shot.position == {"x": 2.0, "y": 3.0} and shot.angle == 0.27 and shot.container_type == 100)
	assert(shot.num_shots == 1 and not shot.has("damage"), "view never changes authoritative damage")
	var enemy_shot := Adapter.projectile({"OwnerId": 9, "BulletId": 3, "Position": Vector2(4, 5), "Angle": 0.0, "BulletType": 7, "NumShots": 15, "AngleInc": 0.42}, 1559)
	assert(enemy_shot.container_type == 1559 and enemy_shot.bullet_type == 7 and enemy_shot.num_shots == 15)
	var metadata := Adapter.descriptors({"782": {"id": "Wizard", "class": "Player"}}, {"782": {"Player": true}}, {"782": [{"Speed": 100.0, "LifetimeMS": 600, "Wavy": true, "BulletType": 7}]}, {"72": {"descriptor": {"Speed": 1.0}}})
	assert(metadata.objects["782"].player)
	assert(metadata.objects["782"].projectiles[0].speed == 100.0)
	assert(metadata.objects["782"].projectiles[0].Wavy and metadata.objects["782"].projectiles[0].BulletType == 7)
	assert(metadata.tiles["72"].source_descriptor.Speed == 1.0)
	print("FSOD ADAPTER SELFTEST PASS")
	quit(0)
