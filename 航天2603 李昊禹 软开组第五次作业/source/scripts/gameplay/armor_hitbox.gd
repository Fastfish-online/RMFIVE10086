extends StaticBody3D

var target: Node


func take_damage(amount: int, source_team: String = "") -> void:
	if target and target.has_method("take_damage"):
		target.take_damage(amount, source_team)

