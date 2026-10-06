class_name GravebagRealm
extends Node2D
## GRAVEBAG realm ground + dressing (design/game-brief.md: one moonlit realm).
## Code-drawn tile grid: grass-base palette with 4 value variants, scattered
## detail (flowers/pebbles/grass tufts), a narrowed walkable trail cross with
## edge trim, and seeded-RNG props (tree / rock / glowing mushroom) kept clear
## of spawn/exit lanes. No wiring: gameplay systems live elsewhere; this draws
## ground/props and owns bounds math. Trees and large rocks also get simple
## StaticBody2D blockers (child nodes, spawned in _ready); everything else is
## visual-only with no collision.
## NOTE (scaffold): colors and tile size are stub tuning, not data-driven yet;
## they move to config when the realm system graduates from scaffold.

## Playable world bounds in world units. South edge (high y) is easy ground.
const WORLD_BOUNDS: Rect2 = Rect2(0.0, 0.0, 2048.0, 2048.0)
## Ground tile edge length in world units.
const TILE_SIZE: float = 64.0

## Deterministic prop layout seed: same realm on every run, no RNG bleed into
## gameplay (gameplay randf sequence is untouched; layout uses a local RNG).
const PROP_SEED: int = 20261006
## Accepted props to place (attempts run higher; lane rejects are skipped).
const PROP_COUNT: int = 84
## Walkable trail band width + darker edge trim on each side (world units).
## Total dressed width (52) stays inside one 64px tile: grass peeks at the tile
## edges so the cross reads as a trail, never a wall/slab.
const TRAIL_WIDTH: float = 40.0
const TRAIL_TRIM: float = 6.0
## Prop keep-clear half-width around the trail center lines (band + margin).
const TRAIL_CLEAR: float = 56.0
## Spawn/exit keep-clear discs: player spawn, portal + enemy ring, nexus hub.
const KEEP_SPAWN := Vector2(1024.0, 1100.0)
const KEEP_SPAWN_R := 210.0
const KEEP_PORTAL := Vector2(1024.0, 640.0)
const KEEP_PORTAL_R := 240.0
const KEEP_NEXUS := Vector2(1024.0, 1800.0)
const KEEP_NEXUS_R := 250.0
## Inside-bounds margin for prop centers.
const PROP_MARGIN := 80.0

## Prop kinds. i % 3 assignment keeps the mix guaranteed.
const PROP_TREE := 0
const PROP_ROCK := 1
const PROP_SHROOM := 2

## Moonlit grass-base palette: 4 close value variants (RotMG meadow read).
const _GRASS_A := Color(0.24, 0.43, 0.20)
const _GRASS_B := Color(0.27, 0.48, 0.22)
const _GRASS_C := Color(0.20, 0.37, 0.18)
const _GRASS_D := Color(0.31, 0.44, 0.23)
## Sandy trail + darker edge trim + inset cobble speckle.
const _TRAIL_COLOR := Color(0.58, 0.48, 0.30)
const _TRAIL_TRIM := Color(0.36, 0.28, 0.16)
const _TRAIL_COBBLE := Color(0.47, 0.38, 0.24)
## Chunky-outline dark shared by all props/details.
const _INK := Color(0.07, 0.08, 0.06)
const _SHADOW := Color(0.0, 0.0, 0.0, 0.25)
## Tree: trunk + two-tone canopy.
const _TRUNK := Color(0.35, 0.24, 0.14)
const _LEAF := Color(0.13, 0.35, 0.14)
const _LEAF_HI := Color(0.25, 0.52, 0.22)
## Rock: three-tone gray.
const _ROCK := Color(0.45, 0.46, 0.50)
const _ROCK_DK := Color(0.32, 0.33, 0.37)
const _ROCK_HI := Color(0.62, 0.63, 0.68)
## Glowing mushroom: pale stem, teal cap, cyan halo.
const _STEM := Color(0.86, 0.82, 0.70)
const _CAP := Color(0.30, 0.70, 0.82)
const _CAP_HI := Color(0.55, 0.90, 0.95)
const _GLOW := Color(0.35, 0.85, 0.95, 0.16)
## Ground detail accents.
const _PEBBLE := Color(0.55, 0.56, 0.58)
const _TUFT := Color(0.33, 0.55, 0.25)
const _TUFT_DK := Color(0.15, 0.30, 0.13)
const _EDGE_COLOR := Color(0.45, 0.38, 0.22)


