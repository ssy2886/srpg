class_name StoryDialog
extends Control

## StoryDialog —— 全屏剧情演出：暗色背景 + 标题 + 说话人名 + 立绘 + 逐行文本。
## 用法：StoryDialog.play(story_key, on_done)，播完调用 on_done（无参 Callable）。

var _lines: Array = []
var _idx: int = 0
var _on_done: Callable = Callable()
var _title: String = ""

var _speaker_label: Label
var _text_label: Label
var _portrait: TextureRect
var _hint: Label

## 播放指定剧情；story_key 不存在则直接回调 on_done。
static func play(story_key: String, on_done: Callable = Callable()) -> void:
	var story: Dictionary = DataManager.get_story(story_key)
	if story.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	# 用脚本资源自身实例化，避免 class_name 自引用的注册顺序问题。
	var script: Script = load("res://src/StoryDialog.gd")
	var dlg: Control = script.new()
	Engine.get_main_loop().root.add_child(dlg)
	dlg._begin(story, on_done)

func _begin(story: Dictionary, on_done: Callable) -> void:
	_title = story.get("title", "")
	_lines = story.get("lines", [])
	_on_done = on_done
	_idx = 0
	_build_ui()
	_show_line()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 半透明暗背景
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 顶部标题
	if _title != "":
		var tl := Label.new()
		tl.text = _title
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", 28)
		tl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
		tl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		tl.offset_top = 26
		add_child(tl)
	# 立绘（左下）
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(150, 190)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait.offset_left = 40
	_portrait.offset_top = -260
	_portrait.offset_right = 190
	_portrait.offset_bottom = -50
	add_child(_portrait)
	# 文本框（底部）
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 210
	panel.offset_right = -40
	panel.offset_top = -190
	panel.offset_bottom = -40
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 20)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(_speaker_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 19)
	_text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	vb.add_child(_text_label)
	_hint = Label.new()
	_hint.text = "▼ 点击 / 任意键 继续"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -220
	_hint.offset_top = -36
	add_child(_hint)

func _show_line() -> void:
	if _idx >= _lines.size():
		_finish()
		return
	var line: Dictionary = _lines[_idx]
	var sid: String = line.get("speaker", "旁白")
	_speaker_label.text = sid if sid == "旁白" else DataManager.get_character(sid).get("name", sid)
	_text_label.text = line.get("text", "")
	# 立绘：旁白隐藏，角色按 portrait 显示
	if sid == "旁白":
		_portrait.texture = null
	else:
		var path: String = DataManager.get_character(sid).get("portrait", "")
		if path != "" and FileAccess.file_exists(path):
			_portrait.texture = load(path)
		else:
			_portrait.texture = null

func _finish() -> void:
	var cb := _on_done
	queue_free()
	if cb.is_valid():
		cb.call()

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		get_viewport().set_input_as_handled()
		_idx += 1
		_show_line()
