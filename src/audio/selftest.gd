extends SceneTree
## GRAVEBAG audio selftest — runs headless, no autoloads or scene needed.
##
## Usage (from the project root):
##   godot --headless --path . -s res://src/audio/selftest.gd
##
## Asserts every GraveSfx sound generates non-empty 8-bit sample data at the
## expected mix rate, is byte-distinct from the other sounds, and honors the
## mix pass: every sound < 0.5 s except death_sting (< 1.2 s); MIX_DB volumes
## in [-24, 0] dB with shots quiet / hits-kills punchy / UI soft; ±10% pitch
## variance on rapid sounds (shoot/enemy_shoot/hit) and none elsewhere.
## Music asserts: nexus_calm + combat_drive loops are non-empty, > 10 s,
## loop-enabled with 0..size loop points and silence at the seam (seamless),
## byte-distinct from each other, and crossfade_to() switches tracks while
## set_intensity() removes/restores the extra layer.
## Prints SELFTEST PASS and quits 0; prints SELFTEST FAIL and quits 1.

const SOUND_NAMES: Array[String] = [
	"shoot", "enemy_shoot", "hit", "kill", "pickup",
	"potion", "levelup", "death", "death_sting", "extract",
	"ui_click", "fame_tick",
]
const RAPID_SOUNDS: Array[String] = ["shoot", "enemy_shoot", "hit"]

var _failures := 0
var _sfx: GDScript
var _music: GDScript
var _peaks: Dictionary = {}


func _initialize() -> void:
	_sfx = load("res://src/audio/sfx.gd") as GDScript
	if _sfx == null:
		printerr("SELFTEST FAIL: could not load res://src/audio/sfx.gd")
		quit(1)
		return

	_check_mix_constants()
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
		if sound_name == "death_sting":
			if duration <= 0.0 or duration >= float(_sfx.STING_MAX_DURATION):
				printerr("SELFTEST FAIL: death_sting duration=", duration, " (cap 1.2s)")
				_failures += 1
			if duration <= float(_sfx.MAX_DURATION):
				printerr("SELFTEST FAIL: death_sting duration=", duration, " (sting should exceed 0.5s)")
				_failures += 1
		elif duration <= 0.0 or duration >= float(_sfx.MAX_DURATION):
			printerr("SELFTEST FAIL: ", sound_name, " duration=", duration)
			_failures += 1
		_peaks[sound_name] = _peak(stream.data)
		var peak := float(_peaks[sound_name])
		if peak < 0.15 or peak > 0.95:
			printerr("SELFTEST FAIL: ", sound_name, " peak=", peak, " (want 0.15..0.95)")
			_failures += 1
		var fingerprint := str(stream.data.size()) + ":" + str(_hash(stream.data))
		if seen.has(fingerprint):
			printerr("SELFTEST FAIL: ", sound_name, " duplicates ", seen[fingerprint])
			_failures += 1
		else:
			seen[fingerprint] = sound_name
		print("ok: ", sound_name, " frames=", stream.data.size(), " rate=", stream.mix_rate)
	_check_mix_balance()
	_check_pitch_variance()
	_check_music_static()


func _process(_delta: float) -> bool:
	# Pool check runs on the first frame: a node added during _initialize()
	# is not guaranteed _ready() yet, but it is by first _process().
	var player_script := load("res://src/audio/sfx_player.gd") as GDScript
	if player_script == null or not player_script.can_instantiate():
		printerr("SELFTEST FAIL: sfx_player.gd does not load")
		_failures += 1
	else:
		if absf(float(player_script.PITCH_MIN) - 0.9) > 0.0001 or absf(float(player_script.PITCH_MAX) - 1.1) > 0.0001:
			printerr("SELFTEST FAIL: player pitch bounds=", player_script.PITCH_MIN, "..", player_script.PITCH_MAX, " (want 0.9..1.1)")
			_failures += 1
		for sound_name in SOUND_NAMES:
			var bounds: Vector2 = player_script.pitch_bounds_for(sound_name)
			var want_rapid := sound_name in RAPID_SOUNDS
			if want_rapid and (absf(bounds.x - 0.9) > 0.0001 or absf(bounds.y - 1.1) > 0.0001):
				printerr("SELFTEST FAIL: player pitch_bounds_for(", sound_name, ")=", bounds, " (want 0.9..1.1)")
				_failures += 1
			elif not want_rapid and (absf(bounds.x - 1.0) > 0.0001 or absf(bounds.y - 1.0) > 0.0001):
				printerr("SELFTEST FAIL: player pitch_bounds_for(", sound_name, ")=", bounds, " (want 1..1)")
				_failures += 1
			var roll: float = player_script.roll_pitch_for(sound_name)
			if roll < bounds.x - 0.0001 or roll > bounds.y + 0.0001:
				printerr("SELFTEST FAIL: player roll_pitch_for(", sound_name, ")=", roll, " outside ", bounds)
				_failures += 1
		var player := player_script.new() as Node
		root.add_child(player)
		if player.get_child_count() != 8:
			printerr("SELFTEST FAIL: pool size=", player.get_child_count())
			_failures += 1
		elif not player.has_method("play"):
			printerr("SELFTEST FAIL: pooler has no play()")
			_failures += 1
		elif not player.has_method("play_varied"):
			printerr("SELFTEST FAIL: pooler has no play_varied()")
			_failures += 1
		else:
			player.call("play", _sfx.call("shoot"))
			player.call("play_varied", _sfx.call("shoot"), "shoot")
			player.call("play_varied", _sfx.call("pickup"), "pickup")
			print("ok: sfx_player pool=8 play()/play_varied() voiced")
		root.remove_child(player)
		player.queue_free()
	_check_music_player()

	if _failures > 0:
		printerr("SELFTEST FAIL: ", _failures, " failure(s)")
		quit(1)
	else:
		print("SELFTEST PASS")
		quit(0)
	return true


