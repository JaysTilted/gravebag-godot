extends RefCounted
## SPDX-License-Identifier: AGPL-3.0-only
## GDScript adaptation of FSoD 6fd20aad4a7905b13f25389c68368a942a2b68cb,
## wServer/realm/{Entity,Utils}.cs and wServer/logic/{State,Behavior,Transition,
## Cooldown}.cs, behaviors/{Shoot,Follow,Wander,Prioritize,Charge,Orbit,Protect,
## StayAbove,StayBack,Spawn}.cs and transitions/{Timed,PlayerWithin,HpLess}Transition.cs.
## Original source has no author header. No network/runtime/art dependencies.
## Context and movement are in TILES. All tick/cooldown values are integer MS.
## Seeded randomness replaces upstream thread-local RNG (deterministic replay).

const NOT_STARTED := 0
const IN_PROGRESS := 1
const COMPLETED := 2
var rng := RandomNumberGenerator.new()
var states: Dictionary = {}
var storage: Dictionary = {}
var current_state := ""
var _pending: Array = []
var _root: Dictionary
var _seed := 1
var _shots: Array = []
var _events: Array = []

func configure(tree: Dictionary, seed_value: int = 1) -> void:
	_root = tree.duplicate(true)
	states.clear()
	_index(_root, "")
	_seed = seed_value
	reset()

func _index(s: Dictionary, parent: String) -> void:
	s["parent"] = parent
	states[s.id] = s
	for i in s.behaviors.size():
		_index_behavior(s.behaviors[i], "%s/b%d" % [s.id, i])
	for i in s.transitions.size():
		s.transitions[i]["key"] = "%s/t%d" % [s.id, i]
	for child in s.children:
		_index(child, s.id)

func _index_behavior(b: Dictionary, key: String) -> void:
	b["key"] = key
	for i in b.get("children", []).size():
		_index_behavior(b.children[i], "%s/%d" % [key, i])

func reset() -> void:
	storage.clear()
	rng.seed = _seed
	current_state = _deepest(_root.id)
	_pending = _path(current_state)

func _deepest(id: String) -> String:
	while not states[id].children.is_empty():
		id = states[id].children[0].id
	return id

func _path(id: String) -> Array:
	var path: Array = []
	while id != "":
		path.append(id)
		id = states[id].parent
	return path

func _switch(to: String) -> void:
	var old_path := _path(current_state)
	current_state = _deepest(to)
	_pending = []
	for id in _path(current_state):
		if id in old_path:
			break
		_pending.append(id)

## Upstream evaluates transitions BEFORE behaviors, leaf to root; a transition
## still ticks OLD behaviors this tick, and enters the new leaf on the NEXT tick.
## TimedTransition checks <=0 before subtracting and retains storage on re-entry.
func tick(ms: int, context: Dictionary) -> Dictionary:
	_shots = []
	_events = []
	var c := context.duplicate(true)
	if ms < 0 or not c.get("has_target", false) or c.get("dead", false):
		return {"position": c.position, "shots": [], "events": []}
	for id in _pending:
		for b in states[id].behaviors:
			_enter(b, c)
	_pending.clear()
	var transited := false
	for id in _path(current_state):
		var s: Dictionary = states[id]
		if not transited:
			for t in s.transitions:
				if _transition(t, ms, c):
					_switch(t.to)
					transited = true
					break
		for b in s.behaviors:
			_behavior(b, ms, c)
	return {"position": c.position, "shots": _shots, "events": _events}

func _transition(t: Dictionary, ms: int, c: Dictionary) -> bool:
	match t.kind:
		"timed":
			var cool := int(storage.get(t.key, rng.randi_range(0, int(t.ms) - 1) if t.get("randomized", false) else t.ms))
			var ready := cool <= 0
			storage[t.key] = int(t.ms) if ready else cool - ms
			return ready
		"within":
			return c.position.distance_to(c.target) < float(t.radius)
		"hp_less":
			return float(c.hp) < float(t.threshold) if float(t.threshold) > 1.0 else float(c.hp) / float(c.max_hp) < float(t.threshold)
	return false

func _enter(b: Dictionary, c: Dictionary) -> void:
	match b.kind:
		"shoot":
			storage[b.key] = int(b.get("offset", 0))
		"prioritize":
			storage[b.key] = -1
			for child in b.children:
				_enter(child, c)
		"orbit":
			storage[b.key] = {"speed": float(b.speed) + float(b.get("speed_variance", float(b.speed) * 0.1)) * rng.randf_range(-1, 1),
				"radius": float(b.radius) + float(b.get("radius_variance", float(b.speed) * 0.1)) * rng.randf_range(-1, 1)}
		"spawn":
			storage[b.key] = {"number": int(b.initial), "cool": int(b.cooldown)}
			for i in int(b.initial):
				_events.append({"kind": "spawn", "source_id": b.target,
					"position": c.position + Vector2(rng.randf() * 0.5, rng.randf() * 0.5)})

