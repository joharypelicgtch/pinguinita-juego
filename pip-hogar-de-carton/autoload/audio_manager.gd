extends Node
## AUTOLOAD: AudioManager
## - Muchos efectos pequeños (pool de reproductores, máx. 16 voces).
## - Ambiente por capas (bosque / ciudad / lluvia).
## - Música melancólica SOLO en tensión extrema (histéresis: entra >0.75, sale <0.55).
## Si falta un archivo de audio, simplemente no suena (el juego no falla).

const SFX := {
	"pickup": "res://audio/sfx/pickup.ogg",
	"soft_hit": "res://audio/sfx/soft_hit.ogg",
	"place_piece": "res://audio/sfx/place_piece.ogg",
	"cardboard_creak": "res://audio/sfx/cardboard_creak.ogg",
	"collapse": "res://audio/sfx/collapse.ogg",
	"gift_ok": "res://audio/sfx/gift_ok.ogg",
	"gift_no": "res://audio/sfx/gift_no.ogg",
	"step_grass": "res://audio/sfx/step_grass.ogg",
	"step_pavement": "res://audio/sfx/step_pavement.ogg",
	"drop_food": "res://audio/sfx/drop_food.ogg",
}
const AMBIENT := {
	"forest": "res://audio/ambient/forest.ogg",
	"city": "res://audio/ambient/city.ogg",
	"rain": "res://audio/ambient/rain.ogg",
}
const MUSIC_PATH := "res://audio/music/melancholy.ogg"

const POOL_3D := 10
const POOL_UI := 6
const TENSION_ON := 0.75
const TENSION_OFF := 0.55
const CHECK_INTERVAL := 0.25

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _ambient: Dictionary = {}          # name -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_on: bool = false
var _check_timer: float = 0.0
var _tween: Tween


func _ready() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 30.0
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_ui.append(p)

	for key in AMBIENT:
		var stream := _load(AMBIENT[key])
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -80.0
		add_child(p)
		_ambient[key] = p
		if stream:
			_set_loop(stream)
			p.play()

	_music = AudioStreamPlayer.new()
	_music.stream = _load(MUSIC_PATH)
	_music.volume_db = -80.0
	add_child(_music)
	if _music.stream:
		_set_loop(_music.stream)


func _process(delta: float) -> void:
	_update_ambient(delta)
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL:
		_check_timer = 0.0
		_update_music()


# ------------------------------------------------------------------ Efectos

## position = null -> sonido no posicional (UI, regalos). Con Vector3 -> posicional.
func play_sfx(sfx_name: String, position: Variant = null) -> void:
	var stream := _load(SFX.get(sfx_name, ""))
	if stream == null:
		return
	if position is Vector3:
		for p in _pool_3d:
			if not p.playing:
				p.stream = stream
				p.global_position = position
				p.pitch_scale = randf_range(0.92, 1.08)     # variación barata, evita repetición
				p.play()
				return
	else:
		for p in _pool_ui:
			if not p.playing:
				p.stream = stream
				p.pitch_scale = randf_range(0.95, 1.05)
				p.play()
				return


# ------------------------------------------------------------------ Ambiente

func _update_ambient(delta: float) -> void:
	var city := WeatherManager.in_city
	_fade_to("forest", 0.0 if city else -8.0, delta)
	_fade_to("city", -8.0 if city else -80.0, delta)
	var rain_db := -80.0 if WeatherManager.intensity() < 0.2 else linear_to_db(WeatherManager.intensity()) - 6.0
	_fade_to("rain", rain_db, delta)


func _fade_to(key: String, target_db: float, delta: float) -> void:
	var p: AudioStreamPlayer = _ambient.get(key)
	if p == null:
		return
	p.volume_db = move_toward(p.volume_db, target_db, 40.0 * delta)


# ------------------------------------------------------------------ Música en tensión extrema

func _update_music() -> void:
	if _music.stream == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Pinguinita
	if player == null:
		return
	var t := player.stats.tension()
	if t > TENSION_ON and not _music_on:
		_music_on = true
		_fade_music(-8.0, 3.0, true)
	elif t < TENSION_OFF and _music_on:
		_music_on = false
		_fade_music(-80.0, 4.0, false)


func _fade_music(target_db: float, seconds: float, start: bool) -> void:
	if _tween:
		_tween.kill()
	if start and not _music.playing:
		_music.volume_db = -60.0
		_music.play()
	_tween = create_tween()
	_tween.tween_property(_music, "volume_db", target_db, seconds)
	if not start:
		_tween.tween_callback(_music.stop)


# ------------------------------------------------------------------ Utilidades

func _load(path: String) -> AudioStream:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s


func _set_loop(stream: AudioStream) -> void:
	if "loop" in stream:
		stream.loop = true
