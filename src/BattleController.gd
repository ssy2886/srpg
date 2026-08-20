extends Node2D
class_name BattleController

## 显式 preload 依赖，避免 class_name 全局注册顺序导致的解析误报。
const SupportTracker = preload("res://src/SupportTracker.gd")
const Combat = preload("res://src/Combat.gd")
const SkillManager = preload("res://src/SkillManager.gd")
const WeaponTriIcon = preload("res://src/WeaponTriIcon.gd")
const Unit = preload("res://src/Unit.gd")
const StoryDialog = preload("res://src/StoryDialog.gd")
const BattleScene = preload("res://src/BattleScene.gd")

## BattleController —— Phase 1 外层驱动：回合循环、点击选择、移动/攻击、敌方 AI、伤害浮字。
## 用法：建 Node2D 场景挂本脚本；放一个 TileMapLayer 子节点，检查器里把 tile_map 指向它、
## unit_scene 指向 res://scenes/Unit.tscn。运行即加载 prologue_01 开打。

@export var tile_map: TileMap
@export var unit_scene: PackedScene
@export var tile_size: int = 48
@export var start_map: String = "prologue_01"

var units: Array = []
var occupied: Dictionary = {}      # Vector2i -> Unit
var terrain_grid: Array = []
var phase: String = "PLAYER"      # PLAYER | ENEMY
var turn: int = 1
var objective: Dictionary = {}    # 当前地图胜利条件
var battle_over: bool = false     # 胜负已分，锁输入
var _support_unlocks: Array = []  # 本场战斗中新解锁的支持对话请求
var _campaign_snapshot: Dictionary = {}  # 开战前战役快照（战败时还原）
var _player_ids: Array = []        # 本场我方角色 id 列表（用于判定阵亡）
# ---- 战斗内属性面板（Phase 6.1） ----
var stat_panel: Panel = null
var stat_label: Label = null
var forecast_panel: Panel = null   # 战斗预测窗口（选中我方 + 悬停攻击范围内敌人时显示）
var forecast_title: Label = null
var forecast_match: Label = null
var forecast_tri_label: Label = null
var forecast_tri_icon: WeaponTriIcon = null
var forecast_tri_text: Label = null
var forecast_att: Label = null
var forecast_counter: Label = null
var forecast_result: Label = null
var _hover_unit: Unit = null       # 鼠标悬停的单位（用于属性面板预读）
const WEAPON_NAME := {"sword":"剑","axe":"斧","lance":"枪","bow":"弓","anima":"理","light":"光","dark":"暗","staff":"杖"}

var selected: Unit = null
var move_cells: Array = []        # 可移动格
var attack_cells_list: Array = [] # 移动后可攻击格
var _preview_path: Array = []              # 移动路径预览（悬停目标格时）
var _pre_move_pos: Vector2i = Vector2i.ZERO  # 移动前原位（取消行动时返回）
var _moved_this_action: bool = false         # 本回合已移动（用于取消返回原位）
var _inspect_move: Array = []                # 查看目标（敌人）的移动范围
var _inspect_attack: Array = []              # 查看目标（敌人）的攻击范围
var _sys_menu: PopupMenu = null              # 系统菜单（Esc 呼出）
var _action_menu: PopupMenu = null          # 当前行动菜单（攻击/待命/道具）
var cam: Camera2D = null                     # 战斗相机（方向键移动视角）

func _ready() -> void:
	if tile_map == null:
		tile_map = get_node_or_null("TileMap")
	if tile_map != null:
		tile_map.z_index = -10   # 地形沉到最底，让 _draw 画的移动/攻击范围高亮显示在地形之上
		if tile_map.tile_set == null:
			tile_map.tile_set = _build_tileset()
	var map_id := Campaign.current_map_id if Campaign.current_map_id != "" else start_map
	_init_battle(map_id)
	_setup_camera()
	_build_stat_panel()
	_build_forecast_panel()

func _init_battle(map_id: String) -> void:
	if tile_map == null or unit_scene == null:
		push_error("BattleController: 请在检查器设置 tile_map 与 unit_scene")
		return
	var map: Dictionary = DataManager.get_map(map_id)
	if map.is_empty():
		return
	terrain_grid = map.get("grid", [])
	objective = map.get("objective", {})
	_support_unlocks = []

	# 整图背景（方案A）：地图 JSON 指定 bg_image 时用整图铺满，TileMap 不再画彩色方块。
	var bg_img: String = map.get("bg_image", "")
	if bg_img != "":
		_setup_bg_image(bg_img)

	# 铺地形（无背景图时用程序化 TileSet 画彩色方块；有背景图时 TileMap 留空，仅作逻辑层）
	if bg_img == "" and tile_map != null and tile_map.tile_set != null:
		for y in terrain_grid.size():
			for x in terrain_grid[y].size():
				var t: Dictionary = DataManager.get_terrain(terrain_grid[y][x])
				var atlas: Array = t.get("atlas", [0, 0])
				tile_map.set_cell(0, Vector2i(x, y), 0, Vector2i(int(atlas[0]), int(atlas[1])))

	# 生成单位
	for u in map.get("units", []):
		var unit: Unit = unit_scene.instantiate()
		unit.setup(u)
		unit.position = Vector2(unit.grid_pos.x, unit.grid_pos.y) * tile_size \
			+ Vector2(tile_size / 2, tile_size / 2)
		add_child(unit)
		units.append(unit)
		occupied[unit.grid_pos] = unit
		if unit.team == "player" and unit.char_id != "":
			_player_ids.append(unit.char_id)
	# 开战前快照：战败时还原到进入本战之前的状态
	_campaign_snapshot = Campaign.serialize()
	_refresh_unit_visuals()
	print("[BattleController] 地图 %s 载入，单位 %d，玩家阶段开始 | 目标：%s" % [map_id, units.size(), objective.get("description", "—")])
	# 战场开场简短对话（{map_id}_battle），仅首次进入本关时播放
	var battle_key: String = "%s_battle" % map_id
	if not Campaign.is_story_seen(battle_key):
		Campaign.mark_story_seen(battle_key)
		StoryDialog.play(battle_key)

# ---------- 输入 ----------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_moved(event)
		return
	if _action_menu != null or _sys_menu != null:
		return   # 菜单期间，忽略战斗输入（菜单自身处理点击/Esc）
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			# 有选中/行动中 → 取消行动；否则 → 呼出系统菜单
			if selected != null or _moved_this_action:
				_cancel_action()
			else:
				_toggle_system_menu()
			return
		_handle_debug_keys(event)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	# 右键：取消当前操作（取消查看敌方范围 / 取消选中 / 取消行动返回原位）
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if _inspect_move.size() > 0 or _inspect_attack.size() > 0:
			_inspect_move = []
			_inspect_attack = []
			queue_redraw()
		elif selected != null or _moved_this_action:
			_cancel_action()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if phase != "PLAYER" or battle_over:
		return
	var _lp: Vector2 = tile_map.to_local(get_global_mouse_position())
	var cell: Vector2i = Vector2i(int(_lp.x) / tile_size, int(_lp.y) / tile_size)
	_on_tile_clicked(cell)

