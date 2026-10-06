extends RefCounted
class_name LootGrading
## Adapted 2026-10-06 from FSoD (AGPLv3), commit 6fd20aa:
## https://github.com/ossimc82/fabiano-swagger-of-doom
## wServer/logic/loot/LootDefs.cs; db/data/Descriptors.cs, dat1.xml;
## wServer/realm/StatsManager.cs. No equipment affix rarity in this source.
## FSoD LootDefs.cs + db/data/Descriptors.cs. Equipment has fixed XML
## bonuses, NOT randomized affixes. Only projectile damage rolls [min,max).
## The embedded catalog covers every candidate referenced by Lowland.

const MIN_GOD_TIER: int = 0
const MAX_GOD_TIER: int = 5
const SLOT_TYPES := {
	"Weapon": [1, 2, 3, 8, 17, 24],
	"Ability": [4, 5, 11, 12, 13, 15, 16, 18, 19, 20, 21, 22, 23, 25],
	"Armor": [6, 7, 14], "Ring": [9], "Potion": [10],
}
# LootDefs.cs EggRarity and LootTemplates.DefaultEggLoot (not equipment rarity).
const EGG_RARITIES := ["Common", "Uncommon", "Rare", "Legendary"]
const EGG_CHANCES := [0.1, 0.05, 0.01, 0.001]
const STAT_POTION_IDS := {
	"Attack": 0xa1f, "Defense": 0xa20, "Speed": 0xa21,
	"Vitality": 0xa34, "Wisdom": 0xa35, "Dexterity": 0xa4c,
	"Life": 0xae9, "Mana": 0xaea,
}


## Compatibility adapter only: god_tier is an equipment tier here. FSoD
## never improves loot because of killer level. Real deaths must roll the
## enemy table and use each winning item's XML bag_type, not this adapter.
static func grade_loot(_killer_level: int, god_tier: int) -> String:
	var best := "brown"
	for item in ITEMS:
		if int(item.equipment_tier) == clampi(god_tier, MIN_GOD_TIER, MAX_GOD_TIER):
			var bag: String = BagTiers.for_bag_type(int(item.bag_type))
			if BagTiers.compare_rank(bag, best) > 0:
				best = bag
	return best


static func item_definition(item_name: String) -> Dictionary:
	for item in ITEMS:
		if String(item.key) == item_name:
			return item.duplicate(true)
	return {}


static func tier_candidates(equipment_tier: int, item_type: String) -> Array:
	var candidates: Array = []
	for item in ITEMS:
		if int(item.equipment_tier) == equipment_tier and int(item.slot_type) in SLOT_TYPES.get(item_type, []):
			candidates.append(item.duplicate(true))
	return candidates


## Fixed equipment bonuses exposed as degenerate ranges; no affix RNG.
static func stat_roll_ranges(item_name: String) -> Dictionary:
	var ranges := {}
	var item: Dictionary = item_definition(item_name)
	for stat in item.get("stats", {}):
		var amount: int = int(item.stats[stat])
		ranges[stat] = [amount, amount]
	return ranges


static func roll_stats(item_name: String) -> Dictionary:
	return item_definition(item_name).get("stats", {}).duplicate(true)


## StatsManager.DamageRandom.obf6: upper bound excluded unless min == max.
## Supply its next unsigned random integer, not a float, to preserve modulo.
static func roll_projectile_damage(item_name: String, random_value: int, projectile: int = 0) -> int:
	var item: Dictionary = item_definition(item_name)
	var ranges: Array = item.get("damage_ranges", [])
	if projectile < 0 or projectile >= ranges.size():
		return 0
	var low: int = int(ranges[projectile][0])
	var high: int = int(ranges[projectile][1])
	return low if low == high else low + posmod(random_value, high - low)


