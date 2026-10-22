class_name SurvivalStats
extends Node
## Componente de supervivencia. Cuélgalo como hijo de la Pinguinita.
## Sin muerte: al llegar la salud a 0 hay DESMAYO (reaparece en el refugio).

signal fainted
signal stat_changed(stat_name: String, value: float)

const MAX := 100.0

# Tasas por segundo (ajustables en pruebas)
const HUNGER_RATE := 0.35
const COLD_RATE := 1.2
const WARM_REGEN_SHELTER := 2.5
const STRESS_NIGHT := 0.6
const STRESS_DECAY_SHELTER := 3.0
const HEALTH_REGEN := 1.0
const HEALTH_DRAIN := 1.5

var health: float = MAX
var hunger: float = MAX      # 100 = lleno
var warmth: float = MAX
var stress: float = 0.0

var sheltered: bool = false
var shelter_quality: float = 1.0     # 1.0 cartón ... 2.0 reforzado (lo fija el BuildingSystem)
var threat_nearby: bool = false      # lo fija HumanNPC mientras persigue


func _process(delta: float) -> void:
	_tick_hunger(delta)
	_tick_warmth(delta)
	_tick_stress(delta)
	_tick_health(delta)


func _tick_hunger(delta: float) -> void:
	hunger = clampf(hunger - HUNGER_RATE * delta, 0.0, MAX)
	stat_changed.emit("hunger", hunger)


func _tick_warmth(delta: float) -> void:
	var cold := WeatherManager.cold_factor()
	if GameClock.is_night():
		cold += 0.5
	if sheltered:
		cold = maxf(cold - shelter_quality * 0.8, 0.0)
		warmth += WARM_REGEN_SHELTER * shelter_quality * delta * (1.0 if cold <= 0.0 else 0.2)
	warmth = clampf(warmth - cold * COLD_RATE * delta, 0.0, MAX)
	stat_changed.emit("warmth", warmth)


func _tick_stress(delta: float) -> void:
	var s := 0.0
	if GameClock.is_night():
		s += STRESS_NIGHT
	if WeatherManager.current == WeatherManager.Weather.STORM:
		s += 1.0
	if threat_nearby:
		s += 4.0
	if sheltered:
		s -= STRESS_DECAY_SHELTER
	stress = clampf(stress + s * delta, 0.0, MAX)
	stat_changed.emit("stress", stress)


func _tick_health(delta: float) -> void:
	if hunger <= 0.0 or warmth <= 0.0:
		health -= HEALTH_DRAIN * delta
	elif hunger > 40.0 and warmth > 40.0 and stress < 80.0:
		health += HEALTH_REGEN * (2.0 if sheltered else 1.0) * delta
	health = clampf(health, 0.0, MAX)
	stat_changed.emit("health", health)
	if health <= 0.0:
		fainted.emit()


func damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	stress = minf(stress + amount * 1.5, MAX)
	if health <= 0.0:
		fainted.emit()


func eat(nutrition: float) -> void:
	hunger = minf(hunger + nutrition, MAX)
	stress = maxf(stress - nutrition * 0.2, 0.0)


func recover_after_faint() -> void:
	## Despierta en el refugio con penalización leve (el Main mueve al jugador y avanza el reloj).
	health = 40.0
	hunger = minf(hunger, 40.0)
	warmth = 50.0
	stress = 30.0


## 0..1. Lo usa AudioManager: la música melancólica solo entra en tensión extrema.
func tension() -> float:
	var t := 0.0
	t += (1.0 - health / MAX) * 0.5
	t += (stress / MAX) * 0.4
	if hunger < 20.0 or warmth < 20.0:
		t += 0.15
	if threat_nearby:
		t += 0.2
	return clampf(t, 0.0, 1.0)
