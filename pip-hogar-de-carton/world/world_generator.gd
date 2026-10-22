class_name WorldGenerator
extends Node3D
## Mundo aleatorio con límite. Misma semilla = mismo mapa. Nueva partida = mapa nuevo.
##  - Bosque (160x160 m): terreno por ruido, claro de inicio plano, árboles con jitter, recursos.
##  - Ciudad (160x160 m, a 220 m al este): manzanas con edificios/parques/solares sorteados.
##  - Cada zona cuelga de su propio nodo raíz para poder liberarla (unload_zone).
## Se generan por filas con `await` para no congelar el juego en PCs lentas.

signal zone_ready(zone_name: String)

const CELL := 2.0
const GRID := 80                         # 80 * 2 m = 160 m
const HALF := GRID * CELL * 0.5
const CITY_OFFSET := Vector3(220.0, 0.0, 0.0)
const BLOCKS := 6
const BLOCK_SIZE := 26.0
const MAX_PICKUPS_PER_ZONE := 140
const MAX_HUMANS := 12

@export var human_scene: PackedScene     # HumanNPC
@export var pickup_scene: PackedScene    # escena con propiedad `item_id` (String)
@export var crumb_scene: PackedScene

var world_seed: int = 0
var player_spawn: Vector3 = Vector3(0.0, 1.5, 0.0)
var city_built: bool = false
var forest_root: Node3D
var city_root: Node3D

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _sidewalk_loops: Array = []          # Array de PackedVector3Array (rutas de humanos)

const FOREST_LOOT := { "twig": 5.0, "leaf": 5.0, "cardboard": 1.0, "crumbs": 0.5, "special_twig": 0.25 }
const CITY_LOOT := { "cardboard": 4.0, "bottle_cap": 3.0, "cloth_scrap": 2.0, "trash": 3.0, "crumbs": 1.0 }


# ------------------------------------------------------------------ API pública

func generate(seed_value: int) -> void:
	world_seed = seed_value
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.02

	forest_root = Node3D.new()
	forest_root.name = "Forest"
	add_child(forest_root)

	await _build_forest_terrain()
	_build_connector()
	_scatter_trees()
	_scatter_pickups(forest_root, Vector3.ZERO, FOREST_LOOT, 110, 14.0)
	zone_ready.emit("forest")


func generate_city() -> void:
	if city_built:
		return
	city_built = true
	city_root = Node3D.new()
	city_root.name = "City"
	city_root.position = CITY_OFFSET
	add_child(city_root)

	_build_city_ground()
	await get_tree().process_frame
	_build_city_blocks()
	await get_tree().process_frame
	_scatter_pickups(city_root, CITY_OFFSET, CITY_LOOT, 90, 0.0, true)
	_spawn_humans()
	zone_ready.emit("city")


func unload_zone(root: Node3D) -> void:
	if root and is_instance_valid(root):
		root.queue_free()


func is_in_city(pos: Vector3) -> bool:
	return pos.x > CITY_OFFSET.x - HALF - 4.0


func height_at(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 6.0
	var clearing := smoothstep(6.0, 22.0, Vector2(x, z).length())   # claro de inicio plano
	var east_flat := 1.0 - smoothstep(55.0, 78.0, x)                # borde este plano (sendero)
	return h * clearing * east_flat


# ------------------------------------------------------------------ Bosque

func _build_forest_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gz in GRID:
		for gx in GRID:
			var x0 := gx * CELL - HALF
			var z0 := gz * CELL - HALF
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x0 + CELL, height_at(x0 + CELL, z0), z0)
			var p01 := Vector3(x0, height_at(x0, z0 + CELL), z0 + CELL)
			var p11 := Vector3(x0 + CELL, height_at(x0 + CELL, z0 + CELL), z0 + CELL)
			for v in [p00, p10, p01, p10, p11, p01]:
				st.set_color(_ground_color(v))
				st.add_vertex(v)
		if gz % 10 == 0:
			await get_tree().process_frame     # reparte la carga en varios frames
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vertex_material()
	forest_root.add_child(mi)
	mi.create_trimesh_collision()


func _ground_color(v: Vector3) -> Color:
	var t := clampf((v.y + 4.0) / 10.0, 0.0, 1.0)
	return Color("4f6b3a").lerp(Color("7a8a4a"), t) * Color(1, 1, 1).lerp(Color("a89070"), _rng.randf() * 0.15)


