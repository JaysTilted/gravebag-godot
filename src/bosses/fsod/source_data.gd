# SPDX-License-Identifier: AGPL-3.0-only
# Adapted from FSoD at 6fd20aad4a7905b13f25389c68368a942a2b68cb.
# Sources: wServer/logic/db/BehaviorDb.SnakePit.cs (Snakepit Guard),
# db/data/dat1.xml:62257-62297, wServer/realm/Utils.cs:188-193,
# wServer/realm/entities/Projectile.cs:55. Original FSoD authors retain attribution.
# See LICENSE and plans/fsod-boss-integration.md. No upstream visual assets.
extends RefCounted

const SOURCE_ID := "Snakepit Guard"
const SOURCE_REVISION := "6fd20aad4a7905b13f25389c68368a942a2b68cb"
const SOURCE_OBJECT_TYPE := 0x0e26
const MAX_HP := 5500.0
const DEFENSE := 50.0
const PHASE2_FRACTION := 0.6 # Strictly less, not <= (HpLessTransition).
const MOVE_SPEED := 0.2
const SPAWN_RANGE_TILES := 4.0
const ACQUIRE_RANGE_TILES := 10.0
const FOLLOW_RANGE_TILES := 3.0
const SHOOT_RADII_TILES := [25.0, 10.0, 15.0]
const COUNTS := [3, 6, 3]
const SPREAD_DEGREES := [25.0, 60.0, 120.0] # Shoot default = 360/count.
const COOLDOWN_MS := [1000, 1000, 2000]
const COOLDOWN_VARIANCE_MS := [200, 0, 0]
const PROJECTILES := [
	{"object_id": "Snake Spit", "speed": 45.0, "damage": 65.0, "lifetime_ms": 2000, "size": 100, "dazed_ms": 0, "rotation_degrees": 0.0},
	{"object_id": "Snake Spinner", "speed": 45.0, "damage": 55.0, "lifetime_ms": 2000, "size": 100, "dazed_ms": 2000, "rotation_degrees": 90.0},
	{"object_id": "Snake Ball Spinner", "speed": 30.0, "damage": 100.0, "lifetime_ms": 3000, "size": 150, "dazed_ms": 4000, "rotation_degrees": 120.0},
]
# Adapter choices, NOT source constants: GRAVEBAG pixels per FSoD tile;
# source defaults to 20 TPS but the real server can configure/lag its ticks.
const DEFAULT_TILE_PX := 32.0
const ADAPTER_TICK_MS := 50

static func movement_tiles_per_second() -> float:
	return 5.55 * MOVE_SPEED + 0.74

static func projectile_pixels_per_second(index: int, tile_px: float) -> float:
	return float(PROJECTILES[index]["speed"]) / 10.0 * tile_px

static func directions(origin: Vector2, target: Vector2, index: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var base := (target - origin).angle()
	var spacing := deg_to_rad(float(SPREAD_DEGREES[index]))
	var start := base - spacing * float(COUNTS[index] - 1) / 2.0
	for i in COUNTS[index]:
		out.append(Vector2.from_angle(start + spacing * i))
	return out
