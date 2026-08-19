extends Node2D
class_name Unit

## 战斗单位。从角色/职业 JSON 计算初始战斗属性，供 Phase 1/2 使用。
## 实际移动/攻击逻辑将在 Phase 1 的战斗控制器里基于 grid_pos 实现。

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var label: Label = $Label

## 待构建精灵路径（setup 在 add_child 前调用，sprite 尚未 @onready，故延后到 _ready 构建）。
var _spr_path: String = ""
var _hud: Node = null   # 头顶 HUD（HP 条 + 名称），见 UnitHud.gd

const FRAME_W: int = 64   # 精灵表每帧宽（与 generate_sprites.py 保持一致）
const FRAME_H: int = 64
const UNIT_ANIMS: Array = ["idle", "move", "attack", "hurt", "dead"]

var data: Dictionary = {}
var team: String = "player"
var grid_pos: Vector2i = Vector2i.ZERO
var stats: Dictionary = {}
var max_hp: int = 1
var hp: int = 1
var personal_skill: String = ""
var class_skills: Array = []
var char_id: String = ""
var class_id: String = ""
var acted: bool = false
var equipped_weapon: String = ""
var display_name: String = ""
var is_lord: bool = false
# ---- 养成（Phase 2） ----
var lvl: int = 1
var exp: int = 0
var weapon_ranks: Dictionary = {}   # 武器类型 -> 等级 letter (E~S)
var weapon_exp: Dictionary = {}      # 武器类型 -> 累计武器EXP
var inventory: Array = []            # 持有道具 id（转职道具等）
# ---- 技能状态（Phase 3） ----
var personal_skills: Array = []          # 额外个人专属技能 id（characters.json 的 personal_skills 数组）
var shield: int = 0                      # 当前护盾值（warding_light），回合切换清零
var pending_ignore_def: float = 0.0      # armor_pierce 激活后，下次攻击无视防御比例（仅生效一次）
var active_cooldowns: Dictionary = {}    # skill_id -> 剩余冷却回合

func setup(d: Dictionary) -> void:
	data = d
	team = d.get("team", "player")
	var p: Array = d.get("pos", [0, 0])
	grid_pos = Vector2i(int(p[0]), int(p[1]))

	var char: Dictionary = {}
	if d.has("char_id") and DataManager.characters.has(d["char_id"]):
		char_id = d["char_id"]
		char = DataManager.get_character(char_id)
		class_id = char.get("base_class", "lord")
	else:
		class_id = d.get("class", "brigand")   # 敌方用 class 字段

	var cls: Dictionary = DataManager.get_class_data(class_id)
	lvl = int(d.get("lv", 1))

	# 从职业基础 + 成长率算出"全新"进度
	stats = cls.get("base_stats", {}).duplicate()
	_apply_levelups(lvl, cls.get("growth_rates", {}), char.get("growth_modifier", {}))
	inventory = d.get("items", [])
	var wranks: Dictionary = cls.get("weapon_ranks", {})
	weapon_ranks = {}
	weapon_exp = {}
	for wt in wranks.keys():
		weapon_ranks[wt] = wranks[wt]
		weapon_exp[wt] = DataManager.wrank_exp_for_rank(wranks[wt])
	exp = 0

	# ---- Phase 6：跨战进度覆盖 ----
	# 我方且有角色 id 时，优先用 Campaign.roster 里已固化的进度；
	# 首次出场则把当前进度写回 roster，作为后续养成的权威来源。
	if team == "player" and char_id != "":
		if Campaign.roster.has(char_id):
			_apply_progress(Campaign.roster[char_id])
		else:
			Campaign.roster[char_id] = progress_dict()

	# 派生属性（class_id 可能被 roster 覆盖过，需重读职业）
	cls = DataManager.get_class_data(class_id)
	max_hp = int(stats.get("hp", 1))
	hp = max_hp
	is_lord = cls.get("is_lord", false)
	personal_skill = char.get("personal_skill", "")
	personal_skills = char.get("personal_skills", [])
	class_skills = cls.get("class_skills", [])

	display_name = char.get("name", d.get("char_id", class_id))
	# 装备武器：地图指定则用指定，否则按当前职业首个武器类型取默认武器
	if d.has("weapon"):
		equipped_weapon = d["weapon"]
	elif weapon_ranks.size() > 0:
		equipped_weapon = DataManager.default_weapon_for(weapon_ranks.keys()[0])
	refresh_label()

	var spr_path: String = char.get("battle_sprite", "")
	# 敌方/无立绘角色：回退到职业通用精灵 assets/sprites/units/{class_id}.png
	if spr_path == "":
		var cls_spr := "res://assets/sprites/units/%s.png" % class_id
		if FileAccess.file_exists(cls_spr):
			spr_path = cls_spr
	_spr_path = spr_path   # sprite 此时（@onready）未就绪，延后到 _ready 构建

	# 头顶 HUD：HP 条 + 名称/Lv，绘制在精灵之上（作为最后一个子节点）
	_hud = Node2D.new()
	_hud.set_script(load("res://src/UnitHud.gd"))
	add_child(_hud)
	# label.visible 在 _ready 设（label 此时才 @onready 就绪）

