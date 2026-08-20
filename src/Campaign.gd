extends Node

## 支持关系追踪器（class_name 注册顺序在 autoload 之前不确定，这里显式 preload 以避开编译期未声明）。
const _ST = preload("res://src/SupportTracker.gd")

## Campaign —— 战役进度单例（AutoLoad，名称 Campaign）。
## 作为「大地图 ↔ 战斗」之间的中转状态：记录已通关关卡、拥有角色、主线 flag、拥有道具，
## 以及战斗结束待弹出的支持对话。场景切换时本单例不销毁，进度得以保留。

const INITIAL_PARTY := ["lyra", "garrett", "mira"]

var cleared_maps: Dictionary = {}   # map_id -> true
var owned_chars: Dictionary = {}    # char_id -> true
var owned_items: Dictionary = {}    # item_id -> true
var story_flags: Dictionary = {}    # flag -> true
var pending_support: Array = []     # 战斗结束待弹的支持对话请求 [{a,b,rank}]
var pending_decision: String = ""   # 战斗胜利后待弹出的抉择点 id（仿 pending_support）
var decisions_made: Dictionary = {}  # decision_id -> true（抉择点只触发一次）
var stories_seen: Dictionary = {}    # story_key -> true（剧情对话只播一次）
var current_map_id: String = ""     # WorldMap 进入战斗前设置，Battle 读取

# ---- Phase 6：永久死亡 + 角色进度持久化 ----
var permadeath: bool = false        # 永久死亡开关（标题界面可切换）
# 战斗动画模式：0=全开(每次攻击都弹特写) 1=仅特写(仅暴击/击杀时弹) 2=关闭(不弹特写,地图内快速结算)
var battle_anim: int = 0
var roster: Dictionary = {}         # char_id -> 进度字典（lvl/exp/stats/武器/职业/道具）
                                    # 是角色养成的"权威存档"，跨战斗保留；permadeath 下阵亡即抹除。

func _ready() -> void:
	reset()

func reset() -> void:
	cleared_maps.clear()
	owned_chars.clear()
	owned_items.clear()
	story_flags.clear()
	pending_support.clear()
	pending_decision = ""
	decisions_made.clear()
	stories_seen.clear()
	current_map_id = ""
	roster.clear()
	permadeath = false
	for c in INITIAL_PARTY:
		owned_chars[c] = true

## 开新游戏：清空进度并把永久死亡开关设为用户选择（不立即写盘，首胜时落档）。
func new_game(pd: bool) -> void:
	reset()
	permadeath = pd

# ---- 抉择点（Phase 5） ----
func mark_decided(id: String) -> void:
	decisions_made[id] = true
func is_decided(id: String) -> bool:
	return decisions_made.get(id, false)

# ---- 剧情已读（每段剧情只播一次） ----
func mark_story_seen(key: String) -> void:
	stories_seen[key] = true
func is_story_seen(key: String) -> bool:
	return stories_seen.get(key, false)

# ---- Phase 6：序列化 / 反序列化 ----
## 把当前战役状态打包成可 JSON 化的字典。
func serialize() -> Dictionary:
	return {
		"permadeath": permadeath,
		"cleared_maps": cleared_maps,
		"owned_chars": owned_chars,
		"owned_items": owned_items,
		"story_flags": story_flags,
		"decisions_made": decisions_made,
		"stories_seen": stories_seen,
		"current_map_id": current_map_id,
		"roster": roster,
		"support": _ST.get_instance().progress,
	}

## 从字典恢复战役状态（继续游戏时调用）。
func deserialize(d: Dictionary) -> void:
	reset()
	permadeath = bool(d.get("permadeath", false))
	battle_anim = int(d.get("battle_anim", 0))
	cleared_maps = d.get("cleared_maps", {})
	owned_chars = d.get("owned_chars", {})
	owned_items = d.get("owned_items", {})
	story_flags = d.get("story_flags", {})
	decisions_made = d.get("decisions_made", {})
	stories_seen = d.get("stories_seen", {})
	current_map_id = d.get("current_map_id", "")
	roster = d.get("roster", {})
	_ST.get_instance().progress = d.get("support", {})
	# 兜底：初始队伍至少存在（防止旧档缺字段）
	for c in INITIAL_PARTY:
		if not owned_chars.has(c):
			owned_chars[c] = true

# ---- 关卡 ----
func mark_cleared(map_id: String) -> void:
	cleared_maps[map_id] = true
func is_cleared(map_id: String) -> bool:
	return cleared_maps.get(map_id, false)

# ---- 角色 ----
func grant_char(id: String) -> void:
	owned_chars[id] = true
func owns_char(id: String) -> bool:
	return owned_chars.get(id, false)
func owned_char_list() -> Array:
	return owned_chars.keys()

# ---- 主线 flag ----
func set_flag(f: String) -> void:
	story_flags[f] = true
func has_flag(f: String) -> bool:
	return story_flags.get(f, false)

# ---- 道具 ----
func grant_item(id: String) -> void:
	owned_items[id] = true
func owns_item(id: String) -> bool:
	return owned_items.get(id, false)
func owned_item_list() -> Array:
	return owned_items.keys()
