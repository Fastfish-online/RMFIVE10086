extends Node3D

const TARGET_SCRIPT = preload("res://scripts/gameplay/damageable_target.gd")
const SUPPLY_SCRIPT = preload("res://scripts/gameplay/supply_zone.gd")
const ENERGY_SCRIPT = preload("res://scripts/gameplay/energy_mechanism.gd")
const ARMOR_HITBOX_SCRIPT = preload("res://scripts/gameplay/armor_hitbox.gd")

# RMUC 2023 full-field training map.
# Overall dimensions and module families follow the official rulebook. The
# polygonal layout is reconstructed for simulation from the supplied overhead
# reference; it is not a replacement for DJI fabrication CAD.

const RED := Color("ff4d57")
const RED_DARK := Color("68151d")
const BLUE := Color("21d8e6")
const BLUE_DARK := Color("0b5367")
const FLOOR := Color("171b20")
const PLATFORM := Color("4b535b")
const PLATFORM_TOP := Color("69727a")
const STEEL := Color("a5adb5")
const WHITE := Color("e5edf2")
const YELLOW := Color("ffba2f")

var overview_camera: Camera3D
var player_camera: Camera3D


func _ready() -> void:
	build_field()
	player_camera = get_node_or_null("../Infantry/GimbalYaw/GimbalPitch/Aimcamera")
	overview_camera = Camera3D.new()
	overview_camera.name = "OverviewCamera"
	overview_camera.position = Vector3(0.0, 19.5, 15.5)
	overview_camera.fov = 58.0
	add_child(overview_camera)
	overview_camera.look_at(Vector3.ZERO, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if overview_camera.is_current():
			if player_camera:
				player_camera.make_current()
		else:
			overview_camera.make_current()


func material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.82
	result.metallic = 0.08
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = emission
	return result


func add_box(name: String, position: Vector3, size: Vector3, color: Color, rotation := Vector3.ZERO, collision := true) -> Node3D:
	var root: Node3D
	if collision:
		root = StaticBody3D.new()
	else:
		root = Node3D.new()
	root.name = name
	root.position = position
	root.rotation = rotation
	add_child(root)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material(color)
	root.add_child(mesh_instance)
	if collision:
		var collision_shape := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision_shape.shape = shape
		root.add_child(collision_shape)
	return root


func add_cylinder(name: String, position: Vector3, radius: float, height: float, color: Color, sides := 12) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = position
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = sides
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = material(color)
	body.add_child(mesh_instance)
	var collision_shape := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body


func add_prism(name: String, polygon: PackedVector2Array, height: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	add_child(body)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_y := height
	# Fan triangulation; supplied polygons are convex or gently notched.
	for i in range(1, polygon.size() - 1):
		for index in [0, i + 1, i]:
			var p := polygon[index]
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(p.x, top_y, p.y))
		for index in [0, i, i + 1]:
			var p := polygon[index]
			surface.set_normal(Vector3.DOWN)
			surface.add_vertex(Vector3(p.x, 0.0, p.y))
	for i in polygon.size():
		var next := (i + 1) % polygon.size()
		var a := polygon[i]
		var b := polygon[next]
		var normal := Vector3(b.y - a.y, 0.0, a.x - b.x).normalized()
		for vertex in [Vector3(a.x, 0.0, a.y), Vector3(b.x, top_y, b.y), Vector3(a.x, top_y, a.y), Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y), Vector3(b.x, top_y, b.y)]:
			surface.set_normal(normal)
			surface.add_vertex(vertex)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = material(color)
	body.add_child(mesh_instance)

	var points := PackedVector3Array()
	for p in polygon:
		points.append(Vector3(p.x, 0.0, p.y))
		points.append(Vector3(p.x, top_y, p.y))
	var collision_shape := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body


