class_name Pickup
extends Area3D
## Recurso recogible. Se construye solo (malla + colisión), así la escena es mínima.
## Al tocarlo la Pinguinita, lo añade al inventario.

@export var item_id: String = "crumbs"

const COLORS := {
	"twig": Color("6a4e34"), "leaf": Color("5a9a45"), "cardboard": Color("b08a5a"),
	"crumbs": Color("e8d8a0"), "special_twig": Color("e0b030"), "bottle_cap": Color("4a90c2"),
	"cloth_scrap": Color("a9556a"), "trash": Color("7a7a80"),
}


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.3, 0.3)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(item_id, Color.WHITE)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Pinguinita:
		body.add_item(item_id, 1)
		queue_free()
