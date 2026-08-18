# -*- coding: utf-8 -*-
"""
SRPG 数据/战斗自检器（无 Godot 环境下的静态验证 + 公式仿真）。
加载工程真实 JSON，复刻 Combat 的 triangle/accuracy/_calc 公式，
核对所有交叉引用并仿真每张地图的攻防预测，抓出运行时最可能崩的
数据与数值异常（NaN/越界/悬空引用）。
"""
import json, os, glob

ROOT = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(ROOT, "..", "data")
ASSETS = os.path.join(ROOT, "..", "assets")

def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)

classes = {c["id"]: c for c in load("classes.json")["classes"]}
characters = {c["id"]: c for c in load("characters.json")["characters"]}
skills = {s["id"]: s for s in load("skills.json")["skills"]}
weapons = {w["id"]: w for w in load("weapons.json")["weapons"]}
terrain = {t["id"]: t for t in load("terrain.json")["terrain"]}
items = {i["id"]: i for i in load("items.json")["items"]}
decisions = load("decisions.json")["decisions"]  # 已是 {id: {...}} 字典
world = load("world.json")
maps = {}
for p in glob.glob(os.path.join(DATA, "maps", "*.json")):
    m = json.load(open(p, encoding="utf-8"))
    maps[m["id"]] = m

# ---- 公式复刻（与 src/Combat.gd 同源） ----
TRI_HIT, TRI_DMG, CRIT_MULT = 15, 1, 1.5
WRANK_HIT_BONUS, WRANK_DMG_BONUS = 5, 1
WRANK_ORDER = ["E", "D", "C", "B", "A", "S"]
WEAPON_TYPES = set(weapons[w]["type"] for w in weapons) | {"sword","axe","lance","bow","anima","light","dark","staff"}
DEFAULT_WEAPON = {"sword":"iron_sword","axe":"iron_axe","lance":"iron_lance",
                 "bow":"short_bow","anima":"fire_tome","light":"light_tome","staff":"heal_staff"}

errors, warns = [], []
def err(m): errors.append(m)
def warn(m): warns.append(m)

def triangle(a, d):
    phys = ["sword","axe","lance"]; mag = ["anima","light","dark"]
    order = phys if a in phys else (mag if a in mag else [])
    if not order or d not in order: return 0
    ia, idf = order.index(a), order.index(d)
    if (ia+1)%3 == idf: return 1
    if (idf+1)%3 == ia: return -1
    return 0

def accuracy(att, dfn, w, wtype, dtype, terr_avo=0, sup_hit=0, sup_avo=0, wrank_hit=0, ignore_avo=False):
    skl = att["skl"]; lck = att["lck"]
    dspd = dfn["spd"]; dlck = dfn["lck"]
    tri = triangle(wtype, dtype)
    acc = skl*2 + lck//2 + w.get("hit",0) + tri*TRI_HIT + sup_hit + wrank_hit
    avo = 0 if ignore_avo else (dspd*2 + dlck + terr_avo + sup_avo)
    return max(0, min(100, acc - avo))

def calc(att, dfn, w, dtype, tdict, wrank_idx=0):
    wtype = w.get("type","")
    is_magic = wtype in ("anima","light","dark")
    atk = (att["mag"] if is_magic else att["str"]) + w.get("might",0)
    raw_def = dfn["res"] if is_magic else dfn["def"]
    eff_def = round(raw_def)
    tri = triangle(wtype, dtype)
    tdef = tdict.get("def",0)
    dmg = max(0, atk - eff_def - tdef + tri*TRI_DMG + wrank_idx*WRANK_DMG_BONUS)
    chance = accuracy(att, dfn, w, wtype, dtype, tdict.get("avo",0), 0, 0, wrank_idx*WRANK_HIT_BONUS)
    crit = att["skl"]//2 + w.get("crit",0)
    return {"chance":chance, "dmg":dmg, "crit_chance":crit, "adv":tri}

def base_stats(class_id, lvl=1):
    c = classes.get(class_id, {})
    s = dict(c.get("base_stats", {}))
    return s

def unit_class_id(u):
    # 复刻 Unit.setup 的分辨逻辑：char_id 必须在 characters 才生效，否则用 class 字段
    if u.get("char_id") and u["char_id"] in characters:
        return characters[u["char_id"]].get("base_class", u["char_id"])
    return u.get("class_id") or u.get("class")

def resolve_class_id(u):
    # 与 Unit.setup 等价：返回有效 class_id，无法解析返回 None
    cid = unit_class_id(u)
    if cid and cid in classes:
        return cid
    return None

def unit_weapon(u):
    if u.get("weapon"): return weapons.get(u["weapon"], {})
    cid = u.get("class_id") or u.get("char_id")
    cls = classes.get(cid, {})
    wr = cls.get("weapon_ranks", {})
    if wr:
        return weapons.get(DEFAULT_WEAPON.get(list(wr.keys())[0], ""), {})
    return {}

# ---- 引用校验 ----
for cid, c in characters.items():
    bc = c.get("base_class","")
    if bc not in classes: err(f"角色 {cid} 的 base_class={bc} 不在 classes.json")
    for s in [c.get("personal_skill","")] + c.get("personal_skills",[]) + c.get("class_skills",[]):
        if s and s not in skills: err(f"角色 {cid} 技能 {s} 不在 skills.json")
    for fld in ("battle_sprite","portrait"):
        if c.get(fld):
            fp = os.path.join(ASSETS, "..", c[fld].replace("res://assets/", "assets/")) if c[fld].startswith("res://") else c[fld]
            if not os.path.exists(fp): warn(f"角色 {cid} 的 {fld} 文件缺失: {c[fld]}")

