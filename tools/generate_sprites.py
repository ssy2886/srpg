#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成战斗 Q 版精灵表（占位用，可随时重跑 / 微调后替换真实素材）。

输出： assets/sprites/units/{id}.png
布局： 横排 5 帧  idle | move | attack | hurt | dead
帧尺寸： 64 x 64   -> 单张图 320 x 64

纯标准库（zlib + struct）写 PNG，无需 Pillow。
真实美术接入时：用外部生图模型照本布局出图覆盖同名文件即可，
代码侧通过 SpriteFrames 按 5 等分横向切片读取，无需改动。
"""
import os
import zlib
import struct

FW, FH = 64, 64          # 单帧尺寸
FRAMES = ["idle", "move", "attack", "hurt", "dead"]
SHEET_W = FW * len(FRAMES)

# ---------- 极简 RGBA 画布 ----------
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = bytearray([0]) * (w * h * 4)

    def px(self, x, y, rgba):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            a = rgba[3] if len(rgba) > 3 else 255
            self.buf[i] = rgba[0]; self.buf[i+1] = rgba[1]
            self.buf[i+2] = rgba[2]; self.buf[i+3] = a

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.px(x, y, c)

    def disc(self, cx, cy, r, c):
        r2 = r * r
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                dx, dy = x - cx, y - cy
                if dx * dx + dy * dy <= r2:
                    self.px(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                dx, dy = (x - cx) / rx, (y - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    self.px(x, y, c)

    def line(self, x0, y0, x1, y1, c, thick=1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for s in range(steps + 1):
            t = s / steps if steps else 0
            self.px(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)
            if thick > 1:
                self.px(x0 + (x1 - x0) * t + 1, y0 + (y1 - y0) * t, c)


def write_png(path, cv):
    raw = bytearray()
    for y in range(cv.h):
        raw.append(0)  # filter type 0
        raw += cv.buf[y * cv.w * 4:(y + 1) * cv.w * 4]
    comp = zlib.compress(bytes(raw), 9)

    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(
            ">I", zlib.crc32(typ + data) & 0xffffffff)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", cv.w, cv.h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", comp)
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# ---------- 角色配色（职业原型可辨识即可，真实素材可覆盖） ----------
CHARS = {
    "lyra": dict(armor=(58, 123, 213), accent=(245, 197, 66), hair=(255, 224, 138),
                 skin=(241, 201, 165), weapon="sword", dark=(30, 60, 120)),
    "garrett": dict(armor=(150, 96, 58), accent=(201, 162, 92), hair=(107, 74, 43),
                    skin=(224, 168, 126), weapon="sword", dark=(80, 50, 30)),
    "mira": dict(armor=(108, 79, 176), accent=(185, 140, 255), hair=(46, 37, 53),
                 skin=(238, 206, 184), weapon="staff", dark=(60, 40, 110)),
    "seraphina": dict(armor=(238, 238, 245), accent=(255, 216, 107), hair=(255, 209, 232),
                      skin=(245, 214, 196), weapon="stafforb", dark=(170, 150, 120)),
    # ---- 职业通用占位（按 class id 命名，多个同职业单位共用） ----
    "mercenary": dict(armor=(150, 96, 58), accent=(201, 162, 92), hair=(107, 74, 43),
                      skin=(224, 168, 126), weapon="sword", dark=(80, 50, 30)),
    "brigand": dict(armor=(122, 52, 42), accent=(70, 45, 25), hair=(40, 30, 25),
                    skin=(210, 160, 120), weapon="axe", dark=(60, 25, 20), bulk=2),
    "archer": dict(armor=(92, 112, 92), accent=(60, 75, 60), hair=(82, 62, 40),
                   skin=(220, 180, 140), weapon="bow", dark=(45, 55, 45)),
}

def weapon_shape(cv, kind, hx, hand_y, pal):
    """在抬手位置画武器剪影。hx 为持械手 x。"""
    if kind == "sword":
        cv.line(hx, hand_y, hx, hand_y - 22, (205, 212, 224))      # 银刃
        cv.line(hx - 1, hand_y, hx + 1, hand_y, pal["dark"])       # 护手
    elif kind == "axe":
        cv.line(hx, hand_y, hx, hand_y - 20, (120, 80, 40))        # 柄
        cv.disc(hx, hand_y - 20, 7, (150, 150, 160))              # 斧头
        cv.disc(hx, hand_y - 20, 3, pal["dark"])
    elif kind == "staff":
        cv.line(hx, hand_y, hx, hand_y - 24, (120, 80, 40))        # 杖身
        cv.disc(hx, hand_y - 24, 3, pal["accent"])                 # 杖顶
    elif kind == "stafforb":
        cv.line(hx, hand_y, hx, hand_y - 24, (200, 170, 120))      # 金杖
        cv.disc(hx, hand_y - 24, 5, pal["accent"])                 # 法球
    elif kind == "bow":
        for k in range(-12, 13):                                    # 竖向弯弓（木）+ 弦 + 箭
            y = hand_y + k
            x = hx + (1 - (k / 12.0) ** 2) * 10                     # 向右鼓出的弧
            cv.px(x, y, (120, 80, 40))
        cv.line(hx, hand_y - 12, hx, hand_y + 12, (230, 230, 230))  # 弦
        cv.line(hx, hand_y, hx + 22, hand_y, (150, 110, 60))        # 箭杆
        cv.px(hx + 22, hand_y, (220, 220, 220))                     # 箭头


def draw_chibi(cv, pal, pose):
    """在 64x64 画布里画一个 Q 版小人；pose 决定姿态。"""
    skin, armor, accent, hair, dark = (pal["skin"], pal["armor"],
                                       pal["accent"], pal["hair"], pal["dark"])
    bulk = int(pal.get("bulk", 0))          # brigand 等壮硕职业加宽
    lean = 0
    bob = 0
    if pose == "move":
        bob = -2
    elif pose == "attack":
        lean = 4
    elif pose == "hurt":
        lean = -5

    cx = 32 + lean
    head_y = 18 + bob
    # 腿（idle/attack 并拢；move 跨步；hurt 后撤）
    leg_c = dark
    if pose == "move":
        cv.rect(cx - 8, 50, cx - 3, 60, leg_c)
        cv.rect(cx + 2, 50, cx + 9, 58, leg_c)
    elif pose == "hurt":
        cv.rect(cx - 7, 50, cx - 2, 58, leg_c)
        cv.rect(cx + 1, 50, cx + 6, 60, leg_c)
    else:
        cv.rect(cx - 6, 50, cx - 2, 60, leg_c)
        cv.rect(cx + 2, 50, cx + 6, 60, leg_c)
    # 躯干（袍/甲）
    cv.rect(cx - 9 - bulk, 28, cx + 9 + bulk, 50, armor)
    cv.rect(cx - 9 - bulk, 28, cx + 9 + bulk, 32, accent)            # 领口/披风边
    # 头
    cv.ellipse(cx, head_y, 11 + bulk, 12, skin)
    cv.ellipse(cx, head_y - 9, 12 + bulk, 7, hair)            # 头发
    cv.rect(cx - 12 - bulk, head_y - 11, cx + 12 + bulk, head_y - 6, hair)  # 刘海
    # 眼睛（hurt/dead 变化）
    if pose == "dead":
        cv.line(cx - 6, head_y - 2, cx - 2, head_y + 2, dark)
        cv.line(cx - 2, head_y - 2, cx - 6, head_y + 2, dark)
        cv.line(cx + 2, head_y - 2, cx + 6, head_y + 2, dark)
        cv.line(cx + 6, head_y - 2, cx + 2, head_y + 2, dark)
    elif pose == "hurt":
        cv.disc(cx - 4, head_y, 1.5, dark)
        cv.disc(cx + 4, head_y, 1.5, dark)
    else:
        cv.rect(cx - 6, head_y - 1, cx - 4, head_y + 1, dark)
        cv.rect(cx + 4, head_y - 1, cx + 6, head_y + 1, dark)

    # 手臂 / 武器
    if pose == "attack":
        cv.line(cx + 8, 34, cx + 14, 30, skin)         # 前伸手臂
        weapon_shape(cv, pal["weapon"], cx + 15, 29, pal)
    elif pose == "hurt":
        cv.line(cx - 9, 34, cx - 14, 28, skin)         # 双臂上扬挡
        cv.line(cx + 9, 34, cx + 14, 28, skin)
    else:
        cv.line(cx - 9, 34, cx - 11, 46, skin)
        cv.line(cx + 9, 34, cx + 11, 46, skin)

    if pose == "hurt":
        # 受击红闪
        cv.rect(0, 0, 63, 63, (255, 60, 60, 90))
    if pose == "dead":
        # 倒地：在脚下画一个躺平的椭圆 + 灰化覆盖
        cv.ellipse(cx, 56, 16, 5, armor)
        cv.ellipse(cx + 14, 54, 6, 5, skin)
        cv.rect(0, 0, 63, 63, (90, 90, 100, 110))

    # 脚下阴影
    cv.ellipse(32, 61, 12, 3, (0, 0, 0, 70))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.normpath(os.path.join(here, "..", "assets", "sprites", "units"))
    os.makedirs(out_dir, exist_ok=True)
    sheets = {}
    for cid, pal in CHARS.items():
        sheet = Canvas(SHEET_W, FH)
        for fi, pose in enumerate(FRAMES):
            fcv = Canvas(FW, FH)
            draw_chibi(fcv, pal, pose)
            # 拷到 sheet 对应帧位置
            ox = fi * FW
            for y in range(FH):
                for x in range(FW):
                    i = (y * FW + x) * 4
                    sheet.buf[((y * SHEET_W + ox + x)) * 4:(y * SHEET_W + ox + x) * 4 + 4] = \
                        fcv.buf[i:i + 4]
        sheets[cid] = sheet
        out = os.path.join(out_dir, cid + ".png")
        write_png(out, sheet)
        print("wrote", out, "(%dx%d)" % (SHEET_W, FH))

    # 预览拼图：4 张精灵表竖排，便于直接打开查看
    gap = 4
    prev = Canvas(SHEET_W, len(CHARS) * (FH + gap) - gap)
    for ri, cid in enumerate(CHARS.keys()):
        oy = ri * (FH + gap)
        for y in range(FH):
            for x in range(SHEET_W):
                i = (y * SHEET_W + x) * 4
                prev.buf[((oy + y) * prev.w + x) * 4:((oy + y) * prev.w + x) * 4 + 4] = \
                    sheets[cid].buf[i:i + 4]
    write_png(os.path.join(out_dir, "_preview.png"), prev)
    print("wrote", os.path.join(out_dir, "_preview.png"),
          "(%dx%d)" % (prev.w, prev.h))


if __name__ == "__main__":
    main()
