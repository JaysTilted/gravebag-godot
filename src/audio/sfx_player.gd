class_name GraveSfxPlayer
extends Node
## Tiny round-robin AudioStreamPlayer pool for GraveSfx streams.
##
## Autoload-ready: drop into the scene tree (or register as an autoload) and
## call play(). Overlapping sounds each get their own voice; when every voice
## is busy the oldest is reused. Zero per-play allocation after _ready().
##
## Mix-aware playback: play_varied(stream, sound_name) applies the GraveSfx
## MIX_DB trim plus ±10% pitch variance on rapid sounds (shoot/enemy_shoot/
## hit) so sprays don't machine-gun. Plain play() stays raw for callers that
## manage the mix themselves.
##
## Usage:
##   $SfxPlayer.play(GraveSfx.pickup())
##   $SfxPlayer.play_varied(GraveSfx.shoot(), "shoot")

const Sfx := preload("res://src/audio/sfx.gd")

## Pitch variance bounds for rapid sounds (±10%).
const PITCH_MIN := 0.9
const PITCH_MAX := 1.1

@export var pool_size := 8

var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in pool_size:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Master"
		add_child(voice)
		_pool.append(voice)


func play(stream: AudioStreamWAV, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _pool.is_empty():
		return
	var voice := _pool[_next]
	_next = (_next + 1) % _pool.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch_scale
	voice.play()


## Mix-aware play: MIX_DB trim + pitch variance for rapid sounds.
func play_varied(stream: AudioStreamWAV, sound_name: String) -> void:
	play(stream, Sfx.mix_db_for(sound_name), roll_pitch_for(sound_name))


## Pitch bounds for a sound: (0.9, 1.1) on rapid sounds, (1, 1) otherwise.
static func pitch_bounds_for(sound_name: String) -> Vector2:
	if sound_name in Sfx.RAPID_SOUNDS:
		return Vector2(PITCH_MIN, PITCH_MAX)
	return Vector2.ONE


## Randomized pitch within pitch_bounds_for(sound_name).
static func roll_pitch_for(sound_name: String) -> float:
	var bounds := pitch_bounds_for(sound_name)
	if bounds.x >= bounds.y:
		return 1.0
	return randf_range(bounds.x, bounds.y)
