extends SceneTree
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
		printerr("FAIL: ", label)
		_failures += 1


func _initialize() -> void:
	# Tier order + colors.
	var want_order: Array[String] = ["brown", "pink", "purple", "blue", "white"]
	_check(BagTiers.ORDER == want_order, "tier order brown->white")
	_check(BagTiers.TOP_RANK == 4, "top rank is 4")
	_check(BagTiers.tier_color_hex("brown") == 0x8A5A2B, "brown color")
	_check(BagTiers.tier_color_hex("pink") == 0xFF7AB3, "pink color")
	_check(BagTiers.tier_color_hex("purple") == 0xA55AFF, "purple color")
	_check(BagTiers.tier_color_hex("blue") == 0x3FA9FF, "blue color")
	_check(BagTiers.tier_color_hex("white") == 0xF5F2FF, "white color")
	var rising := true
	for i in range(1, BagTiers.ORDER.size()):
		if BagTiers.despawn_sec(BagTiers.ORDER[i]) <= BagTiers.despawn_sec(BagTiers.ORDER[i - 1]):
			rising = false
	_check(rising, "despawn strictly rising with rank")

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

	# Kill grading.
	_check(LootGrading.grade_loot(1, 0) == "brown", "grade weakest->brown")
	_check(LootGrading.grade_loot(12, 2) == "pink", "grade mid->pink")
	_check(LootGrading.grade_loot(1, 3) == "purple", "grade elder-lean->purple")
	_check(LootGrading.grade_loot(20, 4) == "blue", "grade near-max->blue")
	_check(LootGrading.grade_loot(20, 5) == "white", "grade max->white")
	_check(LootGrading.grade_loot(-50, 99) == "blue", "grade clamps inputs")

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
