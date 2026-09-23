extends CharacterBody3D
## 第一人称玩家控制器。
##
## 负责基础移动 / 跳跃 / 视角控制，并对外暴露 [method add_external_force]
## 供钩爪等系统在不与输入逻辑打架的前提下施加外力。

@export_group("移动")
@export var move_speed: float = 7.0
@export var ground_accel: float = 14.0
@export var air_accel: float = 4.0
@export var ground_friction: float = 12.0
@export var air_friction: float = 0.8
@export var jump_velocity: float = 6.0

@export_group("视角")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_deg: float = 89.0

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

## 外力累加器。写入方（如钩爪）必须在物理帧开始前调用 add_external_force，
## 因此写入方的 process_physics_priority 需要小于玩家的（默认 0）。
var _external_force: Vector3 = Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	elif event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()


func _physics_process(delta: float) -> void:
	_apply_external_force(delta)
	_apply_gravity(delta)
	_apply_horizontal_movement(delta)
	_apply_jump()
	move_and_slide()


## 累加一个加速度（单位 m/s²）。同一物理帧内多次调用会叠加。
## 钩爪的拉力就是通过这里注入的。
func add_external_force(acceleration: Vector3) -> void:
	_external_force += acceleration


func _apply_external_force(delta: float) -> void:
	if _external_force != Vector3.ZERO:
		velocity += _external_force * delta
		_external_force = Vector3.ZERO


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func _apply_horizontal_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()
		# 只在输入方向上"补足"到 move_speed：被钩爪拽到高速时不会被输入逻辑拖慢
		if horizontal.dot(wish_dir) < move_speed:
			var accel := ground_accel if is_on_floor() else air_accel
			horizontal += wish_dir * accel * delta
	else:
		var friction := ground_friction if is_on_floor() else air_friction
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


func _look(relative: Vector2) -> void:
	# 水平旋转整个身体，垂直旋转只作用于摄像机云台
	rotate_y(-relative.x * mouse_sensitivity)
	var limit := deg_to_rad(pitch_limit_deg)
	camera_rig.rotation.x = clampf(
		camera_rig.rotation.x - relative.y * mouse_sensitivity, -limit, limit
	)


func _toggle_mouse_capture() -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)
