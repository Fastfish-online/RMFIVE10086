extends AnimatableBody3D

var plate_index := 0
var mechanism: Node
var active_plate := false
var active_material: Material
var inactive_material: Material


func _ready() -> void:
	add_to_group("energy_plates")


func set_active(value: bool) -> void:
	active_plate = value
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.material_override = active_material if value else inactive_material


func take_damage(_amount: int, source_team: String = "") -> void:
	if active_plate and mechanism and mechanism.has_method("plate_hit"):
		active_plate = false
		var mesh := get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.material_override = inactive_material
		mechanism.plate_hit(plate_index, source_team)


func is_current_target() -> bool:
	return active_plate
