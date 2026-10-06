class_name GraveMusic
extends Node
## GRAVEBAG procedural music — every track synthesized in code, no external audio.
##
## Two original loops, generated as looped AudioStreamWAV (8-bit mono,
## MIX_RATE Hz):
## - nexus_calm: slow eighth-note arps over a swelling triad pad (84 BPM).
## - combat_drive: driving eighth-note bass + square lead with kick/snare/hat
##   at a 140 BPM feel.
## Each loop is exactly BARS_PER_LOOP bars of BEATS_PER_BAR; every voice
## envelope returns to zero at its slot edge, so the first and last frames
## sit at center (128) and the FORWARD loop point is click-free.
##
## Playback: drop this node in the tree, crossfade_to() picks the track and
## set_intensity(0..1) fades the extra layer (arp on calm, lead on combat)
## in or out. Base and layer are separate looped streams kept in sync.
##
## Usage:
##   var music := GraveMusic.new()
##   add_child(music)
##   music.crossfade_to("nexus_calm")
##   music.set_intensity(0.5)

const MIX_RATE := 22050
const TRACKS: Array[String] = ["nexus_calm", "combat_drive"]
const BARS_PER_LOOP := 8
const BEATS_PER_BAR := 4
## Calm loop tempo (slow arps + pad).
const CALM_BPM := 84.0
## Combat loop tempo (driving bass + lead).
const COMBAT_BPM := 140.0
## Every loop must exceed this duration (both loops are 13+ s).
const MIN_DURATION := 10.0
## Mixer trims for the two playback voices.
const BASE_DB := -8.0
const LAYER_ON_DB := -2.0
const LAYER_OFF_DB := -40.0

static var _cache: Dictionary = {}

var current_track: String = ""
var intensity: float = 1.0

var _base: AudioStreamPlayer
var _layer: AudioStreamPlayer
var _fade: Tween


static func stream_for(track_name: String) -> AudioStreamWAV:
	match track_name:
		"nexus_calm":
			return nexus_calm()
		"combat_drive":
			return combat_drive()
	return null


static func base_for(track_name: String) -> AudioStreamWAV:
	match track_name:
		"nexus_calm":
			return _parts_calm()["base"] as AudioStreamWAV
		"combat_drive":
			return _parts_combat()["base"] as AudioStreamWAV
	return null


static func layer_for(track_name: String) -> AudioStreamWAV:
	match track_name:
		"nexus_calm":
			return _parts_calm()["layer"] as AudioStreamWAV
		"combat_drive":
			return _parts_combat()["layer"] as AudioStreamWAV
	return null


static func nexus_calm() -> AudioStreamWAV:
	return _parts_calm()["mix"] as AudioStreamWAV


static func combat_drive() -> AudioStreamWAV:
	return _parts_combat()["mix"] as AudioStreamWAV


func _ready() -> void:
	_ensure_players()


func _exit_tree() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()


func _ensure_players() -> void:
	if _base == null:
		_base = AudioStreamPlayer.new()
		_base.bus = &"Master"
		add_child(_base)
	if _layer == null:
		_layer = AudioStreamPlayer.new()
		_layer.bus = &"Master"
		add_child(_layer)


## Switch the loop; safe to call any time (returns false on unknown tracks).
func crossfade_to(track_name: String, fade_sec: float = 0.8) -> bool:
	if not (track_name in TRACKS):
		return false
	var b := base_for(track_name)
	var l := layer_for(track_name)
	if b == null or l == null:
		return false
	_ensure_players()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	current_track = track_name
	_base.stream = b
	_layer.stream = l
	_base.volume_db = BASE_DB
	_layer.volume_db = _layer_target_db()
	_base.play(0.0)
	if intensity > 0.02:
		_layer.play(0.0)
	else:
		_layer.stop()
	if fade_sec > 0.01 and is_inside_tree():
		_base.volume_db = BASE_DB - 18.0
		_layer.volume_db = _layer_target_db() - 18.0
		var tw := create_tween()
		tw.set_parallel()
		tw.tween_property(_base, "volume_db", BASE_DB, fade_sec)
		tw.tween_property(_layer, "volume_db", _layer_target_db(), fade_sec)
		_fade = tw
	return true


## Extra-layer blend: 0 removes the arp/lead, 1 brings it fully in.
func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	_ensure_players()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_base.volume_db = BASE_DB
	_layer.volume_db = _layer_target_db()
	if current_track == "" or _base.stream == null:
		return
	if not _base.playing:
		_base.play(0.0)
	if intensity <= 0.02:
		_layer.stop()
	elif not _layer.playing and _layer.stream != null:
		_layer.play(_base.get_playback_position())


