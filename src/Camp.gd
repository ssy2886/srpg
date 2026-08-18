extends Control
class_name Camp

## 支持关系追踪器（无 class_name，显式 preload 以稳定解析）。
const SupportTracker = preload("res://src/SupportTracker.gd")
const SupportDialog = preload("res://src/SupportDialog.gd")

## Camp —— 大地图营地 / 角色与支持列表（Phase 3 收尾 + UI）。
## 提供两个标签：
##   1) 角色：我方名册（立绘 + 姓名/称号/职业/武器等级/技能/背景），可逐个查看。
##   2) 支持：已拥有角色两两关系的 C/B/A 进度，解锁后可点击回放台词（走 SupportDialog）。
## 数据全部来自 DataManager / Campaign / SupportTracker，零硬编码。Esc 返回大地图。

const RANK_NAMES := ["C", "B", "A"]
const WEAPON_NAME := {"sword":"剑","axe":"斧","lance":"枪","bow":"弓","anima":"理","light":"光","dark":"暗","staff":"杖"}

var tab := 0            # 0 角色 / 1 支持 / 2 道具
var roster_sel := 0
var support_sel := 0
var item_sel := 0

var _owned: Array = []          # 拥有角色 id（按 Campaign）
var _support_entries: Array = [] # [{a,b,rank,text,unlocked}]

# 持久节点
var roster_list: VBoxContainer
var support_list: VBoxContainer
var item_list: VBoxContainer
var detail: Control
var portrait: TextureRect
var portrait_hint: Label
var name_label: Label
var title_label: Label
var class_label: Label
var rank_label: Label
var stat_label: Label
var weapon_label: Label
var skill_label: Label
var bg_label: Label
var tab_roster: Button
var tab_support: Button
var tab_items: Button

# 属性中文名（显示用，与 classes.json base_stats 键对应）
const STAT_NAME := {
	"hp": "HP", "str": "力量", "mag": "魔法", "skl": "技巧", "spd": "速度",
	"lck": "幸运", "def": "防御", "res": "魔防", "con": "体格", "move": "移动",
}
const STAT_ORDER := ["hp", "str", "mag", "skl", "spd", "lck", "def", "res", "con", "move"]

func _ready() -> void:
	# 满屏锚点让 size 自动跟随窗口；UI 构建延迟一帧等 size 就绪，避免布局偏移。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_owned = Campaign.owned_char_list()
	_build_static_ui.call_deferred()
	_switch_tab.call_deferred(0)

