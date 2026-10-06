extends RefCounted
class_name Records
## Lifetime fame bank + best-dive records + settings for GRAVEBAG.
##
## Cross-run persistence: fame banked on death accumulates here, the best
## dive (level, kills, bags, fame) keeps the per-stat maximum, and player
## settings (autofire, volume) survive restarts. Saved with a ConfigFile
## at SAVE_PATH (`user://gravebag.save`).
##
## FSoD fame representation adapted 2026-10-06 from db/FameStats.cs:
## https://github.com/ossimc82/fabiano-swagger-of-doom (AGPL-3.0),
## commit 6fd20aad4a7905b13f25389c68368a942a2b68cb.
## FSoD account fame is an integer death-award currency (FameStats.cs).
## Fractional legacy saves/deposits are floored; there is no fame cap or
## spending rule in FameStats/DailyQuestConstants. Daily quests pay tokens.
## Pure logic: no nodes, no scene wiring.

## Default save location for the live game.
const SAVE_PATH: String = "user://gravebag.save"

## Settings defaults: autofire on, volume at 80%.
const DEFAULT_AUTOFIRE: bool = true
const DEFAULT_VOLUME: float = 0.8

const MIN_VOLUME: float = 0.0
const MAX_VOLUME: float = 1.0


## Lifetime fame banked across all dives. Grows only via bank_fame().
var banked_fame: float = 0.0
## Best single dive, per-stat maximums (a later dive can raise kills
## without beating level).
var best_level: int = 0
var best_kills: int = 0
var best_bags: int = 0
var best_fame: float = 0.0
## Hold-click/autofire assist. Defaults on.
var autofire: bool = DEFAULT_AUTOFIRE
## Master volume, linear 0..1. Defaults to DEFAULT_VOLUME.
var volume: float = DEFAULT_VOLUME


## Restore every field to its default (no dive yet, empty bank).
func reset() -> void:
	banked_fame = 0.0
	best_level = 0
	best_kills = 0
	best_bags = 0
	best_fame = 0.0
	autofire = DEFAULT_AUTOFIRE
	volume = DEFAULT_VOLUME


## Add fame to the lifetime bank. Ignores non-positive or non-finite
## amounts. Returns the bank total.
func bank_fame(amount: float) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return banked_fame
	banked_fame += floor(amount)
	return banked_fame


## Record one finished dive. Each best stat keeps its maximum, so a dive
## that only beats kills still counts. Negative inputs clamp to zero.
## Returns true when at least one best improved.
func record_dive(p_level: int, p_kills: int, p_bags: int, p_fame: float) -> bool:
	var improved := false
	var level: int = clampi(p_level, 0, 20)
	if level > best_level:
		best_level = level
		improved = true
	var kills: int = maxi(p_kills, 0)
	if kills > best_kills:
		best_kills = kills
		improved = true
	var bags: int = maxi(p_bags, 0)
	if bags > best_bags:
		best_bags = bags
		improved = true
	var fame: float = 0.0
	if is_finite(p_fame):
		fame = floor(maxf(p_fame, 0.0))
	if fame > best_fame:
		best_fame = fame
		improved = true
	return improved


func set_autofire(enabled: bool) -> void:
	autofire = enabled


## Set master volume, clamped to 0..1. Non-finite input is ignored.
func set_volume(value: float) -> void:
	if not is_finite(value):
		return
	volume = clampf(value, MIN_VOLUME, MAX_VOLUME)


## Write all fields to `path`. Returns the ConfigFile save error (OK on
## success).
func save_to(path: String = SAVE_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("bank", "fame", banked_fame)
	cfg.set_value("best", "level", best_level)
	cfg.set_value("best", "kills", best_kills)
	cfg.set_value("best", "bags", best_bags)
	cfg.set_value("best", "fame", best_fame)
	cfg.set_value("settings", "autofire", autofire)
	cfg.set_value("settings", "volume", volume)
	return cfg.save(path)


## Read all fields from `path`. Missing or corrupt files reset to
## defaults and return the load error (OK on success). Never leaves
## half-loaded state: fields are defaults unless the whole file parsed.
func load_from(path: String = SAVE_PATH) -> Error:
	reset()
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK:
		reset()
		return err
	banked_fame = _as_nonneg_float(cfg.get_value("bank", "fame", 0.0))
	best_level = mini(20, _as_nonneg_int(cfg.get_value("best", "level", 0)))
	best_kills = _as_nonneg_int(cfg.get_value("best", "kills", 0))
	best_bags = _as_nonneg_int(cfg.get_value("best", "bags", 0))
	best_fame = _as_nonneg_float(cfg.get_value("best", "fame", 0.0))
	autofire = _as_bool(cfg.get_value("settings", "autofire", DEFAULT_AUTOFIRE),
			DEFAULT_AUTOFIRE)
	volume = _as_volume(cfg.get_value("settings", "volume", DEFAULT_VOLUME))
	return OK


static func _as_nonneg_float(v: Variant) -> float:
	if v is float and is_finite(v):
		return floor(maxf(v, 0.0))
	if v is int:
		return maxf(float(v), 0.0)
	return 0.0


static func _as_nonneg_int(v: Variant) -> int:
	if v is int:
		return maxi(v, 0)
	if v is float and is_finite(v):
		return maxi(int(floor(v)), 0)
	return 0


static func _as_bool(v: Variant, fallback: bool) -> bool:
	if v is bool:
		return v
	if v is int:
		return v != 0
	return fallback


static func _as_volume(v: Variant) -> float:
	if v is float and is_finite(v):
		return clampf(v, MIN_VOLUME, MAX_VOLUME)
	if v is int:
		return clampf(float(v), MIN_VOLUME, MAX_VOLUME)
	return DEFAULT_VOLUME
