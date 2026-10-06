class_name GravebagRealm
extends Node2D
## GRAVEBAG realm ground scaffold (design/game-brief.md: one moonlit realm).
## Code-drawn tile grid with 3 ground variants + a path cross. No wiring:
## gameplay systems live elsewhere; this draws ground and owns bounds math.
## NOTE (scaffold): colors and tile size are stub tuning, not data-driven yet;
## they move to config when the realm system graduates from scaffold.

## Playable world bounds in world units. South edge (high y) is easy ground.
const WORLD_BOUNDS: Rect2 = Rect2(0.0, 0.0, 2048.0, 2048.0)
## Ground tile edge length in world units.
const TILE_SIZE: float = 64.0

const _GROUND_A := Color(0.10, 0.14, 0.20)
const _GROUND_B := Color(0.12, 0.16, 0.23)
const _GROUND_C := Color(0.09, 0.12, 0.18)
const _PATH_COLOR := Color(0.23, 0.20, 0.15)
const _EDGE_COLOR := Color(0.45, 0.38, 0.22)


## Clamps a world position into WORLD_BOUNDS. Pure math, safe to call anywhere.
## Example: `GravebagRealm.clamp_to_bounds(player.global_position)`
static func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, WORLD_BOUNDS.position.x, WORLD_BOUNDS.position.x + WORLD_BOUNDS.size.x),
		clampf(pos.y, WORLD_BOUNDS.position.y, WORLD_BOUNDS.position.y + WORLD_BOUNDS.size.y)
	)


func _draw() -> void:
	var cols := int(WORLD_BOUNDS.size.x / TILE_SIZE)
	var rows := int(WORLD_BOUNDS.size.y / TILE_SIZE)
	for cy in rows:
		for cx in cols:
			var variant := (cx * 7 + cy * 13) % 3
			var color := _GROUND_A
			if variant == 1:
				color = _GROUND_B
			elif variant == 2:
				color = _GROUND_C
			# Path cross through the middle, in tile space.
			if cx == cols / 2 or cy == rows / 2:
				color = _PATH_COLOR
			var cell := Rect2(
				WORLD_BOUNDS.position + Vector2(cx, cy) * TILE_SIZE,
				Vector2(TILE_SIZE, TILE_SIZE)
			)
			draw_rect(cell, color)
	draw_rect(WORLD_BOUNDS, _EDGE_COLOR, false, 2.0)
