class_name GraveSfx
extends RefCounted
## GRAVEBAG procedural SFX — every sound synthesized in code (8-bit chiptune).
##
## Autoload-ready: no instance state, only static funcs. Either
## `GraveSfx.shoot()` directly via class_name, or register this script as an
## autoload singleton. Each func returns a fresh AudioStreamWAV (8-bit mono,
## MIX_RATE Hz), always under 0.5s, with a distinct pitch envelope.
##
## Usage:
##   var player := GraveSfxPlayer.new()
##   player.play(GraveSfx.shoot())

const MIX_RATE := 22050
const MAX_DURATION := 0.5

enum Wave { SQUARE, SAW, SINE }


static func shoot() -> AudioStreamWAV:
	# Player laser: bright square zap sliding down 880 -> 440 Hz, 0.12 s.
	return _tone(880.0, 440.0, 0.12, Wave.SQUARE, 0.55)


static func enemy_shoot() -> AudioStreamWAV:
	# Enemy shot: lower square blip 440 -> 220 Hz, 0.15 s. Darker than shoot().
	return _tone(440.0, 220.0, 0.15, Wave.SQUARE, 0.45)


static func hit() -> AudioStreamWAV:
	# Impact thud: low square 200 -> 80 Hz buried in noise, 0.15 s.
	return _tone(200.0, 80.0, 0.15, Wave.SQUARE, 0.6, 0.6)


static func kill() -> AudioStreamWAV:
	# Kill confirm: saw sweep 600 -> 100 Hz, 0.30 s. Grittier than hit().
	return _tone(600.0, 100.0, 0.30, Wave.SAW, 0.55, 0.15)


static func pickup() -> AudioStreamWAV:
	# Loot pickup: two-note bright chirp (660, 990 Hz), 0.18 s total.
	return _arp([660.0, 990.0], 0.09, Wave.SQUARE, 0.5)


static func potion() -> AudioStreamWAV:
	# Potion glug: sine rising 300 -> 900 Hz with wobble, 0.35 s.
	return _tone(300.0, 900.0, 0.35, Wave.SINE, 0.55, 0.0, 0.08)


static func levelup() -> AudioStreamWAV:
	# Level-up fanfare: four-note square arpeggio, 0.40 s total.
	return _arp([523.25, 659.25, 783.99, 1046.5], 0.10, Wave.SQUARE, 0.5)


static func death() -> AudioStreamWAV:
	# Player death: long saw fall 400 -> 50 Hz with noise wash, 0.45 s.
	return _tone(400.0, 50.0, 0.45, Wave.SAW, 0.6, 0.3)


static func extract() -> AudioStreamWAV:
	# Extraction: shimmering sine rise 500 -> 1500 Hz, 0.40 s.
	return _tone(500.0, 1500.0, 0.40, Wave.SINE, 0.5)


static func ui_click() -> AudioStreamWAV:
	# UI click: ultra-short 1200 -> 900 Hz tick, 0.05 s.
	return _tone(1200.0, 900.0, 0.05, Wave.SQUARE, 0.35)


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