func _check_mix_constants() -> void:
	if absf(float(_sfx.PITCH_VARIANCE) - 0.10) > 0.0001:
		printerr("SELFTEST FAIL: PITCH_VARIANCE=", _sfx.PITCH_VARIANCE, " (want 0.10)")
		_failures += 1
	if absf(float(_sfx.PITCH_MIN) - 0.9) > 0.0001 or absf(float(_sfx.PITCH_MAX) - 1.1) > 0.0001:
		printerr("SELFTEST FAIL: pitch bounds=", _sfx.PITCH_MIN, "..", _sfx.PITCH_MAX, " (want 0.9..1.1)")
		_failures += 1
	for sound_name in SOUND_NAMES:
		if not (_sfx.MIX_DB as Dictionary).has(sound_name):
			printerr("SELFTEST FAIL: MIX_DB missing ", sound_name)
			_failures += 1


func _check_mix_balance() -> void:
	# Volumes in range: every MIX_DB entry within [-24, 0] dB.
	for sound_name in SOUND_NAMES:
		var db := float(_sfx.call("mix_db_for", sound_name))
		if db < -24.0 or db > 0.0:
			printerr("SELFTEST FAIL: MIX_DB[", sound_name, "]=", db, " (want -24..0 dB)")
			_failures += 1
	# Balance: shots quiet, hits/kills punchy, UI soft.
	_check_db_below("shoot", "hit", "shots quiet under hits")
	_check_db_below("shoot", "kill", "shots quiet under kills")
	_check_db_below("enemy_shoot", "hit", "enemy shots quiet under hits")
	_check_db_below("ui_click", "shoot", "UI soft under shots")
	_check_db_below("ui_click", "pickup", "UI soft under pickup")
	_check_db_below("fame_tick", "kill", "fame tick soft under kills")
	_check_db_at_most("shoot", -10.0, "shots quiet")
	_check_db_at_most("enemy_shoot", -10.0, "enemy shots quiet")
	_check_db_at_least("hit", -6.0, "hits punchy")
	_check_db_at_least("kill", -6.0, "kills punchy")
	_check_db_at_most("ui_click", -14.0, "UI soft")
	# Synthesis peaks follow the same hierarchy.
	_check_peak_below("shoot", "hit", "shot peak under hit peak")
	_check_peak_below("enemy_shoot", "kill", "enemy shot peak under kill peak")
	_check_peak_below("ui_click", "kill", "UI peak soft under kill peak")
	# Signature durations: level-up arpeggio present, fame tick short.
	var levelup_dur := _duration_of("levelup")
	if levelup_dur < 0.30 or levelup_dur >= 0.5:
		printerr("SELFTEST FAIL: levelup arpeggio duration=", levelup_dur, " (want 0.30..<0.5)")
		_failures += 1
	var fame_dur := _duration_of("fame_tick")
	if fame_dur <= 0.0 or fame_dur >= 0.2:
		printerr("SELFTEST FAIL: fame_tick duration=", fame_dur, " (want <0.2s)")
		_failures += 1
	print("ok: mix balance shots-quiet/hits-punchy/ui-soft")


