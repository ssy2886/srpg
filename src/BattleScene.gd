class_name BattleScene
extends Control

## BattleScene —— 全屏战斗特写（A+a：2D立绘 + 全屏演出）。
## 双方正常比例人物分立左右，按战报数据演出：前冲→挥砍→受击→(暴击特写)→追击→返回。
## 用法：BattleScene.play(att, def, report, on_hit_apply, on_done)
##   report: [{attacker, defender, hit, damage, crit, miss}] 依次演出
##   on_hit_apply(index): 第 index 次命中落地时回调（用于真实扣血/结算）
##   on_done: 全部演完回调（切回地图）

var _steps: Array = []
var _on_hit: Callable = Callable()
var _on_done: Callable = Callable()
var _idx: int = 0

var _left: TextureRect    # 攻方立绘
var _right: TextureRect   # 守方立绘
var _left_hp: ProgressBar
var _right_hp: ProgressBar
var _dmg_label: Label
var _left_info: Dictionary = {}
var _right_info: Dictionary = {}

static func play(att: Unit, def: Unit, steps: Array, on_hit: Callable, on_done: Callable) -> void:
	var script: Script = load("res://src/BattleScene.gd")
	var sc: Control = script.new()
	Engine.get_main_loop().root.add_child(sc)
	sc._begin(att, def, steps, on_hit, on_done)

func _begin(att: Unit, def: Unit, steps: Array, on_hit: Callable, on_done: Callable) -> void:
	_steps = steps
	_on_hit = on_hit
	_on_done = on_done
	_left_info = {"unit": att, "name": att.display_name, "hp": att.hp, "max_hp": att.max_hp}
	_right_info = {"unit": def, "name": def.display_name, "hp": def.hp, "max_hp": def.max_hp}
	_idx = 0
	_build_ui()
	# 开场：双方滑入
	_slide_in()

func _unit_portrait(u: Unit) -> Texture2D:
	var sid: String = u.char_id if u.char_id != "" else ""
	if sid == "":
		sid = u.class_id   # 敌人用职业通用立绘（若无则回退）
	var cutout := "res://assets/portraits/cutout/%s.png" % sid
	if FileAccess.file_exists(cutout):
		return _load_tex(cutout)
	var p: String = DataManager.get_character(sid).get("portrait", "")
	if p != "" and FileAccess.file_exists(p):
		return _load_tex(p)
	return null

func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if FileAccess.file_exists(path + ".import"):
		var r = load(path)
		if r != null:
			return r
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 背景：暗色渐变 + 中央战场光
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var floor_glow := ColorRect.new()
	floor_glow.color = Color(0.2, 0.18, 0.3, 0.5)
	floor_glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	floor_glow.offset_left = -512
	floor_glow.offset_right = 512
	floor_glow.offset_top = -160
	floor_glow.offset_bottom = 0
	add_child(floor_glow)

	# 攻方立绘（左侧，面朝右）
	_left = TextureRect.new()
	_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left.custom_minimum_size = Vector2(360, 480)
	_left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_left.offset_left = 60
	_left.offset_top = -240
	_left.offset_right = 420
	_left.offset_bottom = 240
	_left.texture = _unit_portrait(_left_info.unit)
	add_child(_left)
	# 守方立绘（右侧，面朝左=翻转）
	_right = TextureRect.new()
	_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right.custom_minimum_size = Vector2(360, 480)
	_right.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_right.offset_left = -420
	_right.offset_top = -240
	_right.offset_right = -60
	_right.offset_bottom = 240
	_right.texture = _unit_portrait(_right_info.unit)
	_right.flip_h = true
	add_child(_right)

	# 顶部双方 HP 条 + 名字
	_left_hp = _make_hp_bar(true)
	_right_hp = _make_hp_bar(false)
	# 伤害数字（中央）
	_dmg_label = Label.new()
	_dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dmg_label.add_theme_font_size_override("font_size", 72)
	_dmg_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	_dmg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_dmg_label.add_theme_constant_override("shadow_offset_x", 4)
	_dmg_label.add_theme_constant_override("shadow_offset_y", 4)
	_dmg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dmg_label.offset_left = -200
	_dmg_label.offset_right = 200
	_dmg_label.offset_top = -120
	_dmg_label.offset_bottom = -40
	_dmg_label.modulate.a = 0.0
	add_child(_dmg_label)

