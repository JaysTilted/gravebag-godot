class_name CombatPatterns
extends RefCounted
## Pure bullet-pattern helpers for GRAVEBAG (design/game-brief.md: "radial
## rings, spirals, aimed bursts").
##
## All functions are static, take a spawn [param origin] plus an aim point,
## and return unit-length direction vectors. Callers spawn one bullet per
## direction at [param origin]. No nodes, no state, no allocations beyond
## the returned array — safe to call from hot paths.
##
## Usage:
## [codeblock]
## var dirs: PackedVector2Array = CombatPatterns.radial_ring(global_position, 10)
## for dir in dirs:
##     pool.spawn(global_position, dir, bullet_speed)
## [/codeblock]


## Evenly spaced ring of [param count] directions, rotated by
## [param offset_radians]. [param origin] is the caller's spawn point for
## these directions (returned directions are rotation-only). Returns an
## empty array when [param count] <= 0.
static func radial_ring(
	origin: Vector2, count: int, offset_radians: float = 0.0
) -> PackedVector2Array:
	var dirs := PackedVector2Array()
	if count <= 0:
		return dirs
	dirs.resize(count)
	for i in count:
		var ang: float = offset_radians + TAU * float(i) / float(count)
		dirs[i] = Vector2.from_angle(ang)
	return dirs


## [param arm_count] spiral arms rooted at the aim bearing
## ([param aim_point] - [param origin]), rotated by [param rotation_radians].
## Advance rotation each volley for a rotating spiral. Falls back to facing
## +X when aim and origin coincide. Empty array when [param arm_count] <= 0.
static func spiral_arms(
	origin: Vector2, aim_point: Vector2, arm_count: int, rotation_radians: float = 0.0
) -> PackedVector2Array:
	var dirs := PackedVector2Array()
	if arm_count <= 0:
		return dirs
	var to_aim: Vector2 = aim_point - origin
	var base: float = rotation_radians
	if to_aim.length_squared() > 0.0001:
		base += to_aim.angle()
	dirs.resize(arm_count)
	for i in arm_count:
		dirs[i] = Vector2.from_angle(base + TAU * float(i) / float(arm_count))
	return dirs


## [param count] directions fanning symmetrically around the aim bearing
## ([param aim_point] - [param origin]) across [param spread_radians] total.
## Odd counts place the middle shot exactly on the aim bearing. A single shot
## returns the aim bearing. Falls back to facing +X when aim and origin
## coincide. Empty array when [param count] <= 0.
static func aimed_burst(
	origin: Vector2, aim_point: Vector2, count: int, spread_radians: float = 0.0
) -> PackedVector2Array:
	var dirs := PackedVector2Array()
	if count <= 0:
		return dirs
	var to_aim: Vector2 = aim_point - origin
	var center := Vector2.RIGHT
	if to_aim.length_squared() > 0.0001:
		center = to_aim.normalized()
	dirs.resize(count)
	if count == 1:
		dirs[0] = center
		return dirs
	for i in count:
		var t: float = float(i) / float(count - 1) - 0.5  # -0.5 .. +0.5
		dirs[i] = center.rotated(t * spread_radians)
	return dirs
