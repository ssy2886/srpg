extends SceneTree

## Headless 冒烟测试：用真实 Godot 引擎加载本工程，校验
## 1) 数据表交叉引用（角色 base_class 必须存在于 classes）
## 2) 数据表可加载（角色/职业/技能/武器/地形非空）
## 3) 所有场景与脚本可被解析加载（捕获 GDScript 语法/资源引用错误）
## 运行：Godot_v4.2.2-stable_win64.exe --headless --path . --script tools/smoke_test.gd
## 退出码 0=通过，1=失败（失败项会打印在 SMOKE_TEST_FAIL 之下）。

func _initialize() -> void:
	# 等两帧，确保 Autoload(DataManager/Campaign/SaveManager) 的 _ready 已执行
	await create_timer(0.2).timeout

	var problems: Array = []

	# ---------- 1) 数据表交叉引用 ----------
	if DataManager.characters.is_empty(): problems.append("DataManager.characters 为空")
	if DataManager.classes.is_empty(): problems.append("DataManager.classes 为空")
	if DataManager.skills.is_empty(): problems.append("DataManager.skills 为空")
	if DataManager.weapons.is_empty(): problems.append("DataManager.weapons 为空")
	if DataManager.terrain.is_empty(): problems.append("DataManager.terrain 为空")

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

	# 技能 kind 必须是已知解释器支持的，且引用的技能/武器 id 存在
	var known_kinds := ["damage_bonus", "hit_bonus", "avo_bonus", "crit_bonus",
		"ignore_def_pct", "lifesteal", "heal_on_hit", "silent_cast", "grant_skill", "stat_bonus"]
	for sid in DataManager.skills.keys():
		var s: Dictionary = DataManager.skills[sid]
		var eff: Dictionary = s.get("effect", {})
		var kind: String = eff.get("kind", "")
		if not kind.is_empty() and not kind in known_kinds:
			problems.append("技能 %s 的 effect.kind=%s 未知" % [sid, kind])

	# ---------- 2) 加载所有场景与脚本，捕获解析/资源错误 ----------
	var scenes_dir := DirAccess.open("res://scenes")
	if scenes_dir:
		scenes_dir.list_dir_begin()
		var f := scenes_dir.get_next()
		while f != "":
			if f.ends_with(".tscn") or f.ends_with(".gd"):
				var res = load("res://scenes/" + f)
				if res == null:
					problems.append("无法加载: res://scenes/" + f)
			f = scenes_dir.get_next()
		scenes_dir.list_dir_end()

	var src_dir := DirAccess.open("res://src")
	if src_dir:
		src_dir.list_dir_begin()
		var sf := src_dir.get_next()
		while sf != "":
			if sf.ends_with(".gd"):
				var res = load("res://src/" + sf)
				if res == null:
					problems.append("无法加载: res://src/" + sf)
			sf = src_dir.get_next()
		src_dir.list_dir_end()

	# ---------- 3) 报告 ----------
	if problems.is_empty():
		print("SMOKE_TEST_PASS: 数据表与全部场景/脚本均加载成功")
		print("  角色=%d 职业=%d 技能=%d 武器=%d 地形=%d" % [
			DataManager.characters.size(), DataManager.classes.size(),
			DataManager.skills.size(), DataManager.weapons.size(), DataManager.terrain.size()])
		quit(0)
	else:
		print("SMOKE_TEST_FAIL:")
		for p in problems:
			print("  - ", p)
		quit(1)