# ---------- 静态框架 ----------
func _build_static_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "营地 · 角色与支持"
	title.position = Vector2(30, 22)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	add_child(title)

	tab_roster = Button.new(); tab_roster.text = "角色 (1)"; tab_roster.position = Vector2(30, 62)
	tab_roster.pressed.connect(_switch_tab.bind(0)); add_child(tab_roster)
	tab_support = Button.new(); tab_support.text = "支持 (2)"; tab_support.position = Vector2(130, 62)
	tab_support.pressed.connect(_switch_tab.bind(1)); add_child(tab_support)
	tab_items = Button.new(); tab_items.text = "道具 (3)"; tab_items.position = Vector2(230, 62)
	tab_items.pressed.connect(_switch_tab.bind(2)); add_child(tab_items)

	roster_list = VBoxContainer.new(); roster_list.position = Vector2(30, 108)
	roster_list.size = Vector2(280, size.y - 150); add_child(roster_list)

	support_list = VBoxContainer.new(); support_list.position = Vector2(30, 108)
	support_list.size = Vector2(440, size.y - 150); support_list.visible = false; add_child(support_list)

	item_list = VBoxContainer.new(); item_list.position = Vector2(30, 108)
	item_list.size = Vector2(440, size.y - 150); item_list.visible = false; add_child(item_list)

	detail = Control.new(); detail.position = Vector2(340, 108)
	detail.size = Vector2(size.x - 360, size.y - 150); add_child(detail)

	portrait = TextureRect.new(); portrait.position = Vector2(0, 0); portrait.size = Vector2(160, 200)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; detail.add_child(portrait)
	portrait_hint = Label.new(); portrait_hint.position = Vector2(0, 206)
	portrait_hint.add_theme_color_override("font_color", Color(0.5,0.5,0.5)); detail.add_child(portrait_hint)

	name_label = Label.new(); name_label.position = Vector2(180, 0); detail.add_child(name_label)
	title_label = Label.new(); title_label.position = Vector2(180, 28); detail.add_child(title_label)
	class_label = Label.new(); class_label.position = Vector2(180, 56); detail.add_child(class_label)
	rank_label = Label.new(); rank_label.position = Vector2(180, 84); rank_label.size = Vector2(detail.size.x-180, 24)
	rank_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5)); detail.add_child(rank_label)
	stat_label = Label.new(); stat_label.position = Vector2(180, 112); stat_label.size = Vector2(detail.size.x-180, 56)
	stat_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0)); detail.add_child(stat_label)
	weapon_label = Label.new(); weapon_label.position = Vector2(180, 176); weapon_label.size = Vector2(detail.size.x-180, 24)
	weapon_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.95)); detail.add_child(weapon_label)
	skill_label = Label.new(); skill_label.position = Vector2(180, 206); skill_label.size = Vector2(detail.size.x-180, 150)
	skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85)); detail.add_child(skill_label)
	bg_label = Label.new(); bg_label.position = Vector2(0, 372); bg_label.size = Vector2(detail.size.x, 110)
	bg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail.add_child(bg_label)

	var hint := Label.new()
	hint.text = "1/2/3 切换标签 · ↑↓ 选择 · Enter 查看/回放 · Esc 返回大地图"
	hint.position = Vector2(30, size.y - 28)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6)); add_child(hint)

# ---------- 标签切换 ----------
func _switch_tab(t: int) -> void:
	tab = t
	roster_list.visible = (t == 0)
	support_list.visible = (t == 1)
	item_list.visible = (t == 2)
	tab_roster.button_pressed = (t == 0)
	tab_support.button_pressed = (t == 1)
	tab_items.button_pressed = (t == 2)
	match t:
		0: _build_roster()
		1: _build_support()
		2: _build_items()

# ---------- 角色名册 ----------
func _build_roster() -> void:
	for c in roster_list.get_children():
		c.queue_free()
	if _owned.is_empty():
		var l := Label.new(); l.text = "（暂无角色）"; roster_list.add_child(l); return
	roster_sel = clampi(roster_sel, 0, _owned.size() - 1)
	for i in _owned.size():
		var id: String = _owned[i]
		var ch := DataManager.get_character(id)
		var b := Button.new()
		b.text = "%s  %s" % [ch.get("name", id), ch.get("title", "")]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if i == roster_sel:
			b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		b.pressed.connect(_on_roster_pick.bind(i))
		roster_list.add_child(b)
	_show_detail(_owned[roster_sel])

func _on_roster_pick(i: int) -> void:
	roster_sel = i
	_build_roster()

