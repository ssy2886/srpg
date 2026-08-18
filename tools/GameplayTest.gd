extends Node

## GameplayTest —— 用真实 Godot 引擎驱动一局完整战斗,验证 SRPG 核心玩法可玩。
## 流程:新游戏 → 载入 prologue_01 → 选玩家单位 → 计算移动范围 → 战斗预测 →
##       执行攻击(伤害结算/浮字/经验/武器熟练度) → 支持关系追踪。
## 通过判定:无运行期错误 & 关键数值正常。结果打印 GAMEPLAY_PASS / GAMEPLAY_FAIL。

const Combat = preload("res://src/Combat.gd")
const Unit = preload("res://src/Unit.gd")
const SupportTracker = preload("res://src/SupportTracker.gd")

func _ready() -> void:
	print("=== GameplayTest: 驱动一局完整战斗 ===")
	var problems: Array = []

	# 1) 新游戏 + 设当前地图
	Campaign.new_game(false)
	Campaign.current_map_id = "prologue_01"

	# 2) 实例化战斗场景(触发 BattleController._ready → _init_battle → 加载地图/生成单位)
	var scene: PackedScene = load("res://scenes/Battle.tscn")
	var battle = scene.instantiate()
	add_child(battle)
	await get_tree().process_frame   # 让 _ready 与子节点 _ready 跑完

	var bc = battle   # BattleController 实例

	# 3) 检查地图载入
	if not is_instance_valid(bc):
		problems.append("BattleController 实例无效")
		_finish(problems)
		return
	if bc.units.is_empty():
		problems.append("地图载入失败:无单位(tile_map 可能仍为 null,或地图数据缺失)")
		_finish(problems)
		return
	var gw: int = bc.terrain_grid.size()
	var gh: int = bc.terrain_grid[0].size() if gw > 0 else 0
	print("  [OK] 地图载入: 单位 %d, 地形 %dx%d" % [bc.units.size(), gw, gh])

	# 4) 找玩家与敌人
	var att = null
	var def = null
	for u in bc.units:
		if att == null and u.team == "player":
			att = u
		if def == null and u.team == "enemy":
			def = u
	if att == null or def == null:
		problems.append("找不到玩家或敌人单位")
		_finish(problems)
		return
	print("  [OK] 玩家: %s Lv%d HP%d 武器=%s pos=%s" % [att.display_name, att.lvl, att.hp, att.equipped_weapon, str(att.grid_pos)])
	print("  [OK] 敌人: %s Lv%d HP%d 武器=%s pos=%s" % [def.display_name, def.lvl, def.hp, def.equipped_weapon, str(def.grid_pos)])

	if att.equipped_weapon == "":
		problems.append("玩家单位无装备武器")
		_finish(problems)
		return

	# 5) 选择单位 → 计算移动范围(Combat.move_range)
	bc._select_unit(att)
	if bc.move_cells.size() > 0:
		print("  [OK] %s 可移动格数=%d" % [att.display_name, bc.move_cells.size()])
	else:
		problems.append("移动范围为空(Combat.move_range 异常)")

	# 5.5) 测试移动轨迹(path_to + Tween 动画)与取消返回原位
	var orig_pos: Vector2i = att.grid_pos
	var move_target: Vector2i = Vector2i(2, 3)
	if bc.move_cells.has(move_target):
		var path: Array = Combat.path_to(att, move_target, bc.terrain_grid, bc.occupied)
		bc._move_unit(att, move_target)
		await get_tree().create_timer(0.3).timeout
		bc._close_action_menu()
		if att.grid_pos == move_target and path.size() > 0:
			print("  [OK] 移动轨迹: %s→%s 路径%d格 (Tween 动画)" % [str(orig_pos), str(att.grid_pos), path.size()])
		else:
			problems.append("移动异常: grid=%s path=%d" % [str(att.grid_pos), path.size()])
		# 取消行动 → 返回原位
		bc._cancel_action()
		if att.grid_pos == orig_pos:
			print("  [OK] 取消行动返回原位: %s" % str(att.grid_pos))
		else:
			problems.append("取消未返回原位: %s" % str(att.grid_pos))
	else:
		print("  [SKIP] (2,3) 不在 move_cells")

	# 6) 战斗预测(纯逻辑,不掷骰)
	var fc = bc._forecast_attack(att, def)
	print("  [OK] 战斗预测: 命中=%d%% 伤害=%d 暴击=%d%% 三角=%d" % [
		int(fc.get("chance", 0)), int(fc.get("dmg", 0)),
		int(fc.get("crit_chance", 0)), int(fc.get("adv", 0))])
	# 6.5) 武器选择：lyra(lord) 应有剑+枪多把可选
	var uw: Array = att.usable_weapons()
	if uw.size() >= 1:
		print("  [OK] %s 可用武器 %d 把: %s" % [att.display_name, uw.size(), str(uw)])
	else:
		problems.append("可用武器为空")

	# 7) 执行攻击(完整结算:伤害浮字、动画、经验、武器熟练度)
	var def_hp_before: int = def.hp
	var att_exp_before: int = att.exp
	bc._do_attack(att, def)
	await get_tree().process_frame   # 让 floater tween 推进,避免遗留节点
	var hit: bool = def.hp < def_hp_before
	if hit:
		print("  [OK] 攻击命中: 敌HP %d→%d, 我方EXP %d→%d" % [def_hp_before, def.hp, att_exp_before, att.exp])
	elif def.hp == def_hp_before:
		print("  [OK] 攻击未命中(MISS): 敌HP %d, 我方EXP %d→%d" % [def_hp_before, att_exp_before, att.exp])
	else:
		problems.append("敌HP 异常: %d→%d" % [def_hp_before, def.hp])

	# 7.5) 直接调用 _on_tile_clicked 验证选中逻辑（绕过鼠标坐标换算，专注选中行为）
	bc._on_tile_clicked(Vector2i(1, 4))   # garrett 位置
	await get_tree().process_frame
	if bc.selected != null and bc.selected.char_id == "garrett":
		print("  [OK] 点击选中: %s" % bc.selected.display_name)
	else:
		var sname: String = bc.selected.display_name if bc.selected != null else "null"
		problems.append("点击未选中 garrett (selected=%s)" % sname)

	# 8) 支持关系追踪器(支持对话解锁的底层)
	var st = SupportTracker.get_instance()
	st.record_battle_turns([att.char_id, "garrett"], 5)
	var rk = st.rank_of(att.char_id, "garrett")
	print("  [OK] 支持关系: %s↔garrett rank=%d" % [att.char_id, rk])

	_finish(problems)

func _finish(problems: Array) -> void:
	if problems.is_empty():
		print("=== GAMEPLAY_PASS ===")
	else:
		print("=== GAMEPLAY_FAIL ===")
		for p in problems:
			print("  - ", p)
	get_tree().quit()
