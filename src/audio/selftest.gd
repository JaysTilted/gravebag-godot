extends SceneTree
## GRAVEBAG audio selftest — runs headless, no autoloads or scene needed.
##
## Usage (from the project root):
##   godot --headless --path . -s res://src/audio/selftest.gd
##
## Asserts every GraveSfx sound generates non-empty 8-bit sample data at the
## expected mix rate, stays under 0.5 s, and is byte-distinct from the other
## sounds. Prints SELFTEST PASS and quits 0; prints SELFTEST FAIL and quits 1.

const SOUND_NAMES: Array[String] = [
	"shoot", "enemy_shoot", "hit", "kill", "pickup",
	"potion", "levelup", "death", "extract", "ui_click",
]

var _failures := 0
var _sfx: GDScript


func _initialize() -> void:
	_sfx = load("res://src/audio/sfx.gd") as GDScript
	if _sfx == null:
		printerr("SELFTEST FAIL: could not load res://src/audio/sfx.gd")
		quit(1)
		return

	var seen: Dictionary = {}
	for sound_name in SOUND_NAMES:
		var stream: AudioStreamWAV = _sfx.call(sound_name)
		if stream == null:
			printerr("SELFTEST FAIL: ", sound_name, " returned null")
			_failures += 1
			continue
		if stream.format != AudioStreamWAV.FORMAT_8_BITS:
			printerr("SELFTEST FAIL: ", sound_name, " is not 8-bit")
			_failures += 1
		if stream.mix_rate != _sfx.MIX_RATE:
			printerr("SELFTEST FAIL: ", sound_name, " mix_rate=", stream.mix_rate)
			_failures += 1
		if stream.stereo:
			printerr("SELFTEST FAIL: ", sound_name, " is stereo, expected mono")
			_failures += 1
		if stream.data.is_empty():
			printerr("SELFTEST FAIL: ", sound_name, " has empty sample data")
			_failures += 1
			continue
		var duration := float(stream.data.size()) / float(stream.mix_rate)
		if duration <= 0.0 or duration >= 0.5:
			printerr("SELFTEST FAIL: ", sound_name, " duration=", duration)
			_failures += 1
		var fingerprint := str(stream.data.size()) + ":" + str(_hash(stream.data))
		if seen.has(fingerprint):
			printerr("SELFTEST FAIL: ", sound_name, " duplicates ", seen[fingerprint])
			_failures += 1
		else:
			seen[fingerprint] = sound_name
		print("ok: ", sound_name, " frames=", stream.data.size(), " rate=", stream.mix_rate)


func _process(_delta: float) -> bool:
	# Pool check runs on the first frame: a node added during _initialize()
	# is not guaranteed _ready() yet, but it is by first _process().
	var player_script := load("res://src/audio/sfx_player.gd") as GDScript
	if player_script == null or not player_script.can_instantiate():
		printerr("SELFTEST FAIL: sfx_player.gd does not load")
		_failures += 1
	else:
		var player := player_script.new() as Node
		root.add_child(player)
		if player.get_child_count() != 8:
			printerr("SELFTEST FAIL: pool size=", player.get_child_count())
			_failures += 1
		elif not player.has_method("play"):
			printerr("SELFTEST FAIL: pooler has no play()")
			_failures += 1
		else:
			player.call("play", _sfx.call("shoot"))
			print("ok: sfx_player pool=8 play() voiced")
		root.remove_child(player)
		player.queue_free()

	if _failures > 0:
		printerr("SELFTEST FAIL: ", _failures, " failure(s)")
		quit(1)
	else:
		print("SELFTEST PASS")
		quit(0)
	return true


func _hash(data: PackedByteArray) -> int:
	# FNV-1a 32-bit over the raw bytes — cheap distinctness check.
	var h := 2166136261
	for b in data:
		h = (h ^ b) * 16777619
		h = h & 0xFFFFFFFF
	return h