# Extracted from db/data/dat1.xml; stat IDs use realm/Stats.cs names.
const ITEMS := [
	{"key": "Saber", "object_type": 2669, "slot_type": 1, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[75, 105]]},
	{"key": "Long Sword", "object_type": 2561, "slot_type": 1, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[75, 120]]},
	{"key": "Power Wand", "object_type": 2672, "slot_type": 8, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[35, 50]]},
	{"key": "Missile Wand", "object_type": 2565, "slot_type": 8, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[40, 55]]},
	{"key": "Iron Shield", "object_type": 2569, "slot_type": 5, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Defense": 4}, "damage_ranges": [[100, 140]]},
	{"key": "Leather Armor", "object_type": 2573, "slot_type": 6, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {"Defense": 6}, "damage_ranges": []},
	{"key": "Basilisk Hide Armor", "object_type": 2681, "slot_type": 6, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {"Defense": 7}, "damage_ranges": []},
	{"key": "Chainmail", "object_type": 2575, "slot_type": 7, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {"Defense": 6}, "damage_ranges": []},
	{"key": "Blue Steel Mail", "object_type": 2684, "slot_type": 7, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {"Defense": 7}, "damage_ranges": []},
	{"key": "Blue Steel Dagger", "object_type": 2674, "slot_type": 2, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[20, 75]]},
	{"key": "Dusky Rose Dagger", "object_type": 2675, "slot_type": 2, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[25, 80]]},
	{"key": "Crossbow", "object_type": 2587, "slot_type": 3, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[20, 50]]},
	{"key": "Greywood Bow", "object_type": 2678, "slot_type": 3, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[25, 55]]},
	{"key": "Health Potion", "object_type": 2594, "slot_type": 10, "equipment_tier": 1, "bag_type": 0, "soulbound": false, "stats": {}, "damage_ranges": [], "effects": [{"type": "Heal", "amount": 100}]},
	{"key": "Magic Potion", "object_type": 2595, "slot_type": 10, "equipment_tier": 1, "bag_type": 0, "soulbound": false, "stats": {}, "damage_ranges": [], "effects": [{"type": "Magic", "amount": 100}]},
	{"key": "Ring of Attack", "object_type": 2596, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Attack": 3}, "damage_ranges": []},
	{"key": "Ring of Defense", "object_type": 2597, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Defense": 3}, "damage_ranges": []},
	{"key": "Ring of Speed", "object_type": 2598, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Speed": 3}, "damage_ranges": []},
	{"key": "Ring of Vitality", "object_type": 2614, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Vitality": 3}, "damage_ranges": []},
	{"key": "Ring of Wisdom", "object_type": 2615, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Wisdom": 3}, "damage_ranges": []},
	{"key": "Ring of Dexterity", "object_type": 2637, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Dexterity": 3}, "damage_ranges": []},
	{"key": "Ring of Health", "object_type": 2599, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Health": 40}, "damage_ranges": []},
	{"key": "Ring of Magic", "object_type": 2600, "slot_type": 9, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Mana": 40}, "damage_ranges": []},
	{"key": "Flame Burst Spell", "object_type": 2772, "slot_type": 11, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[30, 70]]},
	{"key": "Remedy Tome", "object_type": 2775, "slot_type": 4, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Seal of the Pilgrim", "object_type": 2777, "slot_type": 12, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Cloak of Darkness", "object_type": 2647, "slot_type": 13, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Robe of the Apprentice", "object_type": 2686, "slot_type": 14, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {"Defense": 3, "Wisdom": 1}, "damage_ranges": []},
	{"key": "Robe of the Acolyte", "object_type": 2653, "slot_type": 14, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {"Defense": 4, "Wisdom": 1, "Mana": 10}, "damage_ranges": []},
	{"key": "Reinforced Quiver", "object_type": 2658, "slot_type": 15, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Dexterity": 1}, "damage_ranges": [[140, 180]]},
	{"key": "Bronze Helm", "object_type": 2663, "slot_type": 16, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {"Defense": 3}, "damage_ranges": []},
	{"key": "Comet Staff", "object_type": 2713, "slot_type": 17, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[15, 35]]},
	{"key": "Serpentine Staff", "object_type": 2714, "slot_type": 17, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[20, 40]]},
	{"key": "Spider Venom", "object_type": 2724, "slot_type": 18, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Breathtaker Skull", "object_type": 2731, "slot_type": 19, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Wilderlands Trap", "object_type": 2738, "slot_type": 20, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Suspension Orb", "object_type": 2626, "slot_type": 21, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Deception Prism", "object_type": 2844, "slot_type": 22, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Discharge Scepter", "object_type": 2862, "slot_type": 23, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": []},
	{"key": "Plain Katana", "object_type": 3142, "slot_type": 24, "equipment_tier": 2, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[30, 70]]},
	{"key": "Thunder Katana", "object_type": 3143, "slot_type": 24, "equipment_tier": 3, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[45, 65]]},
	{"key": "Four-Point Star", "object_type": 3156, "slot_type": 25, "equipment_tier": 1, "bag_type": 1, "soulbound": false, "stats": {}, "damage_ranges": [[175, 275]]},
]
