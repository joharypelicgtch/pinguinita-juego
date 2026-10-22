class_name Pinguinita
extends CharacterBody3D
## Jugador: WASD + ratón, cámara en 3ª persona orbital con SpringArm3D.
##
## Estructura de escena esperada:
##   Pinguinita (CharacterBody3D) [este script]
##   ├─ CollisionShape3D
##   ├─ Visual (Node3D con la malla chibi)
##   ├─ SurvivalStats (Node) [survival_stats.gd]
##   └─ CamPivot (Node3D)
##       └─ SpringArm3D (spring_length = 4.0)
##           └─ Camera3D

signal item_collected(item_id: String, amount: int)
signal hit_received(damage: float)

@export var walk_speed: float = 3.5
@export var run_speed: float = 5.5
@export var jump_velocity: float = 4.2
@export var mouse_sensitivity: float = 0.003
@export var turn_speed: float = 10.0

@onready var cam_pivot: Node3D = $CamPivot
@onready var visual: Node3D = $Visual
@onready var stats: SurvivalStats = $SurvivalStats

var inventory: Dictionary = {}       # { "twig": 3, "leaf": 5, ... }
var build_mode: bool = false         # lo cambia el BuildingSystem

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch: float = -0.25
var _knockback: Vector3 = Vector3.ZERO


func _ready() -> void:
	_ensure_input_map()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stats.fainted.connect(_on_fainted)
	add_to_group("player")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.2, 0.4)
		cam_pivot.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw := cam_pivot.global_rotation.y
	var dir := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed

	# Hambre/frío bajos = más lenta (feedback sin números en pantalla)
	if stats.warmth < 25.0 or stats.hunger < 15.0:
		speed *= 0.7

	velocity.x = dir.x * speed + _knockback.x
	velocity.z = dir.z * speed + _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, 14.0 * delta)

	move_and_slide()

	if dir.length() > 0.1:
		var target := atan2(dir.x, dir.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target, turn_speed * delta)
		# Andar de pingüino: balanceo barato sin animaciones pesadas
		visual.rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.12
	else:
		visual.rotation.z = lerpf(visual.rotation.z, 0.0, 8.0 * delta)


# --- Interacción con humanos --------------------------------------------------

## Empujón/patada: impulso + daño leve. Sin gore, sin muerte.
func apply_hit(impulse: Vector3, damage: float) -> void:
	_knockback = Vector3(impulse.x, 0.0, impulse.z)
	velocity.y = maxf(impulse.y, velocity.y)
	if damage > 0.0:
		stats.damage(damage)
		hit_received.emit(damage)
	AudioManager.play_sfx("soft_hit", global_position)


# --- Inventario --------------------------------------------------------------

func add_item(item_id: String, amount: int = 1) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + amount
	item_collected.emit(item_id, amount)
	AudioManager.play_sfx("pickup", global_position)


func has_items(cost: Dictionary) -> bool:
	for k in cost:
		if inventory.get(k, 0) < cost[k]:
			return false
	return true


func spend_items(cost: Dictionary) -> bool:
	if not has_items(cost):
		return false
	for k in cost:
		inventory[k] -= cost[k]
	return true


func _on_fainted() -> void:
	## Lo resuelve Main (mueve al refugio, avanza el reloj, pierde parte del inventario).
	get_tree().call_group("main", "on_player_fainted", self)


# --- Mapa de entradas por código (plug & play, sin tocar Project Settings) ----

func _ensure_input_map() -> void:
	_key("move_forward", KEY_W); _key("move_back", KEY_S)
	_key("move_left", KEY_A); _key("move_right", KEY_D)
	_key("run", KEY_SHIFT); _key("jump", KEY_SPACE)
	_key("interact", KEY_E); _key("build_toggle", KEY_B)
	_key("build_rotate_left", KEY_Q); _key("build_rotate_right", KEY_E)
	_mouse("place", MOUSE_BUTTON_LEFT); _mouse("cancel", MOUSE_BUTTON_RIGHT)


func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
