extends Control
class_name WorldMap

## 显式 preload 依赖，避免 class_name 全局注册顺序导致的解析误报。
const SupportTracker = preload("res://src/SupportTracker.gd")
const SupportDialog = preload("res://src/SupportDialog.gd")
const DecisionDialog = preload("res://src/DecisionDialog.gd")
const StoryDialog = preload("res://src/StoryDialog.gd")

## WorldMap —— 圣魔之光石式大地图探索层（Phase 3）。
## 读取 data/world.json 渲染节点，按 Campaign 状态判定显露，进入战斗后由 BattleController 回传结果。
## 用法：设为游戏主场景（或经 Battle 切换进入）。需把 Campaign.gd 注册为 Autoload。

const MARGIN_X := 110.0
const MARGIN_Y := 110.0

var nodes: Array = []
var cursor: int = 0
var _world: Dictionary = {}
var _font: Font
var _bg_tex: Texture2D = null       # 大地图背景图（res://assets/worldmap/worldmap_bg.png）
var _party_pos: Vector2 = Vector2.ZERO   # 队伍小人当前位置
var _party_tex: Texture2D = null    # 队伍小人精灵（lyra.png 第一帧，缩小）
var _move_from: Vector2 = Vector2.ZERO    # 移动轨迹起点（移动中高亮）
var _move_to: Vector2 = Vector2.ZERO      # 移动轨迹终点
var _moving: bool = false

func _ready() -> void:
	# 满屏锚点让 size 自动跟随窗口（_ready 时 viewport 尺寸未就绪，手动设 size 会偏）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	# 清理从战斗切回时可能残留的支持对话
	SupportDialog.close_all()
	# 弹出本场战斗结束待弹的支持对话（C/B/A 级演出）
	for req in Campaign.pending_support:
		var txt: String = SupportTracker.get_instance().dialog_text(req.a, req.b, req.rank)
		SupportDialog.show_dialog(req.a, req.b, txt)
	Campaign.pending_support = []
	_save_progress()
	# 弹出战斗胜利后待弹的抉择点（Phase 5，仿 pending_support）
	if Campaign.pending_decision != "":
		var pid: String = Campaign.pending_decision
		Campaign.pending_decision = ""
		var cb := func():
			queue_redraw()
			_save_progress()
		DecisionDialog.open_dialog(pid, cb)
	# 读大地图节点
	var text := FileAccess.get_file_as_string("res://data/world.json")
	_world = JSON.parse_string(text)
	nodes = _world.get("nodes", [])
	if nodes.is_empty():
		push_error("WorldMap: world.json 解析失败或节点为空")
	_focus_first_available()
	_bg_tex = _load_texture("res://assets/worldmap/worldmap_bg.png")
	_party_tex = _load_texture("res://assets/sprites/units/lyra.png")
	if nodes.size() > 0:
		_party_pos = _node_pos(cursor)

func _load_texture(path: String) -> Texture2D:
	# 有 .import 用 load()（最快），否则直接 Image.load()（避免未导入资源的 loader 警告）。
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

func _focus_first_available() -> void:
	for i in nodes.size():
		if _is_available(nodes[i]):
			cursor = i
			return

## 落盘当前战役进度（含 permadeath / roster / 抉择 / 支持）。
func _save_progress() -> void:
	SaveManager.save(Campaign.serialize())

## 显露判定：满足 unlock 全部条件才显露（已清的也允许重打，便于演示）。
func _is_unlocked(n: Dictionary) -> bool:
	var u: Dictionary = n.get("unlock", {})
	for c in u.get("requires_clear", []):
		if not Campaign.is_cleared(c):
			return false
	# requires_any_clear：满足任一已通关即可（用于分支汇合）
	var any_clear: Array = u.get("requires_any_clear", [])
	if not any_clear.is_empty():
		var any_ok := false
		for c in any_clear:
			if Campaign.is_cleared(c):
				any_ok = true
				break
		if not any_ok:
			return false
	for c in u.get("requires_character", []):
		if not Campaign.owns_char(c):
			return false
	for f in u.get("requires_flag", []):
		if not Campaign.has_flag(f):
			return false
	# forbid_flag：命中任一则隐藏（用于抉择互斥分支，如选了霜峰则隐藏河谷）
	for f in u.get("forbid_flag", []):
		if Campaign.has_flag(f):
			return false
	return true

