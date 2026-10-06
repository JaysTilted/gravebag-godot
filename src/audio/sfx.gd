class_name GraveSfx
extends RefCounted
## GRAVEBAG procedural SFX — every sound synthesized in code (8-bit chiptune).
##
## Autoload-ready: no instance state, only static funcs. Either
## `GraveSfx.shoot()` directly via class_name, or register this script as an
## autoload singleton. Each func returns a fresh AudioStreamWAV (8-bit mono,
## MIX_RATE Hz) with a distinct pitch envelope.
##
## Mix (game feel): shots sit quiet under combat, hits/kills punch through,
## UI stays soft. MIX_DB is the single balance table (dB trim applied at
## playback); synthesis volumes follow the same hierarchy. Rapid-fire sounds
## (shoot/enemy_shoot/hit) take ±10% pitch variance at playback so sprays
## don't machine-gun — see pitch_range_for()/roll_pitch() and
## GraveSfxPlayer.play_varied().
##
## Durations: every sound < 0.5 s except death_sting (< 1.2 s).
##
## Usage:
##   var player := GraveSfxPlayer.new()
##   player.play(GraveSfx.shoot())
##   player.play_varied(GraveSfx.shoot(), "shoot")

const MIX_RATE := 22050
const MAX_DURATION := 0.5
const STING_MAX_DURATION := 1.2
## Pitch variance for rapid sounds (±10% so sprays don't machine-gun).
const PITCH_VARIANCE := 0.10
const PITCH_MIN := 0.9
const PITCH_MAX := 1.1
## Sounds that get pitch variance at playback.
const RAPID_SOUNDS := ["shoot", "enemy_shoot", "hit"]
## Per-sound volume balance table (dB trim at playback).
## Shots quiet, hits/kills punchy, UI soft.
const MIX_DB := {
	"shoot": -12.0,
	"enemy_shoot": -14.0,
	"hit": -4.0,
	"kill": -6.0,
	"pickup": -8.0,
	"potion": -8.0,
	"levelup": -6.0,
	"death": -6.0,
	"death_sting": -6.0,
	"extract": -8.0,
	"ui_click": -18.0,
	"fame_tick": -14.0,
}

enum Wave { SQUARE, SAW, SINE }


static func mix_db_for(sound_name: String) -> float:
	return float(MIX_DB.get(sound_name, 0.0))


static func pitch_range_for(sound_name: String) -> Vector2:
	if sound_name in RAPID_SOUNDS:
		return Vector2(PITCH_MIN, PITCH_MAX)
	return Vector2.ONE


static func roll_pitch(sound_name: String) -> float:
	var bounds := pitch_range_for(sound_name)
	if bounds.x >= bounds.y:
		return 1.0
	return randf_range(bounds.x, bounds.y)


static func shoot() -> AudioStreamWAV:
	# Player laser: bright square zap sliding down 880 -> 440 Hz, 0.12 s.
	# Quiet by design (MIX_DB -12 dB); variance at playback.
	return _tone(880.0, 440.0, 0.12, Wave.SQUARE, 0.40)


static func enemy_shoot() -> AudioStreamWAV:
	# Enemy shot: lower square blip 440 -> 220 Hz, 0.15 s. Darker than shoot().
	# Quietest shot (MIX_DB -14 dB); variance at playback.
	return _tone(440.0, 220.0, 0.15, Wave.SQUARE, 0.35)


static func hit() -> AudioStreamWAV:
	# Impact thud: low square 200 -> 80 Hz buried in noise, 0.15 s.
	# Punchy (MIX_DB -4 dB); variance at playback.
	return _tone(200.0, 80.0, 0.15, Wave.SQUARE, 0.70, 0.6)


static func kill() -> AudioStreamWAV:
	# Kill confirm: saw sweep 600 -> 100 Hz, 0.30 s. Grittier than hit().
	# Punchy (MIX_DB -6 dB).
	return _tone(600.0, 100.0, 0.30, Wave.SAW, 0.65, 0.15)


static func pickup() -> AudioStreamWAV:
	# Loot pickup: two-note bright chirp (660, 990 Hz), 0.18 s total.
	return _arp([660.0, 990.0], 0.09, Wave.SQUARE, 0.50)


