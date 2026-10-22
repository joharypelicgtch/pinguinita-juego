class_name HumanNPC
extends CharacterBody3D
## Humano gigante de la ciudad. FSM simple, percepción a 5 Hz (barato).
## Violencia máxima: patada o empujón. Sin gore.
##
## Se mueve por una lista de waypoints (aceras). Sin NavMesh pesado.

enum Kind { INDIFFERENT, BENEVOLENT, HOSTILE }
enum State { WALK, SIDESTEP, DROP_FOOD, CHASE, KICK, COOLDOWN }

signal dropped_food(position: Vector3)

@export var kind: Kind = Kind.INDIFFERENT
@export var walk_speed: float = 1.6
@export var chase_speed: float = 3.2
@export var crumb_scene: PackedScene          # escena de migas (pickup "crumbs")

const SENSE_INTERVAL := 0.2                   # 5 Hz
const NOTICE_RANGE := 6.0
const KICK_RANGE := 1.3
const LOSE_INTEREST_RANGE := 10.0
const KICK_COOLDOWN := 2.5
const KICK_DAMAGE := 10.0                     # leve
const KICK_IMPULSE := 7.0

var waypoints: Array[Vector3] = []
var state: State = State.WALK

var _wp_index: int = 0
var _sense_timer: float = 0.0
var _state_timer: float = 0.0
var _player: Pinguinita
var _dist_to_player: float = 999.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _gave_food: bool = false


func _ready() -> void:
	add_to_group("humans")
	_player = get_tree().get_first_node_in_group("player") as Pinguinita


func _physics_process(delta: float) -> void:
	_sense_timer += delta
	if _sense_timer >= SENSE_INTERVAL:
		_sense_timer = 0.0
		_sense()

	_state_timer -= delta
	match state:
		State.WALK:      _do_walk(delta)
		State.SIDESTEP:  _do_sidestep(delta)
		State.DROP_FOOD: _do_drop_food()
		State.CHASE:     _do_chase(delta)
		State.KICK:      _do_kick()
		State.COOLDOWN:  _do_cooldown(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# --- Percepción (5 Hz) --------------------------------------------------------

func _sense() -> void:
	if _player == null:
		return
	_dist_to_player = global_position.distance_to(_player.global_position)

	match kind:
		Kind.INDIFFERENT:
			# Si la cría estorba, se aparta o la esquiva (empujón SIN daño)
			if state == State.WALK and _dist_to_player < 1.6:
				_set_state(State.SIDESTEP, 0.6)
		Kind.BENEVOLENT:
			if state == State.WALK and _dist_to_player < 4.0 and not _gave_food and randf() < 0.15:
				_set_state(State.DROP_FOOD, 0.8)
		Kind.HOSTILE:
			var hidden: bool = _player.stats.sheltered
			if state == State.WALK and _dist_to_player < NOTICE_RANGE and not hidden:
				_set_state(State.CHASE, 0.0)
				_player.stats.threat_nearby = true
			elif state == State.CHASE and (hidden or _dist_to_player > LOSE_INTEREST_RANGE):
				_player.stats.threat_nearby = false
				_set_state(State.WALK, 0.0)


func _set_state(new_state: State, duration: float) -> void:
	state = new_state
	_state_timer = duration


# --- Estados ------------------------------------------------------------------

func _do_walk(_delta: float) -> void:
	if waypoints.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var target := waypoints[_wp_index]
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.6:
		_wp_index = (_wp_index + 1) % waypoints.size()
		return
	_move_towards(to.normalized(), walk_speed)


func _do_sidestep(_delta: float) -> void:
	# Se aparta de la cría con un empujón suave (sin daño)
	if _player:
		var away := (_player.global_position - global_position)
		away.y = 0.0
		if away.length() < 1.6 and _state_timer > 0.3:
			_player.apply_hit(away.normalized() * 2.5 + Vector3.UP * 0.5, 0.0)
	velocity.x = 0.0
	velocity.z = 0.0
	if _state_timer <= 0.0:
		_set_state(State.WALK, 0.0)


func _do_drop_food() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _state_timer <= 0.0:
		_gave_food = true
		var pos := global_position + Vector3(0.4, 0.1, 0.4)
		dropped_food.emit(pos)
		if crumb_scene:
			var crumb := crumb_scene.instantiate() as Node3D
			get_parent().add_child(crumb)
			crumb.global_position = pos
		_set_state(State.WALK, 0.0)


func _do_chase(_delta: float) -> void:
	if _player == null:
		_set_state(State.WALK, 0.0)
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	if to.length() <= KICK_RANGE:
		_set_state(State.KICK, 0.25)   # pequeño "wind-up" para que el jugador reaccione
		return
	_move_towards(to.normalized(), chase_speed)


func _do_kick() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _state_timer <= 0.0:
		if _player and global_position.distance_to(_player.global_position) <= KICK_RANGE + 0.5:
			var dir := (_player.global_position - global_position)
			dir.y = 0.0
			_player.apply_hit(dir.normalized() * KICK_IMPULSE + Vector3.UP * 3.0, KICK_DAMAGE)
		_set_state(State.COOLDOWN, KICK_COOLDOWN)


func _do_cooldown(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _state_timer <= 0.0:
		if _player:
			_player.stats.threat_nearby = false   # el humano se va; la amenaza termina
		_set_state(State.WALK, 0.0)


func _move_towards(dir: Vector3, speed: float) -> void:
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.15)
