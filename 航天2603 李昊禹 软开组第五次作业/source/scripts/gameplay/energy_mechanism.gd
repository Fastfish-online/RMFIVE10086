extends Node3D

const PLATE_SCRIPT = preload("res://scripts/gameplay/energy_plate.gd")
const PLATE_COUNT := 5

var rotor: Node3D
var plates: Array[AnimatableBody3D] = []
var sequence := [0, 3, 1, 4, 2]
var progress := 0
var cooldown := 0.0
var rotation_speed := 0.48


func get_game_controller() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("activate_energy_step"):
			return node
		node = node.get_parent()
	return null


func _ready() -> void:
	build_mechanism()
	set_current_plate()


func _physics_process(delta: float) -> void:
	if rotor:
		rotor.rotate_x(rotation_speed * delta)
	if cooldown > 0.0:
		cooldown -= delta
		if cooldown <= 0.0:
			progress = 0
			set_current_plate()


func make_material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.26
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


func build_mechanism() -> void:
	rotor = Node3D.new()
	rotor.name = "Rotor"
	add_child(rotor)
	var dark := make_material(Color("17202a"))
	var active := make_material(Color("ffbd28"), 4.0)
	var frame := make_material(Color("7d8790"))
	var cyan := make_material(Color("20d9e8"), 2.2)
	var backing := make_material(Color("0b1016"))

	# Layered back plate and segmented neon ring make the mechanism readable
	# from both the operator camera and the overview camera.
	var back := MeshInstance3D.new()
	var back_mesh := CylinderMesh.new()
	back_mesh.top_radius = 1.48
	back_mesh.bottom_radius = 1.48
	back_mesh.height = 0.12
	back_mesh.radial_segments = 32
	back.mesh = back_mesh
	back.position.x = 0.13
	back.rotation.z = PI / 2.0
	back.material_override = backing
	rotor.add_child(back)
	for ring_index in 20:
		var ring_angle := TAU * float(ring_index) / 20.0
		var segment := MeshInstance3D.new()
		var segment_mesh := BoxMesh.new()
		segment_mesh.size = Vector3(0.1, 0.1, 0.46)
		segment.mesh = segment_mesh
		segment.position = Vector3(-0.02, cos(ring_angle) * 1.58, sin(ring_angle) * 1.58)
		segment.rotation.x = -ring_angle
		segment.material_override = cyan if ring_index % 2 == 0 else frame
		rotor.add_child(segment)

	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.34
	hub_mesh.bottom_radius = 0.34
	hub_mesh.height = 0.42
	hub_mesh.radial_segments = 16
	hub.mesh = hub_mesh
	hub.rotation.z = PI / 2.0
	hub.material_override = frame
	rotor.add_child(hub)

	for i in PLATE_COUNT:
		var angle := TAU * float(i) / float(PLATE_COUNT)
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.1, 1.0, 0.1)
		arm.mesh = arm_mesh
		arm.position = Vector3(0.0, cos(angle) * 0.62, sin(angle) * 0.62)
		arm.rotation.x = -angle
		arm.material_override = frame
		rotor.add_child(arm)

		var plate := AnimatableBody3D.new()
		plate.name = "RunePlate%d" % i
		plate.set_script(PLATE_SCRIPT)
		plate.set("plate_index", i)
		plate.set("mechanism", self)
		plate.set("active_material", active)
		plate.set("inactive_material", dark)
		plate.position = Vector3(0.0, cos(angle) * 1.15, sin(angle) * 1.15)
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var plate_mesh := CylinderMesh.new()
		plate_mesh.top_radius = 0.31
		plate_mesh.bottom_radius = 0.31
		plate_mesh.height = 0.14
		plate_mesh.radial_segments = 6
		mesh.mesh = plate_mesh
		mesh.rotation.z = PI / 2.0
		plate.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.31
		# A generous depth is retained as a secondary physical fallback; the
		# bullet also performs exact world-space hex-target detection.
		shape.height = 0.5
		collision.shape = shape
		collision.rotation.z = PI / 2.0
		plate.add_child(collision)
		rotor.add_child(plate)
		plates.append(plate)


func set_current_plate() -> void:
	for i in plates.size():
		plates[i].call("set_active", cooldown <= 0.0 and i == sequence[progress])
	var game := get_game_controller()
	if game and game.has_method("energy_progress_changed"):
		game.energy_progress_changed(progress, PLATE_COUNT, cooldown)


func plate_hit(index: int, source_team: String) -> void:
	if cooldown > 0.0 or index != sequence[progress]:
		return
	var game := get_game_controller()
	if game and game.has_method("activate_energy_step"):
		game.activate_energy_step(source_team if source_team != "" else "red")
	progress += 1
	if game and game.has_method("energy_progress_changed"):
		game.energy_progress_changed(progress, PLATE_COUNT, 0.0)
	if progress >= PLATE_COUNT:
		cooldown = 45.0
		if game and game.has_method("activate_energy_buff"):
			game.activate_energy_buff(source_team if source_team != "" else "red", 30.0)
		progress = 0
	set_current_plate()
