#!/usr/bin/env python3
"""生成 app 图标 —— **从 app 内那张时代插画裁出来**，不手搓几何图形。

为什么改成这样（2026-08-28）：上一版是 PIL 画的一条折线 + 一个三角形房子，
硬边、无抗锯齿、留白大，缩到桌面 60×60 只剩一条蓝线。更要命的是它和 app 里
那 5 张 Seedream 绘本插画**不是一个视觉语言** —— 打开 app 是绘本，图标是折线图。

现在的做法：取 `cottage`（普通人家）那张插画里小木屋的那一块。
选 cottage 而不是别的时代，是因为它是这套隐喻的中位数 ——
「有个自己的小家」，暖、具体、不炫富，也正是这个 app 想让人奔向的东西。

裁切框是**按图里房子的实际位置定的**，不是拍脑袋的比例：
房子连烟囱在原图约 x∈[1130,1470] y∈[300,590]，取一个把它连同左侧松树、
下方草地一起包住的正方形，让房子占画面中央约六成 —— 小尺寸下辨识的就是这个轮廓。

    python3 make_icon.py          # 重跑逐像素一致（无随机、不联网）
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
# 底图 SSOT 在 ~/Edu，不在本仓 —— 和 sync-skins.sh 同一个源，避免两份图漂
SRC = pathlib.Path.home() / "Edu" / "points" / "skins" / "cottage" / "bg.jpg"
OUT = HERE / "Resources" / "icon-1024.png"
OUT_ASSET = HERE / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

S = 1024

if not SRC.is_file():
    sys.exit(f"✘ 底图不在：{SRC}\n   它的 SSOT 在 ~/Edu/points/skins/，先确认那边有图")

src = Image.open(SRC).convert("RGB")
W, H = src.size

# 裁切框按**比例**算，这样换一张同构图的底图也不会错位
cx0, cx1 = int(W * 0.685), int(W * 0.960)          # 房子 + 右侧松树
cy0 = int(H * 0.300)
side = cx1 - cx0
cy1 = cy0 + side
if cy1 > H:                                         # 底边不够就整体上移，不拉伸
    cy1, cy0 = H, H - side
crop = src.crop((cx0, cy0, cx1, cy1)).resize((S, S), Image.LANCZOS)

# 稍微提一点饱和与对比 —— 缩到 60×60 后细节会被平均掉，不提就发灰
crop = ImageEnhance.Color(crop).enhance(1.12)
crop = ImageEnhance.Contrast(crop).enhance(1.06)

# 四角轻暗角：让图标在浅色桌面壁纸上也有边界感（不是为了好看，是为了看得见轮廓）。
#
# ⚠ 用**径向遮罩 + 高斯模糊**，不要手画同心矩形描边。
# 2026-08-28 第一版就是一圈圈 rectangle(outline=a) 叠出来的，结果画面正中央
# 多出一个硬矩形亮框 —— 描边只覆盖最外 140 圈，再往里遮罩值突然归零，
# 那道台阶在图上就是一条边。渐变要的是连续函数，不是一圈圈叠。
mask = Image.new("L", (S, S), 0)                    # 0=不压暗
ImageDraw.Draw(mask).ellipse(
    [-S * 0.16, -S * 0.16, S * 1.16, S * 1.16], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(S * 0.11))
mask = mask.point(lambda v: 255 - v)                # 反过来：中心亮、四角暗
mask = mask.point(lambda v: int(v * 0.30))          # 暗角强度，最多压 30%
crop = Image.composite(Image.new("RGB", (S, S), (26, 19, 13)), crop, mask)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT_ASSET.parent.mkdir(parents=True, exist_ok=True)
crop.save(OUT, "PNG")
crop.save(OUT_ASSET, "PNG")
print(f"✅ 图标已生成 {S}×{S}")
print(f"   {OUT}")
print(f"   {OUT_ASSET}")
print(f"   源：{SRC}  裁切 x[{cx0},{cx1}] y[{cy0},{cy1}]")
