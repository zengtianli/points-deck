#!/usr/bin/env python3
"""生成 app 图标：画的就是这个 app 讲的事 —— 一条从低处涨上去的市值曲线，
末端一间亮起来的小房子（市值 = 住什么房，这是整套激励的核心隐喻）。

深绿→金的渐变对应「小康之家 → 金碧辉煌」那条路，不用高饱和原色
（那是廉价儿童 app 的观感，不是我们要的）。不用外部素材、不联网，重跑逐像素一致。
"""
import pathlib

from PIL import Image, ImageDraw

S = 1024
TOP = (31, 75, 87)          # garden 档的深青 —— 与 app 内 Era.garden 同族
BOT = (20, 42, 50)
LINE = (143, 227, 240)      # Era.garden.accent
HOUSE = (255, 233, 168)     # Era.golden.accent —— 终点是金
GRID = (255, 255, 255, 22)

img = Image.new("RGB", (S, S), TOP)
d = ImageDraw.Draw(img)

for y in range(S):                                   # 竖向渐变
    t = y / (S - 1)
    d.line([(0, y), (S, y)],
           fill=tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3)))

ov = Image.new("RGBA", (S, S), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
M = 150
x0, x1, y0, y1 = M, S - M, M, S - M
for i in range(1, 4):
    y = y0 + (y1 - y0) * i / 4
    od.line([(x0, y), (x1, y)], fill=GRID, width=4)
img = Image.alpha_composite(img.convert("RGBA"), ov).convert("RGB")
d = ImageDraw.Draw(img)

# 市值曲线：有涨有跌但总体向上 —— 账本本来就是这样(seed 的曲线也有回撤)
pts_x = [0.00, 0.18, 0.32, 0.46, 0.58, 0.72, 0.86, 1.00]
pts_y = [0.92, 0.80, 0.86, 0.62, 0.70, 0.44, 0.36, 0.16]
curve = [(x0 + (x1 - x0) * a, y0 + (y1 - y0) * b) for a, b in zip(pts_x, pts_y)]
d.line(curve, fill=LINE, width=26, joint="curve")

# 终点的小房子
hx, hy = curve[-1]
w, h = 130, 96
d.polygon([(hx - w * 0.62, hy - h * 0.18), (hx, hy - h * 0.95), (hx + w * 0.62, hy - h * 0.18)],
          fill=HOUSE)
d.rounded_rectangle([hx - w * 0.42, hy - h * 0.18, hx + w * 0.42, hy + h * 0.52],
                    radius=12, fill=HOUSE)

out = pathlib.Path(__file__).parent / "Resources" / "icon-1024.png"
img.save(out)
print(f"✅ {out}")

# 写进 Assets.xcassets —— xcodebuild 那条路靠 actool 编它，缺了就是个没图标的包
ac = out.parent / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
if ac.parent.is_dir():
    img.save(ac)
    print(f"✅ {ac}")
else:
    raise SystemExit(f"❌ 没有 {ac.parent} —— Assets.xcassets 结构不对，别静默跳过")