func _check_pitch_variance() -> void:
	for sound_name in SOUND_NAMES:
		var bounds: Vector2 = _sfx.call("pitch_range_for", sound_name)
		var want_rapid := sound_name in RAPID_SOUNDS
		if want_rapid and (absf(bounds.x - 0.9) > 0.0001 or absf(bounds.y - 1.1) > 0.0001):
			printerr("SELFTEST FAIL: pitch_range_for(", sound_name, ")=", bounds, " (want 0.9..1.1)")
			_failures += 1
		elif not want_rapid and (absf(bounds.x - 1.0) > 0.0001 or absf(bounds.y - 1.0) > 0.0001):
			printerr("SELFTEST FAIL: pitch_range_for(", sound_name, ")=", bounds, " (want 1..1)")
			_failures += 1
		for i in 20:
			var roll: float = _sfx.call("roll_pitch", sound_name)
			if roll < bounds.x - 0.0001 or roll > bounds.y + 0.0001:
				printerr("SELFTEST FAIL: roll_pitch(", sound_name, ")=", roll, " outside ", bounds)
				_failures += 1
				break
	print("ok: pitch variance rapid=±10% fixed=1.0")


func _check_db_below(quiet: String, loud: String, why: String) -> void:
	var q := float(_sfx.call("mix_db_for", quiet))
	var l := float(_sfx.call("mix_db_for", loud))
	if not q < l:
		printerr("SELFTEST FAIL: MIX_DB[", quiet, "]=", q, " not below [", loud, "]=", l, " (" + why + ")")
		_failures += 1


func _check_db_at_most(sound_name: String, cap: float, why: String) -> void:
	var db := float(_sfx.call("mix_db_for", sound_name))
	if not db <= cap:
		printerr("SELFTEST FAIL: MIX_DB[", sound_name, "]=", db, " above ", cap, " (" + why + ")")
		_failures += 1


func _check_db_at_least(sound_name: String, floor: float, why: String) -> void:
	var db := float(_sfx.call("mix_db_for", sound_name))
	if not db >= floor:
		printerr("SELFTEST FAIL: MIX_DB[", sound_name, "]=", db, " below ", floor, " (" + why + ")")
		_failures += 1


func _check_peak_below(quiet: String, loud: String, why: String) -> void:
	if not _peaks.has(quiet) or not _peaks.has(loud):
		return
	if not float(_peaks[quiet]) < float(_peaks[loud]):
		printerr("SELFTEST FAIL: peak[", quiet, "]=", _peaks[quiet], " not below peak[", loud, "]=", _peaks[loud], " (" + why + ")")
		_failures += 1


func _duration_of(sound_name: String) -> float:
	var stream: AudioStreamWAV = _sfx.call(sound_name)
	return float(stream.data.size()) / float(stream.mix_rate)


func _peak(data: PackedByteArray) -> float:
	var peak := 0.0
	for b in data:
		var v := absf(float(int(b) - 128) / 127.0)
		if v > peak:
			peak = v
	return peak


func _hash(data: PackedByteArray) -> int:
	# FNV-1a 32-bit over the raw bytes — cheap distinctness check.
	var h := 2166136261
	for b in data:
		h = (h ^ b) * 16777619
		h = h & 0xFFFFFFFF
	return h


