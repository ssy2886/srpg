extends Node

## Headless 冒烟测试主场景：用真实 Godot 引擎加载工程，校验数据表与所有场景/脚本，
## 最后打印 SMOKE_TEST_PASS/FAIL 到 stdout 并 quit。通过临时切换 project.godot 主场景运行。

func _ready() -> void:
	print("SMOKE_START")
	var problems: Array = []

	# 1) 数据表交叉引用
	if DataManager.characters.is_empty(): problems.append("DataManager.characters 为空")
	if DataManager.classes.is_empty(): problems.append("DataManager.classes 为空")
	if DataManager.skills.is_empty(): problems.append("DataManager.skills 为空")
	if DataManager.weapons.is_empty(): problems.append("DataManager.weapons 为空")
	if DataManager.terrain.is_empty(): problems.append("DataManager.terrain 为空")
	if DataManager.decisions.is_empty(): problems.append("DataManager.decisions 为空(抉择点未加载)")

	for cid in DataManager.characters.keys():
		var ch: Dictionary = DataManager.characters[cid]
		var bc: String = ch.get("base_class", "")
		if not bc.is_empty() and not DataManager.classes.has(bc):
			problems.append("角色 %s 的 base_class=%s 在 classes 中缺失" % [cid, bc])

	for wid in DataManager.weapons.keys():
		var w: Dictionary = DataManager.weapons[wid]
		var t: String = w.get("type", "")
		if not DataManager.DEFAULT_WEAPON.has(t):
			problems.append("武器 %s 的 type=%s 不在 DEFAULT_WEAPON" % [wid, t])

	# 白名单须与 src/SkillManager.gd 实际支持的 effect.kind 保持一致（集中解释处）。
	var known_kinds := ["adjacent_ally_damage_reduction", "adjacent_ally_hit_bonus",
		"avoid_bonus", "crit_bonus", "magic_avoid_ignore", "ignore_defense", "shield_ally"]
	for sid in DataManager.skills.keys():
		var s: Dictionary = DataManager.skills[sid]
		var eff: Dictionary = s.get("effect", {})
		var kind: String = eff.get("kind", "")
		if not kind.is_empty() and not kind in known_kinds:
			problems.append("技能 %s 的 effect.kind=%s 未知" % [sid, kind])

	# 2) 显式加载所有脚本（即便场景能加载，脚本解析错误也必须被捕获）。
	#    load() 一个 .gd 时若脚本本身有 Parse Error，会返回 null。
	var src_dir := DirAccess.open("res://src")
	if src_dir:
		src_dir.list_dir_begin()
		var f := src_dir.get_next()
		while f != "":
			if f.ends_with(".gd"):
				print("  load script/", f)
				var res = load("res://src/" + f)
				if res == null:
					problems.append("脚本解析失败: res://src/" + f)
			f = src_dir.get_next()
		src_dir.list_dir_end()

	# 3) 加载并实例化所有场景（实例化会真正执行各脚本 _ready，捕获运行期错误）。
	var scenes_dir := DirAccess.open("res://scenes")
	if scenes_dir:
		scenes_dir.list_dir_begin()
		var f := scenes_dir.get_next()
		while f != "":
			if f.ends_with(".tscn"):
				print("  load scene/", f)
				var res = load("res://scenes/" + f)
				if res == null:
					problems.append("无法加载: res://scenes/" + f)
					f = scenes_dir.get_next()
					continue
				print("  instantiate/", f)
				var inst = res.instantiate()
				if inst == null:
					problems.append("实例化失败: res://scenes/" + f)
					f = scenes_dir.get_next()
					continue
				# 加入场景树，触发 _ready（拿到有效 viewport），随后移除，避免互相干扰。
				get_tree().root.add_child(inst)
				await get_tree().process_frame
				inst.queue_free()
			f = scenes_dir.get_next()
		scenes_dir.list_dir_end()

	# 3) 报告
	if problems.is_empty():
		print("SMOKE_TEST_PASS: 数据表与全部场景/脚本均加载成功")
		print("  角色=%d 职业=%d 技能=%d 武器=%d 地形=%d 抉择=%d" % [
			DataManager.characters.size(), DataManager.classes.size(),
			DataManager.skills.size(), DataManager.weapons.size(), DataManager.terrain.size(), DataManager.decisions.size()])
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_FAIL:")
		for p in problems:
			print("  - ", p)
		get_tree().quit(1)
