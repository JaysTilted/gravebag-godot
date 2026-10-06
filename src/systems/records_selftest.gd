extends SceneTree
## FSoD numeric rules + records persistence. Headless:
## godot --headless --path . -s res://src/systems/records_selftest.gd
## Isolated temporary save only; never writes Records.SAVE_PATH.

const TMP_PATH := "user://gravebag-records-selftest.tmp.save"
var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		printerr("FAIL: ", label)
		_failures += 1


func _initialize() -> void:
	_check_fsod()
	_check_records()
	print("SELFTEST PASS" if _failures == 0 else "SELFTEST FAIL: %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_fsod() -> void:
	# Player.Leveling.cs:78-87. Six exact level-goal checks plus thresholds.
	for row in [[1, 50], [2, 150], [5, 450], [10, 950], [19, 1850], [20, 1950]]:
		_check(XpLedger.xp_for_next_level(row[0]) == row[1], "FSoD XP goal %d = %d" % row)
	_check(XpLedger.xp_at_level(2) == 50, "level 2 cumulative XP 50")
	_check(XpLedger.xp_at_level(3) == 200, "level 3 cumulative XP 200")
	_check(XpLedger.xp_at_level(10) == 4050, "level 10 cumulative XP 4050")
	_check(XpLedger.xp_to_max_level() == 18050, "level 20 cumulative XP 18050")
	_check(XpLedger.xp_for_next_level(0) == 0 and XpLedger.xp_for_next_level(21) == 0,
			"invalid levels have no goal")

	# Inject endpoint rolls to assert exact randomized stat-gain bounds.
	var low := XpLedger.new(XpLedger.WIZARD_PROFILE, func(a: int, _b: int) -> int: return a)
	var high := XpLedger.new(XpLedger.WIZARD_PROFILE, func(_a: int, b: int) -> int: return b)
	_check(low.hp == 100 and low.mp == 100 and low.stats[2] == 12, "Wizard initial HP/MP/attack 100/100/12")
	low.grant_xp(49.0)
	_check(low.level == 1 and low.xp == 49, "49 XP does not level")
	low.hp = 1
	low.mp = 1
	low.grant_xp(1.0)
	high.grant_xp(50.0)
	_check(low.level == 2 and low.xp == 0 and low.hp == 120 and low.mp == 105
			and low.stats[2] == 13, "min level-2 gains and full HP/MP refill")
	_check(high.hp == 130 and high.mp == 115 and high.stats[2] == 14, "max level-2 inclusive gains")
	low.grant_xp(18000.0)
	high.grant_xp(18000.0)
	_check(low.level == 20 and low.hp == 480 and low.mp == 195 and low.stats[2] == 31,
			"min level-20 stats 480/195/31")
	_check(high.hp == 670 and high.mp == 385 and high.stats[2] == 50,
			"max level-20 stats 670/385/50; MP capped")
	var capper := XpLedger.new(XpLedger.WIZARD_PROFILE, func(_a: int, b: int) -> int: return b)
	capper.stats = XpLedger.WIZARD_PROFILE["caps"].duplicate()
	capper.grant_xp(50.0)
	_check(capper.stats == XpLedger.WIZARD_PROFILE["caps"], "all eight stat caps applied on level-up")
	_check(low.pending_fame == 18.0 and low.xp == 0, "level 20 already has 18 base fame")
	low.grant_xp(1950.0)
	_check(low.total_xp == 20000 and low.xp == 1950 and low.pending_fame == 20.0,
			"post-20 XP remains lifetime XP; fame is 1000:1")
	_check(low.hp == 480, "post-20 XP does not increase stats")
	_check(is_equal_approx(XpLedger.new().attack_multiplier(), 0.74), "12 attack damage factor 0.74")
	_check(high.attack_multiplier(25) == 2.0, "75 effective attack damage factor 2")
	_check(high.attack_multiplier(25, false, true) == 3.0, "Damaging multiplies by 1.5")
	_check(high.attack_multiplier(25, true, true) == 0.5, "Weak overrides Damaging")
	_check(is_equal_approx(XpLedger.new().hp_regen(), 2.44), "12 vitality HP regen 2.44")
	_check(is_equal_approx(XpLedger.new().mp_regen(), 1.22), "12 wisdom MP regen 1.22")
	_check(high.hp_regen(0, true) == 1.0 and high.mp_regen(0, true) == 0.0, "Sick/Quiet source regen")

	# DamageCounter.cs:88-103. Lower clamp first, then upper, truncate.
	_check(XpLedger.kill_xp(1000, 1.0, 100, 100, 1, 1) == 5, "level-1 kill cap 5 XP")
	_check(XpLedger.kill_xp(1000, 1.0, 100, 100, 1, 1, true) == 25, "level-1 quest cap 25 XP")
	_check(XpLedger.kill_xp(1000, 1.0, 100, 100, 1, 20) == 100, "solo 1000-HP enemy grants 100 XP")
	_check(XpLedger.kill_xp(10000, 1.0, 1, 1000, 2, 20) == 100, "small hitter gets 10% enemy-XP floor")
	_check(XpLedger.kill_xp(100000, 1.0, 1, 1000, 2, 20) == 195, "level-20 cap overrides floor")
	_check(XpLedger.kill_xp(100000, 1.0, 1000, 1000, 1, 20, true) == 975, "level-20 quest cap 975 XP")
	_check(XpLedger.kill_xp(123, 1.0, 100, 100, 1, 20) == 12, "kill XP truncates fractions")
	_check(XpLedger.kill_xp(1000, 1.0, 0, 0, 1, 1) == 0, "no damage gives no XP")

	var diver := XpLedger.new()
	diver.grant_xp(999.0)
	_check(diver.pending_fame == 0.0, "999 lifetime XP = 0 fame")
	diver.grant_xp(1.0)
	_check(diver.level == 5 and diver.xp == 200 and diver.pending_fame == 1.0,
			"1000 lifetime XP at level 5 = 1 fame (live +0 fix)")
	_check(diver.banked_fame == 0.0, "fame not banked alive")
	_check(diver.die() == 1.0 and diver.banked_fame == 1.0 and diver.pending_fame == 0.0,
			"sub-20 death banks nonzero fame")
	_check(diver.die() == 0.0, "death banking idempotent")
	diver.grant_xp(99999.0)
	diver.record_kill()
	_check(diver.total_xp == 1000 and diver.fame_stats.is_empty(), "dead ledger ignores XP/events")
	var boosted := XpLedger.new()
	boosted.xp_boosted = true
	boosted.grant_xp(9025.0)
	_check(boosted.level == 20 and boosted.total_xp == 18050 and not boosted.xp_boosted,
			"XP boost doubles reward then disables at 20")
	boosted.grant_xp(1000.0)
	_check(boosted.total_xp == 19050, "level-20 XP no longer boosted")
	for row in [[0, 0], [19, 0], [20, 150], [150, 400], [400, 800], [800, 2000], [2000, 0]]:
		_check(XpLedger.fame_goal(row[0]) == row[1], "FSoD fame goal %d = %d" % row)

	var tally := XpLedger.new()
	tally.record_kill(true, false, true, true, true)
	_check(tally.fame_stats == {"god_assists": 1, "quests_completed": 1}, "assist is not killer/cube/Oryx")
	tally.record_kill(true, true, true, true, true)
	_check(tally.fame_stats["god_kills"] == 1 and tally.fame_stats["god_assists"] == 2
			and tally.fame_stats["cube_kills"] == 1 and tally.fame_stats["oryx_kills"] == 1, "last hitter kill counters")
	tally.record_shot(7)
	tally.record_hit(7)
	tally.record_hit(7)
	tally.record_shot(8)
	tally.remove_projectile(8)
	tally.record_hit(8)
	_check(tally.fame_stats["shots"] == 2 and tally.fame_stats["shots_that_damage"] == 1,
			"each projectile counted as hit once; removed shots cannot hit")

	# FameStats.CalculateTotal: exact sequential floor, gear and First Born.
	var award := XpLedger.new()
	award.grant_xp(100000.0)
	_check(award.death_fame() == 293, "100 base -> 293 with four 25% bonuses, cube friend, First Born")
	award.character_id = 1
	_check(award.death_fame() == 380, "ancestor adds 10% + 20 before other bonuses")
	award.character_id = 2
	award.fame_stats = {"shots": 4, "shots_that_damage": 1, "potions_drunk": 1,
		"special_ability_uses": 1, "teleports": 1, "cube_kills": 1}
	award.account_best_fame = 100
	_check(award.death_fame() == 100, "25% accuracy boundary does not grant Accurate; best tie no First Born")
	award.fame_stats["shots_that_damage"] = 3
	_check(award.death_fame() == 133, "75% accuracy grants two bonuses, not Sniper, plus First Born")
	award.fame_stats["shots_that_damage"] = 1
	award.equipment_fame_bonuses = [5, 10, 0, 0, 100]
	_check(award.death_fame() == 126, "four gear slots add 15% once then First Born; fifth ignored")
	award.equipment_fame_bonuses = []
	award.fame_stats["god_kills"] = 1
	award.fame_stats["monster_kills"] = 9
	_check(award.death_fame() == 100, "10% gods boundary does not grant Enemy of Gods")
	award.fame_stats["god_kills"] = 9
	award.fame_stats["monster_kills"] = 1
	_check(award.death_fame() == 133, "90% gods grants both 10% bonuses then First Born")
	award.fame_stats["shots_that_damage"] = 4
	award.fame_stats["oryx_kills"] = 1
	award.fame_stats["tiles_uncovered"] = 4000001
	award.fame_stats["level_up_assists"] = 1001
	award.fame_stats["quests_completed"] = 1001
	for dungeon in XpLedger.DUNGEONS:
		award.fame_stats[dungeon + "_completed"] = 1
	_check(award.death_fame() == 309, "all event bonuses follow source floor order")
	award.fame_stats = {"shots": 4, "shots_that_damage": 1, "potions_drunk": 1,
		"special_ability_uses": 1, "teleports": 1, "cube_kills": 1,
		"tiles_uncovered": 1000000, "level_up_assists": 100, "quests_completed": 1000}
	_check(award.death_fame() == 100, "explorer/team/quest thresholds are strictly greater")
	award.grant_xp(100000.0)
	_check(award.pending_fame == 200.0, "200000 XP = 200 base fame")
	award.grant_xp(1000.0)
	_check(award.pending_fame == 201.0, "fame continues above 200; no invented cap")
	var invalid := XpLedger.new()
	for amount in [-1.0, 0.0, NAN, INF]:
		invalid.grant_xp(amount)
	_check(invalid.total_xp == 0 and invalid.level == 1, "invalid XP input ignored")


func _check_records() -> void:
	_check(Records.SAVE_PATH == "user://gravebag.save", "live save API unchanged")
	var records := Records.new()
	_check(records.autofire and records.volume == 0.8 and records.banked_fame == 0.0, "record defaults")
	_check(records.bank_fame(2.0) == 2.0 and records.bank_fame(3.5) == 5.0, "bank uses whole FSoD fame")
	for amount in [0.0, -1.0, NAN, INF]:
		records.bank_fame(amount)
	_check(records.banked_fame == 5.0, "bank ignores invalid input")
	_check(records.record_dive(5, 10, 2, 1.5), "first dive improves")
	_check(records.record_dive(3, 20, 1, 0.5), "kills improve independently")
	_check(records.best_level == 5 and records.best_kills == 20 and records.best_bags == 2
			and records.best_fame == 1.0, "best dive per-stat maxima with whole fame")
	_check(not records.record_dive(-4, -2, -1, NAN), "invalid dive improves nothing")
	records.record_dive(99, 0, 0, 0.0)
	_check(records.best_level == 20, "best level capped at 20")
	records.set_autofire(false)
	records.set_volume(2.0)
	_check(not records.autofire and records.volume == 1.0, "autofire toggle + volume ceiling")
	records.set_volume(-1.0)
	records.set_volume(NAN)
	_check(records.volume == 0.0, "volume floor and invalid input ignored")
	records.set_volume(0.25)
	DirAccess.remove_absolute(TMP_PATH)
	_check(records.save_to(TMP_PATH) == OK, "save temporary records")
	var restored := Records.new()
	_check(restored.load_from(TMP_PATH) == OK, "restore temporary records")
	_check(restored.banked_fame == 5.0 and restored.best_level == 20 and restored.best_kills == 20
			and restored.best_bags == 2 and restored.best_fame == 1.0
			and not restored.autofire and restored.volume == 0.25, "all record fields round-trip")
	DirAccess.remove_absolute(TMP_PATH)
	_check(restored.load_from(TMP_PATH) != OK and restored.banked_fame == 0.0
			and restored.autofire and restored.volume == 0.8, "missing save resets defaults")
	var corrupt := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if corrupt == null:
		_check(false, "corrupt fixture writable")
	else:
		corrupt.store_string("[unclosed section\njunk")
		corrupt.close()
		_check(restored.load_from(TMP_PATH) != OK and restored.best_level == 0, "corrupt save resets defaults")
	var legacy := ConfigFile.new()
	legacy.set_value("bank", "fame", 12.75)
	legacy.set_value("best", "level", 99)
	legacy.set_value("best", "kills", "wrong type")
	legacy.set_value("best", "fame", 4.75)
	_check(legacy.save(TMP_PATH) == OK and restored.load_from(TMP_PATH) == OK, "legacy save loads")
	_check(restored.banked_fame == 12.0 and restored.best_level == 20
			and restored.best_kills == 0 and restored.best_fame == 4.0, "legacy fractions migrate; wrong types safe")
	DirAccess.remove_absolute(TMP_PATH)
