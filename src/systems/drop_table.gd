extends RefCounted
class_name DropTable
## Drop-table helper for GRAVEBAG: threshold rows plus the tier each pays.
##
## Port of the rules from the prior Phaser design (`src/game/bags.ts`,
## `meetsThreshold` / `rollDrops` / `bestBagForDrops`). Every row rolls
## independently (one rand() call per row, in order); the best rolled
## tier decides the bag.
##
## Pure logic: no nodes, no scene wiring.

## One row of a drop table: a threshold plus the tier it pays.
class Entry:
	extends RefCounted
	## Stable key for logs and tests (e.g. "draught", "relic").
	var key: String = ""
	## Drop chance in [0, 1]: rolls below it. 0 never, >= 1 always.
	var threshold: float = 0.0
	## Bag tier this entry drops into.
	var tier: String = "brown"

	func _init(p_key: String = "", p_threshold: float = 0.0, p_tier: String = "brown") -> void:
		key = p_key
		threshold = p_threshold
		tier = p_tier


## Does a uniform [0, 1) roll beat the threshold? Clamp-exact: a 0
## threshold never drops, 1 (or more) always drops.
static func meets_threshold(roll01: float, threshold: float) -> bool:
	if not (threshold > 0.0):
		return false
	if threshold >= 1.0:
		return true
	return roll01 < threshold


## Roll every row independently (one rand() call per row, in order) and
## return the winning entries. `rand` is a Callable returning a float
## in [0, 1).
static func roll_drops(rand: Callable, table: Array) -> Array:
	var wins: Array = []
	for entry in table:
		if meets_threshold(rand.call(), float(entry.threshold)):
			wins.append(entry)
	return wins


## Best bag tier among rolled drops (highest rank), or "" when the
## table paid nothing.
static func best_bag_for_drops(drops: Array) -> String:
	var best: String = ""
	for drop in drops:
		if best == "" or BagTiers.compare_rank(String(drop.tier), best) > 0:
			best = String(drop.tier)
	return best
