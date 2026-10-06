extends RefCounted
class_name BagTiers
## Loot-bag tier table for GRAVEBAG (RotMG-like looter).
##
## Port of the NUMBERS and rules from the prior Phaser design
## (`src/game/bags.ts` in the breadth prototype): ladder low -> high is
## brown, pink, purple, blue, white. Brown/pink are public (anyone nearby
## can loot); purple and up are soulbound (killer only). Blue is the
## potion bag (a single draught, still soulbound). White is the rare bag
## with the longest ground life. Despawn times rise strictly with rank so
## a better bag is never punished with a shorter pickup window.
##
## Pure logic: no nodes, no scene wiring.

const ORDER: Array[String] = ["brown", "pink", "purple", "blue", "white"]

const TOP_RANK: int = 4

# Ground-sprite tints, 0xRRGGBB.
const COLORS := {
	"brown": 0x8A5A2B,
	"pink": 0xFF7AB3,
	"purple": 0xA55AFF,
	"blue": 0x3FA9FF,
	"white": 0xF5F2FF,
}

# Rank per tier: 0 (common) .. 4 (rarest).
const RANKS := {
	"brown": 0,
	"pink": 1,
	"purple": 2,
	"blue": 3,
	"white": 4,
}

# Seconds a bag waits on the ground before fading. Strictly rising.
const DESPAWN_SEC := {
	"brown": 60.0,
	"pink": 120.0,
	"purple": 200.0,
	"blue": 260.0,
	"white": 340.0,
}


static func is_valid_tier(tier: String) -> bool:
	return RANKS.has(tier)


## True for the public bags (brown, pink): anyone can loot.
static func is_public_bag(tier: String) -> bool:
	return not is_soulbound(tier)


## True once purple-or-better: only the killer may loot.
static func is_soulbound(tier: String) -> bool:
	return int(RANKS[tier]) >= int(RANKS["purple"])


## May this diver loot the bag? Public bags are free for all; soulbound
## bags (purple and up) open only for the killer.
static func can_loot(tier: String, is_killer: bool) -> bool:
	if is_killer:
		return true
	return is_public_bag(tier)


## Compare two tiers by rank: negative if a < b, 0 if equal, positive.
static func compare_rank(a: String, b: String) -> int:
	return int(RANKS[a]) - int(RANKS[b])


## Ground-sprite tint as a 0xRRGGBB integer.
static func tier_color_hex(tier: String) -> int:
	return int(COLORS[tier])


## Ground-sprite tint as a Color.
static func tier_color(tier: String) -> Color:
	return Color.html("%06X" % tier_color_hex(tier))


## Despawn window in seconds.
static func despawn_sec(tier: String) -> float:
	return float(DESPAWN_SEC[tier])


## Despawn window in milliseconds (frame-clock friendly).
static func despawn_msec(tier: String) -> int:
	return int(despawn_sec(tier) * 1000.0)