## 调试/养成快捷键（正式版可改为道具菜单 UI）
func _handle_debug_keys(event: InputEventKey) -> void:
	if selected == null or selected.team != "player":
		return
	match event.keycode:
		KEY_P:   # 转职：选中的我方单位满足条件则转第一个分支
			if selected.can_promote():
				var choices: Array = selected.promote_choices()
				if choices.size() > 0 and selected.promote_to(choices[0]):
					_show_banner("转职成功！\n%s → %s" % [
						selected.display_name, DataManager.get_class_data(choices[0]).get("name", choices[0])],
						Color(0.6, 0.85, 1.0), true)
					print("[BattleController] %s 转职为 %s" % [selected.display_name, choices[0]])
			else:
				print("[BattleController] %s 暂不可转职（需 Lv10 + 转职道具）" % selected.display_name)
		KEY_0:   # 调试：+100 经验
			_show_floater(selected.position, "EXP+100", Color(0.8, 0.9, 1.0))
			selected.gain_exp(100)
		KEY_9:   # 调试：直接置 Lv10 并发放转职道具，便于演示转职
			if selected.inventory.find(DataManager.PROMOTE_ITEM) == -1:
				selected.inventory.append(DataManager.PROMOTE_ITEM)
			if selected.lvl < 10:
				selected.gain_exp((10 - selected.lvl) * 100)
			_show_floater(selected.position, "调试 Lv10", Color(0.6, 0.85, 1.0))
		KEY_K:   # 主动：armor_pierce（破甲，加勒特持有）
			_try_activate(selected, "armor_pierce")
		KEY_H:   # 主动：warding_light（守护之光，米拉持有）
			_try_activate(selected, "warding_light")
		KEY_T:   # 调试：为选中单位与所有友军 +15 并肩回合（演示支持解锁，每按升一级）
			for a in _alive("player"):
				if a.char_id != "" and a != selected:
					_support_unlocks.append_array(SupportTracker.get_instance().record_battle_turns([selected.char_id, a.char_id], 15))
			_show_floater(selected.position, "支持+15", Color(1.0, 0.8, 1.0))

func _on_tile_clicked(cell: Vector2i) -> void:
	if selected == null:
		var u = occupied.get(cell)
		if u and u.team == "player" and not u.acted:
			_select_unit(u)
		elif u and u.team == "enemy":
			_inspect_unit(u)   # 点敌人：查看其移动/攻击范围
		return

	if occupied.has(cell) and occupied[cell] == selected:
		# 点自己 = 原地攻击（显示攻击范围，不动也能打）；若想待机选行动菜单"待命"或再点空白
		_show_attack_range(selected)
		return
	if cell in attack_cells_list and occupied.has(cell) and occupied[cell].team == "enemy":
		_pick_weapon_and_attack(selected, occupied[cell])
		return
	if cell in move_cells:
		_move_unit(selected, cell)
		return   # 移动到达后由 _move_unit 弹出行动菜单（攻击/待命/道具）
	if occupied.has(cell) and occupied[cell].team == "player" and not occupied[cell].acted:
		_select_unit(occupied[cell])  # 切换选中
		return
	if occupied.has(cell) and occupied[cell].team == "enemy":
		_inspect_unit(occupied[cell])   # 已选中时再点敌人：查看其范围
		return
	_end_unit_action(selected)       # 点别处 = 待机

## 查看敌人（或任意单位）的移动范围与攻击范围预览。
func _inspect_unit(u: Unit) -> void:
	selected = null
	move_cells = []
	attack_cells_list = []
	_preview_path = []
	_inspect_move = Combat.move_range(u, terrain_grid, occupied)
	var w: Dictionary = DataManager.get_weapon(u.equipped_weapon)
	_inspect_attack = []
	if not w.is_empty():
		# 敌人移动后可攻击的所有格（简化：当前位置 + 各可移动格的攻击范围并集）
		var cells: Array = _inspect_move.duplicate()
		cells.append(u.grid_pos)
		var seen := {}
		for c in cells:
			for a in Combat.attack_cells(c, w.get("range", [1, 1]), terrain_grid):
				seen[a] = true
		_inspect_attack = seen.keys()
	_refresh_unit_visuals()
	_update_stat_panel()
	queue_redraw()

# ---------- 玩家操作 ----------
func _select_unit(u: Unit) -> void:
	selected = u
	move_cells = Combat.move_range(u, terrain_grid, occupied)
	attack_cells_list = []
	_preview_path = []
	_inspect_move = []
	_inspect_attack = []
	_moved_this_action = false
	_pre_move_pos = u.grid_pos
	_refresh_unit_visuals()
	_update_stat_panel()
	queue_redraw()

func _move_unit(u: Unit, cell: Vector2i) -> void:
	var path: Array = Combat.path_to(u, cell, terrain_grid, occupied)
	var half: Vector2 = Vector2(tile_size / 2, tile_size / 2)
	occupied.erase(u.grid_pos)
	u.grid_pos = cell
	occupied[cell] = u
	_moved_this_action = true
	_preview_path = []
	move_cells = []
	u.play_anim("move")
	var tw := create_tween()
	if path.size() > 0:
		for step in path:
			tw.tween_property(u, "position", Vector2(step.x, step.y) * tile_size + half, 0.08)
	else:
		tw.tween_property(u, "position", Vector2(cell.x, cell.y) * tile_size + half, 0.08)
	tw.tween_callback(func() -> void: u.play_anim("idle"))
	tw.tween_callback(func() -> void: _show_action_menu(u))
	queue_redraw()

func _show_attack_range(u: Unit) -> void:
	var w: Dictionary = DataManager.get_weapon(u.equipped_weapon)
	if w.is_empty():
		attack_cells_list = []
	else:
		attack_cells_list = Combat.attack_cells(u.grid_pos, w.get("range", [1, 1]), terrain_grid)
	queue_redraw()

## 完整战斗序列（火纹标准）：主攻 → 反击（若存活且射程够）→ 双方按速度差追加追击。
## 速度 spd 比对方高 4 点及以上 → 该方攻击后再追击一次（连击）。
## 先预演算每一步（掷骰存结果），弹全屏战斗特写演出；每次命中落地时回调真实结算。
const FOLLOWUP_SPD_DIFF := 4

signal combat_scene_done   # 战斗特写播放完毕

func _do_attack(att: Unit, def: Unit) -> void:
	# 预演算战斗步骤（掷骰但不改真实 HP）。
	var steps: Array = _simulate_combat(att, def)
	if steps.is_empty():
		return
	att.pending_ignore_def = 0.0
	# 弹全屏战斗特写：每次命中落地回调应用结算，全部演完回地图。
	var on_hit := func(step_index: int) -> void:
		var st: Dictionary = steps[step_index]
		_apply_strike_result(st.attacker, st.defender, st)
	var on_done := func() -> void:
		_update_stat_panel()
		_check_phase_end()
		combat_scene_done.emit()
	BattleScene.play(att, def, steps, on_hit, on_done)
	await combat_scene_done   # 等待特写播完（敌方 AI 需逐个行动不叠加）

## 预演算战斗序列，返回步骤数组 [{attacker, defender, hit, damage, crit, miss, killed}]。
## 掷骰在 Combat.resolve 内完成；用临时 HP 副本推演进/亡，不改真实单位。
func _simulate_combat(att: Unit, def: Unit) -> Array:
	var steps: Array = []
	if att == null or def == null:
		return steps
	var a_hp: int = att.hp
	var d_hp: int = def.hp
	var seq: Array = []   # [attacker, defender] 出手顺序
	seq.append([att, def])
	# 反击
	if _can_counter(def, att):
		seq.append([def, att])
	# 追击
	var a_spd: int = int(att.stats.get("spd", 0))
	var d_spd: int = int(def.stats.get("spd", 0))
	if a_spd - d_spd >= FOLLOWUP_SPD_DIFF:
		seq.append([att, def])
	elif d_spd - a_spd >= FOLLOWUP_SPD_DIFF and _can_counter(def, att):
		seq.append([def, att])
	for pair in seq:
		var A: Unit = pair[0]
		var D: Unit = pair[1]
		if a_hp <= 0 or d_hp <= 0:
			break
		var res: Dictionary = _resolve_attack(A, D)
		if res.get("empty", false):
			continue
		var step := {
			"attacker": A, "defender": D,
			"hit": res.hit, "crit": res.get("crit", false),
			"damage": res.damage, "res": res
		}
		if res.hit:
			if A == att:
				d_hp -= res.damage
				step["killed"] = d_hp <= 0
			else:
				a_hp -= res.damage
				step["killed"] = a_hp <= 0
		else:
			step["miss"] = true
		steps.append(step)
	return steps

