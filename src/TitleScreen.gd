extends Control
class_name TitleScreen

const StoryDialog = preload("res://src/StoryDialog.gd")

## TitleScreen —— 主菜单 / 设置（Phase 6）。
## 提供：新游戏、继续（存在存档时）、永久死亡开关、退出。
## 永久死亡开关影响整局：开 = 我方单位阵亡即永久退场；关 = 重伤撤退，下场满状态回归。

var _permadeath: bool = false
var _pd_btn: Button

func _ready() -> void:
	# 根节点满屏锚点（不手动设 size，避免 _ready 时 viewport 尺寸未就绪导致布局偏移）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.18)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# CenterContainer 自动居中，无需手动算 position。
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(380, 340)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "剑与魔法 · 战旗"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "火焰纹章式垂直切片"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(sub)

	var btn_new := Button.new()
	btn_new.text = "新游戏"
	btn_new.pressed.connect(_on_new)
	vbox.add_child(btn_new)

	var btn_cont := Button.new()
	btn_cont.text = "继续"
	btn_cont.pressed.connect(_on_continue)
	if not SaveManager.has_save():
		btn_cont.disabled = true
		btn_cont.tooltip_text = "暂无存档"
	vbox.add_child(btn_cont)

	_pd_btn = Button.new()
	_pd_btn.pressed.connect(_on_toggle_pd)
	vbox.add_child(_pd_btn)
	_update_pd_label()

	var btn_quit := Button.new()
	btn_quit.text = "退出"
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)

func _on_new() -> void:
	SaveManager.delete_save()
	Campaign.new_game(_permadeath)
	# 新游戏先播开场剧情，结束后再进大地图
	print("[TitleScreen] 新游戏，播放开场剧情，story 数据:", not DataManager.get_story("opening").is_empty())
	StoryDialog.play("opening", func() -> void:
		print("[TitleScreen] 剧情播完，进入大地图")
		get_tree().change_scene_to_file("res://scenes/WorldMap.tscn"))

func _on_continue() -> void:
	var d := SaveManager.load_save()
	if d.is_empty():
		return
	Campaign.deserialize(d)
	get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")

func _on_toggle_pd() -> void:
	_permadeath = not _permadeath
	_update_pd_label()

func _update_pd_label() -> void:
	if _pd_btn:
		_pd_btn.text = "永久死亡：%s" % ("开（阵亡即永久退场）" if _permadeath else "关（重伤撤退）")

func _on_quit() -> void:
	get_tree().quit()