## Clamps a world position into WORLD_BOUNDS. Pure math, safe to call anywhere.
## Example: `GravebagRealm.clamp_to_bounds(player.global_position)`
static func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, WORLD_BOUNDS.position.x, WORLD_BOUNDS.position.x + WORLD_BOUNDS.size.x),
		clampf(pos.y, WORLD_BOUNDS.position.y, WORLD_BOUNDS.position.y + WORLD_BOUNDS.size.y)
	)


func _ready() -> void:
	_spawn_blockers()
	queue_redraw()


## Deterministic prop layout shared by _ready (blockers) and _draw (art).
## Local RNG only: never touches the global gameplay randf sequence.
func _prop_layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	var props: Array = []
	var center := WORLD_BOUNDS.position + WORLD_BOUNDS.size * 0.5
	var tries := 0
	while props.size() < PROP_COUNT and tries < PROP_COUNT * 6:
		tries += 1
		var pos := Vector2(
			rng.randf_range(PROP_MARGIN, WORLD_BOUNDS.size.x - PROP_MARGIN),
			rng.randf_range(PROP_MARGIN, WORLD_BOUNDS.size.y - PROP_MARGIN)
		)
		if not _is_clear(pos, center):
			continue
		var kind: int = props.size() % 3
		props.append({
			"kind": kind,
			"pos": pos,
			"s": rng.randf_range(0.85, 1.25),
			"big": rng.randf() < 0.5,
			"spin": rng.randf_range(0.0, TAU),
		})
	return props


static func _is_clear(pos: Vector2, center: Vector2) -> bool:
	if absf(pos.x - center.x) < TRAIL_CLEAR:
		return false
	if absf(pos.y - center.y) < TRAIL_CLEAR:
		return false
	if pos.distance_to(KEEP_SPAWN) < KEEP_SPAWN_R:
		return false
	if pos.distance_to(KEEP_PORTAL) < KEEP_PORTAL_R:
		return false
	if pos.distance_to(KEEP_NEXUS) < KEEP_NEXUS_R:
		return false
	return true


## Simple StaticBody2D blockers for trees + large rocks (player bumps into
## them; enemies drift as ghosts per combat/enemy.gd mask 0). Default layer 1
## collides with the default CharacterBody2D player mask. Visual-only props
## (mushrooms, small rocks) get no body.
func _spawn_blockers() -> void:
	var i := 0
	for prop in _prop_layout():
		var kind: int = int(prop["kind"])
		var blocks := kind == PROP_TREE or (kind == PROP_ROCK and bool(prop["big"]))
		if not blocks:
			continue
		var s: float = float(prop["s"])
		var body := StaticBody2D.new()
		body.name = "PropBlocker_%d" % i
		body.position = prop["pos"]
		var shape_node := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 15.0 * s if kind == PROP_TREE else 16.0 * s
		shape_node.shape = circle
		body.add_child(shape_node)
		add_child(body)
		i += 1


func _draw() -> void:
	var cols := int(WORLD_BOUNDS.size.x / TILE_SIZE)
	var rows := int(WORLD_BOUNDS.size.y / TILE_SIZE)
	var mid := cols / 2
	for cy in rows:
		for cx in cols:
			_draw_tile(cx, cy, mid)
	draw_rect(WORLD_BOUNDS, _EDGE_COLOR, false, 2.0)
	_draw_props()


