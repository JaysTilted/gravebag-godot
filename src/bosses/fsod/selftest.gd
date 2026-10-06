# SPDX-License-Identifier: AGPL-3.0-only
# Tests of reusable FSoD source data/direction math (not a server simulation).
# Source revision 6fd20aad4a7905b13f25389c68368a942a2b68cb; see LICENSE.
extends SceneTree

const Data := preload("res://src/bosses/fsod/source_data.gd")
var checks := 0
var failures := 0

func _init() -> void:
	_check(Data.SOURCE_ID == "Snakepit Guard", "source identity")
	_check(Data.SOURCE_REVISION == "6fd20aad4a7905b13f25389c68368a942a2b68cb", "pinned provenance")
	_check(Data.MAX_HP == 5500.0 and Data.DEFENSE == 50.0, "XML HP/defense")
	_check(Data.PHASE2_FRACTION == 0.6, "source phase threshold")
	_check(Data.COOLDOWN_MS == [1000, 1000, 2000], "source cooldowns")
	_check(Data.COOLDOWN_VARIANCE_MS == [200, 0, 0], "source inclusive cooldown variance")
	var expected := [[-25.0, 0.0, 25.0], [-150.0, -90.0, -30.0, 30.0, 90.0, 150.0], [-120.0, 0.0, 120.0]]
	for index in 3:
		var dirs: Array[Vector2] = Data.directions(Vector2.ZERO, Vector2.RIGHT, index)
		_check(dirs.size() == int(Data.COUNTS[index]), "volley %d count" % index)
		for i in dirs.size():
			_check(dirs[i].is_equal_approx(Vector2.from_angle(deg_to_rad(float(expected[index][i])))), "volley %d direction %d" % [index, i])
			_check(is_equal_approx(dirs[i].length(), 1.0), "unit direction")
		var rotated: Array[Vector2] = Data.directions(Vector2(10, 15), Vector2(10, 19), index)
		for i in dirs.size():
			_check(rotated[i].is_equal_approx(dirs[i].rotated(PI / 2.0)), "translated/rotated aim")
	_check(is_equal_approx(Data.movement_tiles_per_second(), 1.85), "GetSpeed .2 => 1.85 tiles/s")
	_check(is_equal_approx(Data.projectile_pixels_per_second(0, 32.0), 144.0), "XML speed /10 then tile->px")
	_check(is_equal_approx(Data.projectile_pixels_per_second(2, 32.0), 96.0), "spinner speed conversion")
	_check(is_equal_approx(Data.projectile_pixels_per_second(0, 64.0), 288.0), "tile scale is adapter choice")
	_check(Data.PROJECTILES[0]["lifetime_ms"] == 2000 and Data.PROJECTILES[2]["lifetime_ms"] == 3000, "source lifetimes")
	_check(Data.PROJECTILES[1]["dazed_ms"] == 2000 and Data.PROJECTILES[2]["dazed_ms"] == 4000, "source conditions")
	print("FSOD MATH %s: %d assertions; data/directions only, no encounter/backend port" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)