## 单次攻击判定与结算（含演出/经验/护盾/死亡处理）。

## 防守方是否能反击（武器射程覆盖距离）。
func _can_counter(defender: Unit, attacker: Unit) -> bool:
	if defender.equipped_weapon == "":
		return false
	var w: Dictionary = DataManager.get_weapon(defender.equipped_weapon)
	if w.is_empty():
		return false
	var rng: Array = w.get("range", [1, 1])
	var dist: int = abs(defender.grid_pos.x - attacker.grid_pos.x) + abs(defender.grid_pos.y - attacker.grid_pos.y)
	return dist >= int(rng[0]) and dist <= int(rng[1])

## 用预演算好的 res 结算单次攻击（不再掷骰）：扣血/护盾/死亡/经验/地图浮标。
## 战斗特写命中落地时回调此方法；res 来自 _simulate_combat（掷骰结果已确定）。
func _apply_strike_result(att: Unit, def: Unit, res: Dictionary) -> void:
	if att == null or def == null or not is_instance_valid(att) or not is_instance_valid(def):
		return
	if res.get("empty", false):
		return
	if res.hit:
		var dealt: int = res.damage
		if def.shield > 0:
			var absorbed := mini(def.shield, dealt)
			def.shield -= absorbed
			dealt -= absorbed
		def.hp -= dealt
		def.refresh_label()
		if def.hp <= 0:
			_kill_unit(def)
	# 养成结算：仅我方获得经验与武器熟练度
	if att.team == "player":
		_grant_combat_exp(att, def, res)
	_update_stat_panel()

## 单次攻击判定与结算（含演出/经验/护盾/死亡处理）。敌方 AI 等不播特写时使用。
func _single_strike(att: Unit, def: Unit) -> void:
	if att == null or def == null or not is_instance_valid(att) or not is_instance_valid(def):
		return
	var res: Dictionary = _resolve_attack(att, def)
	if res.get("empty", false):
		return
	if res.hit:
		var txt: String = "%d" % res.damage
		if res.crit:
			txt = "暴击 %d" % res.damage
		_show_floater(def.position, txt, Color(1, 0.3, 0.3))
	else:
		_show_floater(def.position, "MISS", Color(0.9, 0.9, 0.9))
	# 演出：攻击者挥击，命中且未死者受击
	if res.hit:
		att.play_anim("attack")
		if is_instance_valid(def) and def.hp > 0:
			def.play_anim("hurt")
	_apply_strike_result(att, def, res)

## 击杀处理：移除占用/单位列表/释放，检查战斗结束。
func _kill_unit(u: Unit) -> void:
	occupied.erase(u.grid_pos)
	units.erase(u)
	u.queue_free()
	_check_battle_end()

## 战斗经验与武器熟练度结算（含升级/经验条演出）。
func _grant_combat_exp(att: Unit, def: Unit, res: Dictionary) -> void:
	var w: Dictionary = DataManager.get_weapon(att.equipped_weapon)
	var killed: bool = res.hit and (not is_instance_valid(def) or def.hp <= 0)
	var uexp := 1
	if res.hit:
		uexp = clampi(res.damage, 1, 15)
		if killed:
			uexp += 15
	var lv_gained: int = att.gain_exp(uexp)
	var wtype: String = w.get("type", "")
	if wtype != "":
		var wexp := 2 + clampi(res.damage, 0, 10) + (15 if killed else 0)
		att.gain_weapon_exp(wtype, wexp)
	if lv_gained > 0:
		_show_floater(att.position, "升级! Lv%d" % att.lvl, Color(1, 1, 0.3))
	elif res.hit:
		_show_floater(att.position, "EXP+%d" % uexp, Color(0.8, 0.9, 1.0))
	_show_exp_bar(att, uexp, killed)

## 在单位头顶显示经验条：底槽 + 填充（当前 exp/100）+ 获得量标签，动画后消失。
func _show_exp_bar(u: Unit, gained: int, killed: bool) -> void:
	if u == null or not is_instance_valid(u):
		return
	var root := Control.new()
	root.position = u.position + Vector2(-30, -52)
	root.size = Vector2(60, 16)
	add_child(root)
	# 底槽
	var bgc := ColorRect.new()
	bgc.color = Color(0.1, 0.1, 0.15, 0.9)
	bgc.size = Vector2(60, 8)
	root.add_child(bgc)
	# 填充（当前经验百分比）
	var fillc := ColorRect.new()
	var pct: float = clampf(float(u.exp) / 100.0, 0.0, 1.0)
	fillc.color = Color(1.0, 0.85, 0.2) if killed else Color(0.4, 0.7, 1.0)
	fillc.size = Vector2(60.0 * pct, 8)
	root.add_child(fillc)
	# 获得量标签
	var lbl := Label.new()
	lbl.text = "+%d EXP" % gained
	lbl.position = Vector2(0, 8)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	root.add_child(lbl)
	# 动画：停留后淡出
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(root, "modulate:a", 0.0, 0.4)
	tw.tween_callback(root.queue_free)

func _end_unit_action(u: Unit) -> void:
	u.acted = true
	selected = null
	_moved_this_action = false
	_inspect_move = []
	_inspect_attack = []
	_refresh_unit_visuals()
	queue_redraw()
	_check_phase_end()   # 全部玩家行动完则进入敌方阶段

## 取消当前行动：若已移动则返回原位，清除选中与范围。
func _cancel_action() -> void:
	if battle_over:
		return
	if _moved_this_action and selected != null:
		occupied.erase(selected.grid_pos)
		selected.grid_pos = _pre_move_pos
		occupied[_pre_move_pos] = selected
		selected.position = Vector2(_pre_move_pos.x, _pre_move_pos.y) * tile_size + Vector2(tile_size / 2, tile_size / 2)
		_moved_this_action = false
	selected = null
	move_cells = []
	attack_cells_list = []
	_preview_path = []
	_inspect_move = []
	_inspect_attack = []
	_close_action_menu()
	queue_redraw()

# ---------- 系统菜单（Esc 呼出：跳过回合/保存/中断/返回主界面） ----------
func _toggle_system_menu() -> void:
	if _sys_menu != null and is_instance_valid(_sys_menu):
		_close_system_menu()
		return
	_close_action_menu()
	_sys_menu = PopupMenu.new()
	_sys_menu.add_item("结束回合", 0)
	_sys_menu.add_item("保存进度", 1)
	_sys_menu.add_item("中断（回大地图）", 2)
	_sys_menu.add_item("返回主界面", 3)
	_sys_menu.add_separator()
	_sys_menu.add_item("取消", 4)
	var vp := get_viewport_rect().size
	_sys_menu.position = Vector2(vp.x / 2 - 90, vp.y / 2 - 110)
	_sys_menu.id_pressed.connect(_on_system_menu_picked)
	_sys_menu.popup_hide.connect(_close_system_menu)
	add_child(_sys_menu)
	_sys_menu.popup()

