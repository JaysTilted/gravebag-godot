extends RefCounted
class_name DropTable
## Adapted 2026-10-06 from FSoD (AGPLv3), commit 6fd20aa:
## https://github.com/ossimc82/fabiano-swagger-of-doom
## wServer/logic/loot/LootDefs.cs, Loots.cs;
## wServer/logic/db/BehaviorDb.Lowland.cs.
## Active FSoD LootDefs.cs.Populate + Loots.cs.Handle, NOT legacy Loot.cs.
## TierLoot expands to ALL matching XML items, each with chance / count.
## Each candidate rolls independently: zero, one, or multiple can win.

class Entry:
	extends RefCounted
	var key: String = ""
	var threshold: float = 0.0
	var tier: String = "brown" # Bag color, not equipment tier.
	var kind: String = "item"
	var equipment_tier: int = -1
	var item_type: String = ""
	var item: Dictionary = {}
	var soulbound: bool = false

	func _init(p_key: String = "", p_threshold: float = 0.0, p_tier: String = "brown") -> void:
		key = p_key
		threshold = p_threshold
		tier = p_tier


static func tier_loot(equipment_tier: int, item_type: String, chance: float) -> Entry:
	var entry := Entry.new("T%d %s" % [equipment_tier, item_type], chance)
	entry.kind = "tier"
	entry.equipment_tier = equipment_tier
	entry.item_type = item_type
	return entry


static func item_loot(item_name: String, chance: float) -> Entry:
	return _item_entry(LootGrading.item_definition(item_name), chance)


static func _item_entry(definition: Dictionary, chance: float) -> Entry:
	var entry := Entry.new(String(definition.get("key", "")), chance,
		BagTiers.for_bag_type(int(definition.get("bag_type", 0))))
	entry.item = definition.duplicate(true)
	entry.equipment_tier = int(definition.get("equipment_tier", -1))
	entry.soulbound = bool(definition.get("soulbound", false))
	return entry


static func meets_threshold(roll01: float, threshold: float) -> bool:
	if not (threshold > 0.0):
		return false
	if threshold >= 1.0:
		return true
	return roll01 < threshold


static func roll_drops(rand: Callable, table: Array) -> Array:
	var wins: Array = []
	for entry in table:
		if entry.kind == "tier":
			var candidates: Array = LootGrading.tier_candidates(entry.equipment_tier, entry.item_type)
			for candidate in candidates:
				var chance: float = entry.threshold / float(candidates.size())
				if meets_threshold(float(rand.call()), chance):
					wins.append(_item_entry(candidate, chance))
		else:
			if meets_threshold(float(rand.call()), float(entry.threshold)):
				wins.append(entry)
	return wins


static func best_bag_for_drops(drops: Array) -> String:
	var best := ""
	for drop in drops:
		if best == "" or BagTiers.compare_rank(String(drop.tier), best) > 0:
			best = String(drop.tier)
	return best


## All Lowland entries are shared; no Threshold/OnlyOne wrappers there.
## Empty is intentional for Easily Enraged Bunny and Sand Devil.
static func for_enemy(enemy_name: String) -> Array:
	var table: Array = []
	for row in LOWLAND.get(enemy_name, []):
		if row.kind == "tier":
			table.append(tier_loot(int(row.equipment_tier), String(row.item_type), float(row.chance)))
		else:
			table.append(item_loot(String(row.key), float(row.chance)))
	return table


static func roll_enemy_drops(enemy_name: String, rand: Callable) -> Array:
	return roll_drops(rand, for_enemy(enemy_name))


## Call separately for shared and each owner's loot, as Loots.ShowBags does.
## A null owner_id is public; do not infer ownership from bag color.
static func make_bags(drops: Array, owner_id: Variant = null) -> Array:
	var bags: Array = []
	for start in range(0, drops.size(), BagTiers.CAPACITY):
		var contents: Array = drops.slice(start, mini(start + BagTiers.CAPACITY, drops.size()))
		var tier: String = best_bag_for_drops(contents)
		bags.append({"tier": tier, "object_type": BagTiers.object_type(tier),
			"items": contents, "owner_id": owner_id, "despawn_sec": BagTiers.despawn_sec(tier)})
	return bags


