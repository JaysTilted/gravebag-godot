extends RefCounted
class_name LootGrading
## Kill grading for GRAVEBAG: maps a kill to the bag tier it drops.
##
## Port of `gradeLoot` from the prior Phaser design (`src/game/bags.ts`).
## Tougher gods drop better bags, and a high-level killer earns a small
## bonus bump (capped so whites stay rare). Inputs are clamped, so
## out-of-range levels cannot break the table.
##
## Pure logic: no nodes, no scene wiring.

## God strength for grading: 0 = garden pest, 5 = garden elder.
const MIN_GOD_TIER: int = 0
const MAX_GOD_TIER: int = 5


static func grade_loot(killer_level: int, god_tier: int) -> String:
	var level: int = clampi(killer_level, 1, XpLedger.MAX_LEVEL)
	var god: int = clampi(god_tier, MIN_GOD_TIER, MAX_GOD_TIER)
	var bonus: int = 0
	if level >= 20:
		bonus = 2
	elif level >= 12:
		bonus = 1
	var score: int = god * 2 + bonus
	if score <= 2:
		return "brown"
	if score <= 5:
		return "pink"
	if score <= 8:
		return "purple"
	if score <= 10:
		return "blue"
	return "white"
