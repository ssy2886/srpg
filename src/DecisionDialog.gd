class_name DecisionDialog
extends Control

## DecisionDialog —— 抉择点演出（Phase 5）。
## 全屏暗化 + 面板（标题 / 描述 / 选项按钮）。选择后应用 effects 并显示结果，点「继续」关闭并回调 on_close。
## 用法：DecisionDialog.open_dialog(decision_id, on_close)

static var _active: DecisionDialog = null

@onready var title_label: Label = $Panel/TitleLabel
@onready var prompt_label: Label = $Panel/PromptLabel
@onready var options_box: VBoxContainer = $Panel/Options

var _on_close: Callable = Callable()
var _decision_id: String = ""

static func open_dialog(id: String, on_close: Callable = Callable()) -> void:
	if _active != null:
		return
	var d: Dictionary = DataManager.get_decision(id)
	if d.is_empty():
		push_error("DecisionDialog: 找不到抉择点 %s" % id)
		if on_close.is_valid():
			on_close.call()
		return
	# once 且已决定 -> 直接跳过，不重复弹
	if d.get("once", false) and Campaign.is_decided(id):
		if on_close.is_valid():
			on_close.call()
		return
	var scene: PackedScene = load("res://scenes/DecisionDialog.tscn")
	if scene == null:
		if on_close.is_valid():
			on_close.call()
		return
	var dlg: DecisionDialog = scene.instantiate()
	_active = dlg
	Engine.get_main_loop().root.add_child(dlg)
	dlg._setup(id, on_close)

func _setup(id: String, on_close: Callable) -> void:
	_decision_id = id
	_on_close = on_close
	var d: Dictionary = DataManager.get_decision(id)
	title_label.text = d.get("title", "抉择")
	prompt_label.text = d.get("prompt", "")
	for opt in d.get("options", []):
		var btn := Button.new()
		btn.text = opt.get("text", "?")
		btn.custom_minimum_size = Vector2(520, 46)
		btn.connect("pressed", _on_option_pressed.bind(opt))
		options_box.add_child(btn)

func _on_option_pressed(opt: Dictionary) -> void:
	_apply_effects(opt.get("effects", {}))
	Campaign.mark_decided(_decision_id)
	# 清空选项，显示结果文本 + 继续按钮
	for c in options_box.get_children():
		c.queue_free()
	var res: String = opt.get("effects", {}).get("result_text", "")
	var rl := Label.new()
	rl.text = res
	rl.autowrap_mode = 2                       # AUTOWRAP_WORD_SMART
	rl.horizontal_alignment = 1                # HORIZONTAL_ALIGNMENT_CENTER
	rl.custom_minimum_size = Vector2(520, 70)
	options_box.add_child(rl)
	var cont := Button.new()
	cont.text = "继续"
	cont.custom_minimum_size = Vector2(520, 46)
	cont.connect("pressed", _on_close_pressed)
	options_box.add_child(cont)

## 应用选项效果（数据驱动：flag / 角色 / 道具）。
func _apply_effects(eff: Dictionary) -> void:
	for f in eff.get("set_flags", []):
		Campaign.set_flag(f)
	for f in eff.get("clear_flags", []):
		Campaign.story_flags.erase(f)
	if eff.has("grant_char") and eff.grant_char != "":
		Campaign.grant_char(eff.grant_char)
	if eff.has("remove_char") and eff.remove_char != "":
		Campaign.owned_chars.erase(eff.remove_char)
	if eff.has("grant_item") and eff.grant_item != "":
		Campaign.grant_item(eff.grant_item)

func _on_close_pressed() -> void:
	_active = null
	queue_free()
	if _on_close.is_valid():
		_on_close.call()
