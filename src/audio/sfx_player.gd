class_name GraveSfxPlayer
extends Node
## Tiny round-robin AudioStreamPlayer pool for GraveSfx streams.
##
## Autoload-ready: drop into the scene tree (or register as an autoload) and
## call play(). Overlapping sounds each get their own voice; when every voice
## is busy the oldest is reused. Zero per-play allocation after _ready().
##
## Usage:
##   $SfxPlayer.play(GraveSfx.pickup())

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
