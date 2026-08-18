class_name SkillManager
extends RefCounted

## Unit 类型声明（避免 class_name 注册顺序导致的 "Could not find type Unit"）。
const Unit = preload("res://src/Unit.gd")

## SkillManager —— 把 skills.json 里的数据驱动效果接入战斗结算。
## 被动/条件技能在攻击时自动生效；主动技能由 BattleController 调 activate() 触发，带冷却。
## 设计：所有 effect.kind 在此集中解释；加新技能只改 skills.json + 在此为对应 kind 补一行。
## 用法：class_name 全局可用，直接 SkillManager.xxx() 调用，无需注册 Autoload。

## 收集单位当前生效技能（个人专属 + 额外个人技能 + 职业专属）。
static func skills_of(u: Unit) -> Array:
	var ids: Array = []
	if u.personal_skill != "":
		ids.append(u.personal_skill)
	for s in u.personal_skills:
		ids.append(s)
	for s in u.class_skills:
		ids.append(s)
	var out: Array = []
	for id in ids:
		var sk: Dictionary = DataManager.get_skill(id)
		if not sk.is_empty():
			out.append(sk)
	return out

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

## 防守方受伤减少（相邻友军光环 + 自身护盾）。allies 含防守方同队活单位（含自身）。
static func defense_bonus(defender: Unit, allies: Array) -> int:
	var total := 0
	for a in allies:
		if a.hp <= 0:
			continue
		var dist := _manhattan(a.grid_pos, defender.grid_pos)
		for sk in skills_of(a):
			var e: Dictionary = sk.get("effect", {})
			if e.get("kind") == "adjacent_ally_damage_reduction" and dist <= int(e.get("range", 1)):
				total += int(e.get("value", 0))
	total += int(defender.shield)   # 护盾作为减伤项
	return total

## 攻击者暴击率加成（自身 passive，如 keen_edge）。
static func attack_crit_bonus(attacker: Unit) -> int:
	var total := 0
	for sk in skills_of(attacker):
		var e: Dictionary = sk.get("effect", {})
		if e.get("kind") == "crit_bonus":
			total += int(e.get("value", 0))
	return total

## 攻击者命中加成（相邻友军光环，如 royal_edict）。
static func attack_hit_bonus(attacker: Unit, allies: Array) -> int:
	var total := 0
	for a in allies:
		if a.hp <= 0:
			continue
		var dist := _manhattan(a.grid_pos, attacker.grid_pos)
		for sk in skills_of(a):
			var e: Dictionary = sk.get("effect", {})
			if e.get("kind") == "adjacent_ally_hit_bonus" and dist <= int(e.get("range", 1)):
				total += int(e.get("value", 0))
	return total

## 攻击者无视防御比例（armor_pierce 激活后）。attack_ignore_def 返回后由调用方清零（仅生效一次）。
static func attack_ignore_def(attacker: Unit) -> float:
	return attacker.pending_ignore_def

## 单位自身闪避加成（条件技能，无论攻防，如 swift_reaction）。
static func avoid_bonus(u: Unit) -> int:
	var total := 0
	for sk in skills_of(u):
		var e: Dictionary = sk.get("effect", {})
		if e.get("kind") != "avoid_bonus":
			continue
		var trig: Dictionary = sk.get("trigger", {})
		var ok := false
		match trig.get("condition", ""):
			"hp_below_pct":
				ok = (float(u.hp) / float(maxi(1, u.max_hp)) * 100.0) < float(trig.get("value", 0))
		if ok:
			total += int(e.get("value", 0))
	return total

## 攻击者施法不被闪避（silent_cast，仅魔法武器）。
static func magic_avo_ignore(attacker: Unit, wtype: String) -> bool:
	if wtype != "anima" and wtype != "light" and wtype != "dark":
		return false
	for sk in skills_of(attacker):
		if sk.get("effect", {}).get("kind") == "magic_avoid_ignore":
			return true
	return false

## 激活主动技能（ignore_defense / shield_ally）。返回是否成功（失败含：非主动 / 未拥有 / 冷却中）。
static func activate(actor: Unit, skill_id: String, allies: Array) -> bool:
	var sk: Dictionary = DataManager.get_skill(skill_id)
	if sk.is_empty() or sk.get("type") != "active":
		return false
	if skill_id != actor.personal_skill and skill_id not in actor.personal_skills and skill_id not in actor.class_skills:
		return false
	if int(actor.active_cooldowns.get(skill_id, 0)) > 0:
		return false
	var e: Dictionary = sk.get("effect", {})
	match e.get("kind"):
		"ignore_defense":
			actor.pending_ignore_def = float(e.get("value", 0.0))
			actor.active_cooldowns[skill_id] = int(sk.get("cooldown", 0))
			return true
		"shield_ally":
			var rng: int = int(e.get("range", 1))
			var val: int = int(e.get("value", 0))
			for a in allies:
				if a.hp <= 0:
					continue
				if _manhattan(a.grid_pos, actor.grid_pos) <= rng:
					a.shield += val
			actor.active_cooldowns[skill_id] = int(sk.get("cooldown", 0))
			return true
	return false
