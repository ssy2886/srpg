class_name SupportDialog
extends Control

## SupportDialog —— 支持对话演出（双立绘 + 文本框）。静态队列，关闭后弹下一条。
## 用法：SupportDialog.show_dialog(id_a, id_b, text)

static var _queue: Array = []
static var _active: SupportDialog = null

@onready var left: TextureRect = $Panel/LeftPortrait
@onready var right: TextureRect = $Panel/RightPortrait
@onready var text_label: Label = $Panel/TextLabel

static func show_dialog(id_a: String, id_b: String, text: String) -> void:
	_queue.append({"a": id_a, "b": id_b, "text": text})
	if _active == null:
		_pop()

static func _pop() -> void:
	if _queue.is_empty():
		_active = null
		return
	var scene := load("res://scenes/SupportDialog.tscn")
	if scene == null:
		_queue.clear()
		_active = null
		return
	var dlg = scene.instantiate()
	_active = dlg
	Engine.get_main_loop().root.add_child(dlg)
	var item: Dictionary = _queue.pop_front()
	dlg._setup(item.a, item.b, item.text)

## 强制关闭所有残留对话框（从战斗切回大地图时调用，避免叠加残留）。
static func close_all() -> void:
	if _active != null:
		_active.queue_free()
		_active = null
	_queue.clear()

func _setup(id_a: String, id_b: String, text: String) -> void:
	_set_portrait(left, id_a)
	_set_portrait(right, id_b)
	text_label.text = text if text != "" else "（暂无台词）"
	_active = self

static func _set_portrait(tex: TextureRect, id: String) -> void:
	var path: String = DataManager.get_character(id).get("portrait", "")
	if path != "" and FileAccess.file_exists(path):
		tex.texture = load(path)

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		queue_free()
		_active = null
		_pop()
