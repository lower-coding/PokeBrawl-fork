"""Pixel strips for the status moves' projectiles (game/fx/tex/custom/), drawn by code in
the style of the others: few colors, a dark one-pixel outline, no smooth gradients.
Each strip is N square frames side by side, as Vfx.pixel_ball expects.

    python tools/status_sprites.py
"""
import math
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "fx", "tex", "custom")


def strip(name, size, frames, draw):
    im = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
    for f in range(frames):
        fr = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw(fr, f, frames)
        outline(fr)
        im.paste(fr, (f * size, 0))
    im.save(os.path.join(OUT, name + ".png"))
    print(name, im.size)


def outline(fr, col=None):
    """A dark one-pixel edge around everything drawn, in a darker shade of the neighbor."""
    w, h = fr.size
    px = fr.load()
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 200 and not px[nx, ny][:3] == (255, 255, 254):
                    r, g, b, _ = px[nx, ny]
                    edge.append((x, y, col or (r // 3, g // 3, b // 3, 255)))
                    break
    for x, y, c in edge:
        px[x, y] = c


def put(fr, x, y, c):
    if 0 <= x < fr.size[0] and 0 <= y < fr.size[1]:
        fr.load()[x, y] = c


# ---------------------------------------------------------------- Will-O-Wisp: blue flame
def wisp(fr, f, n):
    s = fr.size[0]
    cx = (s - 1) / 2
    ph = f / n * math.tau
    for y in range(s):
        for x in range(s):
            # Teardrop: round below, a tip above that flickers to the side.
            t = (y - 3) / (s - 5)            # 0 at the tip, 1 at the bottom
            if t < 0 or t > 1:
                continue
            sway = 1.6 * math.sin(ph + t * 2.5) * (1 - t)
            half = 5.5 * math.sin(math.pi * min(1.0, t * 0.85 + 0.12)) * (0.35 + 0.65 * t)
            d = abs(x - cx - sway)
            if d <= half:
                k = d / max(half, 0.01)
                if k < 0.35 and t > 0.45:
                    col = (232, 238, 255, 255)
                elif k < 0.7:
                    col = (126, 140, 255, 255)
                else:
                    col = (62, 80, 220, 255)
                put(fr, x, y, col)
    # A spark breaking off the tip.
    put(fr, int(cx + 2.5 * math.sin(ph * 2)), 1 + f % 2, (170, 180, 255, 255))


# ---------------------------------------------------------------- Hypnosis: widening rings
def hypno(fr, f, n):
    s = fr.size[0]
    c = (s - 1) / 2
    cols = [(220, 96, 214, 255), (128, 46, 160, 255)]
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c)
            if d > c:
                continue
            band = (d - f * 4.0 / n) / 2.0
            if (band % 2.0) < 1.0:
                put(fr, x, y, cols[int(band // 2) % 2])
    put(fr, int(c), int(c), (255, 220, 255, 255))


# Hypnosis's beam is a chain of these rings laid across its way (tinted in the game).
def psy_ring(fr, f, n):
    s = fr.size[0]
    c = (s - 1) / 2
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c)
            if 10.0 <= d <= 11.6:
                put(fr, x, y, (255, 255, 255, 255))
            elif 8.2 <= d < 10.0:
                put(fr, x, y, (196, 190, 214, 255))


# ---------------------------------------------------------------- Yawn: a slow bubble
def bubble(fr, f, n):
    s = fr.size[0]
    c = (s - 1) / 2
    ph = f / n * math.tau
    rx = 6.2 + 0.5 * math.sin(ph)
    ry = 6.2 - 0.5 * math.sin(ph)
    for y in range(s):
        for x in range(s):
            d = math.hypot((x - c) / rx, (y - c) / ry)
            if d <= 1.0:
                if d > 0.78:
                    put(fr, x, y, (176, 212, 240, 255))
                else:
                    put(fr, x, y, (206, 232, 250, 110))
    for x, y in ((5, 4), (4, 5), (5, 5), (6, 4)):
        put(fr, x, y, (255, 255, 254, 255))


# ---------------------------------------------------------------- Toxic: rising bubbles
def toxic_bubble(fr, f, n):
    s = fr.size[0]
    c = (s - 1) / 2
    ph = f / n * math.tau
    rx = 4.6 + 0.5 * math.sin(ph)
    ry = 4.6 - 0.5 * math.sin(ph)
    for y in range(s):
        for x in range(s):
            d = math.hypot((x - c) / rx, (y - c) / ry)
            if d <= 1.0:
                put(fr, x, y, (176, 92, 210, 255) if d > 0.7 else (120, 46, 156, 200))
    for x, y in ((4, 3), (3, 4), (4, 4)):
        put(fr, x, y, (240, 200, 250, 255))


# ---------------------------------------------------------------- Disable: a tiny spark
def spark(fr, f, n):
    s = fr.size[0]
    c = (s - 1) / 2
    arm = 3.5 if f % 2 == 0 else 2.5
    for y in range(s):
        for x in range(s):
            dx, dy = abs(x - c), abs(y - c)
            if dx + dy <= 1.0:
                put(fr, x, y, (255, 255, 254, 255))
            elif (dx < 1 and dy <= arm) or (dy < 1 and dx <= arm):
                put(fr, x, y, (255, 150, 226, 255))


# ---------------------------------------------------------------- Charm: a pink heart
def heart(fr, f, n):
    s = fr.size[0]
    c = (s - 1) / 2
    pulse = 1.0 + 0.1 * math.sin(f / n * math.tau)
    for y in range(s):
        for x in range(s):
            hx = (x - c) / (5.8 * pulse)
            hy = -(y - c - 0.8) / (5.8 * pulse)
            if (hx * hx + hy * hy - 1) ** 3 - hx * hx * hy ** 3 <= 0:
                put(fr, x, y, (255, 112, 168, 255) if hy < 0.55 or hx * hx + hy * hy > 0.8 else (255, 160, 200, 255))
    for x, y in ((4, 4), (5, 3), (4, 5)):
        put(fr, x, y, (255, 226, 240, 255))


strip("toxic_bubble", 12, 4, toxic_bubble)
strip("willowisp", 16, 6, wisp)
strip("hypnosis_rings", 24, 6, hypno)
strip("psy_ring", 25, 1, psy_ring)
strip("yawn_bubble", 16, 4, bubble)
strip("disable_spark", 10, 4, spark)
strip("charm_heart", 16, 4, heart)