## 当前养成进度快照（写入 Campaign.roster，供下一场战斗还原）。
func _ready() -> void:
	# setup 在 add_child 前调用，此时 @onready sprite/label 尚未就绪，故精灵帧与 label 在此构建。
	var tex: Texture2D = _load_sprite(_spr_path)
	if sprite != null and tex != null:
		_build_frames(tex)
		sprite.offset = Vector2(0, -20)
		sprite.scale = Vector2(0.7, 0.7)
		sprite.play("idle")
	if label != null:
		label.visible = false

## 加载精灵纹理：有 .import 用 load()（最快），否则直接 Image.load()（避免未导入资源的 loader 警告）。
func _load_sprite(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	if FileAccess.file_exists(path + ".import"):
		var r = load(path)
		if r != null:
			return r
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

func progress_dict() -> Dictionary:
	return {
		"class_id": class_id,
		"lvl": lvl,
		"exp": exp,
		"stats": stats.duplicate(),
		"weapon_ranks": weapon_ranks.duplicate(),
		"weapon_exp": weapon_exp.duplicate(),
		"inventory": inventory.duplicate(),
	}

## 用持久化进度覆盖当前单位（class_id/lvl/exp/stats/武器/道具）。
func _apply_progress(p: Dictionary) -> void:
	if p.is_empty():
		return
	class_id = p.get("class_id", class_id)
	lvl = int(p.get("lvl", lvl))
	exp = int(p.get("exp", 0))
	stats = p.get("stats", stats).duplicate()
	weapon_ranks = p.get("weapon_ranks", weapon_ranks).duplicate()
	weapon_exp = p.get("weapon_exp", weapon_exp).duplicate()
	inventory = p.get("inventory", inventory).duplicate()

## 从横排精灵表（idle|move|attack|hurt|dead）切片出 5 个动画。
## 真实素材只要保持“横排 5 帧、每帧 64x64”的布局即可直接替换，无需改代码。
func _build_frames(tex: Texture2D) -> void:
	if tex == null:
		return
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for i in range(UNIT_ANIMS.size()):
		var name: String = UNIT_ANIMS[i]
		sf.add_animation(name)
		sf.set_animation_loop(name, name in ["idle", "move"])
		sf.set_animation_speed(name, 8 if name in ["idle", "move"] else 1)
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame(name, at)
	sprite.sprite_frames = sf

## 播放指定动作。idle/move 循环；attack/hurt/dead 播一次后用计时器回 idle（不阻塞调用方，杜绝 await 挂起卡死）。
func play_anim(name: String) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(name):
		return
	sprite.play(name)
	if not (name in ["idle", "move"]):
		# 非循环动作：固定 0.4 秒后回 idle（attack/hurt），dead 不回。
		if name == "dead":
			return
		var tw := create_tween()
		tw.tween_interval(0.4)
		tw.tween_callback(func() -> void:
			if sprite != null and is_instance_valid(sprite) and sprite.animation == name:
				sprite.play("idle"))

## 按成长率（含角色个人修正）模拟升级，得到最终属性。
func _apply_levelups(lvl: int, growth: Dictionary, mod: Dictionary) -> void:
	for i in range(maxi(0, lvl - 1)):
		for key in growth.keys():
			var g: int = int(growth[key]) + int(mod.get(key, 0))
			if randi() % 100 < g:
				stats[key] = int(stats.get(key, 0)) + 1

func refresh_label() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_redraw()   # HP 变化刷新头顶血条
	if label == null:
		return
	var txt := "%s Lv%d %d/%d" % [display_name, lvl, hp, max_hp]
	if shield > 0:
		txt += " [盾%d]" % shield
	label.text = txt
	label.add_theme_color_override("font_color", Color.RED if team == "enemy" else Color.GREEN)

## 选中/行动状态表现：选中高亮由 BattleController 画框，这里只管精灵明暗。
## 已行动且未选中 -> 变灰；否则正常白。
func apply_state(sel: bool, acted_flag: bool) -> void:
	if sprite == null:
		return
	if acted_flag and not sel:
		sprite.modulate = Color(0.4, 0.4, 0.45)
	else:
		sprite.modulate = Color.WHITE

# ================= 养成（Phase 2） =================

## 一次升级的成长结算（含角色个人修正）。返回各属性增量，供 UI 展示。
func _roll_one_levelup() -> Dictionary:
	var cls: Dictionary = DataManager.get_class_data(class_id)
	var growth: Dictionary = cls.get("growth_rates", {})
	var char: Dictionary = DataManager.get_character(char_id)
	var mod: Dictionary = char.get("growth_modifier", {})
	var gains: Dictionary = {}
	for key in growth.keys():
		var g: int = int(growth[key]) + int(mod.get(key, 0))
		if randi() % 100 < g:
			stats[key] = int(stats.get(key, 0)) + 1
			gains[key] = int(gains.get(key, 0)) + 1
	return gains

## 获得经验，自动连升多级（封顶 MAX_LEVEL）。返回升了几级。
func gain_exp(amount: int) -> int:
	if team != "player":
		return 0
	exp += int(amount)
	var gained := 0
	while exp >= DataManager.EXP_PER_LEVEL and lvl < DataManager.MAX_LEVEL:
		exp -= DataManager.EXP_PER_LEVEL
		lvl += 1
		_roll_one_levelup()
		gained += 1
	if lvl >= DataManager.MAX_LEVEL:
		exp = 0
	# 属性成长跟在 stats 上，刷新 HP 上限并补足增量
	var new_max := int(stats.get("hp", 1))
	var hp_gain := new_max - max_hp
	if hp_gain > 0:
		hp += hp_gain
	max_hp = new_max
	refresh_label()
	return gained

## 武器熟练度经验：累计后按阈值刷新等级 letter。
func gain_weapon_exp(wtype: String, amount: int) -> void:
	if not weapon_exp.has(wtype):
		weapon_exp[wtype] = 0
	weapon_exp[wtype] += int(amount)
	weapon_ranks[wtype] = DataManager.wrank_letter_from_exp(weapon_exp[wtype])

## 当前武器类型的熟练度索引（0~5），供 Combat 计算命中/伤害加成。
func wrank_index_of(wtype: String) -> int:
	return DataManager.wrank_index(weapon_ranks.get(wtype, "E"))

## 能否转职：我方 + 满 10 级 + 持有转职道具 + 职业有进阶分支。
func can_promote(item_id: String = DataManager.PROMOTE_ITEM) -> bool:
	if team != "player":
		return false
	if lvl < 10:
		return false
	if DataManager.get_class_data(class_id).get("promotes_to", []).size() == 0:
		return false
	return item_id in inventory

func promote_choices() -> Array:
	return DataManager.get_class_data(class_id).get("promotes_to", [])

## 转职：切换到进阶职，重置为 1 级，保留已养成属性并取较高武器熟练度。
func promote_to(new_class_id: String, item_id: String = DataManager.PROMOTE_ITEM) -> bool:
	if not can_promote(item_id):
		return false
	if new_class_id not in promote_choices():
		return false
	class_id = new_class_id
	lvl = 1
	exp = 0
	inventory.erase(item_id)
	var ncls: Dictionary = DataManager.get_class_data(new_class_id)
	class_skills = ncls.get("class_skills", [])
	# 武器熟练度取旧职业与新职业的较高者
	var nwr: Dictionary = ncls.get("weapon_ranks", {})
	for wt in nwr.keys():
		var new_idx: int = DataManager.wrank_index(nwr[wt])
		if not weapon_ranks.has(wt) or DataManager.wrank_index(weapon_ranks[wt]) < new_idx:
			weapon_ranks[wt] = nwr[wt]
			weapon_exp[wt] = DataManager.wrank_exp_for_rank(nwr[wt])
	# 当前武器不属于新职业武器列表时，重新取默认武器
	var cur_wtype: String = DataManager.get_weapon(equipped_weapon).get("type", "")
	if equipped_weapon == "" or not weapon_ranks.has(cur_wtype):
		if weapon_ranks.size() > 0:
			equipped_weapon = DataManager.default_weapon_for(weapon_ranks.keys()[0])
	max_hp = int(stats.get("hp", 1))
	hp = max_hp
	refresh_label()
	return true

## 单位当前可使用的所有武器 id（按 weapon_ranks 等级筛选，含已装备）。
func usable_weapons() -> Array:
	var out: Array = []
	for wid in DataManager.weapons.keys():
		var w: Dictionary = DataManager.get_weapon(wid)
		var wtype: String = w.get("type", "")
		if not weapon_ranks.has(wtype):
			continue
		var unit_rank: String = weapon_ranks[wtype]
		if DataManager.wrank_index(unit_rank) >= DataManager.wrank_index(w.get("rank_required", "E")):
			out.append(wid)
	return out

func _to_string() -> String:
	return "<Unit %s Lv%d hp=%d/%d>" % [char_id if char_id != "" else class_id, lvl, hp, max_hp]

## 每回合切换时调用：清护盾、减主动技能冷却。
func tick_status() -> void:
	shield = 0
	for k in active_cooldowns.keys():
		active_cooldowns[k] = maxi(0, int(active_cooldowns[k]) - 1)