for cid, c in classes.items():
    for wt in c.get("weapon_ranks", {}):
        if wt not in WEAPON_TYPES: err(f"职业 {cid} 武器类型 {wt} 未知")
    for s in c.get("class_skills", []):
        if s and s not in skills: err(f"职业 {cid} 职业技能 {s} 不在 skills.json")
    if "base_stats" not in c: err(f"职业 {cid} 缺 base_stats")

VALID_EFFECTS = {"hit_bonus","avo_bonus","dmg_bonus","ignore_def","defense_bonus",
                 "counter_bonus","counter_reduce","heal","buff","debuff","special","passive",
                 "adjacent_ally_damage_reduction","crit_bonus","shield_ally","ignore_defense",
                 "avoid_bonus","adjacent_ally_hit_bonus","magic_avoid_ignore"}
for sid, s in skills.items():
    for kf in ("id","name","description"):
        if kf not in s: err(f"技能 {sid} 缺字段 {kf}")
    eff = s.get("effect", {})
    if eff and eff.get("kind") not in VALID_EFFECTS: warn(f"技能 {sid} 的 effect.kind={eff.get('kind')} 未登记（SkillManager 可能不解释）")

for iid in items: pass

for mid, m in maps.items():
    g = m.get("grid", [])
    h = len(g); w = len(g[0]) if h else 0
    for row in g:
        if len(row) != w: err(f"地图 {mid} 网格行宽不一致")
    for u in m.get("units", []):
        p = u.get("pos",[0,0])
        if p[0] >= w or p[1] >= h: err(f"地图 {mid} 单位 {u} 坐标越界")
        # 敌方单位常用 char_id 作唯一标签（不在 characters 里），实际按 class 字段解析职业
        if resolve_class_id(u) is None:
            err(f"地图 {mid} 单位 {u.get('char_id', u.get('class','?'))} 无法解析职业")
        if u.get("weapon") and u["weapon"] not in weapons: err(f"地图 {mid} 单位武器 {u['weapon']} 不存在")
    dec = m.get("decision","")
    if dec and dec not in decisions: err(f"地图 {mid} decision={dec} 不在 decisions.json")

for n in world.get("nodes", []):
    if n.get("map_id") and n["map_id"] not in maps: err(f"世界节点 {n.get('id')} map_id={n['map_id']} 无对应地图")
    if n.get("decision") and n["decision"] not in decisions: err(f"世界节点 {n.get('id')} decision={n['decision']} 不在 decisions.json")
    for f in n.get("unlock",{}).get("requires_flag",[]) + n.get("unlock",{}).get("forbid_flag",[]):
        pass

for did, d in decisions.items():
    for opt in d.get("options", []):
        gc = opt.get("effects",{}).get("grant_char", [])
        gcs = [gc] if isinstance(gc, str) else gc
        for c in gcs:
            if c and c not in characters: err(f"抉择 {did} grant_char={c} 不在 characters.json")
        gi = opt.get("effects",{}).get("grant_item", [])
        gis = [gi] if isinstance(gi, str) else gi
        for it in gis:
            if it and it not in items: err(f"抉择 {did} grant_item={it} 不在 items.json")

# ---- 战斗仿真：每张地图 玩家单位 vs 敌方单位（基础属性，无技能加成） ----
print("\n==== 战斗预测仿真（基础属性，无技能/支援） ====")
for mid, m in maps.items():
    players = [u for u in m.get("units",[]) if u.get("team","player")=="player"]
    enemies = [u for u in m.get("units",[]) if u.get("team")=="enemy"]
    for pu in players:
        cls = classes.get(unit_class_id(pu), {})
        att = base_stats(cls.get("id", unit_class_id(pu)))
        w = unit_weapon(pu)
        for eu in enemies:
            ecls = classes.get(unit_class_id(eu), {})
            dfn = base_stats(ecls.get("id", unit_class_id(eu)))
            ew = unit_weapon(eu)
            dtype = ew.get("type","")
            r = calc(att, dfn, w, dtype, terrain.get(m["grid"][eu["pos"][1]][eu["pos"][0]],{}))
            if any(v is None or (isinstance(v,(int,float)) and v != v) for v in r.values()):
                err(f"地图 {mid} {pu.get('char_id',pu.get('class'))}→{eu.get('char_id',eu.get('class'))} 预测含 NaN")
            # adv 方向自检：剑克斧应 adv=1
            if w.get("type")=="sword" and dtype=="axe" and r["adv"]!=1:
                err(f"三角异常: 剑→斧 adv 应为1，实为 {r['adv']}")

# ---- 三角自测 ----
print("\n==== 武器三角自测 ====")
checks = [("sword","axe",1),("axe","lance",1),("lance","sword",1),
          ("anima","light",1),("light","dark",1),("dark","anima",1),
          ("sword","lance",-1),("axe","sword",-1),("sword","sword",0),("bow","sword",0)]
for a,d,exp in checks:
    got = triangle(a,d)
    ok = "OK" if got==exp else "FAIL"
    if got!=exp: err(f"三角 {a}→{d} 期望 {exp} 实得 {got}")
    print(f"  {a:6}→{d:6} adv={got} {ok}")

# ---- 结论 ----
print("\n==== 校验结论 ====")
print(f"数据表: 角色 {len(characters)} / 职业 {len(classes)} / 技能 {len(skills)} / 武器 {len(weapons)} / 地形 {len(terrain)} / 道具 {len(items)} / 抉择 {len(decisions)} / 地图 {len(maps)}")
print(f"ERROR: {len(errors)}   WARN: {len(warns)}")
for e in errors: print("  [E]", e)
for w in warns: print("  [W]", w)
print("\n结果:", "✅ 全部通过" if not errors else "❌ 存在错误，需修复")
