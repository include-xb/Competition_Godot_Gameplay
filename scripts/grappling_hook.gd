class_name GrapplingHook
extends Node3D
## 钩爪 / 抓钩物理系统。
##
## 门槛要求：
## 1. 发射与命中：沿摄像机朝向做射线检测（RayCast3D），命中墙壁 / 锚点后生成绳索。
## 2. 拉力：绳索绷紧时对玩家施加指向锚点的拉力。
## 3. 断开：按键释放，恢复自由状态。
##
## 进阶挑战：
## ★★ 收绳 / 放绳：按按键或滚轮动态调整绳索长度。
##
## ★~★★★★★ 中尚未实现的扩展点用 "进阶" 注释标出。

## 钩爪命中并固定到锚点时发出。
signal hook_attached(anchor: Vector3)
## 钩爪断开（主动释放或失去目标）时发出。
signal hook_released

enum State {
	IDLE, ## 自由状态，未发射
	ATTACHED, ## 已固定在锚点上，持续施加拉力
}

@export_group("发射")
## 钩爪最大射程（米）
@export_range(1.0, 200.0, 1.0) var max_range: float = 60.0
## 可以被钩住的物理层
@export_flags_3d_physics var hookable_mask: int = 1
## 发射键（在项目输入映射中定义）
@export var fire_action: StringName = &"fire_hook"
## 断开键（在项目输入映射中定义）
@export var release_action: StringName = &"release_hook"
## 待机时是否把射线显示出来，方便在编辑器 / 运行时调试瞄准
@export var debug_draw_ray: bool = false

@export_group("绳索约束")
## 绳索能施加的最大拉力（m/s²），同时也是弹簧力的上限
@export_range(0.0, 300.0, 1.0) var pull_force: float = 55.0
## 绳索刚度：绷紧后每超出绳长 1 米所施加的拉力（m/s² 每米）
@export var rope_stiffness: float = 90.0
## 径向远离时的阻尼，抑制绳索来回振荡
@export var rope_damping: float = 6.0
## 玩家在「拉向锚点」方向上的速度达到该值后不再加速，避免被无限加速
@export var max_pull_speed: float = 22.0

@export_group("收绳 / 放绳")
## 按住收绳键时绳索缩短的速度（米/秒）
@export var reel_in_speed: float = 12.0
## 按住放绳键时绳索伸长的速度（米/秒）
@export var reel_out_speed: float = 14.0
## 滚轮每格调整的长度（米）
@export var reel_step: float = 1.5
## 绳索最短长度（米），避免把玩家贴到锚点上
@export var min_rope_length: float = 1.5
## 命中瞬间的绳长占实际距离的比例。
## 小于 1 时绳索一钩住就是绷紧的，玩家立刻被拉向锚点，而不是吊在原地不动。
@export_range(0.3, 1.0, 0.05) var initial_rope_slack: float = 0.85
## 收绳键
@export var reel_in_action: StringName = &"reel_in"
## 放绳键
@export var reel_out_action: StringName = &"reel_out"
## 滚轮收绳（单次步进）
@export var reel_in_step_action: StringName = &"reel_in_step"
## 滚轮放绳（单次步进）
@export var reel_out_step_action: StringName = &"reel_out_step"

@export_group("绳索")
@export var rope_radius: float = 0.05
@export var rope_color: Color = Color(0.95, 0.88, 0.55)
@export var rope_emission_energy: float = 2.5

## 摄像机，决定钩爪的发射方向。在场景中指定。
@export var camera: Camera3D

@onready var _ray: RayCast3D = $RayCast3D
@onready var _rope: MeshInstance3D = $Rope

var _state: State = State.IDLE
var _anchor: Vector3 = Vector3.ZERO
## 命中瞬间的绳索长度，"收绳 / 放绳" 进阶挑战会在此基础上做动态调整
var _rope_length: float = 0.0
var _player: CharacterBody3D = null


func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_warning("GrapplingHook: 未找到父级 CharacterBody3D，拉力将无法生效。")
	if camera == null:
		push_warning("GrapplingHook: 未指定摄像机，钩爪无法确定发射方向。")

	# 钩爪必须比玩家先跑物理帧，才能在本帧 move_and_slide() 之前把拉力写进 velocity
	process_physics_priority = -1

	_setup_ray()
	_setup_rope()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(fire_action):
		fire()
	elif event.is_action_pressed(release_action):
		release()
	# 滚轮是瞬时事件，走单次步进而不是按键的持续调整
	elif event.is_action_pressed(reel_in_step_action):
		adjust_rope_length(-reel_step)
	elif event.is_action_pressed(reel_out_step_action):
		adjust_rope_length(reel_step)


func _process(_delta: float) -> void:
	if _state == State.ATTACHED:
		_update_rope()
	if debug_draw_ray:
		_ray.visible = true


func _physics_process(delta: float) -> void:
	if _state != State.ATTACHED:
		return

	# 锚点所在的物体被销毁 / 移走时自动断开
	if _player == null or not is_instance_valid(_player):
		release()
		return

	_reel_rope(delta)
	_apply_rope_constraint()


