extends Node
## AUTOLOAD: WeatherManager
## Clima por cadena de Markov. En la ciudad llueve más (tono melancólico).

enum Weather { CLEAR, CLOUDY, RAIN, STORM }

signal weather_changed(new_weather: Weather)
signal tragedy(kind: String)         # p. ej. "storm" -> el BuildingSystem daña piezas

const STORM_TRAGEDY_CHANCE := 0.35
const MIN_DURATION := 45.0
const MAX_DURATION := 120.0

# Probabilidades de transición: de -> {a: peso}
const TRANSITIONS := {
	Weather.CLEAR:  { Weather.CLEAR: 0.40, Weather.CLOUDY: 0.60 },
	Weather.CLOUDY: { Weather.CLEAR: 0.25, Weather.CLOUDY: 0.30, Weather.RAIN: 0.45 },
	Weather.RAIN:   { Weather.CLOUDY: 0.35, Weather.RAIN: 0.40, Weather.STORM: 0.25 },
	Weather.STORM:  { Weather.RAIN: 0.70, Weather.CLOUDY: 0.30 },
}

var current: Weather = Weather.CLOUDY
var in_city: bool = false            # lo actualiza el WorldGenerator / Main al cambiar de zona

var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _next_change: float = 60.0


func _ready() -> void:
	_rng.randomize()
	_next_change = _rng.randf_range(MIN_DURATION, MAX_DURATION)


func seed_weather(seed_value: int) -> void:
	_rng.seed = seed_value


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_change:
		_timer = 0.0
		_next_change = _rng.randf_range(MIN_DURATION, MAX_DURATION)
		_roll_next()


func _roll_next() -> void:
	var weights: Dictionary = TRANSITIONS[current].duplicate()
	if in_city:
		for w in [Weather.RAIN, Weather.STORM]:
			if weights.has(w):
				weights[w] *= 2.0
	set_weather(_pick_weighted(weights))


func set_weather(new_weather: Weather) -> void:
	if new_weather == current:
		return
	current = new_weather
	weather_changed.emit(current)
	if current == Weather.STORM and _rng.randf() < STORM_TRAGEDY_CHANCE:
		tragedy.emit("storm")


func _pick_weighted(weights: Dictionary) -> Weather:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := _rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return current


## 0..1 para partículas de lluvia, volumen de ambiente, etc.
func intensity() -> float:
	match current:
		Weather.RAIN: return 0.6
		Weather.STORM: return 1.0
		Weather.CLOUDY: return 0.1
		_: return 0.0


func is_raining() -> bool:
	return current == Weather.RAIN or current == Weather.STORM


## Factor extra de enfriamiento (lo usa SurvivalStats).
func cold_factor() -> float:
	match current:
		Weather.RAIN: return 1.0
		Weather.STORM: return 1.8
		Weather.CLOUDY: return 0.3
		_: return 0.0


## 0..1 densidad de niebla objetivo (la lee Main para el Environment).
func fog_density() -> float:
	match current:
		Weather.CLEAR: return 0.002
		Weather.CLOUDY: return 0.006
		Weather.RAIN: return 0.015
		Weather.STORM: return 0.025
	return 0.005
