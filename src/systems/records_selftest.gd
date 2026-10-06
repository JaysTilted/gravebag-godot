extends SceneTree
## Selftest for src/systems/records.gd (fame bank + best dive + settings).
##
## Run headless from the project root (after `--import` builds the class
## cache that `class_name` lookups need):
##   godot --headless --path . -s res://src/systems/records_selftest.gd
## Prints SELFTEST PASS and exits 0 when every check holds, else
## SELFTEST FAIL with a nonzero exit. No nodes, no scene wiring.
##
## File checks use a temp path only and never touch the live save at
## Records.SAVE_PATH.

const TMP_PATH: String = "user://gravebag-records-selftest.tmp.save"

var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		printerr("FAIL: ", label)
		_failures += 1


func _initialize() -> void:
	_check(Records.SAVE_PATH == "user://gravebag.save", "save path is user://gravebag.save")

	# Settings defaults: autofire on, volume at default.
	var fresh: Records = Records.new()
	_check(fresh.autofire == Records.DEFAULT_AUTOFIRE and fresh.autofire,
			"autofire defaults on")
	_check(fresh.volume == Records.DEFAULT_VOLUME, "volume defaults")
	_check(fresh.banked_fame == 0.0 and fresh.best_level == 0
			and fresh.best_kills == 0 and fresh.best_bags == 0
			and fresh.best_fame == 0.0, "fresh records are zeroed")

	# Bank accumulates; junk input is ignored.
	var bank: Records = Records.new()
	_check(bank.bank_fame(2.0) == 2.0, "bank first deposit")
	_check(bank.bank_fame(3.5) == 5.5 and bank.banked_fame == 5.5,
			"bank accumulates")
	bank.bank_fame(0.0)
	bank.bank_fame(-10.0)
	bank.bank_fame(NAN)
	bank.bank_fame(INF)
	_check(bank.banked_fame == 5.5, "bank ignores zero/negative/non-finite")

	# Best dive keeps the per-stat maximum.
	var best: Records = Records.new()
	_check(best.record_dive(5, 10, 2, 1.5), "first dive improves")
	_check(best.best_level == 5 and best.best_kills == 10
			and best.best_bags == 2 and best.best_fame == 1.5,
			"first dive recorded")
	_check(best.record_dive(3, 20, 1, 0.5), "weaker level but better kills improves")
	_check(best.best_level == 5 and best.best_kills == 20
			and best.best_bags == 2 and best.best_fame == 1.5,
			"best dive keeps max per stat")
	_check(not best.record_dive(1, 1, 0, 0.0), "fully weaker dive improves nothing")
	_check(best.best_level == 5 and best.best_kills == 20,
			"weaker dive changes nothing")
	best.record_dive(-4, -2, -1, -9.0)
	_check(best.best_level == 5 and best.best_kills == 20
			and best.best_bags == 2 and best.best_fame == 1.5,
			"negative dive input clamps to zero")

	# Settings setters: toggle sticks, volume clamps, NaN ignored.
	var cfg: Records = Records.new()
	cfg.set_autofire(false)
	_check(not cfg.autofire, "autofire toggles off")
	cfg.set_autofire(true)
	_check(cfg.autofire, "autofire toggles on")
	cfg.set_volume(0.3)
	_check(cfg.volume == 0.3, "volume sets in range")
	cfg.set_volume(2.0)
	_check(cfg.volume == 1.0, "volume clamps high")
	cfg.set_volume(-1.0)
	_check(cfg.volume == 0.0, "volume clamps low")
	cfg.set_volume(0.5)
	cfg.set_volume(NAN)
	_check(cfg.volume == 0.5, "volume ignores non-finite")

	# Round-trip through a temp path preserves everything.
	DirAccess.remove_absolute(TMP_PATH)
	var wrote: Records = Records.new()
	wrote.bank_fame(12.25)
	wrote.record_dive(9, 42, 3, 4.75)
	wrote.set_autofire(false)
	wrote.set_volume(0.25)
	_check(wrote.save_to(TMP_PATH) == OK, "save to temp path")
	var read: Records = Records.new()
	_check(read.load_from(TMP_PATH) == OK, "load from temp path")
	_check(read.banked_fame == 12.25, "round-trip bank")
	_check(read.best_level == 9 and read.best_kills == 42
			and read.best_bags == 3 and read.best_fame == 4.75,
			"round-trip best dive")
	_check(not read.autofire and read.volume == 0.25, "round-trip settings")
	DirAccess.remove_absolute(TMP_PATH)

	# Missing file loads defaults (and reports an error, not a crash).
	var missing: Records = Records.new()
	missing.bank_fame(99.0)
	var missing_err: Error = missing.load_from(TMP_PATH)
	_check(missing_err != OK, "missing file reports error")
	_check(missing.banked_fame == 0.0 and missing.best_level == 0
			and missing.autofire == Records.DEFAULT_AUTOFIRE
			and missing.volume == Records.DEFAULT_VOLUME,
			"missing file loads defaults")
	DirAccess.remove_absolute(TMP_PATH)

	# Corrupt file loads defaults (and reports an error, not a crash).
	var corrupt_out := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if corrupt_out == null:
		_check(false, "corrupt fixture writable")
	else:
		corrupt_out.store_string("[unclosed section\njunk after")
		corrupt_out.close()
		var broken: Records = Records.new()
		broken.bank_fame(7.0)
		broken.record_dive(8, 8, 8, 8.0)
		broken.set_autofire(false)
		var corrupt_err: Error = broken.load_from(TMP_PATH)
		_check(corrupt_err != OK, "corrupt file reports error")
		_check(broken.banked_fame == 0.0 and broken.best_level == 0
				and broken.best_kills == 0 and broken.best_bags == 0
				and broken.best_fame == 0.0, "corrupt file resets bank and bests")
		_check(broken.autofire == Records.DEFAULT_AUTOFIRE
				and broken.volume == Records.DEFAULT_VOLUME,
				"corrupt file resets settings to defaults")
	DirAccess.remove_absolute(TMP_PATH)

	# Wrong-typed values fall back to defaults, never crash.
	var typed := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if typed == null:
		_check(false, "typed fixture writable")
	else:
		typed.store_string("[bank]\nfame=\"lots\"\n[best]\nlevel=\"nine\"\n")
		typed.close()
		var odd: Records = Records.new()
		_check(odd.load_from(TMP_PATH) == OK, "wrong-typed file still parses")
		_check(odd.banked_fame == 0.0 and odd.best_level == 0,
				"wrong-typed values fall back to zero")
	DirAccess.remove_absolute(TMP_PATH)

	if _failures == 0:
		print("SELFTEST PASS")
	else:
		printerr("SELFTEST FAIL: ", _failures)
	quit(1 if _failures > 0 else 0)