func add_wedge_ramp(name: String, low_center: Vector3, high_center: Vector3, width: float, color: Color) -> StaticBody3D:
	# A true wedge eliminates both end faces above the traversable surface. The
	# low edge sits below the floor and the high edge is exactly deck height.
	var body := StaticBody3D.new()
	body.name = name
	add_child(body)
	var direction := Vector3(high_center.x - low_center.x, 0.0, high_center.z - low_center.z).normalized()
	# Overlap both neighbouring surfaces. Exact coplanar seams can still expose a
	# collision edge, especially after the field is non-uniformly scaled.
	low_center -= direction * 0.18
	high_center += direction * 0.32
	low_center.y = -0.08
	high_center.y += 0.025
	var side := Vector3(-direction.z, 0.0, direction.x) * width * 0.5
	var bottom_y := -0.24
	var points := PackedVector3Array([
		low_center - side, low_center + side, high_center + side, high_center - side,
		Vector3(low_center.x - side.x, bottom_y, low_center.z - side.z),
		Vector3(low_center.x + side.x, bottom_y, low_center.z + side.z),
		Vector3(high_center.x + side.x, bottom_y, high_center.z + side.z),
		Vector3(high_center.x - side.x, bottom_y, high_center.z - side.z)
	])
	var triangles := PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		4, 6, 5, 4, 7, 6,
		0, 4, 5, 0, 5, 1,
		3, 2, 6, 3, 6, 7,
		0, 3, 7, 0, 7, 4,
		1, 5, 6, 1, 6, 2
	])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		surface.add_vertex(points[index])
	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = material(color)
	body.add_child(mesh_instance)
	var collision_shape := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body


