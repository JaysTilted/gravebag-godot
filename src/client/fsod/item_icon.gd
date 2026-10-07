# SPDX-License-Identifier: AGPL-3.0-only
# Hand-authored 8x8 silhouettes. Not video sprites and not source textures.
# Integer scale keeps the pixels hard. Tint is a token, not a copied portrait.
extends Control

const GLYPHS := {
	"blade": ["......X.", ".....XX.", "....XX..", "...XX...", ".XTX....", "..TX....", ".X..X...", "X......."],
	"staff": ["....TT..", "...TXTT.", "....TT..", "....X...", "...X....", "..X.....", ".X......", "X......."],
	"potion": ["...TT...", "...XX...", "...XX...", "..XTTX..", ".XTTTTX.", ".XTTTTX.", ".XTTTTX.", "..XXXX.."],
	"book": [".XXXXXX.", ".XTTTTX.", ".XTXXTX.", ".XTTTTX.", ".XTXXTX.", ".XTTTTX.", ".XXXXXX.", "..XXXXX."],
	"armor": ["..X..X..", ".XXTTXX.", "XXTTTTXX", "X.XTTX.X", "..XTTX..", "..XTTX..", "..XTTX..", "..XXXX.."],
	"ring": ["...TT...", "..TXTT..", "..X..X..", ".X....X.", ".X....X.", "..X..X..", "...XX...", "........"],
	"pouch": ["..TTTT..", "...XX...", "..XTTX..", ".XTTTTX.", ".XTTXTX.", ".XTTTTX.", ".XTTTTX.", "..XXXX.."],
}

var glyph: String = ""
var tint: Color = Color("efcf7a")
var ink: Color = Color("1a1a1a")
var paper: Color = Color("d4d4d4")
var occupied: bool = false

static func glyph_for(descriptor: Dictionary) -> String:
	if descriptor.get("Potion", false) == true:
		return "potion"
	var type: int = int(descriptor.get("SlotType", 0))
	if type == 9:
		return "ring"
	if type in [6, 7, 14]:
		return "armor"
	if type in [4, 5, 11, 12, 13, 15, 16, 18, 19, 20, 21, 22, 23]:
		return "book"
	if type in [8, 17]:
		return "staff"
	if type in [1, 2, 3]:
		return "blade"
	return "pouch"

func present(glyph_name: String, color: Color, ink_color: Color, paper_color: Color, is_occupied: bool) -> void:
	var next := glyph_name if GLYPHS.has(glyph_name) else "pouch"
	if glyph == next and tint == color and ink == ink_color and paper == paper_color and occupied == is_occupied:
		return
	glyph = next
	tint = color
	ink = ink_color
	paper = paper_color
	occupied = is_occupied
	queue_redraw()

func _draw() -> void:
	if not occupied or size.x < 8.0 or size.y < 8.0:
		return
	var rows: Array = GLYPHS[glyph]
	var scale := maxi(1, int(floorf(minf(size.x, size.y) / 8.0)))
	var origin := ((size - Vector2(8, 8) * scale) * 0.5).floor()
	for y in 8:
		for x in 8:
			var pixel: String = rows[y][x]
			if pixel == ".":
				continue
			var cell := Rect2(origin + Vector2(x, y) * scale, Vector2(scale, scale))
			draw_rect(cell.grow(1.0), ink)
			draw_rect(cell, paper if pixel == "X" else tint)
