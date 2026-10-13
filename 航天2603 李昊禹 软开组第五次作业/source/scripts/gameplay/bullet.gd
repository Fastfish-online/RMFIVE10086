
extends Area3D

@export var speed: float = 15.0
@export var lifetime: float = 3.0
@export var damage: int = 10

var direction: Vector3 = Vector3.FORWARD
var source_team: String = ""
var consumed := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	if consumed:
		return
	var start := global_position
	var finish := start + direction.normalized() * speed * delta
	# Energy plates rotate under a scaled battlefield parent. Detect the visible
	# hexagon directly in world space so their gameplay never depends on a thin,
	# nested physics shape or on frame rate.
	for plate in get_tree().get_nodes_in_group("energy_plates"):
		if not plate.has_method("is_current_target") or not plate.is_current_target():
			continue
		var closest := Geometry3D.get_closest_point_to_segment(plate.global_position, start, finish)
		if closest.distance_to(plate.global_position) <= 0.42:
			global_position = closest
			apply_hit(plate)
			return
	# Swept collision prevents a fast projectile from skipping thin armor or
	# energy plates between two rendered frames.
	var query := PhysicsRayQueryParameters3D.create(start, finish)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		apply_hit(hit.collider)
		return
	global_position = finish

func _on_body_entered(body: Node3D) -> void:
	apply_hit(body)


func apply_hit(body: Node) -> void:
	if consumed:
		return
	if body is CharacterBody3D and body.get("team") == source_team:
		return
	consumed = true
	if body.has_method("take_damage"):
		body.take_damage(damage, source_team)
	queue_free()
