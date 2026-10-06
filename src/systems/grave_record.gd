extends RefCounted
class_name GraveRecord
## Grave marker for GRAVEBAG permadeath: where the diver died and what
## they left behind. Reclaim-or-lose: one trip back picks the grave up
## (reclaim), and anything left behind is gone (abandon).
##
## Pure logic: no nodes, no scene wiring. Position is a plain Vector2
## value (not a node); items are caller-owned entries (e.g. Strings).

var position: Vector2 = Vector2.ZERO
var items: Array = []
## True once reclaim() has run: the grave was picked up, not lost.
var reclaimed: bool = false


func _init(p_position: Vector2 = Vector2.ZERO, contents: Array = []) -> void:
	position = p_position
	items = contents.duplicate()


func is_empty() -> bool:
	return items.is_empty()


## Pick the grave up: returns its items and clears the record.
func reclaim() -> Array:
	var got: Array = items.duplicate()
	items.clear()
	reclaimed = true
	return got


## Walk away: the grave and everything in it is lost.
func abandon() -> void:
	items.clear()