func regular_polygon(center: Vector2, radius: float, sides: int, angle_offset := 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in sides:
		var angle := angle_offset + TAU * float(i) / float(sides)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result


func add_glow_strip(name: String, position: Vector3, size: Vector3, color: Color, rotation := Vector3.ZERO) -> void:
	var node := add_box(name, position, size, color, rotation, false)
	var mesh_instance := node.get_child(0) as MeshInstance3D
	mesh_instance.material_override = material(color, 2.3)


func add_guardrail(name: String, start: Vector3, finish: Vector3, color: Color) -> void:
	var delta := finish - start
	var length := Vector2(delta.x, delta.z).length()
	var midpoint := (start + finish) * 0.5
	var angle := atan2(delta.x, delta.z)
	add_box(name + "Top", midpoint + Vector3.UP * 0.46, Vector3(0.075, 0.07, length), color, Vector3(0.0, angle, 0.0), false)
	var post_count := maxi(2, int(length / 0.8) + 1)
	for i in post_count:
		var t := float(i) / float(post_count - 1)
		var point := start.lerp(finish, t)
		add_box(name + "Post%d" % i, point + Vector3.UP * 0.25, Vector3(0.065, 0.5, 0.065), color, Vector3.ZERO, false)


func add_floor_graphics() -> void:
	# Thin geometry is used like painted decals, keeping the project asset-free.
	for x in range(-12, 13, 2):
		add_box("GridX%d" % x, Vector3(float(x), 0.008, 0.0), Vector3(0.018, 0.012, 14.2), Color("293139"), Vector3.ZERO, false)
	for z in range(-6, 7, 2):
		add_box("GridZ%d" % z, Vector3(0.0, 0.009, float(z)), Vector3(27.0, 0.012, 0.018), Color("293139"), Vector3.ZERO, false)

	# Broadcast-reference style white route outlines and center technical motif.
	for z in [-5.9, 5.9]:
		add_box("LaneInner%.1f" % z, Vector3(0.0, 0.018, z), Vector3(25.5, 0.022, 0.055), WHITE, Vector3.ZERO, false)
	for x in [-12.6, 12.6]:
		add_box("SideMark%.1f" % x, Vector3(x, 0.018, 0.0), Vector3(0.055, 0.022, 11.5), WHITE, Vector3.ZERO, false)
	for i in 5:
		var radius := 1.0 + float(i) * 0.34
		var segments := 20
		for j in segments:
			var a := TAU * float(j) / float(segments)
			var p := Vector3(cos(a) * radius, 0.023, sin(a) * radius)
			add_box("CenterArc%d_%d" % [i, j], p, Vector3(0.12, 0.018, 0.035), Color("65717b"), Vector3(0.0, -a, 0.0), false)

	# Large H-shaped base markings visible from the overview camera.
	for sign in [-1.0, 1.0]:
		var accent := RED if sign < 0.0 else BLUE
		var center := Vector3(11.4 * sign, 0.545, 4.65 * sign)
		add_glow_strip("BaseHLeft%s" % sign, center + Vector3(-0.34, 0.0, 0.0), Vector3(0.11, 0.018, 0.85), accent)
		add_glow_strip("BaseHRight%s" % sign, center + Vector3(0.34, 0.0, 0.0), Vector3(0.11, 0.018, 0.85), accent)
		add_glow_strip("BaseHBar%s" % sign, center, Vector3(0.68, 0.018, 0.11), accent)


func add_target(name: String, position: Vector3, target_type: String, team_name: String, color: Color, health: int, rotation_speed := 0.0) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = name
	body.position = position
	body.set_script(TARGET_SCRIPT)
	body.set("target_type", target_type)
	body.set("team", team_name)
	body.set("max_health", health)
	body.set("rotate_speed", rotation_speed)

	var core_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5 if target_type == "base" else 0.42
	cylinder.bottom_radius = cylinder.top_radius
	cylinder.height = 1.5 if target_type == "base" else 1.1
	cylinder.radial_segments = 10
	core_mesh.mesh = cylinder
	core_mesh.material_override = material(color)
	body.add_child(core_mesh)

	# The core is visual only. Only these four armor bodies accept damage, which
	# matches RoboMaster's armor-module hit detection.
	for i in 4:
		var armor_body := StaticBody3D.new()
		armor_body.name = "ArmorHitbox%d" % i
		armor_body.set_script(ARMOR_HITBOX_SCRIPT)
		armor_body.set("target", body)
		armor_body.rotation.y = i * PI / 2.0
		armor_body.position = Vector3(sin(armor_body.rotation.y) * 0.51, 0.0, cos(armor_body.rotation.y) * 0.51)
		var armor := MeshInstance3D.new()
		var armor_mesh := BoxMesh.new()
		armor_mesh.size = Vector3(0.48, 0.24, 0.065)
		armor.mesh = armor_mesh
		armor.material_override = material(color, 2.0)
		armor_body.add_child(armor)
		var armor_collision := CollisionShape3D.new()
		var armor_shape := BoxShape3D.new()
		armor_shape.size = Vector3(0.5, 0.26, 0.08)
		armor_collision.shape = armor_shape
		armor_body.add_child(armor_collision)
		body.add_child(armor_body)
	add_child(body)
	return body


func add_supply_zone(name: String, position: Vector3, team_name: String, color: Color) -> Area3D:
	var area := Area3D.new()
	area.name = name
	area.position = position
	area.set_script(SUPPLY_SCRIPT)
	area.set("team", team_name)
	var collision_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.0, 1.5)
	collision_shape.shape = shape
	collision_shape.position.y = 0.5
	area.add_child(collision_shape)
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(2.2, 0.06, 1.5)
	pad.mesh = pad_mesh
	pad.material_override = material(color, 1.4)
	area.add_child(pad)
	add_child(area)
	return area


