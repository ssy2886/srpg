extends Node

## DataManager —— Autoload 单例，启动时加载 data/ 下所有 JSON 到内存字典。
## 注册方式：Project Settings → Globals → 把本脚本加为 Autoload，名称填 DataManager。

var classes: Dictionary = {}
var characters: Dictionary = {}
var skills: Dictionary = {}
var weapons: Dictionary = {}
var terrain: Dictionary = {}
var items: Dictionary = {}
var decisions: Dictionary = {}
var stories: Dictionary = {}

const DATA_DIR := "res://data/"

## 各武器类型的默认武器 id（单位未指定装备时，按职业首个武器类型取用）。
const DEFAULT_WEAPON := {
	"sword": "iron_sword", "axe": "iron_axe", "lance": "iron_lance",
	"bow": "short_bow", "anima": "fire_tome", "light": "light_tome", "staff": "heal_staff"
}

## ---- 养成（Phase 2）常量 ----
const WRANK_ORDER := ["E", "D", "C", "B", "A", "S"]
const WRANK_EXP_THRESHOLDS := [0, 21, 41, 61, 81, 101]   # 对应 E,D,C,B,A,S 的累计武器EXP
const WRANK_HIT_BONUS := 5     # 每级武器熟练度对命中的加成
const WRANK_DMG_BONUS := 1     # 每级武器熟练度对伤害的加成
const MAX_LEVEL := 20          # 每个职业阶满级
const EXP_PER_LEVEL := 100
const PROMOTE_ITEM := "master_seal"   # 转职道具 id

func default_weapon_for(type: String) -> String:
	return DEFAULT_WEAPON.get(type, "")

## 武器等级 letter -> 索引(0~5) / 反向：由累计武器EXP得等级 letter
func wrank_index(letter: String) -> int:
	return WRANK_ORDER.find(letter) if WRANK_ORDER.has(letter) else 0

func wrank_letter_from_exp(exp: int) -> String:
	var idx := 0
	for i in WRANK_EXP_THRESHOLDS.size():
		if exp >= WRANK_EXP_THRESHOLDS[i]:
			idx = i
	return WRANK_ORDER[idx]

func wrank_exp_for_rank(letter: String) -> int:
	return WRANK_EXP_THRESHOLDS[wrank_index(letter)]

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	classes = _index("classes", "classes.json")
	characters = _index("characters", "characters.json")
	skills = _index("skills", "skills.json")
	weapons = _index("weapons", "weapons.json")
	terrain = _index("terrain", "terrain.json")
	items = _index("items", "items.json")
	decisions = _index("decisions", "decisions.json")
	stories = _load_json("story.json").get("stories", {})
	print("[DataManager] 职业:%d 角色:%d 技能:%d 武器:%d 地形:%d 道具:%d 抉择:%d 剧情:%d" % [
		classes.size(), characters.size(), skills.size(), weapons.size(), terrain.size(), items.size(), decisions.size(), stories.size()])

## 读取 JSON 文件，返回 Dictionary；缺失/损坏则返回 {}。
func _load_json(filename: String) -> Dictionary:
	var path := DATA_DIR + filename
	if not FileAccess.file_exists(path):
		push_error("DataManager: 找不到 %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataManager: JSON 解析失败 %s" % path)
		return {}
	return parsed

## 把数据索引成字典。兼容两种结构：
##  - 列表：[{"id":..., ...}] -> 按每项 id 索引
##  - 字典：{id: {...}} -> 按 key 索引，并把 key 注入为 item["id"]（decisions.json 用此结构）
func _index(list_key: String, filename: String) -> Dictionary:
	var d := _load_json(filename)
	var raw: Variant = d.get(list_key, [])
	var out: Dictionary = {}
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			out[item["id"]] = item
	elif typeof(raw) == TYPE_DICTIONARY:
		for key in raw.keys():
			var item: Variant = raw[key]
			if typeof(item) == TYPE_DICTIONARY:
				if not item.has("id"):
					var copy: Dictionary = item.duplicate()
					copy["id"] = key
					out[key] = copy
				else:
					out[key] = item
			else:
				out[key] = item
	return out

## ---- 查询接口 ----
func get_class_data(id: String) -> Dictionary: return classes.get(id, {})
func get_character(id: String) -> Dictionary: return characters.get(id, {})
func get_skill(id: String) -> Dictionary: return skills.get(id, {})
func get_weapon(id: String) -> Dictionary: return weapons.get(id, {})
func get_terrain(id: String) -> Dictionary: return terrain.get(id, {})
func get_item(id: String) -> Dictionary: return items.get(id, {})
func get_decision(id: String) -> Dictionary: return decisions.get(id, {})
func get_story(id: String) -> Dictionary: return stories.get(id, {})

## 读取一张地图（maps/ 下的 JSON）。
func get_map(map_id: String) -> Dictionary:
	return _load_json("maps/" + map_id + ".json")