func _draw_tile(cx: int, cy: int, mid: int) -> void:
	var on_trail := cx == mid or cy == mid
	var h := absi(cx * 73856093 ^ cy * 19349663)
	var base := _GRASS_A
	match h % 4:
		1:
			base = _GRASS_B
		2:
			base = _GRASS_C
		3:
			base = _GRASS_D
	var cell := Rect2(
		WORLD_BOUNDS.position + Vector2(cx, cy) * TILE_SIZE,
		Vector2(TILE_SIZE, TILE_SIZE)
	)
	draw_rect(cell, base)
	if on_trail:
		_draw_trail_band(cell, cx == mid, cy == mid, h)
	else:
		_draw_detail(cell, h)


## Narrow sand band + edge trim centered in the tile (walkable trail read).
## Trail tiles skip grass detail; cobble speckle dresses the sand instead.
func _draw_trail_band(cell: Rect2, vertical: bool, horizontal: bool, h: int) -> void:
	var half := (TRAIL_WIDTH + TRAIL_TRIM * 2.0) * 0.5
	var c := cell.position + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	if vertical:
		draw_rect(Rect2(cell.position.x + 32.0 - half, cell.position.y, half * 2.0, TILE_SIZE), _TRAIL_TRIM)
		draw_rect(Rect2(cell.position.x + 32.0 - TRAIL_WIDTH * 0.5, cell.position.y, TRAIL_WIDTH, TILE_SIZE), _TRAIL_COLOR)
	if horizontal:
		draw_rect(Rect2(cell.position.x, cell.position.y + 32.0 - half, TILE_SIZE, half * 2.0), _TRAIL_TRIM)
		draw_rect(Rect2(cell.position.x, cell.position.y + 32.0 - TRAIL_WIDTH * 0.5, TILE_SIZE, TRAIL_WIDTH), _TRAIL_COLOR)
	# Cobble speckle pinned inside the sand band.
	for k in 2:
		var ox := float((h >> (4 + k * 6)) % int(TRAIL_WIDTH - 10.0)) - (TRAIL_WIDTH - 10.0) * 0.5
		var oy := float((h >> (7 + k * 6)) % 48 + 8)
		var p := c + (Vector2(ox, oy - 32.0) if vertical else Vector2(oy - 32.0, ox))
		draw_circle(p, 3.0, _TRAIL_COBBLE)


## One scattered detail per grass tile: flower, pebbles, or grass tuft.
func _draw_detail(cell: Rect2, h: int) -> void:
	var px := cell.position.x + float((h >> 4) % 48 + 8)
	var py := cell.position.y + float((h >> 10) % 48 + 8)
	var p := Vector2(px, py)
	match h % 5:
		0:
			_draw_flower(p, h)
		1:
			_draw_pebbles(p, h)
		2, 3:
			_draw_tuft(p)
		_:
			pass


func _draw_flower(p: Vector2, h: int) -> void:
	var petal := Color(1.0, 0.85, 0.30)
	match (h >> 8) % 3:
		1:
			petal = Color(1.0, 1.0, 1.0)
		2:
			petal = Color(1.0, 0.55, 0.70)
	draw_line(p, p + Vector2(0, -7), _TUFT_DK, 2.0)
	draw_circle(p + Vector2(0, -8), 4.5, _INK)
	draw_circle(p + Vector2(0, -8), 3.0, petal)
	draw_circle(p + Vector2(0, -8), 1.2, Color(1.0, 0.95, 0.60))


func _draw_pebbles(p: Vector2, h: int) -> void:
	for k in 3:
		var off := Vector2(float((h >> (5 + k * 4)) % 14 - 7), float((h >> (7 + k * 4)) % 12 - 6))
		draw_circle(p + off, 3.2, _INK)
		draw_circle(p + off, 2.2, _PEBBLE)


func _draw_tuft(p: Vector2) -> void:
	for dx in [-4.0, 0.0, 4.0]:
		var tip := p + Vector2(dx, -9.0 - absf(dx) * 0.4)
		draw_line(p + Vector2(dx * 0.4, 0), tip, _TUFT_DK, 3.0)
		draw_line(p + Vector2(dx * 0.4, 0), tip, _TUFT, 1.5)