func add_team_half(prefix: String, sign: float, accent: Color, dark: Color) -> void:
	# Base region: clipped octagonal platform close to the short boundary.
	var base_center := Vector2(11.4 * sign, 4.65 * sign)
	add_prism(prefix + "BaseDeck", regular_polygon(base_center, 2.05, 8, PI / 8.0), 0.32, PLATFORM_TOP)
	add_prism(prefix + "BasePad", regular_polygon(base_center, 1.05, 6, PI / 6.0), 0.52, dark)
	add_glow_strip(prefix + "BaseGlow", Vector3(base_center.x, 0.57, base_center.y), Vector3(1.25, 0.08, 0.08), accent, Vector3(0.0, sign * PI / 4.0, 0.0))

	# Raised zig-zag highway closely matching the long elevated side lanes.
	var road := PackedVector2Array([
		Vector2(13.8 * sign, -6.8 * sign), Vector2(7.0 * sign, -6.8 * sign),
		Vector2(6.0 * sign, -5.7 * sign), Vector2(6.0 * sign, -3.5 * sign),
		Vector2(8.1 * sign, -2.4 * sign), Vector2(10.7 * sign, -2.4 * sign),
		Vector2(11.6 * sign, -1.1 * sign), Vector2(13.8 * sign, -1.1 * sign)
	])
	add_prism(prefix + "Highway", road, 0.58, PLATFORM_TOP)
	add_glow_strip(prefix + "HighwayEdge", Vector3(9.9 * sign, 0.63, -6.78 * sign), Vector3(7.4, 0.07, 0.08), accent)

	# Trapezoid highlands and access ramps.
	var highland := PackedVector2Array([
		Vector2(5.8 * sign, -2.2 * sign), Vector2(3.3 * sign, -1.8 * sign),
		Vector2(2.7 * sign, -3.3 * sign), Vector2(3.8 * sign, -4.5 * sign),
		Vector2(6.1 * sign, -4.0 * sign)
	])
	add_prism(prefix + "TrapezoidHighland", highland, 0.92, PLATFORM)
	add_wedge_ramp(
		prefix + "HighlandRamp",
		Vector3(4.7 * sign, -0.06, -6.05 * sign),
		Vector3(4.7 * sign, 0.92, -3.55 * sign),
		2.4,
		PLATFORM_TOP
	)
	add_glow_strip(prefix + "HighlandGlow", Vector3(4.65 * sign, 0.98, -2.08 * sign), Vector3(2.2, 0.08, 0.08), accent)

	# Outpost and rough-road blocks in the open field.
	add_glow_strip(prefix + "OutpostGlow", Vector3(7.4 * sign, 1.48, 0.65 * sign), Vector3(1.0, 0.07, 0.07), accent)
	for i in 3:
		add_box(prefix + "RoughRoad%d" % i, Vector3((9.0 + i * 1.05) * sign, 0.18 + (i % 2) * 0.08, -0.45 * sign), Vector3(0.82, 0.35, 1.4), PLATFORM, Vector3(0.0, 0.0, deg_to_rad(5.0 * sign)))

	# Small hex resource island.
	var island_center := Vector2(3.9 * sign, 1.45 * sign)
	add_prism(prefix + "SmallResourceIsland", regular_polygon(island_center, 1.05, 6, PI / 6.0), 0.55, PLATFORM_TOP)
	add_glow_strip(prefix + "IslandGlow", Vector3(island_center.x, 0.61, island_center.y), Vector3(1.15, 0.06, 0.08), accent, Vector3(0.0, PI / 3.0, 0.0))

	# Spawn/repair markings.
	add_prism(prefix + "SpawnZone", regular_polygon(Vector2(10.8 * sign, 3.95 * sign), 1.25, 6, PI / 6.0), 0.035, Color(accent.r, accent.g, accent.b, 0.72))