## 进阶 ★★：按住收绳 / 放绳键时动态改变绳索长度（滚轮走 [method adjust_rope_length]）。
func _reel_rope(delta: float) -> void:
	if Input.is_action_pressed(reel_in_action):
		adjust_rope_length(-reel_in_speed * delta)
	if Input.is_action_pressed(reel_out_action):
		adjust_rope_length(reel_out_speed * delta)


## 把绳索长度调整 [param amount] 米（正数放绳、负数收绳），并钳制到合法范围。
## 这是收放绳的唯一入口，UI 或脚本也可以直接调用。
func adjust_rope_length(amount: float) -> void:
	if _state != State.ATTACHED:
		return
	_rope_length = clampf(_rope_length + amount, min_rope_length, max_range)


## 门槛要求 2：把玩家拉向锚点。
##
## 绳索是「只能绷紧、不能伸长」的约束：实际距离超出绳长时施加向锚点的拉力，
## 超出越多拉得越狠（封顶 [member pull_force]）。因此收绳会缩短绳长把玩家拽近，
## 放绳则让绳索松弛、玩家重新被重力支配。
func _apply_rope_constraint() -> void:
	var to_anchor := _anchor - _player.global_position
	var distance := to_anchor.length()
	if distance < 0.001:
		return

	var stretch := distance - _rope_length
	if stretch <= 0.0:
		return # 绳索松弛，不施加任何力

	var pull_dir := to_anchor / distance
	var radial_speed := _player.velocity.dot(pull_dir)

	# 只在玩家径向远离时阻尼，否则会抵消收绳把人拽近的效果
	var force := stretch * rope_stiffness - minf(radial_speed, 0.0) * rope_damping
	force = clampf(force, 0.0, pull_force)

	if radial_speed < max_pull_speed:
		_player.add_external_force(pull_dir * force)


## 门槛要求 1：朝摄像机朝向发射，射线命中后生成绳索。
## 返回是否成功钩中。
func fire() -> bool:
	if _state != State.IDLE or camera == null:
		return false

	# 让射线与摄像机同位同向；target_position 是局部坐标，-Z 即摄像机前方
	_ray.global_transform = camera.global_transform
	_ray.target_position = Vector3(0.0, 0.0, -max_range)
	_ray.force_raycast_update()

	if not _ray.is_colliding():
		return false

	_anchor = _ray.get_collision_point()
	_state = State.ATTACHED

	var distance := 0.0
	if _player != null:
		distance = _player.global_position.distance_to(_anchor)
	_rope_length = clampf(distance * initial_rope_slack, min_rope_length, max_range)

	_rope.visible = true
	_update_rope()
	hook_attached.emit(_anchor)
	return true


## 门槛要求 3：断开钩爪，恢复自由状态。
func release() -> void:
	if _state == State.IDLE:
		return
	_state = State.IDLE
	_rope.visible = false
	hook_released.emit()


func is_attached() -> bool:
	return _state == State.ATTACHED


func get_anchor() -> Vector3:
	return _anchor


func get_rope_length() -> float:
	return _rope_length


func _find_player() -> CharacterBody3D:
	var node := get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _setup_ray() -> void:
	_ray.enabled = true
	_ray.collision_mask = hookable_mask
	_ray.hit_from_inside = false
	# 射线从摄像机出发，摄像机位于玩家体内，必须排除玩家自己
	if _player != null:
		_ray.add_exception(_player)


func _setup_rope() -> void:
	var cylinder := CylinderMesh.new()
	# 单位圆柱，实际粗细与长度全部交给节点 scale 控制
	cylinder.height = 1.0
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 1

	var material := StandardMaterial3D.new()
	material.albedo_color = rope_color
	material.emission_enabled = true
	material.emission = rope_color
	material.emission_energy_multiplier = rope_emission_energy
	cylinder.material = material

	_rope.mesh = cylinder
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.visible = false


func _update_rope() -> void:
	var from := get_muzzle_position()
	var to := _anchor
	var offset := to - from
	var length := offset.length()

	if length < 0.001:
		_rope.visible = false
		return
	_rope.visible = true

	# 构造一个 Y 轴对齐到绳索方向的右手坐标系
	var up := offset / length
	var right := up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := right.cross(up)

	# 逐列缩放：X/Z 是绳子半径，Y 拉长到绳长。
	# 不能用 Basis.scaled()，它是按「行」缩放的，会把长度错误地缩放到 Z 轴上，
	# 导致绳索方向恒为世界 Y 轴（看起来永远垂直于地面）。
	var rope_basis := Basis(right, up, forward)
	rope_basis.x *= rope_radius
	rope_basis.y *= length
	rope_basis.z *= rope_radius

	_rope.global_transform = Transform3D(rope_basis, from + offset * 0.5)


## 绳索的可视起点（世界坐标）：摄像机稍下方，视觉上像是从玩家手里射出的。
## 钩爪未连接时也可调用。
func get_muzzle_position() -> Vector3:
	if camera != null:
		return camera.global_position - Vector3(0.0, 0.2, 0.0)
	if _player != null:
		return _player.global_position
	return global_position
