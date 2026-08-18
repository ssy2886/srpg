extends Node2D
## 单位头顶 HUD：HP 条 + 名称/Lv + 护盾提示。
## 作为 Unit 的最后一个子节点，绘制在精灵之上；HP 变化时由 Unit.refresh_label 触发 queue_redraw。

## Unit 类型声明（避免 class_name 注册顺序导致的 "Could not find type Unit"）。
const Unit = preload("res://src/Unit.gd")

const BAR_W: float = 44.0
const BAR_H: float = 6.0

func _draw() -> void:
	var u: Unit = get_parent()
	if u == null or not is_instance_valid(u):
		return
	var bx: float = -BAR_W / 2.0
	var by: float = -66.0
	var ratio: float = clamp(float(u.hp) / float(max(u.max_hp, 1)), 0.0, 1.0)

	# 外框 + 底
	draw_rect(Rect2(bx - 1, by - 1, BAR_W + 2, BAR_H + 2), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), Color(0.45, 0.08, 0.08))
	# 填充：我方绿、敌方红
	var col: Color = Color(0.35, 0.9, 0.35) if u.team == "player" else Color(0.95, 0.35, 0.3)
	draw_rect(Rect2(bx, by, BAR_W * ratio, BAR_H), col)
	# 护盾：蓝色细条（warding_light 等）
	if u.shield > 0:
		draw_rect(Rect2(bx, by - 4, BAR_W, 3), Color(0.4, 0.7, 1.0, 0.95))

	# 名称 + Lv（血条上方居中）
	var font: Font = ThemeDB.fallback_font
	if font != null:
		var txt := "%s Lv%d" % [u.display_name, u.lvl]
		var fs: int = 12
		var name_col: Color = Color(1, 1, 1) if u.team == "player" else Color(1, 0.7, 0.7)
		draw_string(font, Vector2(bx, by - 6), txt,
			HORIZONTAL_ALIGNMENT_CENTER, BAR_W, fs, name_col)