func is_track_playing() -> bool:
	return _base != null and _base.stream != null and _base.playing


func is_layer_active() -> bool:
	return _layer != null and _layer.playing and intensity > 0.02


func layer_gain_db() -> float:
	if _layer == null:
		return LAYER_OFF_DB
	return _layer.volume_db


func _layer_target_db() -> float:
	return lerpf(LAYER_OFF_DB, LAYER_ON_DB, intensity)


## Calm loop: one render pass producing pad (base) + arp (layer) voices.
static func _parts_calm() -> Dictionary:
	if _cache.has("calm"):
		return _cache["calm"] as Dictionary
	var beat := 60.0 / CALM_BPM
	var eighth := beat * 0.5
	var bar_dur := beat * float(BEATS_PER_BAR)
	var frames := int(bar_dur * float(BARS_PER_LOOP) * float(MIX_RATE))
	# Original 8-bar loop: Am F C G | Am F Dm Em.
	var roots := [45, 41, 48, 43, 45, 41, 50, 52]
	var is_minor := [true, false, false, false, true, false, true, true]
	var chord_freqs: Array = []
	for b in BARS_PER_LOOP:
		var root := int(roots[b]) + 12
		var third := root + (3 if bool(is_minor[b]) else 4)
		chord_freqs.append([_midi(root), _midi(third), _midi(root + 7)])
	var arp_pat := [0, 1, 2, 3, 2, 1, 0, 1]
	var base := PackedFloat32Array()
	base.resize(frames)
	var layer := PackedFloat32Array()
	layer.resize(frames)
	var ph0 := 0.0
	var ph1 := 0.0
	var ph2 := 0.0
	var pha := 0.0
	var cur_bar := -1
	var inc0 := 0.0
	var inc1 := 0.0
	var inc2 := 0.0
	var cur_slot := -1
	var inca := 0.0
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var bar := mini(int(t / bar_dur), BARS_PER_LOOP - 1)
		if bar != cur_bar:
			cur_bar = bar
			var incs: Array = chord_freqs[bar]
			inc0 = TAU * float(incs[0]) / float(MIX_RATE)
			inc1 = TAU * float(incs[1]) / float(MIX_RATE)
			inc2 = TAU * float(incs[2]) / float(MIX_RATE)
		var t_bar := t - float(bar) * bar_dur
		var swell := pow(sin(PI * clampf(t_bar / bar_dur, 0.0, 1.0)), 0.5)
		ph0 += inc0
		ph1 += inc1
		ph2 += inc2
		base[i] = (sin(ph0) + sin(ph1) + sin(ph2)) * 0.11 * swell
		var slot := int(t / eighth)
		if slot != cur_slot:
			cur_slot = slot
			var sbar := mini(slot / 8, BARS_PER_LOOP - 1)
			var tones: Array = chord_freqs[sbar]
			var step := int(arp_pat[slot % 8])
			var tone := 0.0
			if step == 0:
				tone = float(tones[0]) * 2.0
			elif step == 1:
				tone = float(tones[1]) * 2.0
			elif step == 2:
				tone = float(tones[2]) * 2.0
			else:
				tone = float(tones[0]) * 4.0
			inca = TAU * tone / float(MIX_RATE)
		pha += inca
		var t_slot := t - float(slot) * eighth
		var p := clampf(t_slot / eighth, 0.0, 1.0)
		var env := clampf(t_slot / 0.008, 0.0, 1.0) * pow(1.0 - p, 1.2)
		layer[i] = sin(pha) * 0.30 * env
	var parts := _to_bytes(base, layer)
	_cache["calm"] = parts
	return parts


