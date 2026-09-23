extends SceneTree
## 钩爪的冒烟测试：无头运行，逐条验证门槛要求与 ★★ 收放绳。
##
## 覆盖：
##   门槛 1 发射与命中 —— 朝视线方向 Raycast 命中锚点
##   门槛 2 拉力       —— 命中后玩家被拉向锚点
##   门槛 3 断开       —— 按键释放后恢复自由
##   ★★ 收绳 / 放绳   —— 收绳把玩家拽近，放绳让玩家重新下落
##
## 用法：
##   godot --headless --path <项目目录> --script res://tools/hook_smoke_test.gd

## 用作瞄准目标的锚点，相对 main.tscn 根节点。
## 选高处那个，玩家会被明显拉离地面。
const ANCHOR_PATH := "Level/Anchors/AnchorTower"

var _main: Node
var _player: CharacterBody3D
var _hook: Node
var _camera: Camera3D
var _target := Vector3.ZERO

var _frame := 0
var _failed := false

var _attached := false
var _reeling_in := false
var _reeling_out := false
var _released := false

var _dist_on_attach := 0.0
var _y_on_attach := 0.0
var _dist_after_pull := 0.0
var _dist_after_reel_in := 0.0
var _dist_after_reel_out := 0.0


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_player = _main.get_node("Player")
	_hook = _player.get_node("GrapplingHook")
	_camera = _player.get_node("CameraRig/Camera3D")
	print("[test] 场景已加载")
	# 节点要等进入场景树后 global_position 才有效，目标位置留到第 1 帧再取


func _fail(message: String) -> void:
	_failed = true
	printerr("[test][FAIL] ", message)


func _check(condition: bool, ok_message: String, fail_message: String) -> void:
	if condition:
		print("[test] ", ok_message)
	else:
		_fail(fail_message)


func _distance_to_anchor() -> float:
	return _player.global_position.distance_to(_hook.get_anchor())


func _finish() -> bool:
	print("[test] 结果：", "FAILED" if _failed else "ALL PASSED")
	return true


func _physics_process(_delta: float) -> bool:
	_frame += 1

	if _frame == 1:
		var anchor := _main.get_node_or_null(ANCHOR_PATH) as Node3D
		if anchor == null:
			_fail("找不到锚点节点 %s" % ANCHOR_PATH)
			return _finish()
		_target = anchor.global_position
		print("[test] 目标锚点=%s" % _target)

	# --- 等玩家落地站稳，再开始测 ---
	if _frame == 60:
		return _phase_fire()
	if _attached and _frame == 180:
		return _phase_check_pull()
	if _reeling_in and _frame == 270:
		return _phase_check_reel_in()
	if _reeling_out and _frame == 400:
		return _phase_check_reel_out()
	if _released and _frame == 500:
		return _phase_finish()

	if _frame > 600:
		_fail("测试超时（frame=%d）" % _frame)
		return _finish()
	return false


## 门槛 1：朝视线方向发射钩爪，射线命中锚点。
func _phase_fire() -> bool:
	_check(
		_player.is_on_floor(),
		"玩家已落地 y=%.2f" % _player.global_position.y,
		"玩家未在 60 帧内落地，position=%s" % _player.global_position
	)

	_camera.look_at(_target, Vector3.UP)
	var fired: bool = _hook.fire()
	_check(fired, "Raycast 命中，绳索已生成", "fire() 未命中目标，射线检测失效")
	if not fired:
		return _finish()

	_attached = true
	_dist_on_attach = _distance_to_anchor()
	_y_on_attach = _player.global_position.y
	print("[test] 锚点=%s 绳长=%.2f 初始距离=%.2f" % [
		_hook.get_anchor(), _hook.get_rope_length(), _dist_on_attach
	])
	_check_rope_orientation()
	return false