func _show_detail(id: String) -> void:
	var ch := DataManager.get_character(id)
	if ch.is_empty():
		return
	name_label.text = "姓名：%s" % ch.get("name", id)
	title_label.text = "称号：%s" % ch.get("title", "")

	# ---- 实时进度（来自 Campaign.roster；新角色/未出战则用职业基础） ----
	var prog: Dictionary = Campaign.roster.get(id, {})
	var live_class_id: String = prog.get("class_id", ch.get("base_class", "")) if not prog.is_empty() else ch.get("base_class", "")
	var cls := DataManager.get_class_data(live_class_id)
	var lvl: int = int(prog.get("lvl", 1)) if not prog.is_empty() else 1
	var exp: int = int(prog.get("exp", 0)) if not prog.is_empty() else 0
	var stats: Dictionary = prog.get("stats", cls.get("base_stats", {})) if not prog.is_empty() else cls.get("base_stats", {})
	var wr: Dictionary = prog.get("weapon_ranks", {}) if not prog.is_empty() else {}
	if wr.is_empty():
		wr = cls.get("weapon_ranks", {})

	class_label.text = "职业：%s（%s） · Lv %d" % [cls.get("name", "?"),
		"领主" if ch.get("is_lord", false) else "同伴", lvl]
	rank_label.text = "经验：%d / %d" % [exp, DataManager.EXP_PER_LEVEL]

	# ---- 属性面板 ----
	var line1 := ""
	var line2 := ""
	for i in STAT_ORDER.size():
		var key: String = STAT_ORDER[i]
		var val: int = int(stats.get(key, 0))
		var cell := "%s %d" % [STAT_NAME.get(key, key), val]
		if i < 5:
			line1 += cell + "    "
		else:
			line2 += cell + "    "
	stat_label.text = line1 + "\n" + line2

	# ---- 武器等级 ----
	var wr_text := "武器等级："
	if wr.is_empty():
		wr_text += "无"
	else:
		for k in wr.keys():
			wr_text += "%s %s    " % [WEAPON_NAME.get(k, k), wr[k]]
	weapon_label.text = wr_text

	# ---- 技能说明（名称 + 描述） ----
	var sk_lines: Array = []
	var ps: String = ch.get("personal_skill", "")
	if ps != "":
		sk_lines.append(_skill_line("个人技", ps))
	for s in ch.get("personal_skills", []):
		sk_lines.append(_skill_line("个人技", s))
	for s in cls.get("class_skills", []):
		sk_lines.append(_skill_line("职业技能", s))
	skill_label.text = "\n".join(sk_lines) if sk_lines.size() > 0 else "（无技能）"

	bg_label.text = "背景：%s" % ch.get("background", "")

	# 立绘
	var p: String = ch.get("portrait", "")
	if p != "" and FileAccess.file_exists(p):
		portrait.texture = load(p)
		portrait_hint.text = ""
	else:
		portrait.texture = null
		portrait_hint.text = "（立绘待生成）"

## 生成一行技能说明文本：标签 + 名称 + 描述（+ 类型/冷却）。
func _skill_line(tag: String, sid: String) -> String:
	var sk := DataManager.get_skill(sid)
	if sk.is_empty():
		return "【%s】%s" % [tag, sid]
	var desc: String = sk.get("description", "")
	var extra := ""
	if sk.get("type", "") != "":
		extra += "（%s" % sk.get("type", "")
		if int(sk.get("cooldown", 0)) > 0:
			extra += " · 冷却%d" % int(sk.get("cooldown", 0))
		extra += "）"
	var body: String = sk.get("name", sid)
	if desc != "":
		body += "：" + desc
	return "【%s】%s%s" % [tag, body, extra]

# ---------- 支持列表 ----------
func _build_support() -> void:
	for c in support_list.get_children():
		c.queue_free()
	_support_entries.clear()
	var st: RefCounted = SupportTracker.get_instance()
	for i in _owned.size():
		for j in range(i + 1, _owned.size()):
			var a: String = _owned[i]; var b: String = _owned[j]
			var sup := _find_support(a, b)
			if sup == null:
				continue
			var ranks: Array = sup.get("ranks", [])
			var cur: int = st.rank_of(a, b)
			for r in ranks.size():
				var rank_idx := r + 1
				var key := "%s_%s" % [RANK_NAMES[r], b]
				var text: String = DataManager.get_character(a).get("support_lines", {}).get(key, "")
				_support_entries.append({"a": a, "b": b, "rank": rank_idx, "text": text, "unlocked": cur >= rank_idx})
	if _support_entries.is_empty():
		var l := Label.new(); l.text = "（暂无可查看的支持关系，去战场上并肩作战解锁吧）"
		support_list.add_child(l); return
	support_sel = clampi(support_sel, 0, _support_entries.size() - 1)
	for idx in _support_entries.size():
		var e: Dictionary = _support_entries[idx]
		var na: String = DataManager.get_character(e.a).get("name", e.a)
		var nb: String = DataManager.get_character(e.b).get("name", e.b)
		var b2 := Button.new()
		var tag := "★" if e.unlocked else "锁"
		var suffix := "（点击回放）" if e.unlocked else "（未解锁）"
		b2.text = "[%s] %s ↔ %s · %s级 %s" % [tag, na, nb, RANK_NAMES[e.rank - 1], suffix]
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if idx == support_sel:
			b2.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		b2.pressed.connect(_on_support_pick.bind(idx))
		support_list.add_child(b2)

