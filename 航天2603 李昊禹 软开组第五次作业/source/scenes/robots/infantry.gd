extends CharacterBody3D

signal stats_changed
signal destroyed

@export var bullet_scene: PackedScene = preload("res://scenes/projectiles/bullet.tscn")
@export var fire_interval: float = 0.15
@export var mouse_sensitivity: float = 0.002
@export var pitch_limit: float = 30.0
@export var max_health: int = 200
@export var magazine_size: int = 50
@export var team: String = "red"

@onready var muzzle: Marker3D = $GimbalYaw/GimbalPitch/Muzzle
@onready var gimbal_yaw: Node3D = $GimbalYaw
@onready var gimbal_pitch: Node3D = $GimbalYaw/GimbalPitch

const SPEED := 4.5
const ACCELERATION := 11.0
const BRAKE_ACCELERATION := 16.0
# Kept only because the assignment explicitly asks for jumping. A real RM
# infantry chassis cannot jump; 2.2 m/s limits this demo hop to about 0.25 m.
const JUMP_VELOCITY := 2.2
const MAX_HEAT := 100.0
const HEAT_PER_SHOT := 7.0
const HEAT_COOL_RATE := 18.0

var fire_timer := 0.0
var spawn_position: Vector3
var health: int
var ammo: int
var barrel_heat := 0.0
var damage_multiplier := 1.0
var supply_in_progress := false


func _ready() -> void:
	spawn_position = global_position
	health = max_health
	ammo = magazine_size
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = false
	safe_margin = 0.02
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	fire_timer = maxf(fire_timer - delta, 0.0)
	barrel_heat = maxf(barrel_heat - HEAT_COOL_RATE * delta, 0.0)
	if Input.is_action_pressed("fire") and fire_timer <= 0.0:
		if shoot():
			fire_timer = fire_interval

	if Input.is_action_just_pressed("reset"):
		reset_robot()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * SPEED, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, BRAKE_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, BRAKE_ACCELERATION * delta)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		gimbal_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		gimbal_pitch.rotation.x = clampf(
			gimbal_pitch.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-pitch_limit),
			deg_to_rad(pitch_limit)
		)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func shoot() -> bool:
	if bullet_scene == null:
		push_error("Bullet scene is not configured.")
		return false
	if ammo <= 0:
		return false
	if barrel_heat + HEAT_PER_SHOT > MAX_HEAT:
		return false

	var bullet := bullet_scene.instantiate() as Area3D
	if bullet == null:
		push_error("Failed to instantiate bullet scene.")
		return false

	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = muzzle.global_transform
	bullet.set("direction", -muzzle.global_transform.basis.z.normalized())
	bullet.set("source_team", team)
	bullet.set("damage", int(bullet.get("damage") * damage_multiplier))
	ammo -= 1
	barrel_heat += HEAT_PER_SHOT
	stats_changed.emit()
	return true


func take_damage(amount: int, source_team: String = "") -> void:
	if source_team == team:
		return
	health = maxi(health - amount, 0)
	stats_changed.emit()
	if health == 0:
		destroyed.emit()
		reset_robot()


func heal(amount: int) -> void:
	health = mini(health + amount, max_health)
	stats_changed.emit()


func resupply() -> void:
	ammo = magazine_size
	barrel_heat = 0.0
	health = max_health
	stats_changed.emit()


func apply_supply() -> void:
	if supply_in_progress:
		return
	supply_in_progress = true
	ammo = magazine_size
	barrel_heat = 0.0
	stats_changed.emit()
	# RMUL blood-pack approximation: recover 10% max HP per second for 5 s.
	for _tick in 5:
		heal(int(max_health * 0.1))
		await get_tree().create_timer(1.0).timeout
	supply_in_progress = false


func reset_robot() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	health = max_health
	ammo = magazine_size
	stats_changed.emit()
