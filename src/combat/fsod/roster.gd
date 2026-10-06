extends RefCounted
## SPDX-License-Identifier: AGPL-3.0-only
## Adapted from FSoD 6fd20aad4a7905b13f25389c68368a942a2b68cb:
## wServer/logic/db/BehaviorDb.Lowland.cs; db/data/dat1.xml.
## Original C# and XML carry no author header. See LICENSE and integration notes.
## Angles = degrees, ranges = source tiles, timers = integer milliseconds.

const SOURCE_REV := "6fd20aad4a7905b13f25389c68368a942a2b68cb"
const IDS := ["Hobbit Mage", "Hobbit Archer", "Hobbit Rogue", "Sumo Master", "Lil Sumo"]

static func shoot(radius: float, options: Dictionary = {}) -> Dictionary:
	var b := {"kind": "shoot", "radius": radius, "count": 1, "projectile": 0,
		"cooldown": 1000, "offset": 0, "angle_offset": 0.0, "predictive": 0.0}
	b.merge(options, true)
	return b

static func wander(speed: float) -> Dictionary:
	return {"kind": "wander", "speed": speed}

static func follow(speed: float, range_tiles: float) -> Dictionary:
	return {"kind": "follow", "speed": speed, "acquire": 10.0, "range": range_tiles,
		"duration": 0, "cooldown": 0}

static func protect(speed: float, id: String, acquire: float, distance: float, again: float) -> Dictionary:
	return {"kind": "protect", "speed": speed, "target": id, "acquire": acquire,
		"range": distance, "reprotect": again}

static func prioritize(children: Array) -> Dictionary:
	return {"kind": "prioritize", "children": children}

static func timed(ms: int, to: String) -> Dictionary:
	return {"kind": "timed", "ms": ms, "to": to}

static func state(id: String, behaviors: Array = [], transitions: Array = [], children: Array = []) -> Dictionary:
	return {"id": id, "behaviors": behaviors, "transitions": transitions, "children": children}

static func spawn(id: String, max_children: int, cooldown: int) -> Dictionary:
	return {"kind": "spawn", "target": id, "max": max_children,
		"initial": int(max_children * 0.5), "cooldown": cooldown}

static func projectile(speed: float, damage: int, lifetime: int, extra: Dictionary = {}) -> Dictionary:
	var p := {"speed": speed, "min_damage": damage, "max_damage": damage, "lifetime_ms": lifetime}
	p.merge(extra, true)
	return p

static func get_enemy(id: String) -> Dictionary:
	var tree: Dictionary
	var stats: Dictionary
	match id:
		"Hobbit Mage":
			var rings: Array = [state("idle", [], [{"kind": "within", "radius": 12.0, "to": "ring1"}])]
			for i in 3:
				rings.append(state("ring%d" % (i + 1), [shoot(1, {"fixed_angle": float(i * 8),
					"count": 15, "shoot_angle": 24.0, "cooldown": 1200, "projectile": i})],
					[timed(400, "ring%d" % (i + 2) if i < 2 else "idle")]))
			tree = state("root", [prioritize([{"kind": "stay_above", "speed": 0.4, "altitude": 9},
				follow(0.75, 6), wander(0.4)]), spawn("Hobbit Archer", 4, 12000),
				spawn("Hobbit Rogue", 3, 6000)], [], rings)
			stats = {"object_type": 0x617, "max_hp": 200, "defense": 2, "xp_mult": 1.6,
				"projectiles": [projectile(50, 10, 340), projectile(50, 10, 340), projectile(50, 10, 340)],
				"portal": {"id": "Forest Maze Portal", "probability_percent": 20, "despawn_seconds": 100}}
		"Hobbit Archer":
			tree = state("root", [shoot(10)], [], [
				state("run1", [prioritize([protect(1.1, "Hobbit Mage", 12, 10, 1), wander(0.4)])], [timed(400, "run2")]),
				state("run2", [prioritize([{"kind": "stay_back", "speed": 0.8, "range": 4.0}, wander(0.4)])], [timed(600, "run3")]),
				state("run3", [prioritize([protect(1, "Hobbit Archer", 16, 2, 2), wander(0.4)])], [timed(400, "run1")])])
			stats = {"object_type": 0x616, "max_hp": 22, "defense": 0, "xp_mult": null,
				"projectiles": [projectile(60, 8, 2000)]}
		"Hobbit Rogue":
			tree = state("root", [shoot(3), prioritize([protect(1.2, "Hobbit Mage", 15, 9, 2.5),
				follow(0.85, 1), wander(0.4)])])
			stats = {"object_type": 0x615, "max_hp": 26, "defense": 0, "xp_mult": null,
				"projectiles": [projectile(60, 13, 800)]}
		"Sumo Master":
			var hurt := {"kind": "hp_less", "threshold": 0.99, "to": "hurt"}
			tree = state("root", [], [], [
				state("sleeping1", [{"kind": "texture", "value": 0}], [timed(1000, "sleeping2"), hurt]),
				state("sleeping2", [{"kind": "texture", "value": 3}], [timed(1000, "sleeping1"), hurt.duplicate()]),
				state("hurt", [{"kind": "texture", "value": 2}, spawn("Lil Sumo", 5, 200)], [timed(1000, "awake")]),
				state("awake", [{"kind": "texture", "value": 1}, shoot(3, {"cooldown": 250}),
					prioritize([follow(0.05, 1), wander(0.05)])], [{"kind": "hp_less", "threshold": 0.5, "to": "rage"}]),
				state("rage", [{"kind": "texture", "value": 4}, {"kind": "taunt", "value": "Engaging Super-Mode!!!"},
					prioritize([follow(0.6, 1), wander(0.6)])], [], [
					state("shoot", [shoot(8, {"projectile": 1, "cooldown": 150})], [timed(700, "rest")]),
					state("rest", [], [timed(400, "shoot")])])])
			stats = {"object_type": 0x7f00, "max_hp": 340, "defense": 5, "xp_mult": 1.65,
				"projectiles": [projectile(70, 15, 500, {"size": 120}),
					projectile(100, 25, 1000, {"size": 150, "multi_hit": true, "passes_cover": true})]}
		"Lil Sumo":
			tree = state("root", [shoot(8), prioritize([{"kind": "orbit", "speed": 0.4,
				"radius": 2.0, "acquire": 10.0, "target": "Sumo Master",
				"speed_variance": 0.04, "radius_variance": 0.04}, wander(0.4)])])
			stats = {"object_type": 0x7f01, "max_hp": 55, "defense": 4, "xp_mult": 2.0,
				"projectiles": [projectile(50, 10, 3000, {"size": 50})]}
		_:
			return {}
	stats["source_id"] = id
	stats["tree"] = tree
	# DamageCounter.cs: baseline per player, before damage share, level caps and int conversion.
	stats["xp_value"] = float(stats.max_hp) / 10.0 * (float(stats.xp_mult) if stats.xp_mult != null else 1.0)
	stats["missing_xml_fields"] = ["XpMult"] if stats.xp_mult == null else []
	return stats