func build_field() -> void:
	# 28 x 15 m official full-field footprint.
	add_box("ArenaFloor", Vector3(0.0, -0.13, 0.0), Vector3(28.0, 0.25, 15.0), FLOOR)
	# Thin perimeter with 2.4 m collision, rendered dark so the field remains visible.
	add_box("NorthFence", Vector3(0.0, 1.2, -7.48), Vector3(28.0, 2.4, 0.12), Color("252b31"))
	add_box("SouthFence", Vector3(0.0, 1.2, 7.48), Vector3(28.0, 2.4, 0.12), Color("252b31"))
	add_box("WestFence", Vector3(-13.94, 1.2, 0.0), Vector3(0.12, 2.4, 15.0), Color("252b31"))
	add_box("EastFence", Vector3(13.94, 1.2, 0.0), Vector3(0.12, 2.4, 15.0), Color("252b31"))
	add_floor_graphics()

	# Center-symmetric red and blue halves.
	add_team_half("Red", -1.0, RED, RED_DARK)
	add_team_half("Blue", 1.0, BLUE, BLUE_DARK)

	# Central resource island: split-color, raised, climbable complex.
	var center_left := PackedVector2Array([
		Vector2(-3.0, -1.65), Vector2(0.0, -1.65), Vector2(0.0, 1.65),
		Vector2(-2.4, 1.65), Vector2(-3.3, 0.6), Vector2(-3.3, -0.8)
	])
	var center_right := PackedVector2Array([
		Vector2(0.0, -1.65), Vector2(2.4, -1.65), Vector2(3.3, -0.6),
		Vector2(3.3, 0.8), Vector2(3.0, 1.65), Vector2(0.0, 1.65)
	])
	add_prism("CentralResourceRed", center_left, 0.78, Color("60666c"))
	add_prism("CentralResourceBlue", center_right, 0.78, Color("687077"))
	add_box("CentralBridge", Vector3(0.0, 1.15, 0.0), Vector3(0.45, 2.3, 3.2), Color("30363d"))
	add_wedge_ramp("CentralRedRamp", Vector3(-5.1, -0.06, 0.0), Vector3(-3.0, 0.78, 0.0), 2.4, PLATFORM_TOP)
	add_wedge_ramp("CentralBlueRamp", Vector3(5.1, -0.06, 0.0), Vector3(3.0, 0.78, 0.0), 2.4, PLATFORM_TOP)
	add_glow_strip("CentralRedEdge", Vector3(-1.45, 0.84, -1.62), Vector3(2.7, 0.08, 0.08), RED)
	add_glow_strip("CentralBlueEdge", Vector3(1.45, 0.84, 1.62), Vector3(2.7, 0.08, 0.08), BLUE)
	add_guardrail("CentralNorthRail", Vector3(-2.7, 0.78, -1.62), Vector3(2.1, 0.78, -1.62), STEEL)
	add_guardrail("CentralSouthRail", Vector3(-2.1, 0.78, 1.62), Vector3(2.7, 0.78, 1.62), STEEL)

	# Functional rotating energy mechanism: five illuminated armor targets must
	# be hit in the shown order to activate a temporary damage buff.
	var energy := Node3D.new()
	energy.name = "EnergyMechanism"
	# Offset toward the playable red side so the bridge frame does not intercept
	# bullets before they reach the illuminated plates.
	energy.position = Vector3(-0.38, 2.0, 0.0)
	energy.set_script(ENERGY_SCRIPT)
	add_child(energy)
	add_box("EnergyPedestal", Vector3(0.0, 0.62, 0.0), Vector3(0.75, 1.24, 0.75), Color("303840"))
	add_prism("ControlZone", regular_polygon(Vector2(0.0, 3.65), 0.95, 6, PI / 6.0), 0.06, YELLOW)
	add_prism("MirrorControlZone", regular_polygon(Vector2(0.0, -3.65), 0.95, 6, PI / 6.0), 0.06, WHITE)

	# Floor graphics and glowing team split.
	add_glow_strip("RedCenterLine", Vector3(-6.8, 0.02, 0.0), Vector3(13.4, 0.035, 0.055), RED)
	add_glow_strip("BlueCenterLine", Vector3(6.8, 0.02, 0.0), Vector3(13.4, 0.035, 0.055), BLUE)
	# Raised lane edge lighting mirrors the warm/cool split in the reference.
	add_glow_strip("RedOuterEdge", Vector3(-6.8, 0.055, -7.25), Vector3(13.4, 0.05, 0.05), RED)
	add_glow_strip("BlueOuterEdge", Vector3(6.8, 0.055, 7.25), Vector3(13.4, 0.05, 0.05), BLUE)

	# Playable mechanisms: destructible bases, rotating outposts and supply pads.
	add_target("RedBaseTarget", Vector3(-11.4, 1.4, -4.65), "base", "red", RED, 1500)
	add_target("BlueBaseTarget", Vector3(11.4, 1.4, 4.65), "base", "blue", BLUE, 1500)
	add_target("RedRotatingOutpost", Vector3(-7.4, 1.28, -0.65), "outpost", "red", RED, 300, 1.2)
	add_target("BlueRotatingOutpost", Vector3(7.4, 1.28, 0.65), "outpost", "blue", BLUE, 300, -1.2)
	add_supply_zone("RedSupplyZone", Vector3(-10.8, 0.04, -3.0), "red", RED)
	add_supply_zone("BlueSupplyZone", Vector3(10.8, 0.04, 3.0), "blue", BLUE)
