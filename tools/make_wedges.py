"""Genera las imagenes de la rueda de cuñas (Scripts/RadialComms/img). Uso: python3 make_wedges.py <carpeta_salida>"""
import sys, math, os
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "img"
os.makedirs(OUT, exist_ok=True)
S, SS = 440, 4
C = S / 2
R_OUT, R_IN, GAP = 204, 64, 3.0

# tema: (relleno RGBA, contorno RGBA)
THEMES = {
    "blue":   ((14, 24, 40, 208),  (110, 165, 220, 215)),
    "green":  ((14, 36, 28, 208),  (100, 200, 140, 215)),
    "amber":  ((46, 32, 10, 208),  (225, 170, 70, 215)),
    "teal":   ((12, 36, 38, 208),  (90, 200, 205, 215)),
    "purple": ((34, 22, 48, 208),  (170, 130, 220, 215)),
    "red":    ((46, 16, 16, 208),  (225, 105, 100, 215)),
    "grey":   ((28, 30, 34, 208),  (150, 158, 170, 215)),
}
HOVER = ((240, 154, 32, 238), (255, 218, 150, 255))

def wedge(i, fill, outline, lw):
    im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    a0 = -90 + 45 * (i - 1) - 22.5
    a1 = a0 + 45
    def pt(r, a): return (C * SS + r * SS * math.cos(math.radians(a)), C * SS + r * SS * math.sin(math.radians(a)))
    pts, n = [], 40
    for k in range(n + 1):
        da = math.degrees((GAP / 2) / R_OUT)
        pts.append(pt(R_OUT, a0 + da + (a1 - a0 - 2 * da) * k / n))
    for k in range(n + 1):
        da = math.degrees((GAP / 2) / R_IN)
        pts.append(pt(R_IN, a1 - da - (a1 - a0 - 2 * da) * k / n))
    d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=outline, width=int(lw * SS), joint="curve")
    return im.resize((S, S), Image.LANCZOS)

def center(fill, outline, lw):
    im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = (R_IN - GAP - 2) * SS
    d.ellipse([C * SS - r, C * SS - r, C * SS + r, C * SS + r], fill=fill, outline=outline, width=int(lw * SS))
    return im.resize((S, S), Image.LANCZOS)

def save(im, name):
    im.save(os.path.join(OUT, name), optimize=True)

for theme, (fill, outline) in THEMES.items():
    for i in range(1, 9):
        save(wedge(i, fill, outline, 1.6), f"wedge_{theme}_{i}.png")
    f2 = (max(0, fill[0] - 4), max(0, fill[1] - 4), max(0, fill[2] - 4), 228)
    save(center(f2, outline, 2.0), f"center_{theme}.png")
for i in range(1, 9):
    save(wedge(i, HOVER[0], HOVER[1], 2.0), f"wedge_h_{i}.png")
save(center(HOVER[0], HOVER[1], 2.2), "center_h.png")
print(len(os.listdir(OUT)), "imagenes,", sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT)) // 1024, "KB")