## Combat loop: one render pass producing bass+drums (base) + lead (layer).
static func _parts_combat() -> Dictionary:
	if _cache.has("combat"):
		return _cache["combat"] as Dictionary
	var beat := 60.0 / COMBAT_BPM
	var eighth := beat * 0.5
	var bar_dur := beat * float(BEATS_PER_BAR)
	var frames := int(bar_dur * float(BARS_PER_LOOP) * float(MIX_RATE))
	# Original 8-bar loop: Em Em G A | Em Em B A.
	var roots := [40, 40, 43, 45, 40, 40, 47, 45]
	var bass_pat := [0, 0, 12, 0, 0, 12, 0, 7]
	# Original lead line in E minor, one note per quarter-note slot.
	var lead := [
		76, 79, 81, 79, 83, 81, 79, 76,
		79, 81, 83, 86, 81, 83, 81, 79,
		76, 79, 81, 83, 86, 83, 81, 79,
		78, 83, 86, 83, 81, 79, 76, 74,
	]
	var base := PackedFloat32Array()
	base.resize(frames)
	var layer := PackedFloat32Array()
	layer.resize(frames)
	var phb := 0.0
	var phs := 0.0
	var phl := 0.0
	var phk := 0.0
	var cur_e := -1
	var incb := 0.0
	var cur_q := -1
	var lead_f := 0.0
	for i in frames:
		var t := float(i) / float(MIX_RATE)
		var e8 := int(t / eighth)
		if e8 != cur_e:
			cur_e = e8
			var ebar := mini(e8 / 8, BARS_PER_LOOP - 1)
			incb = TAU * _midi(int(roots[ebar]) + int(bass_pat[e8 % 8])) / float(MIX_RATE)
		var t_e := t - float(e8) * eighth
		var pe := clampf(t_e / eighth, 0.0, 1.0)
		var benv := clampf(t_e / 0.005, 0.0, 1.0) * pow(1.0 - pe, 1.5)
		phb += incb
		var saw := 2.0 * fposmod(phb / TAU, 1.0) - 1.0
		var bass := (saw * 0.42 + sin(phb) * 0.18) * benv
		var q := int(t / beat)
		var t_q := t - float(q) * beat
		var drums := 0.0
		if t_q < 0.12:
			var kp := t_q / 0.12
			phk += TAU * lerpf(120.0, 45.0, kp) / float(MIX_RATE)
			drums += sin(phk) * 0.75 * pow(1.0 - kp, 1.5)
		else:
			phk = 0.0
		if (e8 % 2) == 1 and t_e < 0.045:
			drums += _hash_noise(i) * 0.16 * (1.0 - t_e / 0.045)
		var qb := q % 4
		if (qb == 1 or qb == 3) and t_q < 0.09:
			phs += TAU * 190.0 / float(MIX_RATE)
			drums += (_hash_noise(i + 7919) * 0.28 + sin(phs) * 0.22) * (1.0 - t_q / 0.09)
		base[i] = bass + drums
		var qs := mini(int(t / beat), BARS_PER_LOOP * BEATS_PER_BAR - 1)
		if qs != cur_q:
			cur_q = qs
			var ln := int(lead[qs])
			lead_f = _midi(ln) if ln > 0 else 0.0
		var lsample := 0.0
		if lead_f > 0.0:
			var t_l := t - float(qs) * beat
			var pl := clampf(t_l / beat, 0.0, 1.0)
			var lenv := clampf(t_l / 0.01, 0.0, 1.0) * pow(1.0 - pl, 1.1)
			phl += TAU * lead_f * (1.0 + 0.006 * sin(TAU * 5.0 * t)) / float(MIX_RATE)
			lsample = (signf(sin(phl)) * 0.30 + sin(phl) * 0.12) * lenv
		layer[i] = lsample
	var parts := _to_bytes(base, layer)
	_cache["combat"] = parts
	return parts


static func _midi(note: int) -> float:
	return 440.0 * pow(2.0, float(note - 69) / 12.0)


static func _soft(x: float) -> float:
	return x / (1.0 + 0.5 * absf(x))


static func _hash_noise(n: int) -> float:
	var x := sin(float(n) * 12.9898) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0


static func _finish(frames: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = frames
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames.size()
	return stream


static func _to_bytes(base: PackedFloat32Array, layer: PackedFloat32Array) -> Dictionary:
	var n := base.size()
	var base_b := PackedByteArray()
	base_b.resize(n)
	var layer_b := PackedByteArray()
	layer_b.resize(n)
	var mix_b := PackedByteArray()
	mix_b.resize(n)
	for i in n:
		var b := _soft(base[i])
		var l := _soft(layer[i])
		base_b[i] = clampi(128 + int(120.0 * b), 0, 255)
		layer_b[i] = clampi(128 + int(120.0 * l), 0, 255)
		mix_b[i] = clampi(128 + int(120.0 * _soft(base[i] + layer[i])), 0, 255)
	return {"base": _finish(base_b), "layer": _finish(layer_b), "mix": _finish(mix_b)}