func _make_hp_bar(is_left: bool) -> ProgressBar:
	var info: Dictionary = _left_info if is_left else _right_info
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = info.max_hp
	bar.value = info.hp
	bar.custom_minimum_size = Vector2(300, 22)
	bar.show_percentage = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.9, 0.4)
	sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", sb)
	var sbb := StyleBoxFlat.new()
	sbb.bg_color = Color(0.15, 0.15, 0.2)
	sbb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", sbb)
	var name_lbl := Label.new()
	name_lbl.text = info.name
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	if is_left:
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		bar.offset_left = 40; bar.offset_top = 40; bar.offset_right = 340; bar.offset_bottom = 62
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		name_lbl.offset_left = 40; name_lbl.offset_top = 12
	else:
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		bar.offset_left = -340; bar.offset_top = 40; bar.offset_right = -40; bar.offset_bottom = 62
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		name_lbl.offset_left = -340; name_lbl.offset_top = 12
	add_child(bar)
	add_child(name_lbl)
	return bar

func _slide_in() -> void:
	# 双方从两侧滑入
	var l_start := _left.position.x - 200
	var r_start := _right.position.x + 200
	var l_end := _left.position.x
	var r_end := _right.position.x
	_left.position.x = l_start
	_right.position.x = r_start
	_left.modulate.a = 0.0
	_right.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_left, "position:x", l_end, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_right, "position:x", r_end, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_left, "modulate:a", 1.0, 0.4)
	tw.tween_property(_right, "modulate:a", 1.0, 0.4)
	tw.chain().tween_callback(_play_step)

func _play_step() -> void:
	if _idx >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_idx]
	var attacker: Unit = step.attacker
	var atk_rect: TextureRect = _left if attacker == _left_info.unit else _right
	var def_rect: TextureRect = _right if attacker == _left_info.unit else _left
	var dir: float = 1.0 if attacker == _left_info.unit else -1.0
	# 攻击：前冲 → 命中顿帧 → 受击后仰+闪白 → 回位
	var tw := create_tween()
	var orig_x: float = atk_rect.position.x
	tw.tween_property(atk_rect, "position:x", orig_x + dir * 90, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _apply_hit(step, def_rect))
	tw.tween_property(atk_rect, "position:x", orig_x, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void:
		_idx += 1
		_play_step())

func _apply_hit(step: Dictionary, def_rect: TextureRect) -> void:
	# 真实结算回调（扣血/经验等）
	if _on_hit.is_valid():
		_on_hit.call(_idx)
	# 伤害数字
	if step.get("hit", false):
		var dmg: int = int(step.get("damage", 0))
		_dmg_label.text = ("暴击\n%d" % dmg) if step.get("crit", false) else str(dmg)
		_dmg_label.add_theme_font_size_override("font_size", 96 if step.get("crit", false) else 72)
	else:
		_dmg_label.text = "MISS"
		_dmg_label.add_theme_font_size_override("font_size", 56)
	_dmg_label.modulate.a = 1.0
	_dmg_label.scale = Vector2(1.6, 1.6)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dmg_label, "scale", Vector2(1, 1), 0.2)
	tw.tween_property(_dmg_label, "modulate:a", 0.0, 0.8).set_delay(0.4)
	# 受击：后仰 + 闪白 + 震屏
	if step.get("hit", false):
		var def_dir: float = 1.0 if def_rect == _left else -1.0
		var dtw := create_tween()
		dtw.tween_property(def_rect, "position:x", def_rect.position.x + def_dir * 24, 0.08)
		dtw.tween_property(def_rect, "position:x", def_rect.position.x, 0.15)
		_flash_white(def_rect)
		_shake(6.0 if step.get("crit", false) else 3.0)
	# 更新 HP 条
	var dinfo: Dictionary = _left_info if def_rect == _left else _right_info
	var dbar: ProgressBar = _left_hp if def_rect == _left else _right_hp
	if is_instance_valid(dinfo.unit):
		var btw := create_tween()
		btw.tween_property(dbar, "value", max(0, dinfo.unit.hp), 0.3)

func _flash_white(rect: TextureRect) -> void:
	rect.modulate = Color(3, 3, 3)
	var tw := create_tween()
	tw.tween_property(rect, "modulate", Color(1, 1, 1), 0.25)

func _shake(power: float) -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(self, "position", Vector2(randf_range(-power, power), randf_range(-power, power)), 0.03)
	tw.tween_property(self, "position", Vector2.ZERO, 0.05)

func _finish() -> void:
	# 双方淡出，场景释放，回调切回地图
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		var cb := _on_done
		queue_free()
		if cb.is_valid():
			cb.call())

## 加载纹理（带 .import 检测）。