func _is_available(n: Dictionary) -> bool:
	return _is_unlocked(n)

## 判断 b 是否在剧情路线上直接跟在 a 之后（b 的解锁依赖包含 a 的 map_id）。
## 用于画"路线连线"，只连相邻章节，避免所有已解锁节点两两互联成乱网。
func _is_route_link(a: Dictionary, b: Dictionary) -> bool:
	var a_map: String = a.get("map_id", "")
	if a_map == "":
		return false
	var u: Dictionary = b.get("unlock", {})
	if u.get("requires_clear", []).has(a_map):
		return true
	if u.get("requires_any_clear", []).has(a_map):
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT, KEY_DOWN:
				_move_cursor(1)
			KEY_LEFT, KEY_UP:
				_move_cursor(-1)
			KEY_ENTER, KEY_SPACE:
				_enter_current()
			KEY_C:
				get_tree().change_scene_to_file("res://scenes/Camp.tscn")
			KEY_ESCAPE:
				_save_progress()
				get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_local_mouse_position()
		for i in nodes.size():
			if _node_rect(i).has_point(mp) and _is_available(nodes[i]):
				if i == cursor:
					_enter_current()
				else:
					_travel_to(i, true)
				return

func _move_cursor(dir: int) -> void:
	var n := nodes.size()
	for k in range(1, n + 1):
		var idx := (cursor + dir * k + n * 100) % n
		if _is_available(nodes[idx]):
			_travel_to(idx, false)
			return

## 队伍小人沿连线"走着"移动到节点 idx（每帧重绘，0.6s，有行走感）。enter_after=true 则移动完成进入节点。
func _travel_to(idx: int, enter_after: bool) -> void:
	if _moving:
		return
	var from: Vector2 = _node_pos(cursor)
	cursor = idx
	var to: Vector2 = _node_pos(idx)
	_move_from = from
	_move_to = to
	_moving = true
	var tw := create_tween()
	# 每帧更新 _party_pos 并重绘，呈现连续行走
	tw.tween_method(func(t: float) -> void:
		_party_pos = from.lerp(to, t)
		queue_redraw(), 0.0, 1.0, 0.6)
	tw.tween_callback(func() -> void: _on_travel_done(enter_after))
	queue_redraw()

func _on_travel_done(enter_after: bool) -> void:
	_moving = false
	_move_from = Vector2.ZERO
	_move_to = Vector2.ZERO
	queue_redraw()
	if enter_after:
		_enter_current()

func _enter_current() -> void:
	if cursor < 0 or cursor >= nodes.size():
		return
	var n: Dictionary = nodes[cursor]
	# 抉择节点：未决定则弹抉择点（关闭后刷新大地图），纯剧情节点不再进战斗
	var dec_id: String = n.get("decision", "")
	if dec_id != "" and not Campaign.is_decided(dec_id):
		var cb := func():
			queue_redraw()
			_focus_first_available()
			_save_progress()
		DecisionDialog.open_dialog(dec_id, cb)
		return
	var map_id: String = n.get("map_id", "")
	if map_id == "":
		queue_redraw()   # 无地图的剧情/已抉择节点：停留
		return
	Campaign.current_map_id = map_id
	# 进入关卡前剧情（仅首次播放；已看过的直接进战斗）
	var story_key: String = map_id + "_enter"
	if not Campaign.is_story_seen(story_key) and not DataManager.get_story(story_key).is_empty():
		Campaign.mark_story_seen(story_key)
		StoryDialog.play(story_key, func() -> void:
			get_tree().change_scene_to_file("res://scenes/Battle.tscn"))
	else:
		get_tree().change_scene_to_file("res://scenes/Battle.tscn")

