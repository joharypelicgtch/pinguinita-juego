extends Node
## AUTOLOAD: GameClock  (sin class_name, el nombre lo da el Autoload)
## Hora y día del juego. Todo lo demás escucha señales en vez de preguntar cada frame.

signal hour_changed(hour: int)
signal day_changed(day: int)
signal period_changed(is_night: bool)

const DAY_LENGTH_SECONDS := 480.0   # 8 min reales = 1 día de juego

var day: int = 1
var time_of_day: float = 0.30       # 0.0 = medianoche, 0.5 = mediodía
var paused: bool = false

var _last_hour: int = -1
var _was_night: bool = false


func _process(delta: float) -> void:
	if paused:
		return
	time_of_day += delta / DAY_LENGTH_SECONDS
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		day_changed.emit(day)

	var h := int(time_of_day * 24.0)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)

	var night := is_night()
	if night != _was_night:
		_was_night = night
		period_changed.emit(night)


func is_night() -> bool:
	return time_of_day < 0.25 or time_of_day > 0.80


## Pitch del sol: -90 al mediodía (apunta abajo), +90 a medianoche (bajo el horizonte).
func sun_pitch_deg() -> float:
	return 90.0 - time_of_day * 360.0


## 0.0 = noche cerrada, 1.0 = pleno día (para mezclar colores/energía).
func daylight() -> float:
	return clampf(sin((time_of_day - 0.25) * TAU) * 0.5 + 0.5, 0.0, 1.0)


func skip_to_morning() -> void:
	## Usado al desmayarse: avanza hasta el amanecer.
	if time_of_day > 0.30:
		day += 1
		day_changed.emit(day)
	time_of_day = 0.30