func _build_connector() -> void:
	## Sendero plano entre bosque (x=78) y ciudad (x=142).
	var body := StaticBody3D.new()
	body.position = Vector3((HALF - 2.0 + CITY_OFFSET.x - HALF + 2.0) * 0.5, -0.25, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var length := (CITY_OFFSET.x - HALF) - (HALF - 2.0)
	box.size = Vector3(length + 4.0, 0.5, 14.0)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.material_override = _flat_material(Color("8a7a60"))
	body.add_child(mesh)
	forest_root.add_child(body)


func _scatter_trees() -> void:
	var trunk_xf: Array[Transform3D] = []
	var crown_xf: Array[Transform3D] = []
	var step := 7.0
	var x := -HALF + 3.0
	while x < HALF - 3.0:
		var z := -HALF + 3.0
		while z < HALF - 3.0:
			var px := x + _rng.randf_range(-2.5, 2.5)
			var pz := z + _rng.randf_range(-2.5, 2.5)
			var dense := _noise.get_noise_2d(px * 3.0, pz * 3.0) > -0.25
			if px < 55.0 and Vector2(px, pz).length() > 14.0 and dense and _rng.randf() < 0.75:
				var s := _rng.randf_range(0.8, 1.4)
				var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
				var gy := height_at(px, pz)
				trunk_xf.append(Transform3D(basis, Vector3(px, gy + 1.0 * s, pz)))
				crown_xf.append(Transform3D(basis, Vector3(px, gy + 3.2 * s, pz)))
			z += step
		x += step

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18; trunk.bottom_radius = 0.25; trunk.height = 2.0
	trunk.radial_segments = 5; trunk.rings = 1
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0; crown.bottom_radius = 1.4; crown.height = 3.4
	crown.radial_segments = 6; crown.rings = 1
	forest_root.add_child(_multimesh(trunk, trunk_xf, Color("5b4330")))
	forest_root.add_child(_multimesh(crown, crown_xf, Color("2f5a34")))
	# Colisión de troncos: crear StaticBody3D+CylinderShape3D solo para árboles cercanos al
	# jugador (pool de ~30) en vez de uno por árbol. Ahorra mucha RAM/CPU.


func _scatter_pickups(root: Node3D, origin: Vector3, loot: Dictionary, count: int,
		min_dist: float, city: bool = false) -> void:
	if pickup_scene == null:
		return
	count = mini(count, MAX_PICKUPS_PER_ZONE)
	for i in count:
		var local := Vector3(_rng.randf_range(-HALF + 4.0, HALF - 4.0), 0.0,
				_rng.randf_range(-HALF + 4.0, HALF - 4.0))
		if Vector2(local.x, local.z).length() < min_dist:
			continue
		if not city and local.x > 55.0:
			continue
		var y := 0.15 if city else height_at(local.x, local.z) + 0.15
		var p := pickup_scene.instantiate() as Node3D
		p.set("item_id", _pick_weighted(loot))
		root.add_child(p)
		p.position = Vector3(local.x, y, local.z)


# ------------------------------------------------------------------ Ciudad

func _build_city_ground() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GRID * CELL, 1.0, GRID * CELL)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.material_override = _flat_material(Color("3b4150"))   # asfalto azulado
	body.add_child(mesh)
	city_root.add_child(body)


func _build_city_blocks() -> void:
	var b_xf: Array[Transform3D] = []
	var b_col: Array[Color] = []
	var slab_xf: Array[Transform3D] = []
	var start := -(BLOCKS * BLOCK_SIZE) * 0.5 + BLOCK_SIZE * 0.5
	var palette := [Color("6b7a8f"), Color("8c8070"), Color("7a6f78"), Color("5f7068"), Color("9a8c7a")]

	for bz in BLOCKS:
		for bx in BLOCKS:
			var center := Vector3(start + bx * BLOCK_SIZE, 0.0, start + bz * BLOCK_SIZE)
			var inner := BLOCK_SIZE - 8.0                       # 8 m de calle entre manzanas
			slab_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(inner, 0.2, inner)),
					center + Vector3(0, 0.1, 0)))

			# Ruta de humanos: perímetro de la acera
			var o := inner * 0.5 - 1.2
			_sidewalk_loops.append(PackedVector3Array([
				center + Vector3(-o, 0.2, -o), center + Vector3(o, 0.2, -o),
				center + Vector3(o, 0.2, o), center + Vector3(-o, 0.2, o)]))

			var roll := _rng.randf()
			if roll < 0.70:                                     # edificio
				var w := _rng.randf_range(10.0, inner - 2.0)
				var d := _rng.randf_range(10.0, inner - 2.0)
				var h := _rng.randf_range(8.0, 28.0)
				var pos := center + Vector3(_rng.randf_range(-1.0, 1.0), h * 0.5 + 0.2, _rng.randf_range(-1.0, 1.0))
				b_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, d)), pos))
				b_col.append(palette[_rng.randi() % palette.size()])
				_add_box_collider(pos, Vector3(w, h, d))
			# 0.70..0.90 parque / 0.90..1 solar: se dejan vacíos (aquí van árboles pequeños, bancos...)

	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	city_root.add_child(_multimesh(unit, slab_xf, Color("8a8d94")))
	city_root.add_child(_multimesh(unit, b_xf, Color.WHITE, b_col))


func _add_box_collider(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	city_root.add_child(body)


func _spawn_humans() -> void:
	if human_scene == null or _sidewalk_loops.is_empty():
		return
	for i in MAX_HUMANS:
		var loop: PackedVector3Array = _sidewalk_loops[_rng.randi() % _sidewalk_loops.size()]
		var h := human_scene.instantiate() as HumanNPC
		var roll := _rng.randf()
		h.kind = HumanNPC.Kind.INDIFFERENT if roll < 0.70 \
			else (HumanNPC.Kind.BENEVOLENT if roll < 0.85 else HumanNPC.Kind.HOSTILE)
		h.crumb_scene = crumb_scene
		var wps: Array[Vector3] = []
		for p in loop:
			wps.append(p + CITY_OFFSET)
		h.waypoints = wps
		city_root.add_child(h)
		h.global_position = wps[_rng.randi() % wps.size()] + Vector3(0, 0.5, 0)


# ------------------------------------------------------------------ Utilidades

func _multimesh(mesh: Mesh, xforms: Array[Transform3D], color: Color,
		colors: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := _flat_material(color)
	mat.vertex_color_use_as_albedo = mm.use_colors
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # sombras baratas: apagadas
	return mmi


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m


func _vertex_material() -> StandardMaterial3D:
	var m := _flat_material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	return m


func _pick_weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := _rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[0]
