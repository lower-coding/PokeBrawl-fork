"""Pixel sprites for the moves' energy balls.

They replace the smooth glowing spheres (vfx.orb), which looked generic. They follow
Cobblemon's density: a few dozen pixels, no smoothing, flat color bands and a darker rim.
Each file is a horizontal strip of square frames (game/fx/tex/custom/*.png).

"Pixel" transparency: no gradients; alpha uses fixed levels (ALPHA_*), like Cobblemon's
sprites and pixel games: halos, aura flames and electric fields, translucent, over or
around the opaque core.

    python tools/move_sprites.py
"""
import math
import os
import random

from PIL import Image

OUTPUT = os.path.join(os.path.dirname(__file__), "..", "game", "fx", "tex", "custom")

# The only transparency levels used.
ALPHA_STRONG = 190
ALPHA_MID = 120
ALPHA_SOFT = 60


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def strip(n, side, paint, name_id, seed):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (n * side, side), (0, 0, 0, 0))
    for f in range(n):
        frame = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        px = frame.load()
        paint(px, side, f, n, rnd)
        img.paste(frame, (f * side, 0))
    fpath = os.path.join(OUTPUT, name_id)
    img.save(fpath)
    print("wrote", os.path.normpath(fpath), img.size)


def put(px, side, x, y, c):
    if 0 <= x < side and 0 <= y < side and c is not None:
        px[x, y] = c


def layer(px, side, x, y, c):
    """Puts a translucent color over whatever is there (normal blending)."""
    if not (0 <= x < side and 0 <= y < side) or c is None:
        return
    r0, g0, b0, a0 = px[x, y]
    a1 = c[3] / 255.0
    if a0 == 0:
        px[x, y] = c
        return
    a = a1 + a0 / 255.0 * (1 - a1)
    mix = [round((c[i] * a1 + (r0, g0, b0)[i] * a0 / 255.0 * (1 - a1)) / a) for i in range(3)]
    px[x, y] = (mix[0], mix[1], mix[2], round(a * 255))


def disc(px, side, r, bands, light=(-0.35, -0.4), rim_noise=None):
    """Banded disc: light comes from the top left (like the shading of Cobblemon's
    models). bands = [(threshold, color)...] from the inside out, by distance to the
    light point."""
    c = (side - 1) / 2.0
    for y in range(side):
        for x in range(side):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy)
            rr = r + (rim_noise(x, y) if rim_noise else 0.0)
            if d > rr:
                continue
            # Distance to the light point, normalized to the radius.
            dl = math.hypot(dx - light[0] * r, dy - light[1] * r) / (r * 1.6)
            col = bands[-1][1]
            for threshold, cb in bands:
                if dl <= threshold:
                    col = cb
                    break
            if d > rr - 1.0:
                col = bands[-1][1]
            px[x, y] = col


def ring(px, side, r0, r1, color, shape=None):
    """Translucent ring between r0 and r1; "shape(angle)" deforms it (flames)."""
    c = (side - 1) / 2.0
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            extra = shape(math.atan2(y - c, x - c)) if shape else 0.0
            if r0 <= d <= r1 + extra:
                layer(px, side, x, y, color)


def zigzag(px, side, a, b, color, rnd, offset=1.5, above=False):
    """Jagged pixel line between two points (the electric arcs)."""
    steps = max(3, int(math.dist(a, b) / 2.5))
    pts = [a]
    for i in range(1, steps):
        k = i / steps
        x = a[0] + (b[0] - a[0]) * k + rnd.uniform(-offset, offset)
        y = a[1] + (b[1] - a[1]) * k + rnd.uniform(-offset, offset)
        pts.append((x, y))
    pts.append(b)
    paint = layer if above else put
    for p, q in zip(pts, pts[1:]):
        n = int(max(abs(q[0] - p[0]), abs(q[1] - p[1]))) + 1
        for i in range(n + 1):
            k = i / n
            paint(px, side, round(p[0] + (q[0] - p[0]) * k), round(p[1] + (q[1] - p[1]) * k), color)