static func spread(b: Dictionary, bearing: float) -> PackedVector2Array:
	var count := int(b.get("count", 1))
	var dirs := PackedVector2Array()
	if count <= 0:
		return dirs
	var increment := 0.0 if count == 1 else deg_to_rad(float(b.get("shoot_angle", 360.0 / count)))
	var center := deg_to_rad(float(b.fixed_angle)) if b.has("fixed_angle") else bearing
	center += deg_to_rad(float(b.get("angle_offset", 0.0)))
	for i in count:
		dirs.append(Vector2.from_angle(center - increment * (count - 1) / 2.0 + increment * i))
	return dirs

static func source_speed(speed: float) -> float:
	return 5.55 * speed + 0.74 # Utils.GetSpeed, without Slowed

func _move(c: Dictionary, dir: Vector2, speed: float, ms: int) -> void:
	c.position += dir * source_speed(speed) * float(ms) / 1000.0

func _nearest(b: Dictionary, c: Dictionary) -> Variant:
	var acquire := float(b.get("acquire", 10.0))
	if not b.has("target"):
		return c.target if c.position.distance_to(c.target) < acquire else null
	var nearest: Variant = null
	for ally in c.get("allies", []):
		if ally.source_id != b.target:
			continue
		var d: float = c.position.distance_to(ally.position)
		if d < acquire:
			acquire = d
			nearest = ally.position
	return nearest

func _behavior(b: Dictionary, ms: int, c: Dictionary) -> int:
	match b.kind:
		"shoot":
			var cool := int(storage.get(b.key, 0))
			if cool > 0:
				storage[b.key] = cool - ms
				return IN_PROGRESS
			var near: bool = c.position.distance_to(c.target) < float(b.radius)
			if near or b.has("fixed_angle") or b.has("default_angle"):
				var p: Dictionary = c.projectiles[int(b.get("projectile", 0))]
				var aim: float = (c.target - c.position).angle() if near else deg_to_rad(float(b.get("default_angle", 0.0)))
				# Lowland selected roster has no predictive shots. Generic support
				# uses caller's 100ms history, matching Shoot.Predict's angular formula.
				if near and c.has("target_history") and float(b.get("predictive", 0)) != 0:
					var old_angle: float = (c.target_history - c.position).angle()
					aim += (aim - old_angle) / 0.1 * float(p.speed) / 100.0 * float(b.predictive)
				var dirs := spread(b, aim)
				# Upstream prediction is added even after fixedAngle resolution.
				if b.has("fixed_angle") and near and c.has("target_history"):
					var correction: float = ((c.target - c.position).angle() - (c.target_history - c.position).angle()) / 0.1 * float(p.speed) / 100.0 * float(b.get("predictive", 0))
					for i in dirs.size():
						dirs[i] = dirs[i].rotated(correction)
				var low := int(p.min_damage)
				var high := int(p.max_damage)
				_shots.append({"origin": c.position, "directions": dirs, "projectile": int(b.get("projectile", 0)),
					"speed_tiles": float(p.speed) / 10.0, "damage": low if high <= low else rng.randi_range(low, high - 1),
					"descriptor": p.duplicate(true)})
			storage[b.key] = int(b.get("cooldown", 1000))
			return COMPLETED
		"prioritize":
			var index := int(storage.get(b.key, -1))
			if index < 0:
				index = 0 # Upstream keeps index 0 when no child is InProgress.
				for i in b.children.size():
					if _behavior(b.children[i], ms, c) == IN_PROGRESS:
						index = i
						break
			else:
				if _behavior(b.children[index], ms, c) != IN_PROGRESS:
					index = -1
			storage[b.key] = index
			return NOT_STARTED
		"wander":
			var s: Dictionary = storage.get(b.key, {"dir": Vector2.ZERO, "remaining": 0.0})
			var status := IN_PROGRESS
			if float(s.remaining) <= 0:
				s.dir = Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 1)).normalized()
				s.remaining = rng.randi_range(300, 700) / 1000.0
				status = COMPLETED
			_move(c, s.dir, b.speed, ms)
			s.remaining -= source_speed(b.speed) * ms / 1000.0
			storage[b.key] = s
			return status
		"follow", "protect":
			return _follow_or_protect(b, ms, c)
		"stay_above":
			if int(c.get("elevation", 0)) != 0 and int(c.get("elevation", 0)) < int(b.altitude):
				_move(c, (c.get("map_center", c.position) - c.position).normalized(), b.speed, ms)
				return IN_PROGRESS
			return COMPLETED
		"stay_back":
			var cool := int(storage.get(b.key, 1000))
			var status := NOT_STARTED
			if c.position.distance_to(c.target) < float(b.range):
				_move(c, (c.position - c.target).normalized(), b.speed, ms)
				status = COMPLETED if cool <= 0 else IN_PROGRESS
				cool = 1000 if cool <= 0 else cool - ms
			storage[b.key] = cool
			return status
		"orbit":
			var en: Variant = _nearest(b, c)
			if en == null:
				return NOT_STARTED
			var s: Dictionary = storage[b.key]
			var offset: Vector2 = c.position - en
			if offset == Vector2.ZERO:
				offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			var angle := offset.angle() + source_speed(s.speed) / float(s.radius) * ms / 1000.0
			# Source uses nominal radius for the destination, varied radius for angular speed.
			var dest: Vector2 = en + Vector2.from_angle(angle) * float(b.radius)
			_move(c, (dest - c.position).normalized(), s.speed, ms)
			return IN_PROGRESS
		"charge":
			return _charge(b, ms, c)
		"spawn":
			var s: Dictionary = storage[b.key]
			if int(s.cool) <= 0 and int(s.number) < int(b.max):
				_events.append({"kind": "spawn", "source_id": b.target, "position": c.position})
				s.cool = int(b.cooldown)
				s.number += 1
			else:
				s.cool -= ms
			return NOT_STARTED
		"texture", "taunt":
			_events.append({"kind": b.kind, "value": b.value})
			return NOT_STARTED
	push_error("Unsupported FSoD behavior: " + str(b.kind))
	return NOT_STARTED