func _close_system_menu() -> void:
	if _sys_menu != null and is_instance_valid(_sys_menu):
		_sys_menu.queue_free()
	_sys_menu = null

func _on_system_menu_picked(id: int) -> void:
	_close_system_menu()
	match id:
		0:  # 结束回合：所有我方单位标记已行动 → 触发敌方阶段
			for u in units:
				if u.team == "player":
					u.acted = true
			_check_phase_end()
		1:  # 保存进度
			SaveManager.save(Campaign.serialize())
			_show_banner("已保存", Color(0.6, 0.9, 0.6), true)
		2:  # 中断回大地图（保留当前战役进度）
			SaveManager.save(Campaign.serialize())
			get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
		3:  # 返回主界面
			SaveManager.save(Campaign.serialize())
			get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
		4:  # 取消
			pass

# ---------- 行动菜单（移动到达后弹出：攻击/待命/道具） ----------
func _close_action_menu() -> void:
	if _action_menu != null and is_instance_valid(_action_menu):
		_action_menu.queue_free()
	_action_menu = null

func _show_action_menu(u: Unit) -> void:
	if battle_over or u.acted or not is_instance_valid(u):
		return
	_close_action_menu()
	_action_menu = PopupMenu.new()
	_action_menu.add_item("攻击", 0)
	_action_menu.add_item("待命", 1)
	_action_menu.add_item("道具", 2)
	_action_menu.position = u.position + Vector2(24, -24)
	_action_menu.id_pressed.connect(func(id: int) -> void: _on_action_picked(u, id))
	_action_menu.popup_hide.connect(_close_action_menu)
	add_child(_action_menu)
	_action_menu.popup()

func _on_action_picked(u: Unit, id: int) -> void:
	var picked: int = id
	_close_action_menu()
	match picked:
		0:
			_show_attack_range(u)
		1:
			_end_unit_action(u)
		2:
			_show_item_menu(u)

## 道具菜单：列出单位 inventory，选中使用（效果后续完善）。
func _show_item_menu(u: Unit) -> void:
	if u.inventory.is_empty():
		_show_banner("无道具", Color(0.8, 0.8, 0.8), true)
		_show_action_menu(u)
		return
	_close_action_menu()
	_action_menu = PopupMenu.new()
	for i in u.inventory.size():
		var iid: String = u.inventory[i]
		var it: Dictionary = DataManager.get_item(iid)
		_action_menu.add_item(it.get("name", iid), i)
	_action_menu.position = u.position + Vector2(24, -24)
	_action_menu.id_pressed.connect(func(id: int) -> void: _on_item_picked(u, id))
	_action_menu.popup_hide.connect(_close_action_menu)
	add_child(_action_menu)
	_action_menu.popup()

func _on_item_picked(u: Unit, id: int) -> void:
	var iid: String = u.inventory[id]
	var it: Dictionary = DataManager.get_item(iid)
	_close_action_menu()
	_show_banner("使用了 %s" % it.get("name", iid), Color(0.8, 0.9, 1.0), true)
	_end_unit_action(u)

# ---------- 攻击前武器选择 ----------
## 点敌人后：若单位可用武器 >1 把，弹武器菜单；否则直接攻击。
func _pick_weapon_and_attack(att: Unit, def: Unit) -> void:
	var usable: Array = att.usable_weapons()
	if usable.size() <= 1:
		await _do_attack(att, def)
		_end_unit_action(att)
		return
	_close_action_menu()
	_action_menu = PopupMenu.new()
	for i in usable.size():
		var wid: String = usable[i]
		var w: Dictionary = DataManager.get_weapon(wid)
		var mark: String = " ★" if wid == att.equipped_weapon else ""
		_action_menu.add_item("%s  威%d 命%d 暴%d%s" % [
			w.get("name", wid), int(w.get("might", 0)), int(w.get("hit", 0)),
			int(w.get("crit", 0)), mark], i)
	_action_menu.position = att.position + Vector2(24, -24)
	_action_menu.id_pressed.connect(func(id: int) -> void: _on_weapon_picked(att, def, usable[id]))
	_action_menu.popup_hide.connect(_close_action_menu)
	add_child(_action_menu)
	_action_menu.popup()

func _on_weapon_picked(att: Unit, def: Unit, wid: String) -> void:
	_close_action_menu()
	att.equipped_weapon = wid
	_show_banner("装备：%s" % DataManager.get_weapon(wid).get("name", wid), Color(0.9, 0.85, 0.5), true)
	await _do_attack(att, def)
	_end_unit_action(att)
	move_cells = []
	attack_cells_list = []
	_refresh_unit_visuals()
	_update_stat_panel()
	queue_redraw()
	_check_phase_end()

func _check_phase_end() -> void:
	if phase != "PLAYER" or battle_over:
		return
	for u in units:
		if u.team == "player" and not u.acted:
			return
	print("[阶段检查] 全部玩家已行动, 进入敌方阶段")
	_start_enemy_phase()

# ---------- 敌方阶段 ----------
## 不依赖嵌套 await（在 void 函数里 await 易挂起冻结），改用显式协程 + 逐个敌人分帧调度。
func _start_enemy_phase() -> void:
	print("[敌方阶段] 开始, phase=", phase)
	phase = "ENEMY"
	# 统计并肩出战回合（每回合一次），触发支持解锁
	var ids: Array = []
	for u in _alive("player"):
		if u.char_id != "":
			ids.append(u.char_id)
	_support_unlocks.append_array(SupportTracker.get_instance().record_battle_turns(ids))
	selected = null
	move_cells = []
	attack_cells_list = []
	_inspect_move = []
	_inspect_attack = []
	_refresh_unit_visuals()
	queue_redraw()
	_run_enemy_phase_async()   # 异步执行，完成后自行回到玩家阶段

func _run_enemy_phase_async() -> void:
	print("[敌方阶段] AI 协程启动, 敌人数=", units.filter(func(x): return x.team=="enemy" and x.hp>0).size())
	# 逐个敌人行动，每个之间停 0.35s，让玩家看清动作。
	for u in units:
		if battle_over:
			break
		if u.team != "enemy" or u.hp <= 0:
			continue
		print("[敌方阶段] ", u.display_name, " 行动")
		_enemy_act(u)
		await get_tree().create_timer(0.35).timeout
	print("[敌方阶段] 全部敌人行动完")
	_check_battle_end()   # 覆盖 survive 类目标（防守到第 N 回合）
	if battle_over:
		return
	# 回到玩家阶段
	phase = "PLAYER"
	turn += 1
	for u in units:
		u.acted = false
		u.tick_status()   # 清护盾、减主动技能冷却
	_refresh_unit_visuals()
	queue_redraw()
	print("[BattleController] 第 %d 回合 玩家阶段开始" % turn)

