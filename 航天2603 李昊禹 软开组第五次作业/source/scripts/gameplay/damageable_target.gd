extends AnimatableBody3D

@export var target_type := "outpost"
@export var team := "blue"
@export var max_health := 300
@export var rotate_speed := 0.0

var health: int
var active := true


func _ready() -> void:
	health = max_health
	add_to_group("damageable_targets")


func _physics_process(delta: float) -> void:
	if active and rotate_speed != 0.0:
		rotate_y(rotate_speed * delta)


func take_damage(amount: int, source_team: String = "") -> void:
	if not active or source_team == team:
		return
	var game := get_tree().current_scene
	if target_type == "base" and game.has_method("is_base_vulnerable") and not game.is_base_vulnerable(team):
		if game.has_method("show_notice"):
			game.show_notice("BASE SHIELD ACTIVE - DESTROY OUTPOST OR WAIT")
		return
	var applied_damage := 5 if target_type == "base" else amount
	health = maxi(health - applied_damage, 0)
	if game.has_method("register_hit"):
		game.register_hit(target_type, team, applied_damage, health, max_health)
	flash_hit()
	if health == 0:
		active = false
		visible = false
		collision_layer = 0
		collision_mask = 0
		if game.has_method("register_destroyed"):
			game.register_destroyed(target_type, team)


func flash_hit() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.12, 1.12, 1.12), 0.06)
	tween.tween_property(self, "scale", Vector3.ONE, 0.08)