def star(px, side, cx, cy, arm, color, color_borde=None):
    """Four-pointed flash (the white star in the center in Smash)."""
    for k in range(-arm, arm + 1):
        for (x, y) in ((cx + k, cy), (cx, cy + k)):
            put(px, side, x, y, color if abs(k) < arm else (color_borde or color))
    if arm >= 3:
        for (dx, dy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            put(px, side, cx + dx, cy + dy, color)


# ---------------------------------------------------------------- Electro Ball

def electro_ball(px, side, f, n, rnd):
    c = (side - 1) / 2.0
    r = side * 0.3
    white = hexc("fffbe0")
    # Translucent electric field around it (two levels) that jitters.
    jitter = [rnd.uniform(-0.8, 1.2) for _ in range(12)]
    ring(px, side, r, r + 3.2, hexc("ffe14a", ALPHA_SOFT), lambda a: jitter[int((a + math.pi) / math.tau * 12) % 12])
    ring(px, side, r, r + 1.6, hexc("fff07a", ALPHA_MID))
    disc(px, side, r, [(0.18, white), (0.42, hexc("fff07a")), (0.75, hexc("ffd23a")), (2.0, hexc("e89a12"))],
          rim_noise=lambda x, y: rnd.choice([0.0, 0.0, 0.6]))
    # Arcs inside: they cross the ball rim to rim and change every frame.
    for _ in range(2):
        a0 = rnd.uniform(0, math.tau)
        a1 = a0 + rnd.uniform(2.2, 4.0)
        zigzag(px, side, (c + math.cos(a0) * r * 0.85, c + math.sin(a0) * r * 0.85),
               (c + math.cos(a1) * r * 0.85, c + math.sin(a1) * r * 0.85), white, rnd, 1.2)
    # Sparks jumping off the rim: some opaque, some half.
    for _ in range(rnd.randint(3, 5)):
        a = rnd.uniform(0, math.tau)
        p = (c + math.cos(a) * (r - 1), c + math.sin(a) * (r - 1))
        q = (c + math.cos(a + rnd.uniform(-0.5, 0.5)) * (r + rnd.uniform(3.5, 6.5)),
             c + math.sin(a + rnd.uniform(-0.5, 0.5)) * (r + rnd.uniform(3.5, 6.5)))
        if rnd.random() < 0.5:
            zigzag(px, side, p, q, rnd.choice([white, hexc("ffe14a")]), rnd, 1.0)
        else:
            zigzag(px, side, p, q, hexc("fffbe0", ALPHA_STRONG), rnd, 1.0, above=True)


# ---------------------------------------------------------------- Aura Sphere (Smash style)

NIGHT_BLUE = hexc("0b1036")
DEEP_BLUE = hexc("15205e")
MID_BLUE = hexc("2a46c4")
CYAN = hexc("5cb6ff")
LIGHT_CYAN = hexc("c6ecff")


def aura_sphere(px, side, f, n, rnd):
    """Like in Smash Ultimate: a near-black navy core, a cyan rim with electric sparks
    and translucent aura flames spinning around it."""
    c = (side - 1) / 2.0
    r = side * 0.27
    turn = f / n * math.tau
    # Aura flames: two translucent rings with spinning tongues.
    ring(px, side, r, r + 4.0, hexc("3f78ff", ALPHA_SOFT),
        lambda a: 3.5 * max(0.0, math.sin(a * 5 + turn)) + 1.5 * math.sin(a * 9 - turn * 2))
    ring(px, side, r, r + 2.0, hexc("6fb0ff", ALPHA_MID),
        lambda a: 1.5 * max(0.0, math.sin(a * 4 - turn * 1.5)))
    # Dark core with the rim of light (from the inside out).
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            if d > r - 1.0:
                col = LIGHT_CYAN if math.sin(math.atan2(y - c, x - c) * 3 + turn) > -0.2 else CYAN
            elif d > r - 2.2:
                col = CYAN
            elif d > r - 3.4:
                col = MID_BLUE
            elif d > r * 0.45:
                col = DEEP_BLUE
            else:
                col = NIGHT_BLUE
            px[x, y] = col
    # Faint swirl inside the core.
    for arm in range(2):
        for i in range(10):
            k = i / 9.0
            a = turn + arm * math.pi + k * 2.4
            d = (r - 3.5) * (0.25 + 0.75 * k)
            put(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), MID_BLUE)
    # Electric sparks along the rim (cyan and white).
    for _ in range(rnd.randint(2, 3)):
        a = rnd.uniform(0, math.tau)
        p = (c + math.cos(a) * (r - 1.5), c + math.sin(a) * (r - 1.5))
        q = (c + math.cos(a + rnd.uniform(-0.6, 0.6)) * (r + rnd.uniform(3, 5)),
             c + math.sin(a + rnd.uniform(-0.6, 0.6)) * (r + rnd.uniform(3, 5)))
        zigzag(px, side, p, q, rnd.choice([LIGHT_CYAN, hexc("ffffff"), CYAN]), rnd, 1.0)
    # Small flash in the center (in Smash it shows at full charge).
    star(px, side, int(round(c)), int(round(c)), 2 if f % 2 == 0 else 1, hexc("9fd2ff"))


