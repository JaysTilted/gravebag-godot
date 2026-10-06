extends RefCounted
class_name XpLedger
## Adapted from Fabiano Swagger of Doom (AGPL-3.0), 2026-10-06.
## https://github.com/ossimc82/fabiano-swagger-of-doom
## Upstream commit: 6fd20aad4a7905b13f25389c68368a942a2b68cb
## Sources: wServer/realm/entities/player/Player.Leveling.cs,
## wServer/realm/StatsManager.cs, wServer/logic/DamageCounter.cs,
## wServer/logic/FameCounter.cs, db/FameStats.cs, db/data/dat1.xml.
## FSoD Player.Leveling.cs + DamageCounter.cs + FameCounter.cs port.
## XP is lifetime experience, including XP earned below level 20. Base fame
## is floor(total_xp / 1000), NOT a post-20 overflow currency. The legacy xp
## property remains progress since the current level's cumulative threshold.
## Node wiring stays with dive/player: consume stats and record actual events.

const MAX_LEVEL: int = 20
const FAME_XP_RATE: float = 1000.0
## Wizard profile: db/data/dat1.xml:75067-75086. FSoD gains are inclusive
## random rolls, not fixed HP/attack multipliers. A caller may supply another
## class profile with the same base/caps/gains structure (StatsManager order).
const WIZARD_PROFILE := {
	"base": [100, 100, 12, 0, 10, 12, 12, 15],
	"caps": [670, 385, 75, 25, 50, 40, 60, 75],
	"gains": [[20, 30], [5, 15], [1, 2], [0, 0], [0, 2], [0, 1], [0, 2], [1, 2]],
}
const DUNGEONS := ["pirate_caves", "undead_lairs", "abyss_of_demons", "snake_pits",
	"spider_dens", "sprite_worlds", "tombs", "trenches", "jungles", "manors"]

var level: int = 1
var xp: int = 0
var total_xp: int = 0
## Whole base fame; death bonuses are calculated separately, at death.
var pending_fame: float = 0.0
var banked_fame: float = 0.0
var alive: bool = true
var stats: Array = []
var hp: int = 100
var mp: int = 100
## Account context must be supplied by the integrator. No invented ancestor
## bonus without a known character ID; FSoD CharacterId < 2 earns it.
var character_id: int = 2
var account_best_fame: int = 0
var equipment_fame_bonuses: Array[int] = []
var fame_stats: Dictionary = {}
var xp_boosted: bool = false
var _profile: Dictionary
var _roll: Callable
var _rng := RandomNumberGenerator.new()
var _projectiles: Dictionary = {}


func _init(profile: Dictionary = WIZARD_PROFILE, roll: Callable = Callable()) -> void:
	_profile = profile.duplicate(true)
	stats = _profile["base"].duplicate()
	hp = int(stats[0])
	mp = int(stats[1])
	_roll = roll
	_rng.randomize()


## Level 20 keeps a 1950-XP goal: DamageCounter still uses it for kill caps.
static func xp_for_next_level(p_level: int) -> int:
	if p_level < 1 or p_level > MAX_LEVEL:
		return 0
	return 50 + (p_level - 1) * 100


static func xp_at_level(p_level: int) -> int:
	if p_level < 1 or p_level > MAX_LEVEL:
		return 0
	return 50 * (p_level - 1) * (p_level - 1)


static func xp_to_max_level() -> int:
	return xp_at_level(MAX_LEVEL)


## FSoD class quest goals, not fame caps. The initial goal really is zero.
static func fame_goal(fame: int) -> int:
	if fame >= 2000:
		return 0
	if fame >= 800:
		return 2000
	if fame >= 400:
		return 800
	if fame >= 150:
		return 400
	return 150 if fame >= 20 else 0


## DamageCounter.Death: damage-weighted share, 10% minimum enemy XP,
## then 10% level-goal cap (50% for the player's current quest), truncated.
## Every eligible hitter uses this; nearby XP sharing is dive-owned.
static func kill_xp(max_hp: int, exp_multiplier: float, player_damage: int,
		total_damage: int, participants: int, p_level: int, quest: bool = false) -> int:
	if max_hp <= 0 or not is_finite(exp_multiplier) or exp_multiplier <= 0.0 \
			or player_damage <= 0 or total_damage <= 0 or participants <= 0:
		return 0
	var enemy_xp := float(max_hp) / 10.0 * exp_multiplier
	var share := float(participants) * enemy_xp * float(player_damage) / float(total_damage)
	var cap := float(xp_for_next_level(p_level)) * (0.5 if quest else 0.1)
	return int(minf(maxf(share, enemy_xp * 0.1), cap))


