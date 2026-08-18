extends Control
class_name WeaponTriIcon

## 武器相克的图标化视觉：纯绘制，无需图片资源。
## adv = 1  上三角(绿/有利)
## adv = -1 下三角(红/不利)
## adv = 0  菱形(灰/无相克)

var adv: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(18, 18)
	queue_redraw()

func set_state(a: int) -> void:
	adv = a
	queue_redraw()

func _draw() -> void:
	var s: float = size.x
	var cx: float = s * 0.5
	var bd: float = 2.0
	var outline := Color(0.08, 0.08, 0.1)
	var fill: Color
	if adv == 1:
		fill = Color(0.25, 0.85, 0.35)
	elif adv == -1:
		fill = Color(0.92, 0.30, 0.30)
	else:
		fill = Color(0.62, 0.62, 0.68)
	var pts: PackedVector2Array
	if adv == 1:
		pts = PackedVector2Array([Vector2(cx, 1.5), Vector2(s - 1.5, s - 1.5), Vector2(1.5, s - 1.5)])
	elif adv == -1:
		pts = PackedVector2Array([Vector2(1.5, 1.5), Vector2(s - 1.5, 1.5), Vector2(cx, s - 1.5)])
	else:
		pts = PackedVector2Array([Vector2(cx, 0.5), Vector2(s - 0.5, cx), Vector2(cx, s - 0.5), Vector2(0.5, cx)])
	draw_polygon(pts, [fill])
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, outline, bd)
