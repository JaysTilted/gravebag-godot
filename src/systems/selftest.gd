extends SceneTree
## FSoD assertions adapted 2026-10-06 (AGPLv3), commit 6fd20aa:
## https://github.com/ossimc82/fabiano-swagger-of-doom
## wServer/logic/db/BehaviorDb.Lowland.cs; wServer/logic/loot/LootDefs.cs,
## Loots.cs; db/data/dat1.xml; wServer/realm/StatsManager.cs.
## Selftest for src/systems/* (loot/XP/permadeath rules).
##
## Run headless from the project root (after `--import` builds the class
## cache that `class_name` lookups need):
##   godot --headless --path . -s res://src/systems/selftest.gd
## Prints SELFTEST PASS and exits 0 when every check holds, else
## SELFTEST FAIL with a nonzero exit. No nodes, no scene wiring.

var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		printerr("SELFTEST FAIL: ", label)
		_failures += 1


func _initialize() -> void:
	# Tier order + colors.
	var want_order: Array[String] = ["brown", "pink", "purple", "egg", "cyan", "blue", "white", "orange"]
	_check(BagTiers.ORDER == want_order, "FSoD bag type order 0..7")
	_check(BagTiers.TOP_RANK == 7, "FSoD top bag type is 7")
	_check(BagTiers.tier_color_hex("brown") == 0x8A5A2B, "brown color")
	_check(BagTiers.tier_color_hex("pink") == 0xFF7AB3, "pink color")
	_check(BagTiers.tier_color_hex("purple") == 0xA55AFF, "purple color")
	_check(BagTiers.tier_color_hex("blue") == 0x3FA9FF, "blue color")
	_check(BagTiers.tier_color_hex("white") == 0xF5F2FF, "white color")
	for tier in BagTiers.ORDER:
		_check(BagTiers.despawn_msec(tier) == 30000, "%s: FSoD 30s lifetime" % tier)
	_check(BagTiers.CAPACITY == 8, "FSoD bags hold eight items")
	_check(BagTiers.object_type("blue") == 0x50b, "FSoD blue bag object type")
	_check(BagTiers.object_type("white") == 0x50c, "FSoD white bag object type")

	# Soulbound rule: brown/pink public, purple+ killer-only.
	_check(BagTiers.is_public_bag("brown") and BagTiers.is_public_bag("pink"),
			"brown/pink public")
	_check(BagTiers.is_soulbound("purple") and BagTiers.is_soulbound("blue")
			and BagTiers.is_soulbound("white"), "purple+ soulbound")
	_check(BagTiers.can_loot("pink", false) and BagTiers.can_loot("brown", false),
			"stranger loots public bags")
	_check(not BagTiers.can_loot("purple", false) and not BagTiers.can_loot("blue", false)
			and not BagTiers.can_loot("white", false), "stranger shut out of soulbound")
	_check(BagTiers.can_loot("white", true), "killer loots everything")

	# Compatibility grading is XML bag type, never a killer-level bonus.
	_check(LootGrading.grade_loot(1, 0) == "brown", "no T0 candidates: brown adapter")
	_check(LootGrading.grade_loot(12, 2) == "pink", "Lowland T2 equipment: pink")
	_check(LootGrading.grade_loot(1, 3) == "pink", "Lowland T3 equipment: pink")
	_check(LootGrading.grade_loot(20, 3) == LootGrading.grade_loot(1, 3), "killer level cannot upgrade loot")
	_test_fsod()

	# XP curve: level 1 costs 45, edges return 0, total to 20 is 19950.
	_check(XpLedger.xp_for_next_level(1) == 45, "xp level 1 costs 45")
	_check(XpLedger.xp_for_next_level(0) == 0 and XpLedger.xp_for_next_level(20) == 0,
			"xp outside 1..19 is 0")
	_check(XpLedger.xp_to_max_level() == 19950, "xp total to 20 is 19950")

	# XP to 20, then overflow flips to fame; fame banks only on death.
	var diver: XpLedger = XpLedger.new()
	diver.grant_xp(float(XpLedger.xp_to_max_level()))
	_check(diver.level == 20 and diver.xp == 0 and diver.pending_fame == 0.0,
			"exact total reaches 20 with no fame")
	_check(diver.banked_fame == 0.0, "no banked fame before death")
	diver.grant_xp(4000.0)
	_check(diver.level == 20 and diver.pending_fame == 2.0, "overflow flips to fame 2000:1")
	_check(diver.banked_fame == 0.0, "fame stays pending while alive")
	var banked: float = diver.die()
	_check(banked == 2.0 and diver.banked_fame == 2.0 and diver.pending_fame == 0.0,
			"death banks pending fame")
	_check(diver.die() == 0.0, "second death banks nothing")
	diver.grant_xp(99999.0)
	_check(diver.level == 20 and diver.pending_fame == 0.0 and diver.banked_fame == 2.0,
			"dead ledger ignores xp")

	# Drop table: thresholds, independent rolls, best tier wins.
	_check(not DropTable.meets_threshold(0.0, 0.0), "threshold 0 never drops")
	_check(DropTable.meets_threshold(0.999, 1.0), "threshold 1 always drops")
	_check(DropTable.meets_threshold(0.2, 0.5) and not DropTable.meets_threshold(0.7, 0.5),
			"roll below threshold drops")
	var table: Array = [
		DropTable.Entry.new("scrap", 0.5, "brown"),
		DropTable.Entry.new("draught", 0.5, "blue"),
	]
	var rolls := [0.25, 0.9]
	var cursor := [0]
	var rand := func() -> float:
		var v: float = rolls[cursor[0]]
		cursor[0] += 1
		return v
	var wins: Array = DropTable.roll_drops(rand, table)
	_check(wins.size() == 1 and String(wins[0].key) == "scrap", "one rand per row in order")
	_check(DropTable.best_bag_for_drops(wins) == "brown", "best tier of single win")
	_check(DropTable.best_bag_for_drops(table) == "blue", "best tier of full table")
	_check(DropTable.best_bag_for_drops([]) == "", "empty drops pay nothing")

	# Grave record: reclaim-or-lose.
	var grave: GraveRecord = GraveRecord.new(Vector2(7, -3), ["sword", "draught"])
	_check(not grave.is_empty(), "grave holds items")
	var got: Array = grave.reclaim()
	var want_got: Array = ["sword", "draught"]
	_check(got == want_got and grave.is_empty() and grave.reclaimed,
			"grave reclaim clears")
	var lost: GraveRecord = GraveRecord.new(Vector2.ZERO, ["relic"])
	lost.abandon()
	_check(lost.is_empty() and not lost.reclaimed, "abandoned grave is lost")

	if _failures == 0:
		print("SELFTEST PASS")
	else:
		printerr("SELFTEST FAIL: ", _failures)
	quit(1 if _failures > 0 else 0)


