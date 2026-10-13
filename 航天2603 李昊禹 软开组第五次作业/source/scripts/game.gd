extends Node3D

const MINIMAP_SCRIPT = preload("res://scripts/ui/minimap.gd")
const CAMERA_SERVER_SCRIPT = preload("res://scripts/camera_server.gd")

@export var match_duration := 300.0

var time_left := 300.0
var red_score := 0
var blue_score := 0
var match_running := true
var notice_time := 0.0
var energy_progress := 0
var energy_total := 5
var energy_cooldown := 0.0
var buff_time_left := 0.0

var timer_label: Label
var score_label: Label
var stats_label: Label
var target_label: Label
var telemetry_label: Label
var mechanism_label: Label
var notice_label: Label
var result_label: Label
var buff_flash: ColorRect
var camera_output_label: Label
var player: Node3D


func _ready() -> void:
	time_left = match_duration
	player = $Infantry
	build_hud()
	var camera_server := Node.new()
	camera_server.name = "LocalCameraServer"
	camera_server.set_script(CAMERA_SERVER_SCRIPT)
	add_child(camera_server)
	camera_output_label = make_label($HUD, "CameraOutput", Vector2(18, 675), 13, Color("48ff9b"))
	if camera_server.get("last_error") == "":
		camera_output_label.text = "● CAMERA SERVER READY  http://127.0.0.1:8080   640x360"
	else:
		camera_output_label.add_theme_color_override("font_color", Color("ff4d57"))
		camera_output_label.text = "● CAMERA SERVER ERROR  PORT 8080 IS BUSY"
	show_notice("MATCH START - DESTROY THE BLUE BASE")


func _process(delta: float) -> void:
	if match_running:
		time_left = maxf(time_left - delta, 0.0)
		if time_left <= 0.0:
			finish_match("TIME UP")
	if notice_time > 0.0:
		notice_time -= delta
		notice_label.visible = notice_time > 0.0
	if buff_time_left > 0.0:
		buff_time_left = maxf(buff_time_left - delta, 0.0)
		if buff_time_left <= 0.0:
			player.set("damage_multiplier", 1.0)
			show_notice("ENERGY BUFF ENDED")
	if energy_cooldown > 0.0:
		energy_cooldown = maxf(energy_cooldown - delta, 0.0)
	update_hud()


func make_label(parent: Node, name: String, position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = name
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label


func build_hud() -> void:
	var hud := $HUD
	timer_label = make_label(hud, "Timer", Vector2(575, 20), 30, Color.WHITE)
	timer_label.size = Vector2(130, 42)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label = make_label(hud, "Score", Vector2(485, 58), 21, Color("ffd25c"))
	stats_label = make_label(hud, "Stats", Vector2(18, 90), 19, Color.WHITE)
	target_label = make_label(hud, "Targets", Vector2(18, 145), 16, Color("9fe8ff"))
	telemetry_label = make_label(hud, "Telemetry", Vector2(18, 205), 15, Color("ffd25c"))
	mechanism_label = make_label(hud, "Mechanism", Vector2(18, 260), 15, Color("ffbd28"))
	notice_label = make_label(hud, "Notice", Vector2(340, 610), 21, Color("ffd25c"))
	notice_label.size = Vector2(600, 40)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label = make_label(hud, "Result", Vector2(340, 280), 42, Color.WHITE)
	result_label.size = Vector2(600, 100)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.visible = false
	var flash := ColorRect.new()
	flash.name = "BuffFlash"
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.72, 0.08, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash)
	hud.move_child(flash, 0)
	buff_flash = flash

	var minimap := Control.new()
	minimap.name = "Minimap"
	minimap.set_script(MINIMAP_SCRIPT)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-260, 18)
	minimap.size = Vector2(240, 130)
	hud.add_child(minimap)