func _enemy_act(u: Unit) -> void:
	if battle_over:
		return
	var targets: Array = units.filter(func(x): return x.team == "player" and x.hp > 0)
	if targets.is_empty():
		return
	# 选最近目标
	var target: Unit = targets[0]
	var best_d: int = 9999
	for t in targets:
		var d: int = abs(t.grid_pos.x - u.grid_pos.x) + abs(t.grid_pos.y - u.grid_pos.y)
		if d < best_d:
			best_d = d
			target = t
	# 在可移动格中选离目标最近、且能进入攻击范围的格
	var cells: Array = Combat.move_range(u, terrain_grid, occupied)
	cells.append(u.grid_pos)
	var w: Dictionary = DataManager.get_weapon(u.equipped_weapon)
	var rng: Array = w.get("range", [1, 1]) if not w.is_empty() else [1, 1]
	var best_cell: Vector2i = u.grid_pos
	var best_score: int = 9999
	for c in cells:
		var d: int = abs(c.x - target.grid_pos.x) + abs(c.y - target.grid_pos.y)
		var in_range: bool = d >= int(rng[0]) and d <= int(rng[1])
		var score: int = d - (1000 if in_range else 0)
		if score < best_score:
			best_score = score
			best_cell = c
	# 沿路径逐格移动（可见轨迹，而非瞬移）
	if best_cell != u.grid_pos:
		var path: Array = Combat.path_to(u, best_cell, terrain_grid, occupied)
		occupied.erase(u.grid_pos)
		u.grid_pos = best_cell
		occupied[best_cell] = u
		await _tween_along_path(u, path)
	# 攻击（弹战斗特写，演出与结算；不再单独 play_anim，特写已含演出）
	if not w.is_empty():
		var dist: int = abs(u.grid_pos.x - target.grid_pos.x) + abs(u.grid_pos.y - target.grid_pos.y)
		if dist >= int(rng[0]) and dist <= int(rng[1]):
			await _do_attack(u, target)
	u.acted = true

## 让单位沿 path（Array[Vector2i]）逐格移动，呈现行走轨迹。
func _tween_along_path(u: Unit, path: Array) -> void:
	var half: Vector2 = Vector2(tile_size / 2, tile_size / 2)
	if path.is_empty():
		u.position = Vector2(u.grid_pos.x, u.grid_pos.y) * tile_size + half
		return
	u.play_anim("move")
	var tw := create_tween()
	for step in path:
		tw.tween_property(u, "position", Vector2(step.x, step.y) * tile_size + half, 0.12)
	await tw.finished
	u.play_anim("idle")

# ---------- 表现 ----------
func _draw() -> void:
	for c in move_cells:
		draw_rect(Rect2(c.x * tile_size, c.y * tile_size, tile_size, tile_size), Color(0.2, 0.5, 1.0, 0.35))
	for c in attack_cells_list:
		draw_rect(Rect2(c.x * tile_size, c.y * tile_size, tile_size, tile_size), Color(1.0, 0.2, 0.2, 0.35))
	# 查看敌人：移动范围（蓝）+ 攻击范围（红，含移动后可及）
	for c in _inspect_move:
		draw_rect(Rect2(c.x * tile_size, c.y * tile_size, tile_size, tile_size), Color(0.2, 0.5, 1.0, 0.30))
	for c in _inspect_attack:
		draw_rect(Rect2(c.x * tile_size + 3, c.y * tile_size + 3, tile_size - 6, tile_size - 6), Color(1.0, 0.35, 0.1, 0.28))
	# 移动路径预览（白色路径格 + 连线）
	if _preview_path.size() > 0 and selected != null:
		var prev: Vector2 = Vector2(selected.grid_pos.x, selected.grid_pos.y) * tile_size + Vector2(tile_size / 2, tile_size / 2)
		for p in _preview_path:
			draw_rect(Rect2(p.x * tile_size + 4, p.y * tile_size + 4, tile_size - 8, tile_size - 8), Color(1, 1, 1, 0.22))
			var cur: Vector2 = Vector2(p.x, p.y) * tile_size + Vector2(tile_size / 2, tile_size / 2)
			draw_line(prev, cur, Color(1, 1, 1, 0.6), 2.0)
			prev = cur
	# 选中单位黄框
	if selected != null:
		var p: Vector2i = selected.grid_pos
		draw_rect(Rect2(p.x * tile_size + 2, p.y * tile_size + 2, tile_size - 4, tile_size - 4),
			Color(1.0, 0.95, 0.2, 0.95), false, 3.0)

# ---------- 单位状态表现 ----------
func _refresh_unit_visuals() -> void:
	for u in units:
		u.apply_state(u == selected, u.acted)
	_update_stat_panel()

# ---------- 战斗内属性面板（Phase 6.1） ----------
## 右侧属性面板：选中单位显示其面板；选中且悬停在攻击范围内的敌人时改显敌人，便于预读。
func _build_stat_panel() -> void:
	stat_panel = Panel.new()
	stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不拦截格子点击
	stat_panel.size = Vector2(232, 272)
	stat_panel.visible = false
	add_child(stat_panel)
	stat_label = Label.new()
	stat_label.position = Vector2(10, 8)
	stat_label.size = Vector2(210, 250)
	stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_label.add_theme_font_size_override("font_size", 13)
	stat_panel.add_child(stat_label)
	_update_stat_panel()

## 鼠标移动：记录悬停单位并刷新面板。
func _on_mouse_moved(event: InputEventMouseMotion) -> void:
	if tile_map == null or battle_over:
		return
	var _lp: Vector2 = tile_map.to_local(get_global_mouse_position())
	var cell: Vector2i = Vector2i(int(_lp.x) / tile_size, int(_lp.y) / tile_size)
	var u = occupied.get(cell)
	_hover_unit = u if (u != null) else null
	# 移动路径预览：悬停在可移动格上时算最短路径
	if selected != null and selected.team == "player" and not selected.acted \
			and not _moved_this_action and cell in move_cells:
		_preview_path = Combat.path_to(selected, cell, terrain_grid, occupied)
	else:
		_preview_path = []
	_update_stat_panel()
	queue_redraw()

## 决定面板当前显示哪个单位。
func _panel_target() -> Unit:
	if not is_instance_valid(_hover_unit):
		_hover_unit = null
	if selected != null:
		# 选中我方且悬停在攻击范围内的敌人 -> 显示敌人预读
		if _hover_unit != null and _hover_unit != selected and _hover_unit.team == "enemy" \
				and attack_cells_list.has(_hover_unit.grid_pos):
			return _hover_unit
		return selected
	if _hover_unit != null:
		return _hover_unit
	return null

func _update_stat_panel() -> void:
	if stat_panel == null or stat_label == null:
		return
	var u: Unit = _panel_target()
	stat_panel.position = Vector2(get_viewport_rect().size.x - 232, 12)
	if u == null:
		stat_panel.visible = false
		return
	stat_panel.visible = true
	stat_label.text = _unit_stat_text(u)
	_update_forecast()   # 预测窗口随属性面板一起刷新

## 拼接单位完整属性文本（十维 + 武器 + 技能）。
func _unit_stat_text(u: Unit) -> String:
	var cls: Dictionary = DataManager.get_class_data(u.class_id)
	var s: Dictionary = u.stats
	var out: Array = []
	out.append("%s  (Lv%d)" % [u.display_name, u.lvl])
	out.append("职业：%s" % cls.get("name", u.class_id))
	out.append("HP  %d / %d" % [u.hp, u.max_hp])
	out.append("力 %2d   魔 %2d   技 %2d" % [int(s.get("str", 0)), int(s.get("mag", 0)), int(s.get("skl", 0))])
	out.append("速 %2d   幸 %2d   防 %2d" % [int(s.get("spd", 0)), int(s.get("lck", 0)), int(s.get("def", 0))])
	out.append("魔防 %2d  体格 %2d  移动 %2d" % [int(s.get("res", 0)), int(s.get("con", 0)), int(s.get("move", 0))])
	var w: Dictionary = DataManager.get_weapon(u.equipped_weapon)
	out.append("武器：%s" % (w.get("name", "—") if not w.is_empty() else "—"))
	var wr := "武器等级："
	if u.weapon_ranks.is_empty():
		wr += "无"
	else:
		for k in u.weapon_ranks.keys():
			wr += "%s%s  " % [WEAPON_NAME.get(k, k), u.weapon_ranks[k]]
	out.append(wr)
	var ids: Array = []
	if u.personal_skill != "":
		ids.append(u.personal_skill)
	ids.append_array(u.personal_skills)
	ids.append_array(u.class_skills)
	var sk := "技能："
	if ids.is_empty():
		sk += "无"
	else:
		var names: Array = []
		for sid in ids:
			names.append(DataManager.get_skill(sid).get("name", sid))
		sk += "、".join(names)
	out.append(sk)
	return "\n".join(out)