func _row(enemy: String, index: int, equipment_tier: int, item_type: String, chance: float) -> void:
	var table: Array = DropTable.for_enemy(enemy)
	_check(table.size() > index, "%s row %d exists" % [enemy, index])
	if table.size() <= index:
		return
	var row: DropTable.Entry = table[index]
	_check(row.equipment_tier == equipment_tier and row.item_type == item_type
		and row.threshold == chance, "%s: T%d %s chance %s" % [enemy, equipment_tier, item_type, chance])


func _test_fsod() -> void:
	_check(DropTable.LOWLAND.size() == 23, "all 23 Lowland enemies present")
	var row_count := 0
	for enemy in DropTable.LOWLAND:
		var table: Array = DropTable.for_enemy(enemy)
		row_count += table.size()
		for entry in table:
			if entry.kind == "tier":
				_check(not LootGrading.tier_candidates(entry.equipment_tier, entry.item_type).is_empty(), "%s has tier candidates" % enemy)
			else:
				_check(not entry.item.is_empty(), "%s has named item definition" % enemy)
	_check(row_count == 53, "all 53 Lowland loot arguments present")
	_row("Hobbit Mage", 0, 2, "Weapon", 0.3)
	_row("Hobbit Mage", 2, 1, "Ring", 0.11)
	_row("Undead Hobbit Mage", 2, 1, "Ring", 0.12)
	_row("Elf Wizard", 0, 2, "Weapon", 0.36)
	_row("Elf Wizard", 1, 2, "Armor", 0.36)
	_row("Goblin Mage", 2, 1, "Ring", 0.09)
	_row("Goblin Mage", 3, 1, "Ability", 0.38)
	_row("Giant Crab", 0, 2, "Weapon", 0.14)
	_row("Giant Crab", 1, 2, "Armor", 0.19)
	_row("Giant Crab", 2, 1, "Ring", 0.05)
	_row("Giant Crab", 3, 1, "Ability", 0.28)
	_check(DropTable.for_enemy("Hobbit Archer")[0].threshold == 0.04, "Hobbit Archer HP chance .04")
	_check(DropTable.for_enemy("Sumo Master")[1].threshold == 0.05, "Sumo Master MP chance .05")
	_check(DropTable.for_enemy("Enraged Bunny")[0].threshold == 0.01, "Enraged Bunny HP chance .01")
	_check(DropTable.for_enemy("Sandsman King")[4].threshold == 0.04, "Sandsman King HP chance .04")
	_check(DropTable.for_enemy("Sand Devil").is_empty(), "Sand Devil drops nothing")
	_check(DropTable.for_enemy("Easily Enraged Bunny").is_empty(), "pre-transform bunny drops nothing")
	_check(LootGrading.EGG_CHANCES == [0.1, 0.05, 0.01, 0.001], "FSoD Common..Legendary egg probabilities")
	_check(LootGrading.ITEMS.size() == 42, "complete Lowland catalog: 42 items")
	_check(LootGrading.tier_candidates(2, "Weapon").size() == 6, "T2 weapons include katana: six candidates")
	_check(LootGrading.tier_candidates(3, "Armor").size() == 3, "T3 armor: three candidates")
	_check(LootGrading.tier_candidates(1, "Ability").size() == 14, "T1 abilities include star: fourteen candidates")
	_check(LootGrading.tier_candidates(1, "Ring").size() == 8, "T1 rings: eight candidates")
	_check(LootGrading.item_definition("Saber").damage_ranges == [[75, 105]], "Saber damage range 75..105 exclusive")
	_check(LootGrading.roll_projectile_damage("Saber", 0) == 75 and LootGrading.roll_projectile_damage("Saber", 29) == 104
		and LootGrading.roll_projectile_damage("Saber", 30) == 75, "FSoD damage modulo excludes maximum")
	_check(LootGrading.stat_roll_ranges("Leather Armor") == {"Defense": [6, 6]}, "Leather Armor defense fixed at 6")
	_check(LootGrading.roll_stats("Ring of Attack") == {"Attack": 3}, "Ring of Attack bonus fixed at 3")
	_check(LootGrading.roll_stats("Robe of the Acolyte") == {"Defense": 4, "Wisdom": 1, "Mana": 10}, "T3 robe exact fixed bonuses")
	_check(LootGrading.item_definition("Health Potion").effects == [{"type": "Heal", "amount": 100}], "HP potion restores 100")
	_check(LootGrading.item_definition("Magic Potion").effects == [{"type": "Magic", "amount": 100}], "MP potion restores 100")
	var calls := [0]
	var zero := func() -> float:
		calls[0] += 1
		return 0.0
	var wins: Array = DropTable.roll_enemy_drops("Hobbit Mage", zero)
	_check(calls[0] == 33 and wins.size() == 33, "TierLoot expands and rolls all 33 mage candidates, not one per tier")
	_check(is_equal_approx(wins[0].threshold, 0.3 / 6.0), "Hobbit weapon individual probability .3/6")
	var tier_table: Array = [DropTable.tier_loot(2, "Weapon", 0.3)]
	_check(DropTable.roll_drops(func() -> float: return 0.05, tier_table).is_empty(), "roll == divided chance loses")
	_check(DropTable.roll_drops(func() -> float: return 0.049, tier_table).size() == 6, "multiple weapons can independently win")
	_check(DropTable.roll_enemy_drops("Hobbit Mage", func() -> float: return 0.99).is_empty(), "enemy can drop nothing")
	var bags: Array = DropTable.make_bags(wins)
	_check(bags.size() == 5 and bags[0].items.size() == 8 and bags[4].items.size() == 1, "33 items split into five bags of at most eight")
	_check(bags[0].tier == "pink" and bags[0].owner_id == null, "Lowland pink equipment is public")
	var pots: Array = DropTable.roll_enemy_drops("Sumo Master", zero)
	_check(DropTable.best_bag_for_drops(pots) == "brown" and not pots[0].soulbound, "HP/MP potions use public brown bag, not blue")
	_check(DropTable.make_bags(pots, "owner")[0].owner_id == "owner", "ownership is explicit even for brown bags")
	var copy: Dictionary = LootGrading.item_definition("Leather Armor")
	copy.stats.Defense = 999
	_check(LootGrading.roll_stats("Leather Armor").Defense == 6, "definitions returned as defensive copies")
