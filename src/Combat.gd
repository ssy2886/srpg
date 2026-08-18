class_name Combat
extends RefCounted

## Unit 类型声明（避免 class_name 注册顺序导致的 "Could not find type Unit"）。
const Unit = preload("res://src/Unit.gd")

## Combat —— 战斗结算模块（纯函数，Phase 1）。
## 负责：移动范围 BFS、攻击范围、武器三角、True Hit 命中、伤害/暴击。
## 不直接管回合/输入，那些留给 BattleController。地形/支援/光环加成以参数传入，保持本模块纯净。

const TRIANGLE_HIT: int = 15      # 克制方命中加成
const TRIANGLE_DMG: int = 1       # 克制方伤害加成
const CRIT_MULT: float = 1.5      # 暴击倍率

## 计算可移动格（BFS，受地形 cost 影响）。
## 友军格可穿过但不可停留（火纹规则）；敌军格不可进入。occupied: Dictionary{Vector2i:Unit}。
static func move_range(unit: Unit, terrain_grid: Array, occupied: Dictionary) -> Array:
	var start: Vector2i = unit.grid_pos
	var move_pts: int = int(unit.stats.get("move", 5))
	var reached: Dictionary = {start: 0}
	var frontier: Array = [start]
	while frontier.size() > 0:
		var cur: Vector2i = frontier.pop_front()
		var cur_cost: int = reached[cur]
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if nxt.y < 0 or nxt.y >= terrain_grid.size() or nxt.x < 0 or nxt.x >= terrain_grid[nxt.y].size():
				continue
			var t: Dictionary = DataManager.get_terrain(terrain_grid[nxt.y][nxt.x])
			if bool(t.get("impassable", false)):
				continue
			# 敌军格不可进入也不可穿过
			if occupied.has(nxt) and occupied[nxt].team != unit.team:
				continue
			var nc: int = cur_cost + int(t.get("cost", 1))
			if nc > move_pts:
				continue
			if not reached.has(nxt) or nc < reached[nxt]:
				reached[nxt] = nc
				frontier.append(nxt)
	# 起点与友军占据格不可作为停留终点（友军只可穿过）
	reached.erase(start)
	var out: Array = []
	for cell in reached.keys():
		if occupied.has(cell) and occupied[cell].team == unit.team:
			continue   # 友军占据，不可停
		out.append(cell)
	return out

## BFS 还原从 unit 到 target 的最短路径（受地形 cost 与 occupied 限制）。
## 返回 Array[Vector2i]（不含 start，含 target）；target 不可达或就是 start 时返回 []。
static func path_to(unit: Unit, target: Vector2i, terrain_grid: Array, occupied: Dictionary) -> Array:
	var start: Vector2i = unit.grid_pos
	if target == start:
		return []
	var move_pts: int = int(unit.stats.get("move", 5))
	var parent: Dictionary = {}
	var cost: Dictionary = {start: 0}
	var frontier: Array = [start]
	while frontier.size() > 0:
		var cur: Vector2i = frontier.pop_front()
		var cc: int = cost[cur]
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if nxt.y < 0 or nxt.y >= terrain_grid.size() or nxt.x < 0 or nxt.x >= terrain_grid[nxt.y].size():
				continue
			var t: Dictionary = DataManager.get_terrain(terrain_grid[nxt.y][nxt.x])
			if bool(t.get("impassable", false)):
				continue
			# 敌军格不可穿过；友军格可穿过（路径经过），但终点停留合法性由 move_range 控制
			if occupied.has(nxt) and occupied[nxt].team != unit.team:
				continue
			var nc: int = cc + int(t.get("cost", 1))
			if nc > move_pts:
				continue
			if not cost.has(nxt) or nc < cost[nxt]:
				cost[nxt] = nc
				parent[nxt] = cur
				frontier.append(nxt)
	if not parent.has(target):
		return []
	var path: Array = []
	var c: Vector2i = target
	while c != start:
		path.push_front(c)
		c = parent[c]
	return path

## 从某格出发、按武器射程 [min,max]（曼哈顿距离）可攻击到的格。
static func attack_cells(pos: Vector2i, wrange: Array, terrain_grid: Array) -> Array:
	var min_r: int = int(wrange[0])
	var max_r: int = int(wrange[1])
	var out: Array = []
	for y in terrain_grid.size():
		for x in terrain_grid[y].size():
			var d: int = abs(x - pos.x) + abs(y - pos.y)
			if d >= min_r and d <= max_r:
				out.append(Vector2i(x, y))
	return out

## 武器三角：物理 剑>斧>枪>剑；魔法 理>光>暗>理。返回对攻击方的命中/伤害修正与优劣势(-1/0/1)。
static func triangle(att_type: String, def_type: String) -> Dictionary:
	var phys := ["sword", "axe", "lance"]
	var mag := ["anima", "light", "dark"]
	var order: Array = []
	if att_type in phys: order = phys
	elif att_type in mag: order = mag
	else: return {hit = 0, dmg = 0, adv = 0}
	if def_type in order:
		var ia: int = order.find(att_type)
		var idf: int = order.find(def_type)
		if (ia + 1) % 3 == idf: return {hit = TRIANGLE_HIT, dmg = TRIANGLE_DMG, adv = 1}
		if (idf + 1) % 3 == ia: return {hit = -TRIANGLE_HIT, dmg = -TRIANGLE_DMG, adv = -1}
	return {hit = 0, dmg = 0, adv = 0}

