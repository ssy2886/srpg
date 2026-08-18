extends RefCounted

## SupportTracker —— 支持（支援）关系进度追踪（Phase 3）。
## 跨战斗累计任意两我方角色的"并肩出战回合数"，达阈值解锁 C/B/A 级；
## 提供战场数值加成查询。内存单例（静态 _instance），后续接存档。

const RANK_NAMES := ["", "C", "B", "A"]
const BONUS := {   # rank -> {hit, dmg}
	1: {"hit": 5, "dmg": 1},
	2: {"hit": 8, "dmg": 2},
	3: {"hit": 12, "dmg": 3}
}

static var _instance: RefCounted
## GDScript 4.2 不允许在 static 函数里自引用 class_name，故用 load() 取本脚本再 new()。
## 调用方（_ST.get_instance()）走动态分发即可。
static func get_instance():
	if _instance == null:
		_instance = load("res://src/SupportTracker.gd").new()
	return _instance

var progress: Dictionary = {}   # "idA|idB"(排序) -> {turns:int, rank:int}

static func _key(a: String, b: String) -> String:
	var arr := [a, b]
	arr.sort()
	return arr[0] + "|" + arr[1]

## 一场战斗每回合调用：给所有存活我方单位两两 +n 并肩回合。返回本场新解锁对话请求。
func record_battle_turns(alive_ids: Array, n := 1) -> Array:
	var unlocks: Array = []
	for i in alive_ids.size():
		for j in range(i + 1, alive_ids.size()):
			var a: String = alive_ids[i]; var b: String = alive_ids[j]
			var k := _key(a, b)
			if not progress.has(k):
				progress[k] = {"turns": 0, "rank": 0}
			var p: Dictionary = progress[k]
			var old_rank: int = p.rank
			p.turns += n
			var new_rank := _rank_from_data(a, b, p.turns)
			if new_rank > old_rank:
				p.rank = new_rank
				unlocks.append({"a": a, "b": b, "rank": new_rank})
	return unlocks

## 依据 characters.json 的 supports.unlock_turns 阈值推算等级。
func _rank_from_data(a: String, b: String, turns: int) -> int:
	var ch := DataManager.get_character(a)
	for s in ch.get("supports", []):
		if s.with == b:
			var th: Array = s.get("unlock_turns", [])
			var r := 0
			for i in th.size():
				if turns >= int(th[i]):
					r = i + 1
			return r
	return 0

## 当前等级（0=无）。
func rank_of(a: String, b: String) -> int:
	var p: Dictionary = progress.get(_key(a, b), {})
	return int(p.get("rank", 0))

## 等级对应的战场数值加成。
func bonus_for_rank(rank: int) -> Dictionary:
	return BONUS.get(rank, {"hit": 0, "dmg": 0})

## 取某对在某等级的台词（characters.json 的 support_lines["{RANK}_{对方id}"]）。
func dialog_text(a: String, b: String, rank: int) -> String:
	var key := "%s_%s" % [RANK_NAMES[rank], b]
	return DataManager.get_character(a).get("support_lines", {}).get(key, "")