func _find_support(a: String, b: String) -> Dictionary:
	var ch := DataManager.get_character(a)
	for s in ch.get("supports", []):
		if s.get("with", "") == b:
			return s
	var ch2 := DataManager.get_character(b)
	for s in ch2.get("supports", []):
		if s.get("with", "") == a:
			return s
	return {}

func _on_support_pick(idx: int) -> void:
	support_sel = idx
	var e: Dictionary = _support_entries[idx]
	if not e.unlocked:
		return
	SupportDialog.show_dialog(e.a, e.b, e.text)

# ---------- 输入 ----------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
			KEY_1:
				_switch_tab(0)
			KEY_2:
				_switch_tab(1)
			KEY_3:
				_switch_tab(2)
			KEY_UP:
				_move_sel(-1)
			KEY_DOWN:
				_move_sel(1)
			KEY_ENTER, KEY_SPACE:
				match tab:
					0:
						_show_detail(_owned[roster_sel])
					1:
						_on_support_pick(support_sel)
					2:
						_show_item_detail(item_sel)

func _move_sel(dir: int) -> void:
	if tab == 0:
		roster_sel = clampi(roster_sel + dir, 0, _owned.size() - 1)
		_build_roster()
	elif tab == 1:
		support_sel = clampi(support_sel + dir, 0, _support_entries.size() - 1)
		_build_support()
	else:
		item_sel = clampi(item_sel + dir, 0, Campaign.owned_item_list().size() - 1)
		_build_items()

# ---------- 道具 ----------
func _build_items() -> void:
	for c in item_list.get_children():
		c.queue_free()
	var ids: Array = Campaign.owned_item_list()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "暂无道具"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		item_list.add_child(empty)
		_clear_detail()
		return
	for i in ids.size():
		var iid: String = ids[i]
		var it: Dictionary = DataManager.get_item(iid)
		var b := Button.new()
		b.text = "%s" % it.get("name", iid)
		b.custom_minimum_size = Vector2(400, 34)
		if i == item_sel:
			b.modulate = Color(1.0, 0.95, 0.3)
		b.pressed.connect(func() -> void: _show_item_detail(i))
		item_list.add_child(b)
	_show_item_detail(item_sel)

func _show_item_detail(idx: int) -> void:
	var ids: Array = Campaign.owned_item_list()
	if idx < 0 or idx >= ids.size():
		return
	var iid: String = ids[idx]
	var it: Dictionary = DataManager.get_item(iid)
	portrait.texture = null
	portrait_hint.text = "道具"
	name_label.text = it.get("name", iid)
	title_label.text = "类型：%s" % _item_type_name(it.get("type", ""))
	class_label.text = ""
	rank_label.text = ""
	stat_label.text = ""
	weapon_label.text = ""
	skill_label.text = ""
	bg_label.text = it.get("desc", "")
	_build_items()

func _item_type_name(t: String) -> String:
	match t:
		"promote": return "转职道具"
		"promote_ultimate": return "终极转职道具"
		"consumable": return "消耗品"
		_: return t if t != "" else "通用"

func _clear_detail() -> void:
	portrait.texture = null
	name_label.text = ""
	title_label.text = ""
	class_label.text = ""
	rank_label.text = ""
	stat_label.text = ""
	weapon_label.text = ""
	skill_label.text = ""
	bg_label.text = ""