func update_hud() -> void:
	var seconds := ceili(time_left)
	timer_label.text = "%02d:%02d" % [int(seconds / 60), seconds % 60]
	score_label.text = "RED %03d  -  %03d BLUE" % [red_score, blue_score]
	stats_label.text = "HP  %03d/%03d\nAMMO  %02d/%02d" % [player.get("health"), player.get("max_health"), player.get("ammo"), player.get("magazine_size")]
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	telemetry_label.text = "CHASSIS  %4.1f m/s\nBARREL HEAT  %03d/100" % [speed, int(player.get("barrel_heat"))]
	var base_state := "SHIELDED" if time_left > match_duration - 60.0 else "VULNERABLE"
	if energy_cooldown > 0.0:
		mechanism_label.text = "ENERGY  COOLDOWN %02ds\nBASE  %s" % [ceili(energy_cooldown), base_state]
	else:
		mechanism_label.text = "ENERGY  %d/%d   BUFF %02ds\nBASE  %s" % [energy_progress, energy_total, ceili(buff_time_left), base_state]
	var blue_base := find_target("base", "blue")
	var blue_outpost := find_target("outpost", "blue")
	target_label.text = "BLUE BASE  %s\nBLUE OUTPOST  %s" % [target_health_text(blue_base), target_health_text(blue_outpost)]


func find_target(target_type: String, team_name: String) -> Node:
	for target in get_tree().get_nodes_in_group("damageable_targets"):
		if target.get("target_type") == target_type and target.get("team") == team_name:
			return target
	return null


func target_health_text(target: Node) -> String:
	if target == null:
		return "---"
	return "%d/%d" % [target.get("health"), target.get("max_health")]


func register_hit(_target_type: String, target_team: String, amount: int, _health: int, _max_health: int) -> void:
	if target_team == "blue":
		red_score += amount
	else:
		blue_score += amount
	show_notice("HIT +%d" % amount)


func register_destroyed(target_type: String, target_team: String) -> void:
	if target_team == "blue":
		red_score += 100
	else:
		blue_score += 100
	show_notice("%s %s DESTROYED +100" % [target_team.to_upper(), target_type.to_upper()])
	if target_type == "base":
		finish_match("RED VICTORY" if target_team == "blue" else "BLUE VICTORY")


func show_notice(message: String) -> void:
	if notice_label == null:
		return
	notice_label.text = message
	notice_label.visible = true
	notice_time = 2.0


func energy_progress_changed(value: int, total: int, cooldown: float) -> void:
	energy_progress = value
	energy_total = total
	energy_cooldown = cooldown
	if value > 0:
		show_notice("ENERGY TARGET %d/%d" % [value, total])


func activate_energy_buff(team_name: String, duration: float) -> void:
	energy_progress = 0
	energy_cooldown = 45.0
	if team_name == "red":
		buff_time_left = duration
		player.set("damage_multiplier", 1.5)
		red_score += 150
	show_notice("ENERGY MECHANISM ACTIVATED - DAMAGE x1.5")


func activate_energy_step(team_name: String) -> void:
	# Every correct illuminated-plate hit gives immediate feedback and a useful
	# short buff. Completing all five upgrades it to the full mechanism buff.
	if team_name == "red":
		buff_time_left = maxf(buff_time_left, 8.0)
		player.set("damage_multiplier", maxf(player.get("damage_multiplier"), 1.2))
		red_score += 20
	flash_buff_feedback()
	show_notice("RUNE HIT - DAMAGE x1.2 / 8s")


func flash_buff_feedback() -> void:
	if buff_flash == null:
		return
	buff_flash.color = Color(1.0, 0.72, 0.08, 0.24)
	var tween := create_tween()
	tween.tween_property(buff_flash, "color", Color(1.0, 0.72, 0.08, 0.0), 0.45)


func is_base_vulnerable(team_name: String) -> bool:
	if time_left <= match_duration - 60.0:
		return true
	var outpost := find_target("outpost", team_name)
	return outpost == null or not outpost.get("active")


func finish_match(reason: String) -> void:
	match_running = false
	result_label.text = "%s\nFINAL  %d : %d" % [reason, red_score, blue_score]
	result_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
