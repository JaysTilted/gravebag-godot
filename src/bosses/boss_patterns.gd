extends RefCounted
class_name BossPatterns
## Pure bullet-direction helpers for GRAVEBAG bosses.
##
## Stateless direction math only (no nodes, no state): given a pattern shape,
## returns normalized travel directions the combat lane turns into bullets.
## Implements design/game-brief.md (radial rings, spirals, aimed bursts).
## The WARDEN OF THE GATE consumes these; a future combat/patterns module may
## subsume them (integration dedups later).


## Evenly spaced unit directions around a circle.
## @param count bullets in the ring (<= 0 returns an empty array).
## @param offset_rad rotation of the whole ring, radians.
static func radial(count: int, offset_rad: float = 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	for i in count:
		var a := offset_rad + TAU * float(i) / float(count)
		out.append(Vector2(cos(a), sin(a)))
	return out


## One direction per spiral arm at the given tick.
## @param tick volley index; rotation advances by step_rad each tick.
## @param arms number of spiral arms (<= 0 returns an empty array).
static func spiral(tick: int, arms: int = 2, step_rad: float = 0.35, base_offset: float = 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if arms <= 0:
		return out
	var twist := base_offset + float(tick) * step_rad
	for arm in arms:
		var a := twist + TAU * float(arm) / float(arms)
		out.append(Vector2(cos(a), sin(a)))
	return out


## Fan of unit directions centered on origin -> target.
## @param count bullets in the fan (<= 0 returns an empty array).
## @param spread_rad angle between neighbours, radians.
static func aimed(origin: Vector2, target: Vector2, count: int = 3, spread_rad: float = 0.18) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	var base := (target - origin).angle() if not origin.is_equal_approx(target) else 0.0
	var mid := (float(count) - 1.0) * 0.5
	for i in count:
		var a := base + (float(i) - mid) * spread_rad
		out.append(Vector2(cos(a), sin(a)))
	return out
