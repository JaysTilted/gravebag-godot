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


## Wave3 foe variety (wave3/foes lane). Original table, no external refs.
## Depth-band encounter mix: shallow bands lean scrappy (dashers), deep
## bands lean deadly (snipers + splitters), but every band can roll any of
## the three so the mix never goes stale.
const VARIANT_DASHER := &"dasher"
const VARIANT_SNIPER := &"sniper"
const VARIANT_SPLITTER := &"splitter"


## Encounter weights for a depth band. Pure: same band, same table.
## Negative bands clamp to 0 (shallow). Every band weights all three above
## zero so pick_variant distribution always covers the full roster.
static func variant_weights(depth_band: int) -> Dictionary:
	var b := maxi(depth_band, 0)
	if b <= 0:
		return {"dasher": 0.5, "sniper": 0.3, "splitter": 0.2}
	if b == 1:
		return {"dasher": 0.35, "sniper": 0.35, "splitter": 0.3}
	return {"dasher": 0.3, "sniper": 0.35, "splitter": 0.35}


## Roll one variant id for a depth band using the caller's [param rng].
## Pure apart from consuming one rng draw (seeded rng = deterministic
## sequence). Returns one of VARIANT_DASHER / VARIANT_SNIPER /
## VARIANT_SPLITTER, never anything else.
static func pick_variant(depth_band: int, rng: RandomNumberGenerator) -> StringName:
	var w: Dictionary = variant_weights(depth_band)
	var wd := float(w.get("dasher", 0.5))
	var wn := float(w.get("sniper", 0.3))
	var ws := float(w.get("splitter", 0.2))
	var total := wd + wn + ws
	if total <= 0.0:
		return VARIANT_DASHER
	var roll := rng.randf() * total
	if roll < wd:
		return VARIANT_DASHER
	if roll < wd + wn:
		return VARIANT_SNIPER
	return VARIANT_SPLITTER


## Melee lunge bearing: normalized (aim - origin). Falls back to +X when
## aim and origin coincide. Pure unit vector for dasher-style charges.
static func charge_vector(origin: Vector2, aim_point: Vector2) -> Vector2:
	var d: Vector2 = aim_point - origin
	if d.length_squared() < 0.0001:
		return Vector2.RIGHT
	return d.normalized()


## Sniper fan: symmetric fan around the aim bearing, kept as a named alias
## over [method aimed_burst] so volleys share one math path (single fan
## implementation) while call sites read by intent.
static func aimed_fan(
	origin: Vector2, aim_point: Vector2, count: int, spread_radians: float = 0.0
) -> PackedVector2Array:
	return aimed_burst(origin, aim_point, count, spread_radians)