# Exact BehaviorDb.Lowland.cs .Init loot arguments, in source order.
const LOWLAND := {
	"Hobbit Mage": [{"kind": "tier", "equipment_tier": 2, "item_type": "Weapon", "chance": 0.3}, {"kind": "tier", "equipment_tier": 2, "item_type": "Armor", "chance": 0.3}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ring", "chance": 0.11}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ability", "chance": 0.39}, {"kind": "item", "key": "Health Potion", "chance": 0.02}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Hobbit Archer": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Hobbit Rogue": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Undead Hobbit Mage": [{"kind": "tier", "equipment_tier": 3, "item_type": "Weapon", "chance": 0.3}, {"kind": "tier", "equipment_tier": 3, "item_type": "Armor", "chance": 0.3}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ring", "chance": 0.12}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ability", "chance": 0.39}, {"kind": "item", "key": "Magic Potion", "chance": 0.03}],
	"Undead Hobbit Archer": [{"kind": "item", "key": "Magic Potion", "chance": 0.03}],
	"Undead Hobbit Rogue": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Sumo Master": [{"kind": "item", "key": "Health Potion", "chance": 0.05}, {"kind": "item", "key": "Magic Potion", "chance": 0.05}],
	"Lil Sumo": [{"kind": "item", "key": "Health Potion", "chance": 0.02}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Elf Wizard": [{"kind": "tier", "equipment_tier": 2, "item_type": "Weapon", "chance": 0.36}, {"kind": "tier", "equipment_tier": 2, "item_type": "Armor", "chance": 0.36}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ring", "chance": 0.11}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ability", "chance": 0.39}, {"kind": "item", "key": "Health Potion", "chance": 0.02}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Elf Archer": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Elf Swordsman": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Elf Mage": [{"kind": "item", "key": "Magic Potion", "chance": 0.03}],
	"Goblin Rogue": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Goblin Warrior": [{"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Goblin Mage": [{"kind": "tier", "equipment_tier": 3, "item_type": "Weapon", "chance": 0.3}, {"kind": "tier", "equipment_tier": 3, "item_type": "Armor", "chance": 0.3}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ring", "chance": 0.09}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ability", "chance": 0.38}, {"kind": "item", "key": "Health Potion", "chance": 0.02}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Easily Enraged Bunny": [],
	"Enraged Bunny": [{"kind": "item", "key": "Health Potion", "chance": 0.01}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Forest Nymph": [{"kind": "item", "key": "Health Potion", "chance": 0.03}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Sandsman King": [{"kind": "tier", "equipment_tier": 3, "item_type": "Weapon", "chance": 0.3}, {"kind": "tier", "equipment_tier": 3, "item_type": "Armor", "chance": 0.3}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ring", "chance": 0.11}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ability", "chance": 0.39}, {"kind": "item", "key": "Health Potion", "chance": 0.04}],
	"Sandsman Sorcerer": [{"kind": "item", "key": "Magic Potion", "chance": 0.03}],
	"Sandsman Archer": [{"kind": "item", "key": "Magic Potion", "chance": 0.03}],
	"Giant Crab": [{"kind": "tier", "equipment_tier": 2, "item_type": "Weapon", "chance": 0.14}, {"kind": "tier", "equipment_tier": 2, "item_type": "Armor", "chance": 0.19}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ring", "chance": 0.05}, {"kind": "tier", "equipment_tier": 1, "item_type": "Ability", "chance": 0.28}, {"kind": "item", "key": "Health Potion", "chance": 0.02}, {"kind": "item", "key": "Magic Potion", "chance": 0.02}],
	"Sand Devil": [],
}
