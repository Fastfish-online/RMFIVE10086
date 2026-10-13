extends Area3D

@export var team := "red"
@export var cooldown := 8.0

var available := true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not available or not body.has_method("apply_supply"):
		return
	if body.get("team") != team:
		return
	body.apply_supply()
	available = false
	var game := get_tree().current_scene
	if game.has_method("show_notice"):
		game.show_notice("SUPPLY ACTIVE - AMMO FULL, HP +10%/S FOR 5S")
	get_tree().create_timer(cooldown).timeout.connect(_reset_zone)


func _reset_zone() -> void:
	available = true