func _node_pos(i: int) -> Vector2:
	var p: Array = nodes[i].get("pos", [0, 0])
	var sx: float = (size.x - MARGIN_X * 2.0) / 9.0
	var sy: float = (size.y - MARGIN_Y * 2.0 - 60.0) / 6.0
	return Vector2(MARGIN_X + int(p[0]) * sx, MARGIN_Y + int(p[1]) * sy)

func _node_rect(i: int) -> Rect2:
	var c := _node_pos(i)
	return Rect2(c.x - 22, c.y - 22, 44, 44)

func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	# 背景：有图用图，否则深色底 + 网格占位（背景图到位后自动替换）
	if _bg_tex != null:
		draw_texture_rect(_bg_tex, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.14, 0.20))
		for gx in range(0, int(size.x), 64):
			draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(1, 1, 1, 0.03), 1)
		for gy in range(0, int(size.y), 64):
			draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(1, 1, 1, 0.03), 1)
	# 标题
	draw_string(_font, Vector2(30, 44), _world.get("title", "大地图"), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.9, 0.9, 0.7))
	# 剧情路线连线：只连"解锁依赖"上相邻的节点（主线前后章 + 分支），不再两两互联成乱网。
	for i in nodes.size():
		if not _is_unlocked(nodes[i]):
			continue
		for j in nodes.size():
			if i == j or not _is_unlocked(nodes[j]):
				continue
			if _is_route_link(nodes[i], nodes[j]):
				draw_line(_node_pos(i), _node_pos(j), Color(0.25, 0.3, 0.4), 2)
	# 节点（小地标点，不用大圆圈，让小人成为视觉主体）
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		var c := _node_pos(i)
		var unlocked := _is_unlocked(n)
		var cleared := Campaign.is_cleared(n.get("map_id", ""))
		var col: Color
		if not unlocked:
			col = Color(0.18, 0.18, 0.22)
		elif cleared:
			col = Color(0.35, 0.8, 0.4)
		else:
			col = Color(0.9, 0.75, 0.3)
		# 小地标点 + 外圈光晕（代替大圆圈图标）
		draw_circle(c, 7, col)
		draw_arc(c, 10, 0, TAU, 24, Color(col.r, col.g, col.b, 0.5), 2)
		draw_string(_font, c + Vector2(-52, 30), n.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.92))
		if cleared:
			draw_string(_font, c + Vector2(-5, 6), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		if i == cursor and _is_available(n):
			# 当前节点：脉冲高亮圈
			draw_arc(c, 15, 0, TAU, 40, Color(1.0, 0.95, 0.2), 3)
			var hint: String = n.get("reward_hint", "")
			if hint != "":
				draw_string(_font, c + Vector2(-52, -28), "★ %s" % hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.4))
	# 移动轨迹高亮（移动中）
	if _moving:
		draw_line(_move_from, _move_to, Color(1.0, 0.95, 0.3, 0.85), 4.0)
	# 队伍小人（站在节点上，复用 lyra.png 战斗精灵第一帧）
	if _party_tex != null:
		var ps := Vector2(48, 48)
		draw_texture_rect_region(_party_tex, Rect2(_party_pos - Vector2(ps.x / 2.0, ps.y - 8), ps), Rect2(0, 0, 64, 64))
	else:
		draw_circle(_party_pos, 9, Color(1, 1, 1))
	# 底部状态栏
	var party := "队伍：" + ", ".join(Campaign.owned_char_list())
	var items := "道具：" + (", ".join(Campaign.owned_item_list()) if Campaign.owned_item_list().size() > 0 else "无")
	draw_string(_font, Vector2(30, size.y - 52), party, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.9, 1.0))
	draw_string(_font, Vector2(30, size.y - 28), items, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.8))
	var pd := "永久死亡：%s" % ("开" if Campaign.permadeath else "关（重伤撤退）")
	draw_string(_font, Vector2(size.x - 360, size.y - 52), pd, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.6, 0.6))
	draw_string(_font, Vector2(size.x - 360, size.y - 28), "方向键选择 · Enter 进入 · C 营地 · Esc 标题", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6))