func _draw_props() -> void:
	for prop in _prop_layout():
		var kind: int = int(prop["kind"])
		var pos: Vector2 = prop["pos"]
		var s: float = float(prop["s"])
		if kind == PROP_TREE:
			_draw_tree(pos, s)
		elif kind == PROP_ROCK:
			_draw_rock(pos, s, bool(prop["big"]), float(prop["spin"]))
		else:
			_draw_shroom(pos, s)


## Chunky pine: ground blob, outlined trunk, two-tone outlined canopy.
func _draw_tree(pos: Vector2, s: float) -> void:
	draw_circle(pos + Vector2(0, 12) * s, 16.0 * s, _SHADOW)
	var trunk := Rect2(pos + Vector2(-3.5, -2) * s, Vector2(7, 16) * s)
	draw_rect(trunk.grow(2.0 * s), _INK)
	draw_rect(trunk, _TRUNK)
	draw_circle(pos + Vector2(0, -14) * s, 17.0 * s, _INK)
	draw_circle(pos + Vector2(0, -14) * s, 15.0 * s, _LEAF)
	draw_circle(pos + Vector2(-6, -20) * s, 9.0 * s, _INK)
	draw_circle(pos + Vector2(-6, -20) * s, 7.0 * s, _LEAF)
	draw_circle(pos + Vector2(-5, -19) * s, 3.5 * s, _LEAF_HI)
	draw_circle(pos + Vector2(6, -10) * s, 2.5 * s, _LEAF_HI)


## Chunky boulder: outlined irregular poly, dark facet, pale glint.
## Small rocks are pebble clusters (visual-only); big rocks get blockers.
func _draw_rock(pos: Vector2, s: float, big: bool, spin: float) -> void:
	if not big:
		for k in 3:
			var off := Vector2(cos(spin + k * 2.1), sin(spin + k * 2.1)) * 7.0 * s
			draw_circle(pos + off, 4.5 * s, _INK)
			draw_circle(pos + off, 3.0 * s, _ROCK)
		return
	var pts := PackedVector2Array([
		pos + Vector2(-16, 8) * s,
		pos + Vector2(-10, -8) * s,
		pos + Vector2(2, -13) * s,
		pos + Vector2(13, -4) * s,
		pos + Vector2(15, 8) * s,
		pos + Vector2(4, 12) * s,
		pos + Vector2(-8, 12) * s,
	])
	draw_circle(pos + Vector2(0, 10) * s, 17.0 * s, _SHADOW)
	draw_colored_polygon(pts, _ROCK)
	pts.append(pts[0])
	draw_polyline(pts, _INK, 3.0 * s, true)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-10, 8) * s,
		pos + Vector2(-10, -8) * s,
		pos + Vector2(2, -13) * s,
		pos + Vector2(2, 8) * s,
	]), _ROCK_DK)
	draw_circle(pos + Vector2(7, -5) * s, 3.0 * s, _ROCK_HI)


## Glowing mushroom: halo, outlined stem + cap, bright rim, pale spots.
## Visual-only by design (walk over the glow, no collision).
func _draw_shroom(pos: Vector2, s: float) -> void:
	draw_circle(pos, 20.0 * s, _GLOW)
	draw_circle(pos, 12.0 * s, Color(_GLOW, 0.35))
	draw_circle(pos + Vector2(0, 4) * s, 7.0 * s, _SHADOW)
	var stem := Rect2(pos + Vector2(-4, -4) * s, Vector2(8, 12) * s)
	draw_rect(stem.grow(1.5 * s), _INK)
	draw_rect(stem, _STEM)
	var cap_c := pos + Vector2(0, -7) * s
	draw_circle(cap_c, 11.0 * s, _INK)
	draw_circle(cap_c, 9.0 * s, _CAP)
	draw_arc(cap_c + Vector2(0, 1) * s, 6.5 * s, PI * 1.15, PI * 1.85, 12, _CAP_HI, 2.5 * s, true)
	draw_circle(cap_c + Vector2(-4, -2) * s, 1.8 * s, Color.WHITE)
	draw_circle(cap_c + Vector2(3, -4) * s, 1.4 * s, Color.WHITE)
