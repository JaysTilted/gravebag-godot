# Complete FSoD descriptor metadata export

This is a data export for the original C# backend / Godot client bridge, not a
GDScript gameplay rewrite. Do not integrate the earlier loot-prototype commit
`c0775d5`; cherry-pick only the descriptor-export commit from this branch.

## Provenance / reproduction

Source: https://github.com/ossimc82/fabiano-swagger-of-doom at
`6fd20aad4a7905b13f25389c68368a942a2b68cb`, AGPLv3; adapted 2026-10-06.
Rules read: `db/data/XmlDatas.cs`, `Descriptors.cs`, `db/Utils.cs`, plus player
initial-stat/level metadata consumers. Artwork, SWF, and source XML files are
NOT copied into the generated tables. Texture nodes are metadata references
for our art remap. Parent owns licensing/credits and the pinned source submodule.

Stdlib-only extraction API:

```sh
python3 scripts/fsod_assets/extract.py
python3 scripts/fsod_assets/extract.py --check
python3 scripts/fsod_assets/extract.py --source /home/jay/fsod-ref/db/data
```

Default source is the canonical `references/fsod/db/data` submodule; initialize
that pinned submodule before regeneration. Output defaults to `src/data/fsod/`.
`--output DIR` supports isolated builds. No timestamps or absolute host paths
enter JSON; four exact XML SHA256 hashes are recorded in `manifest.json`.
The Python API is `export(data_dir, file_order=FILES, auto_ids=None)` followed by
`serialize(table)`. It returns all tables as structured dictionaries.

## Schema / lookup API

All numeric type-map keys are decimal strings; conversion is `str(packet.type)`
(or `str(int_type)` in Godot). Typed descriptors use their exact C# property
names, not view aliases. The parent owns typed-fields-to-view adaptation.

- `objects.json[type] = {type,id,class,source:{file,ordinal},xml}`. Complete raw
  metadata for every server-indexed object. XML is an ordered tree:
  `{tag,attributes,text,tail,children}`. Repeated tags, animation/texture indices,
  client-only fields, stat caps, skin metadata, and unknown fields are retained.
- `object_descriptors.json[type]`: normalized `ObjectDesc` values/defaults.
- `grounds.json[type] = {source,descriptor,xml}`: normalized `TileDesc` plus all
  raw Ground metadata (textures, blend priorities, animation, sink, etc.).
- `items.json[type]`: all `Item` values/defaults, including ordered `StatsBoost`,
  activation/effect data, projectiles, slot/tier/set IDs, bonuses, potion flags,
  feed power, nullable timers, and enum values. `FamilyName`/`RarityName` are
  convenience strings; `Family`/`Rarity` are numeric C# enum values or null.
- `player_classes.json[type]`: class slot types, original starter equipment,
  initial stat values/caps, inclusive XML level-growth ranges, unlock metadata.
  This is descriptor data, not server character creation: C# Database replaces
  the starter Health Potion slot with -1 and grants a potion stack separately.
- `projectiles.json[owner_type]`: ordered `ProjectileDesc[]`, including flags,
  motion parameters, damage ranges, condition effects, and defaults. Array
  ordinal is NOT necessarily `BulletType`; retain both. Actual class=Projectile
  render objects are in `objects.json` with texture metadata.
- `equipment_sets.json[type] = {source,descriptor,xml}`: set-slot item types,
  first skin/size/color/bullet override, ordered stat bonuses, complete raw data.
- `portals.json`, `pets.json`, `pet_skins.json`: source special descriptor maps.
- `indices.json`: `ObjectTypeToId`, `IdToObjectType`, `TileTypeToId`,
  `IdToTileType`. Name lookup keys are casefolded, matching the source's
  case-insensitive IDs for this dataset. Do not infer type IDs from array order.
- `ignored_objects.json.records`: all 23 source-skipped Object records, raw XML
  and reason. They do not exist in the server lookup indices; don't invent them.
- `manifest.json`: revision/hashes, load order, counts, duplicate decisions,
  enums, auto-ID provenance, and unresolved references.

