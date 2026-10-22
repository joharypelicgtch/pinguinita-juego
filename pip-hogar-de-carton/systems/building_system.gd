class_name BuildingSystem
extends Node3D
## Construcción libre con imanes (sockets cara-con-cara) + integridad + derrumbes.
##
## Controles: B = modo construcción, rueda = cambiar pieza, Q/E = girar 90°,
##            clic izq. = colocar, clic der. = cancelar, E (fuera del modo) = reparar pieza cercana.
##
## Cada pieza tiene 6 sockets (centro de cada cara). El fantasma se imanta cuando uno de sus
## sockets queda a < SNAP_DISTANCE de un socket de OTRA pieza con la normal opuesta.

signal piece_placed(piece: Node3D)
signal piece_destroyed(piece_id: String)
signal shelter_tier_changed(tier: int)

const SNAP_DISTANCE := 0.6
const PLACE_REACH := 9.0
const RAIN_WEAR_PER_SEC := 0.15          # el cartón se moja y se desgasta
const SHELTER_POLL_INTERVAL := 0.5

# tier 1 = cartón, 2 = madera/tela, 3 = reforzado
const PIECES := {
	"cardboard_box": { "cost": {"cardboard": 2, "leaf": 2}, "size": Vector3(1.6, 1.1, 1.6),
		"hp": 30.0, "tier": 1, "shelter": true, "solid": false, "color": Color("b08a5a"), "repair": "cardboard" },
	"cardboard_panel": { "cost": {"cardboard": 1}, "size": Vector3(1.4, 1.0, 0.1),
		"hp": 25.0, "tier": 1, "shelter": false, "solid": true, "color": Color("a67f50"), "repair": "cardboard" },
	"twig_wall": { "cost": {"twig": 4, "leaf": 1}, "size": Vector3(1.4, 1.1, 0.15),
		"hp": 80.0, "tier": 2, "shelter": false, "solid": true, "color": Color("6a4e34"), "repair": "twig" },
	"cloth_roof": { "cost": {"cloth_scrap": 2, "twig": 2}, "size": Vector3(1.8, 0.1, 1.8),
		"hp": 60.0, "tier": 2, "shelter": true, "solid": false, "color": Color("a9556a"), "repair": "cloth_scrap" },
	"cap_roof": { "cost": {"bottle_cap": 6, "cloth_scrap": 1}, "size": Vector3(1.8, 0.12, 1.8),
		"hp": 140.0, "tier": 3, "shelter": true, "solid": false, "color": Color("4a90c2"), "repair": "bottle_cap" },
}

@export var player: Pinguinita

var _build_mode: bool = false
var _ids: Array = PIECES.keys()
var _index: int = 0
var _yaw: float = 0.0
var _ghost: MeshInstance3D
var _ghost_valid: bool = false
var _poll_timer: float = 0.0
var _last_tier: int = 0


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.visible = false
	add_child(_ghost)
	WeatherManager.tragedy.connect(_on_tragedy)
	_refresh_ghost_mesh()


func _process(delta: float) -> void:
	if _build_mode:
		_update_ghost()

	_poll_timer += delta
	if _poll_timer >= SHELTER_POLL_INTERVAL:
		_poll_timer = 0.0
		_update_shelter_state()
		_apply_rain_wear(SHELTER_POLL_INTERVAL)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_toggle"):
		_set_build_mode(not _build_mode)
		return
	if _build_mode:
		if event.is_action_pressed("build_rotate_left"):
			_yaw -= PI * 0.5
		elif event.is_action_pressed("build_rotate_right"):
			_yaw += PI * 0.5
		elif event.is_action_pressed("place") and _ghost_valid:
			_place()
		elif event.is_action_pressed("cancel"):
			_set_build_mode(false)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cycle(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cycle(-1)
	elif event.is_action_pressed("interact"):
		_try_repair()


# ------------------------------------------------------------------ Fantasma / colocación

func _set_build_mode(on: bool) -> void:
	_build_mode = on
	player.build_mode = on
	_ghost.visible = on and _ghost_valid


func _cycle(dir: int) -> void:
	_index = (_index + dir + _ids.size()) % _ids.size()
	_refresh_ghost_mesh()


func _refresh_ghost_mesh() -> void:
	var def: Dictionary = PIECES[_ids[_index]]
	var bm := BoxMesh.new()
	bm.size = def.size
	_ghost.mesh = bm


func _update_ghost() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var to := from + cam.project_ray_normal(center) * 14.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_ghost_valid = false
		_ghost.visible = false
		return

	var def: Dictionary = PIECES[_ids[_index]]
	var pos: Vector3 = hit.position + Vector3.UP * (def.size.y * 0.5)
	_yaw = fposmod(_yaw, TAU)
	pos = _apply_snap(pos, def.size)
	_ghost.global_position = pos
	_ghost.rotation.y = _yaw
	_ghost.visible = true

	_ghost_valid = player.has_items(def.cost) and player.global_position.distance_to(pos) < PLACE_REACH
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 1.0, 0.4, 0.5) if _ghost_valid else Color(1.0, 0.3, 0.3, 0.5)
	_ghost.material_override = mat


func _sockets_for(size: Vector3) -> Array:
	var h := size * 0.5
	return [
		{ "p": Vector3(h.x, 0, 0), "n": Vector3.RIGHT }, { "p": Vector3(-h.x, 0, 0), "n": Vector3.LEFT },
		{ "p": Vector3(0, h.y, 0), "n": Vector3.UP },    { "p": Vector3(0, -h.y, 0), "n": Vector3.DOWN },
		{ "p": Vector3(0, 0, h.z), "n": Vector3.BACK },  { "p": Vector3(0, 0, -h.z), "n": Vector3.FORWARD },
	]