def aura_burst(px, side, f, n, rnd):
    """Impact: the sphere opens into a dark burst with a cyan ring, bolts and the white
    star in the center; at the end the ring breaks apart."""
    c = (side - 1) / 2.0
    k = f / (n - 1)
    r = side * (0.16 + 0.3 * k)
    # Translucent background flash.
    if k < 0.75:
        ring(px, side, 0, r + 4, hexc("4c86ff", ALPHA_SOFT))
    # Dark interior that lightens (translucent) as it opens.
    inner = DEEP_BLUE if k < 0.3 else hexc("15205e", ALPHA_STRONG if k < 0.45 else (ALPHA_MID if k < 0.6 else ALPHA_SOFT))
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= r - 2.5 and k < 0.75:
                layer(px, side, x, y, inner)
    # Ring: cyan with a light edge; broken up in the last frames.
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if r - 2.5 < d <= r:
                if k > 0.6 and rnd.random() < (k - 0.6) * 2.2:
                    continue
                layer(px, side, x, y, LIGHT_CYAN if d > r - 1.0 else (CYAN if k < 0.7 else hexc("5cb6ff", ALPHA_MID)))
    # Electric bolts outward.
    if k < 0.8:
        for i in range(5):
            a = i / 5 * math.tau + rnd.uniform(-0.4, 0.4)
            p = (c + math.cos(a) * r * 0.6, c + math.sin(a) * r * 0.6)
            q = (c + math.cos(a) * (r + 6 + 6 * k), c + math.sin(a) * (r + 6 + 6 * k))
            zigzag(px, side, p, q, LIGHT_CYAN if i % 2 else hexc("ffffff"), rnd, 1.6)
    # Big white star at the start.
    if k < 0.55:
        arm = int(7 - 6 * k)
        star(px, side, int(round(c)), int(round(c)), arm, hexc("ffffff"), LIGHT_CYAN)


# ---------------------------------------------------------------- Shadow Ball

def shadow_ball(px, side, f, n, rnd):
    c = (side - 1) / 2.0
    r = side * 0.34
    phase = f / n * math.tau

    def rim(x, y):
        a = math.atan2(y - c, x - c)
        return 0.7 * math.sin(a * 3 + phase) + 0.5 * math.sin(a * 5 - phase * 2)

    disc(px, side, r, [(0.22, hexc("8a4ec0")), (0.55, hexc("4a2276")), (0.9, hexc("2a1046")), (2.0, hexc("140620"))],
          light=(0.0, 0.0), rim_noise=rim)
    # Broken violet rim of light, spinning.
    for i in range(40):
        a = i / 40 * math.tau
        if math.sin(a * 4 + phase * 2) < 0.1:
            continue
        d = r + rim(c + math.cos(a) * r, c + math.sin(a) * r) + 0.5
        put(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("c07cff"))
    # Escaping wisps.
    for _ in range(3):
        a = rnd.uniform(0, math.tau)
        d = r + rnd.uniform(2, 4)
        put(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("6a2fa0", 200))


# ---------------------------------------------------------------- Sun (Solar Beam)

def sun(px, side, f, n, rnd):
    c = (side - 1) / 2.0
    r = side * 0.27
    disc(px, side, r, [(0.25, hexc("fffef0")), (0.55, hexc("fff3a0")), (0.9, hexc("ffd34a")), (2.0, hexc("f0a020"))])
    # Short rays around it, spinning (8 points, alternating long and short).
    turn = f / n * (math.tau / 8)
    for i in range(8):
        a = turn + i / 8 * math.tau
        length = r + (5 if i % 2 == 0 else 3)
        for d in range(int(r) + 1, int(length) + 1):
            col = hexc("fff3a0") if d < length - 1 else hexc("ffc83a")
            put(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), col)


if __name__ == "__main__":
    os.makedirs(OUTPUT, exist_ok=True)
    strip(6, 30, electro_ball, "electroball.png", 7)
    strip(8, 40, aura_sphere, "aurasphere_ball.png", 11)
    strip(8, 64, aura_burst, "aurasphere_burst.png", 19)
    strip(6, 24, shadow_ball, "shadowball.png", 13)
    strip(6, 28, sun, "sun_ball.png", 17)
