class_name ChickManager
extends Node3D
## Crías: se cuidan, no se heredan, no se juegan. Si se descuidan:
##   - se las lleva un humano (pérdida permanente, escena suave) o
##   - se pierden (hay una ventana para encontrarlas y recuperarlas).
## Sin gore, sin muertes en pantalla.

signal chick_born(chick_id: int)
signal chick_lost(chick_id: int, reason: String)     # "taken_by_human" | "wandered_off"
signal chick_recovered(chick_id: int)

enum ChickState { ACTIVE, LOST, GONE }

const MAX_CHICKS := 3
const DAYS_PER_BIRTH := 3
const BASE_CARE_DECAY := 0.15
const EXPOSED_MULTIPLIER := 3.0
const COMPANY_BONUS := 0.3
const FEED_AMOUNT := 40.0
const CARE_RISK_THRESHOLD := 20.0
const RISK_SECONDS_TO_LOSE := 25.0
const RECOVERY_WINDOW_SECONDS := 180.0
const HUMAN_TAKE_RANGE := 12.0
const HOSTILE_RANGE := 5.0
const FOLLOW_SPEED := 3.0

@export var chick_scene: PackedScene
@export var player: Pinguinita

var chicks: Array[Dictionary] = []     # { id, node, care, risk_time, state, lost_timer }
var shelter_position: Vector3 = Vector3.ZERO
var family_active: bool = false

var _next_id: int = 1
var _family_start_day: int = 0


func _ready() -> void:
	GameClock.day_changed.connect(_on_day_changed)


## Llamar cuando la pareja se muda al refugio.
func start_family(shelter_pos: Vector3) -> void:
	family_active = true
	shelter_position = shelter_pos
	_family_start_day = GameClock.day


func _on_day_changed(day: int) -> void:
	if not family_active or chicks.size() >= MAX_CHICKS:
		return
	if day - _family_start_day >= DAYS_PER_BIRTH * (chicks.size() + 1):
		_spawn_chick()


func _spawn_chick() -> void:
	var node: Node3D = chick_scene.instantiate() if chick_scene else Node3D.new()
	add_child(node)
	node.global_position = shelter_position + Vector3(0.5, 0.0, 0.5)
	var c := { "id": _next_id, "node": node, "care": 70.0, "risk_time": 0.0,
			"state": ChickState.ACTIVE, "lost_timer": 0.0 }
	_next_id += 1
	chicks.append(c)
	chick_born.emit(c.id)


func feed(chick_id: int) -> bool:
	## El jugador gasta una migaja y alimenta a la cría (se llama desde la interacción).
	for c in chicks:
		if c.id == chick_id and c.state == ChickState.ACTIVE and player.spend_items({ "crumbs": 1 }):
			c.care = minf(c.care + FEED_AMOUNT, 100.0)
			return true
	return false


func _process(delta: float) -> void:
	for i in chicks.size():
		var c: Dictionary = chicks[i]
		match c.state:
			ChickState.ACTIVE: _tick_active(c, i, delta)
			ChickState.LOST:   _tick_lost(c, delta)


func _tick_active(c: Dictionary, index: int, delta: float) -> void:
	var node: Node3D = c.node
	var near_shelter := node.global_position.distance_to(shelter_position) < 6.0
	var exposed := not near_shelter and (WeatherManager.is_raining() or GameClock.is_night())
	var hostile_near := _hostile_near(node.global_position)

	var decay := BASE_CARE_DECAY
	if exposed:
		decay *= EXPOSED_MULTIPLIER
	if hostile_near:
		decay *= 2.0
	var gain := COMPANY_BONUS if (near_shelter and player.stats.sheltered) else 0.0
	c.care = clampf(c.care - decay * delta + gain * delta, 0.0, 100.0)

	# Seguir a la mamá/papá si no está en el refugio (formación barata, sin pathfinding)
	if player.global_position.distance_to(node.global_position) < 18.0 and not near_shelter:
		var angle := TAU * float(index) / maxf(chicks.size(), 1.0)
		var target := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.4
		node.global_position = node.global_position.move_toward(target, FOLLOW_SPEED * delta)

	# Riesgo de pérdida
	if c.care < CARE_RISK_THRESHOLD:
		c.risk_time += delta
	else:
		c.risk_time = maxf(c.risk_time - delta * 2.0, 0.0)
	if c.risk_time >= RISK_SECONDS_TO_LOSE:
		_lose(c)


func _lose(c: Dictionary) -> void:
	var node: Node3D = c.node
	if _any_human_within(node.global_position, HUMAN_TAKE_RANGE):
		# Un humano la recoge con cuidado. Pérdida permanente, escena suave (la dispara el Main).
		c.state = ChickState.GONE
		node.visible = false
		chick_lost.emit(c.id, "taken_by_human")
	else:
		# Se aleja sola. Ventana para encontrarla.
		c.state = ChickState.LOST
		c.lost_timer = RECOVERY_WINDOW_SECONDS
		var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(30.0, 50.0)
		node.global_position += away
		chick_lost.emit(c.id, "wandered_off")


func _tick_lost(c: Dictionary, delta: float) -> void:
	c.lost_timer -= delta
	var node: Node3D = c.node
	if player.global_position.distance_to(node.global_position) < 2.0 and Input.is_action_just_pressed("interact"):
		c.state = ChickState.ACTIVE
		c.care = 40.0
		c.risk_time = 0.0
		chick_recovered.emit(c.id)
	elif c.lost_timer <= 0.0:
		c.state = ChickState.GONE
		node.visible = false
		chick_lost.emit(c.id, "taken_by_human")     # nadie la encontró: una persona la acoge


func _hostile_near(pos: Vector3) -> bool:
	for h in get_tree().get_nodes_in_group("humans"):
		if h is HumanNPC and h.kind == HumanNPC.Kind.HOSTILE and h.global_position.distance_to(pos) < HOSTILE_RANGE:
			return true
	return false


func _any_human_within(pos: Vector3, radius: float) -> bool:
	for h in get_tree().get_nodes_in_group("humans"):
		if h.global_position.distance_to(pos) < radius:
			return true
	return false


func active_count() -> int:
	var n := 0
	for c in chicks:
		if c.state == ChickState.ACTIVE:
			n += 1
	return n