func _check_music_static() -> void:
	_music = load("res://src/audio/music.gd") as GDScript
	if _music == null:
		printerr("SELFTEST FAIL: could not load res://src/audio/music.gd")
		_failures += 1
		return
	for want in ["nexus_calm", "combat_drive"]:
		if not (want in _music.TRACKS):
			printerr("SELFTEST FAIL: music TRACKS missing ", want)
			_failures += 1
	if int(_music.BARS_PER_LOOP) < 8:
		printerr("SELFTEST FAIL: music BARS_PER_LOOP=", _music.BARS_PER_LOOP, " (want >= 8)")
		_failures += 1
	var bpms := {"nexus_calm": float(_music.CALM_BPM), "combat_drive": float(_music.COMBAT_BPM)}
	var seen: Dictionary = {}
	for track_name in ["nexus_calm", "combat_drive"]:
		var stream: AudioStreamWAV = _music.call("stream_for", track_name)
		if stream == null:
			printerr("SELFTEST FAIL: music ", track_name, " returned null")
			_failures += 1
			continue
		if stream.format != AudioStreamWAV.FORMAT_8_BITS:
			printerr("SELFTEST FAIL: music ", track_name, " is not 8-bit")
			_failures += 1
		if stream.mix_rate != _music.MIX_RATE:
			printerr("SELFTEST FAIL: music ", track_name, " mix_rate=", stream.mix_rate)
			_failures += 1
		if stream.stereo:
			printerr("SELFTEST FAIL: music ", track_name, " is stereo, expected mono")
			_failures += 1
		if stream.data.is_empty():
			printerr("SELFTEST FAIL: music ", track_name, " has empty sample data")
			_failures += 1
			continue
		var duration := float(stream.data.size()) / float(stream.mix_rate)
		if duration <= float(_music.MIN_DURATION):
			printerr("SELFTEST FAIL: music ", track_name, " duration=", duration, " (want >", _music.MIN_DURATION, "s)")
			_failures += 1
		var want_dur := float(_music.BARS_PER_LOOP) * float(_music.BEATS_PER_BAR) * 60.0 / float(bpms[track_name])
		if absf(duration - want_dur) > 0.25:
			printerr("SELFTEST FAIL: music ", track_name, " duration=", duration, " (want ~", want_dur, "s for 8 bars)")
			_failures += 1
		if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			printerr("SELFTEST FAIL: music ", track_name, " loop_mode=", stream.loop_mode, " (want FORWARD)")
			_failures += 1
		if stream.loop_begin != 0 or stream.loop_end != stream.data.size():
			printerr("SELFTEST FAIL: music ", track_name, " loop points=", stream.loop_begin, "..", stream.loop_end, " (want 0..", stream.data.size(), ")")
			_failures += 1
		var first := int(stream.data[0])
		var last := int(stream.data[stream.data.size() - 1])
		if abs(first - 128) > 10 or abs(last - 128) > 10:
			printerr("SELFTEST FAIL: music ", track_name, " seam bytes=", first, "/", last, " (want ~128 for a seamless loop)")
			_failures += 1
		var peak := _peak(stream.data)
		if peak < 0.15 or peak > 0.99:
			printerr("SELFTEST FAIL: music ", track_name, " peak=", peak, " (want 0.15..0.99)")
			_failures += 1
		var fingerprint := str(stream.data.size()) + ":" + str(_hash(stream.data))
		if seen.has(fingerprint):
			printerr("SELFTEST FAIL: music ", track_name, " duplicates ", seen[fingerprint])
			_failures += 1
		else:
			seen[fingerprint] = track_name
		print("ok: music ", track_name, " dur=", snappedf(duration, 0.01), "s loop=", stream.loop_begin, "..", stream.loop_end)
	var bogus: AudioStreamWAV = _music.call("stream_for", "no_such_track")
	if bogus != null:
		printerr("SELFTEST FAIL: music stream_for(bogus) should be null")
		_failures += 1
	print("ok: music loops distinct + loop-enabled + seamless")


func _check_music_player() -> void:
	if _music == null:
		return
	var node := _music.new() as Node
	if node == null:
		printerr("SELFTEST FAIL: music node does not instantiate")
		_failures += 1
		return
	root.add_child(node)
	if not node.has_method("crossfade_to") or not node.has_method("set_intensity"):
		printerr("SELFTEST FAIL: music node missing crossfade_to/set_intensity")
		_failures += 1
		root.remove_child(node)
		node.queue_free()
		return
	if bool(node.call("crossfade_to", "nope", 0.0)):
		printerr("SELFTEST FAIL: music crossfade_to(bogus) should fail")
		_failures += 1
	for track_name in ["nexus_calm", "combat_drive"]:
		if not bool(node.call("crossfade_to", track_name, 0.0)):
			printerr("SELFTEST FAIL: music crossfade_to(", track_name, ") failed")
			_failures += 1
			continue
		if String(node.get("current_track")) != track_name:
			printerr("SELFTEST FAIL: music current_track=", node.get("current_track"))
			_failures += 1
		if not bool(node.call("is_track_playing")):
			printerr("SELFTEST FAIL: music ", track_name, " not playing after crossfade")
			_failures += 1
	node.call("set_intensity", 0.0)
	if float(node.get("intensity")) != 0.0 or bool(node.call("is_layer_active")):
		printerr("SELFTEST FAIL: music set_intensity(0) did not remove layer")
		_failures += 1
	node.call("set_intensity", 1.0)
	if float(node.get("intensity")) != 1.0 or not bool(node.call("is_layer_active")):
		printerr("SELFTEST FAIL: music set_intensity(1) did not restore layer")
		_failures += 1
	node.call("set_intensity", 2.0)
	if float(node.get("intensity")) != 1.0:
		printerr("SELFTEST FAIL: music set_intensity(2) not clamped to 1")
		_failures += 1
	node.call("set_intensity", -1.0)
	if float(node.get("intensity")) != 0.0:
		printerr("SELFTEST FAIL: music set_intensity(-1) not clamped to 0")
		_failures += 1
	print("ok: music crossfade + intensity layers")
	root.remove_child(node)
	node.queue_free()