static func potion() -> AudioStreamWAV:
	# Potion glug: sine rising 300 -> 900 Hz with wobble, 0.35 s.
	return _tone(300.0, 900.0, 0.35, Wave.SINE, 0.50, 0.0, 0.08)


static func levelup() -> AudioStreamWAV:
	# Level-up fanfare: four-note square arpeggio
	# C5 E5 G5 C6 (523.25, 659.25, 783.99, 1046.5), 0.40 s total.
	return _arp([523.25, 659.25, 783.99, 1046.5], 0.10, Wave.SQUARE, 0.55)


static func death() -> AudioStreamWAV:
	# Player death: long saw fall 400 -> 50 Hz with noise wash, 0.45 s.
	return _tone(400.0, 50.0, 0.45, Wave.SAW, 0.60, 0.3)


static func death_sting() -> AudioStreamWAV:
	# Death sting: three-note minor descent G4 Eb4 Bb3
	# (392.0, 311.13, 233.08), 0.30 s each, 0.90 s total. The only sound
	# allowed past 0.5 s (cap 1.2 s).
	return _arp([392.0, 311.13, 233.08], 0.30, Wave.SAW, 0.55)


static func extract() -> AudioStreamWAV:
	# Extraction: shimmering sine rise 500 -> 1500 Hz, 0.40 s.
	return _tone(500.0, 1500.0, 0.40, Wave.SINE, 0.50)


static func ui_click() -> AudioStreamWAV:
	# UI click: ultra-short 1200 -> 900 Hz tick, 0.05 s. Softest in the mix.
	return _tone(1200.0, 900.0, 0.05, Wave.SQUARE, 0.30)


static func fame_tick() -> AudioStreamWAV:
	# Fame tick: short bright sine blip 1568 -> 2093 Hz (G6 -> C7), 0.07 s.
	# Soft tally tick for the fame counter (MIX_DB -14 dB).
	return _tone(1568.0, 2093.0, 0.07, Wave.SINE, 0.40)


static func _wave(phase: float, wave: int) -> float:
	match wave:
		Wave.SQUARE:
			return signf(sin(phase))
		Wave.SAW:
			return 2.0 * fposmod(phase / TAU, 1.0) - 1.0
		_:
			return sin(phase)


static func _envelope(time: float, progress: float) -> float:
	var attack := clampf(time / 0.005, 0.0, 1.0)
	return attack * pow(1.0 - progress, 1.5)


static func _finish(frames: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = frames
	return stream


static func _tone(freq_start: float, freq_end: float, duration: float, wave: int, volume: float, noise: float = 0.0, wobble: float = 0.0) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var denom := float(maxi(frames - 1, 1))
	for i in frames:
		var time := float(i) / MIX_RATE
		var progress := float(i) / denom
		var freq := lerpf(freq_start, freq_end, progress)
		if wobble > 0.0:
			freq *= 1.0 + wobble * sin(TAU * 8.0 * time)
		phase += TAU * freq / MIX_RATE
		var sample := _wave(phase, wave)
		if noise > 0.0:
			sample = lerpf(sample, rng.randf_range(-1.0, 1.0), noise)
		sample *= volume * _envelope(time, progress)
		data[i] = clampi(128 + int(127.0 * sample), 0, 255)
	return _finish(data)


static func _arp(notes: Array, note_duration: float, wave: int, volume: float) -> AudioStreamWAV:
	var frames_per_note := int(MIX_RATE * note_duration)
	var data := PackedByteArray()
	data.resize(frames_per_note * notes.size())
	var phase := 0.0
	var note_denom := float(maxi(frames_per_note - 1, 1))
	for n in notes.size():
		var freq := float(notes[n])
		for i in frames_per_note:
			var time := float(i) / MIX_RATE
			var progress := float(i) / note_denom
			phase += TAU * freq / MIX_RATE
			var sample := _wave(phase, wave) * volume * _envelope(time, progress)
			data[n * frames_per_note + i] = clampi(128 + int(127.0 * sample), 0, 255)
	return _finish(data)