# ---------- 战斗预测窗口（武器三角 + 命中/伤害/暴击预读） ----------
func _build_forecast_panel() -> void:
	forecast_panel = Panel.new()
	forecast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forecast_panel.size = Vector2(244, 196)
	forecast_panel.visible = false
	add_child(forecast_panel)
	var pad := 10
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(pad, pad)
	vbox.size = Vector2(forecast_panel.size.x - pad * 2, forecast_panel.size.y - pad * 2)
	vbox.add_theme_constant_override("separation", 4)
	forecast_panel.add_child(vbox)
	# 标题
	forecast_title = Label.new()
	forecast_title.text = "战斗预测"
	forecast_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	forecast_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(forecast_title)
	# 攻方 → 守方
	forecast_match = Label.new()
	forecast_match.add_theme_font_size_override("font_size", 13)
	vbox.add_child(forecast_match)
	# 武器相克行：文字 + 图标 + 彩色结论
	var tri_row := HBoxContainer.new()
	tri_row.add_theme_constant_override("separation", 6)
	forecast_tri_label = Label.new(); forecast_tri_label.text = "武器相克："
	forecast_tri_label.add_theme_font_size_override("font_size", 13)
	tri_row.add_child(forecast_tri_label)
	forecast_tri_icon = WeaponTriIcon.new()
	forecast_tri_icon.custom_minimum_size = Vector2(18, 18)
	tri_row.add_child(forecast_tri_icon)
	forecast_tri_text = Label.new()
	forecast_tri_text.add_theme_font_size_override("font_size", 13)
	tri_row.add_child(forecast_tri_text)
	vbox.add_child(tri_row)
	# 攻方预测
	forecast_att = Label.new()
	forecast_att.add_theme_font_size_override("font_size", 13)
	vbox.add_child(forecast_att)
	# 反击预测
	forecast_counter = Label.new()
	forecast_counter.add_theme_font_size_override("font_size", 13)
	vbox.add_child(forecast_counter)
	# 预计结果
	forecast_result = Label.new()
	forecast_result.add_theme_font_size_override("font_size", 13)
	forecast_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(forecast_result)
	_update_forecast()

## 收集一次攻击的全部参数（技能/支援/三角/熟练度/地形），供实际结算与预测共用，避免两套公式。
func _attack_params(att: Unit, def: Unit) -> Dictionary:
	var w: Dictionary = DataManager.get_weapon(att.equipped_weapon)
	var def_type: String = ""
	if def.equipped_weapon != "":
		def_type = DataManager.get_weapon(def.equipped_weapon).get("type", "")
	var def_terr: Dictionary = DataManager.get_terrain(terrain_grid[def.grid_pos.y][def.grid_pos.x])
	var wtype: String = w.get("type", "")
	var att_allies: Array = _allies_of(att)
	var def_allies: Array = _allies_of(def)
	var crit_b: int = SkillManager.attack_crit_bonus(att)
	var hit_b: int = SkillManager.attack_hit_bonus(att, att_allies)
	var ignore_def: float = SkillManager.attack_ignore_def(att)
	var def_red: int = SkillManager.defense_bonus(def, def_allies)
	var avo_b: int = SkillManager.avoid_bonus(def)
	var m_ignore: bool = SkillManager.magic_avo_ignore(att, wtype)
	var sup: Dictionary = _support_bonus_for(att)
	return {
		"w": w, "def_type": def_type, "def_terr": def_terr, "wtype": wtype,
		"support_hit": hit_b + sup.hit, "support_avo": avo_b, "support_dmg": sup.dmg,
		"wrank_idx": att.wrank_index_of(wtype), "crit_b": crit_b,
		"ignore_def": ignore_def, "def_red": def_red, "m_ignore": m_ignore,
	}

## 实际结算（含掷骰），返回 Combat.resolve 的结果。
func _resolve_attack(att: Unit, def: Unit) -> Dictionary:
	var p: Dictionary = _attack_params(att, def)
	if p.w.is_empty():
		return {"empty": true}
	return Combat.resolve(att, def, p.w, p.def_type, p.def_terr, p.support_hit, p.support_avo,
		p.support_dmg, p.wrank_idx, p.crit_b, p.ignore_def, p.def_red, p.m_ignore)

## 确定性预测（不掷骰），返回 Combat.forecast 的结果。
func _forecast_attack(att: Unit, def: Unit) -> Dictionary:
	var p: Dictionary = _attack_params(att, def)
	if p.w.is_empty():
		return {"chance": 0, "dmg": 0, "crit_chance": 0, "adv": 0, "empty": true}
	return Combat.forecast(att, def, p.w, p.def_type, p.def_terr, p.support_hit, p.support_avo,
		p.support_dmg, p.wrank_idx, p.crit_b, p.ignore_def, p.def_red, p.m_ignore)

## 选中我方且悬停攻击范围内的敌人时，显示战斗预测；否则隐藏。
func _update_forecast() -> void:
	if forecast_panel == null or forecast_att == null:
		return
	var show: bool = selected != null and is_instance_valid(_hover_unit) and selected.team == "player" \
		and _hover_unit != selected and _hover_unit.team == "enemy" \
		and attack_cells_list.has(_hover_unit.grid_pos)
	if not show:
		forecast_panel.visible = false
		return
	# 紧挨属性面板下方排布，避免重叠
	var base_x: float = get_viewport_rect().size.x - forecast_panel.size.x
	var base_y: float = 12.0
	if stat_panel != null and stat_panel.visible:
		base_y = stat_panel.position.y + stat_panel.size.y + 6
	forecast_panel.position = Vector2(base_x, base_y)
	forecast_panel.visible = true
	_fill_forecast(selected, _hover_unit)