func _apply_snap(pos: Vector3, size: Vector3) -> Vector3:
	var rot := Basis(Vector3.UP, _yaw)
	var best := SNAP_DISTANCE
	var offset := Vector3.ZERO
	for s in _sockets_for(size):
		var wp: Vector3 = pos + rot * s.p
		var wn: Vector3 = rot * s.n
		for piece in get_tree().get_nodes_in_group("pieces"):
			for o in piece.get_meta("sockets_world"):
				if wn.dot(o.n) > -0.9:          # solo cara contra cara (normales opuestas)
					continue
				var d := wp.distance_to(o.p)
				if d < best:
					best = d
					offset = o.p - wp
	return pos + offset


func _place() -> void:
	var id: String = _ids[_index]
	var def: Dictionary = PIECES[id]
	if not player.spend_items(def.cost):
		return

	var piece := Node3D.new()
	piece.name = id
	piece.global_transform = Transform3D(Basis(Vector3.UP, _yaw), _ghost.global_position)
	piece.add_to_group("pieces")
	piece.set_meta("id", id)
	piece.set_meta("hp", def.hp)
	piece.set_meta("max_hp", def.hp)
	piece.set_meta("tier", def.tier)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = def.size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_child(mesh)

	if def.solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = def.size
		cs.shape = shape
		body.add_child(cs)
		piece.add_child(body)

	if def.shelter:
		var area := Area3D.new()
		area.name = "ShelterArea"
		area.collision_layer = 0
		area.collision_mask = 1
		var acs := CollisionShape3D.new()
		var ashape := BoxShape3D.new()
		ashape.size = Vector3(def.size.x, 1.2, def.size.z)
		acs.shape = ashape
		acs.position = Vector3(0, 0.1, 0)
		area.add_child(acs)
		piece.add_child(area)

	add_child(piece)
	piece.global_position = _ghost.global_position
	piece.rotation.y = _yaw

	# Sockets en coordenadas de mundo (la pieza es estática, se calculan una vez)
	var rot := Basis(Vector3.UP, _yaw)
	var sw: Array = []
	for s in _sockets_for(def.size):
		sw.append({ "p": piece.global_position + rot * s.p, "n": rot * s.n })
	piece.set_meta("sockets_world", sw)

	AudioManager.play_sfx("place_piece", piece.global_position)
	piece_placed.emit(piece)


# ------------------------------------------------------------------ Integridad / tragedias

func _apply_rain_wear(dt: float) -> void:
	if not WeatherManager.is_raining():
		return
	for piece in get_tree().get_nodes_in_group("pieces"):
		if piece.get_meta("tier") == 1:         # el cartón se moja y cede
			_damage_piece(piece, RAIN_WEAR_PER_SEC * dt * 10.0 * WeatherManager.intensity())


func _on_tragedy(kind: String) -> void:
	if kind != "storm":
		return
	for piece in get_tree().get_nodes_in_group("pieces"):
		var dmg := 40.0 if piece.get_meta("tier") == 1 else (30.0 if piece.get_meta("tier") == 2 else 15.0)
		_damage_piece(piece, dmg * randf_range(0.6, 1.2))


func _damage_piece(piece: Node3D, amount: float) -> void:
	var hp: float = piece.get_meta("hp") - amount
	piece.set_meta("hp", hp)
	if hp <= 0.0:
		AudioManager.play_sfx("collapse", piece.global_position)
		piece_destroyed.emit(piece.get_meta("id"))
		piece.remove_from_group("pieces")
		piece.queue_free()
	else:
		AudioManager.play_sfx("cardboard_creak", piece.global_position)


func _try_repair() -> void:
	var best: Node3D = null
	var best_d := 2.5
	for piece in get_tree().get_nodes_in_group("pieces"):
		var d := player.global_position.distance_to(piece.global_position)
		if d < best_d and piece.get_meta("hp") < piece.get_meta("max_hp"):
			best = piece
			best_d = d
	if best == null:
		return
	var mat_id: String = PIECES[best.get_meta("id")].repair
	if player.spend_items({ mat_id: 1 }):
		best.set_meta("hp", best.get_meta("max_hp"))
		AudioManager.play_sfx("place_piece", best.global_position)


# ------------------------------------------------------------------ Estado del refugio

func _update_shelter_state() -> void:
	var inside := false
	var quality := 1.0
	var tier_max := 0
	for piece in get_tree().get_nodes_in_group("pieces"):
		var t: int = piece.get_meta("tier")
		if PIECES[piece.get_meta("id")].shelter:
			tier_max = maxi(tier_max, t)
			var area := piece.get_node_or_null("ShelterArea") as Area3D
			if area and player in area.get_overlapping_bodies():
				inside = true
				quality = maxf(quality, 0.5 + t * 0.5)    # 1.0 cartón .. 2.0 reforzado
	player.stats.sheltered = inside
	player.stats.shelter_quality = quality
	if tier_max != _last_tier:
		_last_tier = tier_max
		shelter_tier_changed.emit(tier_max)


func get_shelter_tier() -> int:
	return _last_tier


func nearest_shelter_position(from: Vector3) -> Variant:
	var best: Variant = null
	var best_d := INF
	for piece in get_tree().get_nodes_in_group("pieces"):
		if PIECES[piece.get_meta("id")].shelter:
			var d := from.distance_to(piece.global_position)
			if d < best_d:
				best_d = d
				best = piece.global_position
	return best