static func _is_magic(wtype: String) -> bool:
	return wtype in ["anima", "light", "dark"]

## 命中率（0~100）。att_type/def_type 为双方武器 type；地形/支援加成以参数传入。
static func accuracy(attacker: Unit, defender: Unit, weapon: Dictionary, att_type: String, def_type: String,
		def_terrain_avo := 0, support_hit := 0, support_avo := 0, wrank_hit_bonus := 0, ignore_def_avo := false) -> int:
	var skl: int = int(attacker.stats.get("skl", 0))
	var lck: int = int(attacker.stats.get("lck", 0))
	var dspd: int = int(defender.stats.get("spd", 0))
	var dlck: int = int(defender.stats.get("lck", 0))
	var tri: Dictionary = triangle(att_type, def_type)
	var acc: int = skl * 2 + int(lck / 2) + int(weapon.get("hit", 0)) + int(tri.hit) + support_hit + wrank_hit_bonus
	# 施法不被闪避（silent_cast）：防守方闪避归零
	var avo: int = 0 if ignore_def_avo else (dspd * 2 + dlck + def_terrain_avo + support_avo)
	return clampi(acc - avo, 0, 100)

## True Hit：两次掷骰取均值判命中，降低"高命中却 miss"的憋屈感。
static func roll_hit(chance: int) -> bool:
	var r1: int = randi() % 100
	var r2: int = randi() % 100
	return (r1 + r2) / 2.0 < chance

## 结算一次攻击，返回 {hit, crit, damage, chance, adv}。不改单位血量，由调用方应用。
## def_type: 防守方武器 type（用于三角）；def_terrain: 防守方所在地形 dict（取 def/avo）。
## att_wrank_idx: 攻击方武器熟练度索引(0~5)，每级 +WRANK_HIT_BONUS 命中 / +WRANK_DMG_BONUS 伤害。
static func resolve(attacker: Unit, defender: Unit, weapon: Dictionary, def_type: String,
		def_terrain: Dictionary = {}, support_hit := 0, support_avo := 0, support_dmg := 0,
		att_wrank_idx := 0, att_crit_bonus := 0, att_ignore_def_pct := 0.0,
		def_dmg_reduction := 0, def_avo_ignore := false) -> Dictionary:
	var c: Dictionary = _calc(attacker, defender, weapon, def_type, def_terrain,
			support_hit, support_avo, support_dmg, att_wrank_idx, att_crit_bonus,
			att_ignore_def_pct, def_dmg_reduction, def_avo_ignore)
	var chance: int = c.chance
	var hit: bool = roll_hit(chance)
	var dmg: int = c.dmg
	var crit: bool = hit and (randi() % 100 < c.crit_chance)
	if crit:
		dmg = int(floor(dmg * CRIT_MULT))
	return {hit = hit, crit = crit, damage = dmg, chance = chance, adv = int(c.adv)}

## 确定性战斗预测（不掷骰），返回 {chance, dmg, crit_chance, adv}。供 UI 预读命中/伤害/暴击。
static func forecast(attacker: Unit, defender: Unit, weapon: Dictionary, def_type: String,
		def_terrain: Dictionary = {}, support_hit := 0, support_avo := 0, support_dmg := 0,
		att_wrank_idx := 0, att_crit_bonus := 0, att_ignore_def_pct := 0.0,
		def_dmg_reduction := 0, def_avo_ignore := false) -> Dictionary:
	var c: Dictionary = _calc(attacker, defender, weapon, def_type, def_terrain,
			support_hit, support_avo, support_dmg, att_wrank_idx, att_crit_bonus,
			att_ignore_def_pct, def_dmg_reduction, def_avo_ignore)
	return {chance = c.chance, dmg = c.dmg, crit_chance = c.crit_chance, adv = int(c.adv)}

## 计算命中率/伤害/暴击率（确定性部分），供 resolve 与 forecast 共用，避免两套公式漂移。
static func _calc(attacker: Unit, defender: Unit, weapon: Dictionary, def_type: String,
		def_terrain: Dictionary, support_hit: int, support_avo: int, support_dmg: int,
		att_wrank_idx: int, att_crit_bonus: int, att_ignore_def_pct: float,
		def_dmg_reduction: int, def_avo_ignore: bool) -> Dictionary:
	var wtype: String = weapon.get("type", "")
	var is_magic: bool = _is_magic(wtype)
	var atk_stat: int = int(attacker.stats.get("mag" if is_magic else "str", 0)) + int(weapon.get("might", 0))
	var raw_def: int = int(defender.stats.get("res" if is_magic else "def", 0))
	var eff_def: int = int(round(raw_def * (1.0 - att_ignore_def_pct)))   # 破甲：按比例无视防御
	var tri: Dictionary = triangle(wtype, def_type)
	var terr_def: int = int(def_terrain.get("def", 0))
	var dmg: int = maxi(0, atk_stat - eff_def - terr_def + int(tri.dmg) + support_dmg
			+ att_wrank_idx * DataManager.WRANK_DMG_BONUS - int(def_dmg_reduction))
	var chance: int = accuracy(attacker, defender, weapon, wtype, def_type,
			int(def_terrain.get("avo", 0)), support_hit, support_avo, att_wrank_idx * DataManager.WRANK_HIT_BONUS, def_avo_ignore)
	var crit_chance: int = int(attacker.stats.get("skl", 0)) / 2 + int(weapon.get("crit", 0)) + att_crit_bonus
	return {chance = chance, dmg = dmg, crit_chance = crit_chance, adv = int(tri.adv)}
