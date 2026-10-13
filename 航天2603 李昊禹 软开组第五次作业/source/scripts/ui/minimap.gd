extends Control

var player: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player = get_tree().current_scene.get_node_or_null("Infantry")
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func world_to_map(position: Vector3) -> Vector2:
	return Vector2(
		(position.x + 6.0) / 12.0 * size.x,
		(position.z + 4.0) / 8.0 * size.y
	)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.04, 0.06, 0.9), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("93a4b5"), false, 2.0)
	draw_line(world_to_map(Vector3(0, 0, -4.0)), world_to_map(Vector3(0, 0, 4.0)), Color(0.75, 0.8, 0.85, 0.4), 1.0)
	# Major fixed modules.
	for marker in [Vector3(-4.9, 0, -2.48), Vector3(4.9, 0, 2.48), Vector3.ZERO]:
		draw_circle(world_to_map(marker), 5.0, Color("d7b14b"))
	for target in get_tree().get_nodes_in_group("damageable_targets"):
		if not target.visible:
			continue
		var color := Color("ff4d57") if target.get("team") == "red" else Color("21d8e6")
		draw_circle(world_to_map(target.global_position), 4.0, color)
	if player:
		var center := world_to_map(player.global_position)
		var forward := -player.global_transform.basis.z
		var angle := atan2(forward.x, -forward.z)
		var points := PackedVector2Array([
			center + Vector2(0, -8).rotated(angle),
			center + Vector2(5, 6).rotated(angle),
			center + Vector2(-5, 6).rotated(angle)
		])
		draw_colored_polygon(points, Color.WHITE)