## 填充战斗预测窗口：武器相克图标 + 双方命中/伤害/暴击 + 预计残血。
func _fill_forecast(att: Unit, def: Unit) -> void:
	var aw: Dictionary = DataManager.get_weapon(att.equipped_weapon)
	var dw: Dictionary = DataManager.get_weapon(def.equipped_weapon)
	var awt: String = aw.get("type", "") if not aw.is_empty() else ""
	var dwt: String = dw.get("type", "") if not dw.is_empty() else ""
	if aw.is_empty():
		forecast_match.text = "（无武器，无法攻击）"
		forecast_tri_icon.set_state(0)
		forecast_tri_text.text = "—"
		forecast_att.text = ""
		forecast_counter.text = ""
		forecast_result.text = ""
		return
	forecast_match.text = "%s(%s) → %s(%s)" % [
		att.display_name, WEAPON_NAME.get(awt, "徒手"),
		def.display_name, WEAPON_NAME.get(dwt, "徒手")]
	# 武器相克（攻方视角）：图标化
	var tri: Dictionary = Combat.triangle(awt, dwt)
	var adv: int = int(tri.adv)
	forecast_tri_icon.set_state(adv)
	if adv == 1:
		forecast_tri_text.text = "有利"
		forecast_tri_text.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
	elif adv == -1:
		forecast_tri_text.text = "不利"
		forecast_tri_text.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
	else:
		forecast_tri_text.text = "无"
		forecast_tri_text.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	# 攻方预测（含追击标记）
	var a: Dictionary = _forecast_attack(att, def)
	var a_follow: String = " ×2" if int(att.stats.get("spd", 0)) - int(def.stats.get("spd", 0)) >= FOLLOWUP_SPD_DIFF else ""
	forecast_att.text = "%s  命中 %d%%  伤害 %d  暴击 %d%%%s" % [
		att.display_name, int(a.chance), int(a.dmg), int(a.crit_chance), a_follow]
	var def_after: int = def.hp - int(a.dmg)
	if a_follow != "":
		def_after -= int(a.dmg)   # 追击再打一次
	if def_after <= 0:
		forecast_counter.text = ""
		forecast_result.text = "【%s 将被击败】" % def.display_name
		forecast_result.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		return
	# 反击判定：防守方有武器且射程覆盖攻方
	var can_counter: bool = _can_counter(def, att)
	if not can_counter:
		forecast_counter.text = "%s 无法反击" % def.display_name
		forecast_result.text = "预计：%s 剩 %d" % [def.display_name, def_after]
		forecast_result.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		return
	var c: Dictionary = _forecast_attack(def, att)
	var d_follow: String = " ×2" if int(def.stats.get("spd", 0)) - int(att.stats.get("spd", 0)) >= FOLLOWUP_SPD_DIFF else ""
	forecast_counter.text = "%s 反击  命中 %d%%  伤害 %d  暴击 %d%%%s" % [
		def.display_name, int(c.chance), int(c.dmg), int(c.crit_chance), d_follow]
	var att_after: int = att.hp - int(c.dmg)
	if d_follow != "":
		att_after -= int(c.dmg)
	forecast_result.text = "预计：%s 剩 %d / %s 剩 %d" % [
		def.display_name, def_after, att.display_name, maxi(0, att_after)]
	forecast_result.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

func _alive(team: String) -> Array:
	var out: Array = []
	for u in units:
		if u.team == team and u.hp > 0:
			out.append(u)
	return out

## 同队活单位（含自身），供技能光环/护盾范围判定。
func _allies_of(u: Unit) -> Array:
	var out: Array = []
	for x in units:
		if x.team == u.team and x.hp > 0:
			out.append(x)
	return out

## 主动技能激活（调试键调用；正式版换成技能菜单 UI）。
func _try_activate(u: Unit, skill_id: String) -> void:
	if u == null or u.team != "player":
		return
	var ok: bool = SkillManager.activate(u, skill_id, _allies_of(u))
	var sk: Dictionary = DataManager.get_skill(skill_id)
	if ok:
		_show_floater(u.position, "技能·%s" % sk.get("name", skill_id), Color(0.6, 1.0, 0.9))
	else:
		var reason := "冷却中" if int(u.active_cooldowns.get(skill_id, 0)) > 0 else "未习得"
		_show_floater(u.position, "技能不可用(%s)" % reason, Color(0.8, 0.8, 0.8))

## 攻击者若有支持同伴(C/B/A)在场，取其最高等级的命中/伤害加成。
func _support_bonus_for(att: Unit) -> Dictionary:
	var best := {"hit": 0, "dmg": 0}
	if att.char_id == "":
		return best
	for a in _allies_of(att):
		if a == att or a.char_id == "":
			continue
		var r: int = SupportTracker.get_instance().rank_of(att.char_id, a.char_id)
		if r >= 1:
			var b: Dictionary = SupportTracker.get_instance().bonus_for_rank(r)
			best.hit = maxi(best.hit, int(b.get("hit", 0)))
			best.dmg = maxi(best.dmg, int(b.get("dmg", 0)))
	return best

# ---------- 胜负判定 ----------
func _check_battle_end() -> void:
	if battle_over:
		return
	# 败北：我方全灭
	var players := _alive("player")
	if players.is_empty():
		return _end_battle(false, "全军覆没……")
	# 败北：领主阵亡（领主不在存活列表里）
	for u in units:
		if u.team == "player" and u.is_lord and u.hp <= 0:
			return _end_battle(false, "%s 倒下了……" % u.display_name)
	# 胜利：按 objective 类型
	var enemies := _alive("enemy")
	var ot: String = objective.get("type", "rout")
	if ot == "rout" and enemies.is_empty():
		return _end_battle(true, "敌军已全灭！")
	elif ot == "boss":
		var target_id: String = objective.get("target", "")
		if not enemies.any(func(e): return e.char_id == target_id):
			return _end_battle(true, "敌将已伏诛！")
	elif ot == "survive":
		if turn >= int(objective.get("turns", 999)):
			return _end_battle(true, "成功坚守至第 %d 回合！" % turn)

func _end_battle(win: bool, msg: String) -> void:
	battle_over = true
	selected = null
	move_cells = []
	attack_cells_list = []
	_refresh_unit_visuals()
	queue_redraw()
	var color := Color(0.35, 1.0, 0.4) if win else Color(1.0, 0.4, 0.4)
	_show_banner("%s\n%s" % ["胜利！" if win else "败北……", msg], color)
	print("[BattleController] 战斗结束：%s — %s" % ["胜利" if win else "败北", msg])

	if win:
		# 回写养成进度；permadeath 下抹除本场阵亡者
		_apply_battle_result()
		var map_id: String = Campaign.current_map_id if Campaign.current_map_id != "" else start_map
		Campaign.mark_cleared(map_id)
		_apply_map_reward(map_id)
		var mdec: String = DataManager.get_map(map_id).get("decision", "")
		if mdec != "" and not Campaign.is_decided(mdec):
			Campaign.pending_decision = mdec
		Campaign.pending_support = _support_unlocks
		_support_unlocks = []
		SaveManager.save(Campaign.serialize())
	else:
		# 战败：还原到进入本战前的快照（养成/招募全部作废，可重打）
		if not _campaign_snapshot.is_empty():
			Campaign.deserialize(_campaign_snapshot)
		Campaign.pending_decision = ""
		_support_unlocks = []
	# 收尾（延迟看横幅→过关剧情→切场景）异步执行，避免在同步函数里 await 报警。
	_finish_battle_async(win)

## 战斗收尾协程：延迟看横幅 → 过关剧情 → 回大地图。
func _finish_battle_async(win: bool) -> void:
	var map_id: String = Campaign.current_map_id if Campaign.current_map_id != "" else start_map
	await get_tree().create_timer(1.3 if win else 1.6).timeout
	if win:
		var story_key: String = map_id + "_clear"
		if not Campaign.is_story_seen(story_key) and not DataManager.get_story(story_key).is_empty():
			Campaign.mark_story_seen(story_key)
			StoryDialog.play(story_key, func() -> void:
				get_tree().change_scene_to_file("res://scenes/WorldMap.tscn"))
			return
	get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")

## 胜利后应用本场结果到 Campaign：存活者进度回写；permadeath 下阵亡者永久退场。
func _apply_battle_result() -> void:
	var alive_ids: Array = []
	for u in units:
		if u.team == "player" and u.char_id != "":
			alive_ids.append(u.char_id)
			Campaign.roster[u.char_id] = u.progress_dict()   # 存活者进度固化
	for cid in _player_ids:
		if cid in alive_ids:
			continue
		# 阵亡者
		if Campaign.permadeath:
			Campaign.roster.erase(cid)
			Campaign.owned_chars.erase(cid)
			print("[Campaign] 永久死亡：%s 阵亡退场，已移出队伍" % cid)
		# 非永久死亡：保留 roster（重伤撤退，下场满状态回归）

