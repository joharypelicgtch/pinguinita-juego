extends Node3D
## Escena principal mínima: construye por código el árbol descrito en main.gd
## (luz, entorno, mundo, jugador, sistemas, HUD). Sirve para que el proyecto
## abra, compile y exporte desde el primer día. Cuando tengas escenas propias
## (.tscn), reemplaza esto por tu escena Main y borra este archivo.

const PICKUP_SCENE := preload("res://world/pickup.tscn")
const HUMAN_SCENE := preload("res://npc/human.tscn")

var _player: Pinguinita
var _label: Label


func _ready() -> void:
	var main := Node3D.new()
	main.name = "Main"
	main.set_script(load("res://world/main.gd"))

	# Luz única (con sombra) y entorno
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50.0
	main.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	main.add_child(world_env)

	# Mundo
	var world := WorldGenerator.new()
	world.name = "WorldGenerator"
	world.human_scene = HUMAN_SCENE
	world.pickup_scene = PICKUP_SCENE
	world.crumb_scene = PICKUP_SCENE
	main.add_child(world)

	# Jugador: cápsula + cámara en 3ª persona
	_player = Pinguinita.new()
	_player.name = "Pinguinita"
	_player.position = Vector3(0.0, 1.5, 0.0)
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 0.9
	col.shape = capsule
	col.position = Vector3(0, 0.45, 0)
	_player.add_child(col)

	var visual := Node3D.new()
	visual.name = "Visual"
	var body_mesh := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 0.9
	body_mesh.mesh = cm
	body_mesh.position = Vector3(0, 0.45, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.12)
	body_mesh.material_override = mat
	visual.add_child(body_mesh)
	_player.add_child(visual)

	var stats := SurvivalStats.new()
	stats.name = "SurvivalStats"
	_player.add_child(stats)

	var cam_pivot := Node3D.new()
	cam_pivot.name = "CamPivot"
	cam_pivot.position = Vector3(0, 1.0, 0)
	var arm := SpringArm3D.new()
	arm.spring_length = 4.0
	arm.add_excluded_object(_player.get_rid())
	var cam := Camera3D.new()
	arm.add_child(cam)
	cam_pivot.add_child(arm)
	_player.add_child(cam_pivot)
	main.add_child(_player)

	# Sistemas
	var building := BuildingSystem.new()
	building.name = "BuildingSystem"
	building.player = _player
	main.add_child(building)

	var partners := PartnerSystem.new()
	partners.name = "PartnerSystem"
	main.add_child(partners)

	var chicks := ChickManager.new()
	chicks.name = "ChickManager"
	chicks.player = _player
	main.add_child(chicks)

	# Enlaces exportados de Main
	main.set("sun", sun)
	main.set("world_env", world_env)
	main.set("world", world)
	main.set("player", _player)
	main.set("building", building)
	main.set("partners", partners)
	main.set("chicks", chicks)

	# El jugador espera (congelado) hasta que exista el suelo del bosque
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	world.zone_ready.connect(_on_zone_ready)

	# HUD mínimo
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12, 8)
	layer.add_child(_label)
	add_child(layer)

	add_child(main)


func _on_zone_ready(zone_name: String) -> void:
	if zone_name == "forest" and is_instance_valid(_player):
		_player.velocity = Vector3.ZERO
		_player.process_mode = Node.PROCESS_MODE_INHERIT


func _process(_delta: float) -> void:
	if _player == null or _label == null:
		return
	var s := _player.stats
	var inv := ""
	for k in _player.inventory:
		inv += "%s:%d  " % [k, _player.inventory[k]]
	_label.text = "Día %d   Salud %d  Hambre %d  Calor %d  Estrés %d\n%s\n[B] construir  [Esc] ratón" % [
		GameClock.day, s.health, s.hunger, s.warmth, s.stress, inv]
