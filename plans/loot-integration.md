# FSoD loot integration

Adapted 2026-10-06 from https://github.com/ossimc82/fabiano-swagger-of-doom,
commit `6fd20aa` (AGPLv3). Parent owns license/credits packaging.

## Wire the live dive

1. Give each enemy its exact Lowland name; call
   `DropTable.roll_enemy_drops(enemy_name, func(): return randf())` on death.
   All 23 Lowland names and 53 ordered arguments are embedded; `Sand Devil`
   and `Easily Enraged Bunny` intentionally have empty tables.
2. Replace dive.gd `_grade_tier`'s guaranteed `kill` row with these actual
   winning item entries. No wins means no bag. `grade_loot(level, god_tier)`
   keeps its signature but is only an equipment-tier-to-color compatibility
   adapter; killer level never boosts FSoD loot. The embedded catalog covers
   Lowland only (42 items); unsupported equipment tiers have no candidates.
3. Call `DropTable.make_bags(wins)`; spawn one marker per returned bag,
   retain `items` and `owner_id`, and transfer actual items on pickup.
   Bag capacity is 8, lifetime 30s, color is highest XML BagType in each chunk.
   Lowland equipment is public pink; health/magic potions are public brown,
   NOT blue. Color does not establish ownership. Legacy `can_loot(tier, killer)`
   is retained for compatibility only; use the bag's owner_id for real access.
4. On pickup, apply `entry.item.stats` as fixed equipment bonuses and use
   `entry.item.effects` for potions: HP Heal 100, MP Magic 100. The current
   dive heals/restores 50 and awards XP for picking up color-only markers;
   those are GRAVEBAG adapters, not FSoD loot rules.
5. For weapon firing, use the item's `damage_ranges` and
   `LootGrading.roll_projectile_damage(name, next_unsigned_random_integer)`.
   FSoD bounds are minimum-inclusive / maximum-exclusive (equal bounds fixed).
   This helper preserves modulo range semantics, not FSoD's seeded generator.
   Combat owns Attack scaling and projectile implementation.
6. HUD currently shows five colors. Add egg/cyan/orange when those drops are
   introduced; BagTiers now exposes upstream BagType 0..7 and object IDs.
   GRAVEBAG colors remain presentation, not claimed source RGB values.

## Source facts versus absent data

- Lowland uses the active `LootDefs.cs` / `Loots.cs`, not the duplicate legacy
  `Loot.cs` / `LootDef.cs` / `LootBehavior.cs` (the latter has 60s bags).
- `TierLoot(tier,type,chance)` does NOT roll once then choose one item.
  `Populate` divides chance by the matching XML candidate count and `Handle`
  rolls every candidate independently. Multiple items from one tier can win.
- Lowland has no damage-threshold wrappers, loot states, stat potions, or eggs.
  Its rolls are shared and its 42 candidate definitions are not soulbound.
- No randomized weapon/armor/ring affixes or equipment rarity distribution
  exist in the inspected source. `Descriptors.cs` reads fixed `StatsBoost`
  from XML. `stat_roll_ranges` returns [bonus,bonus]; it does not invent RNG.
  Egg rarity names/chances (Common .1, Uncommon .05, Rare .01, Legendary .001)
  and stat-potion IDs are retained as source constants, not added Lowland loot.
- The requested `wServer/db` does not exist; the actual database directory is
  `db`. `db/rotmgprod.sql` has pet rarity, not equipment-stat roll tables.
- Legacy APIs consumed by dive.gd remain callable: Entry(key,chance,color),
  grade_loot(level,tier), roll_drops(rand,table), best_bag_for_drops(drops),
  tier_color(color), despawn_sec(color). No live DISPLAY :1 window restarted.

## Verification

`godot --headless --path . -s res://src/systems/selftest.gd` validates exact
Lowland numbers, all candidate sets, XML bonuses/damage/potions, independent
candidate probabilities, bag chunking/ownership/lifetime, and existing XP/graves.
`bash scripts/verify.sh --fast` is the integration gate.