## 应用地图 JSON 的 reward（角色/道具/flag），仅胜利时调用。
func _apply_map_reward(map_id: String) -> void:
	var map: Dictionary = DataManager.get_map(map_id)
	var rw: Dictionary = map.get("reward", {})
	if rw.has("character"):
		Campaign.grant_char(rw.character)
		print("[Campaign] 获得角色：%s" % rw.character)
	if rw.has("item"):
		Campaign.grant_item(rw.item)
		print("[Campaign] 获得道具：%s" % rw.item)
	if rw.has("flag"):
		Campaign.set_flag(rw.flag)

func _show_banner(text: String, color: Color, auto_hide: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 44)
	var vp := get_viewport_rect().size
	lbl.position = Vector2(vp.x / 2 - 300, vp.y / 2 - 70)
	lbl.size = Vector2(600, 140)
	add_child(lbl)
	if auto_hide:
		var tw := create_tween()
		tw.tween_interval(1.2)
		tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
		tw.tween_callback(lbl.queue_free)

func _show_floater(pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.position = pos - Vector2(20, 40)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position", pos - Vector2(20, 80), 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

# ---------- 地形 TileSet（程序化生成，无需外部美术资源） ----------
## 整图背景：把 bg_image 铺满整个地图区域（mw*tile_size × mh*tile_size），置于最底层。
## 网格、移动/攻击范围高亮（_draw）、单位均叠加在其上；地形逻辑仍走 terrain_grid。
var _bg_sprite: Sprite2D = null
func _setup_bg_image(path: String) -> void:
	if _bg_sprite != null and is_instance_valid(_bg_sprite):
		_bg_sprite.queue_free()
	var tex := _load_image_tex(path)
	if tex == null:
		push_warning("BattleController: 背景图加载失败 " + path)
		return
	_bg_sprite = Sprite2D.new()
	_bg_sprite.texture = tex
	_bg_sprite.centered = false
	_bg_sprite.z_index = -20   # 在 TileMap(-10) 之下，最底
	var mw: int = terrain_grid[0].size() if terrain_grid.size() > 0 else 10
	var mh: int = terrain_grid.size()
	var target := Vector2(mw * tile_size, mh * tile_size)
	_bg_sprite.scale = Vector2(target.x / tex.get_width(), target.y / tex.get_height())
	add_child(_bg_sprite)

## 直接读图片文件为纹理（绕过 .import 依赖，避免无导入时卡死）。
func _load_image_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var r = load(path)
	if r != null:
		return r
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

## 遍历 DataManager.terrain，按 atlas 坐标绘制一张图集 Image，构建 TileSet。
## 每种地形一个 64x64 图块：纯色底 + 简单图案（森林树点/山顶尖/城垛/砖缝/水波）。
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	# 图集宽度 = 最大 atlas 列 + 1
	var max_col: int = 0
	for tid in DataManager.terrain.keys():
		var at: Array = DataManager.terrain[tid].get("atlas", [0, 0])
		max_col = maxi(max_col, int(at[0]))
	var cols_n: int = max_col + 1
	var img := Image.create(tile_size * cols_n, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for tid in DataManager.terrain.keys():
		var at: Array = DataManager.terrain[tid].get("atlas", [0, 0])
		_paint_terrain_tile(img, int(at[0]), int(at[1]), tid)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(tile_size, tile_size)   # 关键：告诉图集每块 64x64，否则 tile 取错区域
	for tid in DataManager.terrain.keys():
		var at: Array = DataManager.terrain[tid].get("atlas", [0, 0])
		src.create_tile(Vector2i(int(at[0]), int(at[1])))
	ts.add_source(src)
	return ts

## 在图集 img 的 (col,row) 图块上绘制指定地形。
func _paint_terrain_tile(img: Image, col: int, row: int, tid: String) -> void:
	var x0: int = col * tile_size
	var y0: int = row * tile_size
	img.fill_rect(Rect2i(x0, y0, tile_size, tile_size), _terrain_color(tid))
	match tid:
		"forest":
			for tx in [8, 30, 46]:
				img.fill_rect(Rect2i(x0 + tx, y0 + 16, 12, 24), Color(0.08, 0.28, 0.08))
				img.fill_rect(Rect2i(x0 + tx + 4, y0 + 40, 4, 10), Color(0.25, 0.18, 0.10))
		"mountain":
			for mx in [16, 42]:
				for dy in 24:
					var w: int = dy + 4
					img.fill_rect(Rect2i(x0 + mx - w / 2, y0 + 52 - dy, w, 1), Color(0.85, 0.85, 0.85))
		"fort":
			for cx in [2, 18, 34, 50]:
				img.fill_rect(Rect2i(x0 + cx, y0 + 6, 10, 10), Color(0.42, 0.27, 0.20))
			img.fill_rect(Rect2i(x0, y0 + 50, tile_size, 4), Color(0.42, 0.27, 0.20))
		"wall":
			for by in [12, 28, 44]:
				img.fill_rect(Rect2i(x0, y0 + by, tile_size, 2), Color(0.12, 0.12, 0.14))
			for bx in [16, 48]:
				img.fill_rect(Rect2i(x0 + bx, y0, 2, tile_size), Color(0.12, 0.12, 0.14))
		"water":
			for wy in [16, 36]:
				img.fill_rect(Rect2i(x0 + 6, y0 + wy, tile_size - 12, 2), Color(0.40, 0.60, 0.85))
				img.fill_rect(Rect2i(x0 + 10, y0 + wy + 8, tile_size - 20, 2), Color(0.35, 0.55, 0.80))
		"plain":
			for px in [10, 32, 50]:
				img.fill_rect(Rect2i(x0 + px, y0 + 42, 3, 3), Color(0.25, 0.45, 0.18))
				img.fill_rect(Rect2i(x0 + px + 14, y0 + 36, 3, 3), Color(0.25, 0.45, 0.18))

func _terrain_color(tid: String) -> Color:
	match tid:
		"plain": return Color(0.35, 0.55, 0.25)
		"forest": return Color(0.18, 0.40, 0.18)
		"mountain": return Color(0.50, 0.45, 0.40)
		"fort": return Color(0.55, 0.35, 0.25)
		"wall": return Color(0.30, 0.30, 0.32)
		"water": return Color(0.20, 0.35, 0.60)
		_: return Color(0.2, 0.2, 0.2)

# ---------- 战斗相机（方向键移动视角，受地图边界限制） ----------
func _setup_camera() -> void:
	if cam == null:
		cam = Camera2D.new()
		add_child(cam)
	var mw: int = 10
	var mh: int = 8
	if terrain_grid.size() > 0:
		mw = terrain_grid[0].size()
		mh = terrain_grid.size()
	var map_px := Vector2(mw * tile_size, mh * tile_size)
	var vp := get_viewport_rect().size
	# 仅当地图超出窗口时才启用相机滚动；否则禁用（避免相机居中导致点击坐标错位）。
	if map_px.x > vp.x or map_px.y > vp.y:
		cam.enabled = true
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = int(map_px.x)
		cam.limit_bottom = int(map_px.y)
		cam.position = map_px / 2.0
	else:
		cam.enabled = false
		cam.position = Vector2.ZERO

## 方向键平移视角（地图大于窗口时生效；Camera2D limit 自动夹在地图边界内）。
func _process(delta: float) -> void:
	if cam == null or not is_instance_valid(cam) or not cam.enabled or battle_over:
		return
	var speed: float = 700.0 * delta
	if Input.is_physical_key_pressed(KEY_LEFT):
		cam.position.x -= speed
	if Input.is_physical_key_pressed(KEY_RIGHT):
		cam.position.x += speed
	if Input.is_physical_key_pressed(KEY_UP):
		cam.position.y -= speed
	if Input.is_physical_key_pressed(KEY_DOWN):
		cam.position.y += speed
