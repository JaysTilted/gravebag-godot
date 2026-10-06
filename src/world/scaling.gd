class_name GravebagScaling
extends RefCounted
## South-to-north difficulty scaffold (design/game-brief.md: leave with the bag).
## Depth 0.0 is the safe south edge, 1.0 the hard north edge.
## Pure functions only: no RNG, no nodes, no I/O. Safe to unit-test headless.
## NOTE (scaffold): the table is stub tuning, not data-driven yet; it moves to
## config when the difficulty system graduates from scaffold.

## World Y of the easy (south) and hard (north) edges. Must match realm bounds.
const SOUTH_Y := 2048.0
const NORTH_Y := 0.0

## South -> north bands. hp/dmg rise northward; each weights row sums to 1.0.
const BANDS: Array = [
	{"name": "south_fields", "min_depth": 0.0, "max_depth": 0.25,
		"hp_mult": 1.0, "dmg_mult": 1.0,
		"weights": {"crawler": 0.70, "spitter": 0.25, "brute": 0.05, "warden": 0.0}},
	{"name": "midlands", "min_depth": 0.25, "max_depth": 0.5,
		"hp_mult": 1.8, "dmg_mult": 1.4,
		"weights": {"crawler": 0.45, "spitter": 0.35, "brute": 0.15, "warden": 0.05}},
	{"name": "highlands", "min_depth": 0.5, "max_depth": 0.75,
		"hp_mult": 2.8, "dmg_mult": 1.9,
		"weights": {"crawler": 0.25, "spitter": 0.35, "brute": 0.30, "warden": 0.10}},
	{"name": "north_gate", "min_depth": 0.75, "max_depth": 1.01,
		"hp_mult": 4.2, "dmg_mult": 2.6,
		"weights": {"crawler": 0.10, "spitter": 0.30, "brute": 0.40, "warden": 0.20}},
]


## Depth (0.0 south -> 1.0 north) for a world Y. Clamped past the edges.
## Example: `GravebagScaling.depth_from_y(enemy.global_position.y)`
static func depth_from_y(y: float) -> float:
	var span := SOUTH_Y - NORTH_Y
	return clampf((SOUTH_Y - y) / span, 0.0, 1.0)


## Band index for a depth in 0.0..1.0 (clamped). Rises northward.
static func band_index_for_depth(depth: float) -> int:
	var d := clampf(depth, 0.0, 1.0)
	for i in BANDS.size():
		var band: Dictionary = BANDS[i]
		if d < float(band["max_depth"]):
			return i
	return BANDS.size() - 1


## Scalar difficulty for a depth. Continuous and strictly rising south->north.
static func difficulty_for_depth(depth: float) -> float:
	return 1.0 + clampf(depth, 0.0, 1.0) * 3.0


## Band stat multipliers for a depth: {"hp_mult": float, "dmg_mult": float}.
static func stats_for_depth(depth: float) -> Dictionary:
	var band: Dictionary = BANDS[band_index_for_depth(depth)]
	return {"hp_mult": float(band["hp_mult"]), "dmg_mult": float(band["dmg_mult"])}


## Spawn weights for a depth: {"crawler": w, "spitter": w, "brute": w, ...}.
## Returns a copy; mutating it never touches the table. Sums to 1.0.
static func spawn_weights_for_depth(depth: float) -> Dictionary:
	var band: Dictionary = BANDS[band_index_for_depth(depth)]
	return (band["weights"] as Dictionary).duplicate()
