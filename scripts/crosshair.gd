extends Control
## 屏幕中央的十字准心。
##
## 挂在 CanvasLayer 下、锚点居中，用 [method _draw] 画四条带描边的短线，
## 中心留空以便看清瞄准目标。鼠标事件一律穿透，不会挡住发射钩爪的按键。

@export_group("形状")
## 每条线从中心向外延伸的长度（像素）
@export var line_length: float = 8.0
## 中心留空的半径（像素），避免遮住瞄准点
@export var center_gap: float = 4.0
## 线的粗细（像素）
@export var thickness: float = 2.0
## 中心点半径，设为 0 则不画中心点
@export var dot_radius: float = 1.5

@export_group("颜色")
@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
## 描边颜色，让准心在浅色背景上也看得清
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.45)
## 描边比主线宽出的像素，设为 0 则不描边
@export var outline_width: float = 2.0

const _DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


func _ready() -> void:
	# 准心只是装饰，不能拦截鼠标事件
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5

	for direction in _DIRECTIONS:
		var from := center + direction * center_gap
		var to := center + direction * (center_gap + line_length)
		if outline_width > 0.0:
			draw_line(from, to, outline_color, thickness + outline_width, true)
		draw_line(from, to, color, thickness, true)

	if dot_radius > 0.0:
		if outline_width > 0.0:
			draw_circle(center, dot_radius + outline_width * 0.5, outline_color)
		draw_circle(center, dot_radius, color)
