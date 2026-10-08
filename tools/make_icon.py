"""生成 App 图标（1024×1024）：深绿渐变背景 + 白色哑铃 + 向上箭头。"""
import sys
from PIL import Image, ImageDraw

S = 1024
out = sys.argv[1]
img = Image.new("RGB", (S, S))
top, bottom = (22, 120, 80), (8, 60, 45)
px = img.load()
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)
W = (255, 255, 255)
cy = 600
# 杆
d.rounded_rectangle([250, cy - 28, 774, cy + 28], radius=28, fill=W)
# 片
for x0, x1, h in [(170, 250, 300), (250, 320, 220), (704, 774, 220), (774, 854, 300)]:
    d.rounded_rectangle([x0, cy - h // 2, x1, cy + h // 2], radius=30, fill=W)
# 向上箭头（质量变好）
d.polygon([(512, 190), (640, 330), (562, 330), (562, 430), (462, 430), (462, 330), (384, 330)], fill=(140, 235, 170))
img.save(out)