## Exact coverage / representative IDs

3831 indexed objects; 2232 general ObjectDesc; 333 grounds; 1281 items;
14 player classes; 57 portals; 130 pets; 131 pet skins; 6 equipment sets;
1397 owned projectile descriptors (3831 owner keys, including empty arrays).
All requested source Object/Ground/EquipmentSet records are accounted for.
No unresolved projectile target, starter item, or set-piece references.

Wizard `0x030e` / 782: slots `[17,11,14,9,...]`, staff `0xa97`, spell `0xa2e`;
initial HP 100/cap 670, Attack 12/cap 75, HP growth 20..30 inclusive.
Hobbit Mage `0x617` / 1559: HP 200, Defense 2; three projectiles IDs 0,1,2,
all Damage 10, LifetimeMS 340, Speed 50. Grass `0x48` / 72.

## AutoAssign reconciliation (required after backend bootstrap)

`Addition.xml` contains three real objects without type attributes. Do not
invent stable runtime IDs for them. Checked-in output explicitly records
`auto_id_mode="fresh-server-defaults"` and `runtime_auto_ids_supplied=false`;
its 50000/50001/50002 types are the exact fresh `AutoAssign` defaults, not proof
of an existing server's assignments. Both counters and persisted named IDs
must come from that server's `autoId.cfg` once it is available:

```sh
python3 scripts/fsod_assets/extract.py --auto-id-config /explicit/runtime/autoId.cfg
```

Only that explicit file's integer ID/counter settings are read. No automatic
HOME lookup, credentials, other server settings, config writeback, or secret
value output. The exporter rebuilds type maps, aliases, and inserted `ext`
XML type attributes from those IDs; provenance becomes
`auto_id_mode="runtime-autoId.cfg"`, `runtime_auto_ids_supplied=true`.
Alternatively `--auto-id-map ids.json` accepts an explicit structured ID map;
Python callers pass it via `export(..., auto_ids=map)`.
Do not rewrite the original server XML or silently use fresh defaults for
live packet types if the server's assignments differ.

## Source merge/default subtleties (preserved, not repaired)

- XmlDatas enumerates XML files without specifying a sort. This export records
  the deterministic order dat0, dat1, Addition, EquipmentSets. These particular
  files have no cross-file type collisions, so their typed result is unchanged
  by file enumeration order. Three untyped Addition objects retain XML order.
- Within each file: AddObjects, then AddGrounds, then AddSetTypes. Last type/name
  assignment wins. Old aliases and old category dictionary entries are NOT
  purged (unit fixtures cover this). Grey Circle's name resolves to type 101;
  both ground 97 and 101 remain. Classless/PetAbility/PetBehavior objects skip
  indexing; raw ignored data is retained separately.
- C# Single fields are rounded to float32 before JSON serialization. Flags are
  presence tests, not their text/attribute truth value. Tier absent/UT -> -1.
- Ground absent Speed defaults to 0 in TileDesc; Grass has no Speed node.
  This is a source default, not an invented client movement multiplier.
- TileDesc PushY uses the Ground dy-attribute guard rather than Animate's dy.
  We preserve that source behavior; raw Animate attributes remain available.
- ObjectDesc reads SpawnProbability, while Hobbit XML says SpawnProb. Typed
  SpawnProbability is therefore 0; the original raw SpawnProb node is retained.
- Projectile fixed Damage sets min=max; ranged max semantics belong to runtime.
  No randomized equipment affixes or rarity distributions are fabricated.

## Tests / receipt

`node --test tests/fsod-data.test.mjs` invokes nine stdlib Python source-rule
fixtures, validates full table counts and representative IDs, performs two
byte-identical complete regenerations, and tests runtime auto-ID reconciliation.
All scratch directories are removed in finally blocks. With an uninitialized
source submodule, the adapter downloads only the four raw XML files from the
pinned public revision, verifies recorded SHA256, and stages them in /tmp;
it never reads an operator worktree to turn a clean-clone red into green.
No source XML is checked into this export lane; no live Godot was restarted.