## Keep grant_xp(float) for the existing dive. Kill rewards should first use
## kill_xp(), not bag rank; this method accepts already-calculated XP.
func grant_xp(amount: float) -> void:
	if not alive or not is_finite(amount) or amount <= 0.0:
		return
	total_xp += int(amount) * (2 if xp_boosted else 1)
	while level < MAX_LEVEL and total_xp >= xp_at_level(level + 1):
		level += 1
		for i in range(stats.size()):
			var gain: Array = _profile["gains"][i]
			var increase: int = int(_roll.call(int(gain[0]), int(gain[1]))) if _roll.is_valid() \
					else _rng.randi_range(int(gain[0]), int(gain[1]))
			stats[i] = mini(int(stats[i]) + clampi(increase, int(gain[0]), int(gain[1])), int(_profile["caps"][i]))
		hp = int(stats[0])
		mp = int(stats[1])
		if level == MAX_LEVEL:
			xp_boosted = false
	xp = total_xp - xp_at_level(level)
	pending_fame = float(floori(float(total_xp) / FAME_XP_RATE))


## StatsManager.DamageModifier: attack includes equipment boost.
func attack_multiplier(boost: int = 0, weak: bool = false, damaging: bool = false) -> float:
	if weak:
		return 0.5
	return (0.5 + float(int(stats[2]) + boost) / 75.0 * 1.5) * (1.5 if damaging else 1.0)


func hp_regen(boost: int = 0, sick: bool = false) -> float:
	return 1.0 + 0.12 * (0 if sick else int(stats[5]) + boost)


func mp_regen(boost: int = 0, quiet: bool = false) -> float:
	return 0.0 if quiet else 0.5 + 0.06 * (int(stats[6]) + boost)


## FameCounter counts all eligible players as assists, only last hitter as
## killer. Cube/Oryx count only for killer; quest completion counts assists.
func record_kill(god: bool = false, killer: bool = true, quest: bool = false,
		cube: bool = false, oryx: bool = false) -> void:
	if not alive:
		return
	record_event("god_assists" if god else "monster_assists")
	if quest:
		record_event("quests_completed")
	if killer:
		record_event("god_kills" if god else "monster_kills")
		if cube:
			record_event("cube_kills")
		if oryx:
			record_event("oryx_kills")


func record_event(event: String, count: int = 1) -> void:
	if alive and count > 0:
		fame_stats[event] = int(fame_stats.get(event, 0)) + count


func record_shot(projectile_id: int) -> void:
	if alive:
		record_event("shots")
		_projectiles[projectile_id] = true


func record_hit(projectile_id: int) -> void:
	if alive and _projectiles.has(projectile_id):
		_projectiles.erase(projectile_id)
		record_event("shots_that_damage")


func remove_projectile(projectile_id: int) -> void:
	_projectiles.erase(projectile_id)


func _count(event: String) -> int:
	return maxi(0, int(fame_stats.get(event, 0)))


## FameStats.CalculateTotal in exact source order. Each bonus floors the
## preceding subtotal; equipment bonuses share one subtotal, then First Born.
## No fame cap/spending rule exists in these source files; daily quests pay
## Fortune Tokens (1,1,2,2), not fame. Returns whole death-award fame.
func death_fame() -> int:
	var base := floori(float(total_xp) / FAME_XP_RATE)
	var bonus := float(base) * 0.1 + 20.0 if character_id < 2 else 0.0
	for event in ["shots_that_damage", "potions_drunk", "special_ability_uses", "teleports"]:
		if _count(event) == 0:
			bonus = floor(bonus) + (base + floor(bonus)) * 0.25
	var tunnel_rat := true
	for dungeon in DUNGEONS:
		if _count(dungeon + "_completed") == 0:
			tunnel_rat = false
	if tunnel_rat:
		bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	var kills := _count("god_kills") + _count("monster_kills")
	var god_ratio := float(_count("god_kills")) / float(kills) if kills > 0 else 0.0
	for threshold in [0.1, 0.5]:
		if god_ratio > threshold:
			bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	if _count("oryx_kills") > 0:
		bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	var accuracy := float(_count("shots_that_damage")) / float(_count("shots")) if _count("shots") > 0 else 0.0
	for threshold in [0.25, 0.5, 0.75]:
		if accuracy > threshold:
			bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	for threshold in [1000000, 4000000]:
		if _count("tiles_uncovered") > threshold:
			bonus = floor(bonus) + (base + floor(bonus)) * 0.05
	for threshold in [100, 1000]:
		if _count("level_up_assists") > threshold:
			bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	if _count("quests_completed") > 1000:
		bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	if _count("cube_kills") == 0:
		bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	var equipped := 0.0
	for i in range(mini(4, equipment_fame_bonuses.size())):
		if equipment_fame_bonuses[i] > 0:
			equipped += (base + floor(bonus)) * float(equipment_fame_bonuses[i]) / 100.0
	bonus = floor(bonus) + floor(equipped)
	if base + floor(bonus) > account_best_fame:
		bonus = floor(bonus) + (base + floor(bonus)) * 0.1
	return base + floori(bonus)


## Idempotent death banking; source death award includes bonuses, not just
## the displayed base fame. Events and XP cannot change after death.
func die() -> float:
	if not alive:
		return 0.0
	var banked := float(death_fame())
	alive = false
	banked_fame += banked
	pending_fame = 0.0
	return banked