## 绳索朝向：本地 Y 轴必须对齐锚点方向、长度等于实际距离。
## 曾经因为误用 Basis.scaled()（按行缩放）导致绳索恒为竖直方向，这里守住它。
func _check_rope_orientation() -> void:
	var rope := _hook.get_node("Rope") as MeshInstance3D
	var to_anchor: Vector3 = _hook.get_anchor() - _hook.get_muzzle_position()
	var rope_y: Vector3 = rope.global_transform.basis.y
	_check(
		rope_y.normalized().dot(to_anchor.normalized()) > 0.999
		and absf(rope_y.length() - to_anchor.length()) < 0.01,
		"绳索朝向正确：Y 轴=%s 长度=%.2f" % [rope_y.normalized(), rope_y.length()],
		"绳索朝向错误：Y 轴=%s（期望 %s）长度=%.2f（期望 %.2f）" % [
			rope_y.normalized(), to_anchor.normalized(), rope_y.length(), to_anchor.length()
		]
	)


## 门槛 2：绳索绷紧后玩家被拉向锚点（离地上升、距离缩短）。
func _phase_check_pull() -> bool:
	_dist_after_pull = _distance_to_anchor()
	var y_now: float = _player.global_position.y
	_check(
		_dist_after_pull < _dist_on_attach - 1.0 and y_now > _y_on_attach + 1.0,
		"拉力生效，玩家被拉向锚点：距离 %.2f -> %.2f，高度 %.2f -> %.2f" % [
			_dist_on_attach, _dist_after_pull, _y_on_attach, y_now
		],
		"拉力未生效：距离 %.2f -> %.2f，高度 %.2f -> %.2f" % [
			_dist_on_attach, _dist_after_pull, _y_on_attach, y_now
		]
	)

	# ★★ 开始收绳
	print("[test] 按下收绳键")
	Input.action_press("reel_in")
	_reeling_in = true
	return false


## ★★ 收绳：绳长缩短，玩家被拽得更近。
func _phase_check_reel_in() -> bool:
	Input.action_release("reel_in")
	var rope_length: float = _hook.get_rope_length()
	_dist_after_reel_in = _distance_to_anchor()
	_check(
		rope_length < _dist_on_attach * 0.85 and _dist_after_reel_in < _dist_after_pull - 1.0,
		"收绳生效：绳长=%.2f，距离 %.2f -> %.2f" % [rope_length, _dist_after_pull, _dist_after_reel_in],
		"收绳未生效：绳长=%.2f，距离 %.2f -> %.2f" % [rope_length, _dist_after_pull, _dist_after_reel_in]
	)

	# ★★ 开始放绳
	print("[test] 按下放绳键")
	Input.action_press("reel_out")
	_reeling_out = true
	return false


## ★★ 放绳：绳长伸长，绳索松弛，玩家重新被重力支配。
func _phase_check_reel_out() -> bool:
	Input.action_release("reel_out")
	var rope_length: float = _hook.get_rope_length()
	_dist_after_reel_out = _distance_to_anchor()
	_check(
		rope_length > _hook.min_rope_length and _dist_after_reel_out > _dist_after_reel_in + 0.5,
		"放绳生效：绳长=%.2f，距离 %.2f -> %.2f" % [
			rope_length, _dist_after_reel_in, _dist_after_reel_out
		],
		"放绳未生效：绳长=%.2f，距离 %.2f -> %.2f" % [
			rope_length, _dist_after_reel_in, _dist_after_reel_out
		]
	)

	# 门槛 3：断开钩爪
	_check(_hook.is_attached(), "断开前状态为 ATTACHED", "断开前状态异常")
	_hook.release()
	_released = true
	_check(not _hook.is_attached(), "release() 后恢复 IDLE 自由状态", "release() 后仍为 ATTACHED")
	return false


func _phase_finish() -> bool:
	_check(
		_player.velocity.y < 0.0 or _player.is_on_floor(),
		"断开后恢复自由，velocity.y=%.2f" % _player.velocity.y,
		"断开后玩家仍被向上拉，velocity.y=%.2f" % _player.velocity.y
	)
	return _finish()