func _follow_or_protect(b: Dictionary, ms: int, c: Dictionary) -> int:
	var is_follow: bool = b.kind == "follow"
	var s: Dictionary = storage.get(b.key, {"phase": 0, "remaining": 0})
	var en: Variant = _nearest(b, c)
	# Follow's upstream early player-type return leaves storage unchanged.
	if is_follow and en == null:
		return NOT_STARTED
	var status := NOT_STARTED
	var duration := int(b.get("duration", 0))
	if int(s.phase) == 0:
		if en != null and (not is_follow or int(s.remaining) <= 0):
			s.phase = 1
			if is_follow and duration > 0:
				s.remaining = duration
		elif is_follow and int(s.remaining) > 0:
			s.remaining -= ms
	if int(s.phase) == 2:
		if en == null:
			s.phase = 0
		else:
			status = COMPLETED
			if c.position.distance_to(en) > float(b.range) + (1.0 if is_follow else 0.0):
				s.phase = 1
				s.remaining = duration
	if int(s.phase) == 1:
		if en == null:
			s.phase = 0
		elif is_follow and duration > 0 and int(s.remaining) <= 0:
			s.phase = 0
			s.remaining = int(b.get("cooldown", 1000))
			status = COMPLETED
		else:
			if int(s.remaining) > 0:
				s.remaining -= ms
			var offset: Vector2 = en - c.position
			var distance := float(b.range) if is_follow else float(b.reprotect)
			if offset.length() > distance:
				if is_follow:
					offset -= Vector2(rng.randi_range(-2, 1), rng.randi_range(-2, 1)) / 2.0
				_move(c, offset.normalized(), b.speed, ms)
				status = IN_PROGRESS
			else:
				s.phase = 2
				s.remaining = 0
				status = COMPLETED
	storage[b.key] = s
	return status

func _charge(b: Dictionary, ms: int, c: Dictionary) -> int:
	var s: Dictionary = storage.get(b.key, {"dir": Vector2.ZERO, "remaining": 0})
	var status := NOT_STARTED
	var speed := float(b.get("speed", 4.0))
	var cooldown := int(b.get("cooldown", 2000))
	if int(s.remaining) <= 0:
		if s.dir == Vector2.ZERO:
			var offset: Vector2 = c.target - c.position
			# Preserve upstream AND check: an axis-aligned target cannot start Charge.
			if offset.length() < float(b.get("range", 10.0)) and offset.x != 0 and offset.y != 0:
				s.dir = offset.normalized()
				s.remaining = cooldown
				if offset.length() / source_speed(speed) < float(s.remaining):
					s.remaining = int(offset.length() / source_speed(speed) * 1000)
		else:
			s.dir = Vector2.ZERO
			s.remaining = cooldown
			status = COMPLETED
	if s.dir != Vector2.ZERO:
		_move(c, s.dir, speed, ms)
		status = IN_PROGRESS
	s.remaining -= ms
	storage[b.key] = s
	return status
