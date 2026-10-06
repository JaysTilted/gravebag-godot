extends RefCounted
class_name BagTiers
## Adapted 2026-10-06 from FSoD (AGPLv3), commit 6fd20aa:
## https://github.com/ossimc82/fabiano-swagger-of-doom
## wServer/logic/loot/Loots.cs; db/data/dat1.xml.
## Color hex values are GRAVEBAG presentation, not upstream numeric data.
## FSoD Loots.cs.ShowBag: highest XML BagType wins; 8 items per bag,
## every bag lives 30 seconds. Ownership belongs to the rolled loot,
## not its color (even a brown bag can have an owner).

const ORDER: Array[String] = ["brown", "pink", "purple", "egg", "cyan", "blue", "white", "orange"]
const TOP_RANK: int = 7
const CAPACITY: int = 8
const OBJECT_TYPES := [0x500, 0x506, 0x503, 0x508, 0x509, 0x50b, 0x50c, 0xfff]
const COLORS := {
	"brown": 0x8A5A2B, "pink": 0xFF7AB3, "purple": 0xA55AFF,
	"egg": 0xF5DEB3, "cyan": 0x00FFFF, "blue": 0x3FA9FF,
	"white": 0xF5F2FF, "orange": 0xFF8A1A,
}
const RANKS := {"brown": 0, "pink": 1, "purple": 2, "egg": 3, "cyan": 4, "blue": 5, "white": 6, "orange": 7}
const DESPAWN_SEC := {"brown": 30.0, "pink": 30.0, "purple": 30.0, "egg": 30.0, "cyan": 30.0, "blue": 30.0, "white": 30.0, "orange": 30.0}


static func for_bag_type(bag_type: int) -> String:
	return ORDER[bag_type] if bag_type >= 0 and bag_type < ORDER.size() else "brown"


static func object_type(tier: String) -> int:
	return int(OBJECT_TYPES[int(RANKS.get(tier, 0))])


static func is_valid_tier(tier: String) -> bool:
	return RANKS.has(tier)


## Legacy color-based API for existing callers. Real FSoD bag ownership
## must come from DropTable.make_bags().owner_id, independent of color.
static func is_public_bag(tier: String) -> bool:
	return not is_soulbound(tier)


static func is_soulbound(tier: String) -> bool:
	return int(RANKS.get(tier, 0)) >= int(RANKS["purple"])


static func can_loot(tier: String, is_killer: bool) -> bool:
	return is_killer or is_public_bag(tier)


static func compare_rank(a: String, b: String) -> int:
	return int(RANKS.get(a, 0)) - int(RANKS.get(b, 0))


static func tier_color_hex(tier: String) -> int:
	return int(COLORS.get(tier, COLORS.brown))


static func tier_color(tier: String) -> Color:
	return Color.html("%06X" % tier_color_hex(tier))


static func despawn_sec(tier: String) -> float:
	return float(DESPAWN_SEC.get(tier, 30.0))


static func despawn_msec(tier: String) -> int:
	return int(despawn_sec(tier) * 1000.0)
