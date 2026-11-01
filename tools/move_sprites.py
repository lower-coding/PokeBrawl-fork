"""Pixel sprites for the moves' energy balls.

They replace the smooth glowing spheres used before, which looked generic. They follow
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
    """A plasma globe: a see-through ball with a stronger rim, a white-hot opaque core and
    arcs from the core to the rim that change every frame; a faint field jitters around."""
    c = (side - 1) / 2.0
    r = side * 0.3
    white = hexc("fffbe0")
    jitter = [rnd.uniform(-0.8, 1.4) for _ in range(12)]
    ring(px, side, r, r + 3.2, hexc("ffe14a", ALPHA_SOFT), lambda a: jitter[int((a + math.pi) / math.tau * 12) % 12])
    # The ball itself: translucent inside, a stronger shell at the rim.
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            if d > r - 1.0:
                layer(px, side, x, y, hexc("fff07a", ALPHA_STRONG))
            elif d > r - 2.2:
                layer(px, side, x, y, hexc("ffe14a", ALPHA_MID))
            else:
                layer(px, side, x, y, hexc("fff07a", ALPHA_SOFT))
    # Arcs from the core out to the rim.
    for _ in range(rnd.randint(3, 4)):
        a = rnd.uniform(0, math.tau)
        zigzag(px, side, (c, c), (c + math.cos(a) * (r - 0.5), c + math.sin(a) * (r - 0.5)),
               rnd.choice([white, hexc("fff07a")]), rnd, 1.1)
    # White-hot core.
    core = r * (0.32 if f % 2 == 0 else 0.26)
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= core:
                put(px, side, x, y, white if d <= core - 1.0 else hexc("fff07a"))
    # A few sparks jumping off the rim, half see-through.
    for _ in range(rnd.randint(2, 3)):
        a = rnd.uniform(0, math.tau)
        p = (c + math.cos(a) * r, c + math.sin(a) * r)
        q = (c + math.cos(a + rnd.uniform(-0.5, 0.5)) * (r + rnd.uniform(3.0, 5.5)),
             c + math.sin(a + rnd.uniform(-0.5, 0.5)) * (r + rnd.uniform(3.0, 5.5)))
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


# ---------------------------------------------------------------- Sludge Bomb

def sludge_bomb(px, side, f, n, rnd):
    """A lumpy blob of purple sludge that wobbles, with bubbles that swell and pop and
    translucent drops hanging off it."""
    c = (side - 1) / 2.0
    r = side * 0.33
    phase = f / n * math.tau

    def lumps(x, y):
        a = math.atan2(y - c, x - c)
        return 1.0 * math.sin(a * 3 + phase) + 0.6 * math.sin(a * 2 - phase)

    disc(px, side, r, [(0.25, hexc("c58ae0")), (0.55, hexc("9152b8")), (0.9, hexc("663089")), (2.0, hexc("3d1757"))],
         rim_noise=lumps)
    # Bubbles: each one swells over a few frames and pops (a ring, then nothing).
    for i in range(4):
        life = (f + i * 2) % n
        a = i * 1.7 + 0.4
        d = r * (0.25 + 0.15 * i)
        bx, by = round(c + math.cos(a) * d), round(c + math.sin(a) * d)
        if life < n - 2:
            size = 1 + life // 2
            for dx in range(-size, size + 1):
                for dy in range(-size, size + 1):
                    if abs(math.hypot(dx, dy) - size) < 0.6:
                        put(px, side, bx + dx, by + dy, hexc("e3b8f5"))
        elif life == n - 2:
            for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
                layer(px, side, bx + dx, by + dy, hexc("e3b8f5", ALPHA_MID))
    # Drops hanging below, stretching and falling off.
    for i, x_off in enumerate((-0.45, 0.1, 0.5)):
        x = round(c + x_off * r)
        top = round(c + r * (0.85 - 0.1 * i))
        length = 2 + (f + i * 3) % 4
        for y in range(top, top + length):
            layer(px, side, x, y, hexc("663089", ALPHA_STRONG if y < top + length - 1 else ALPHA_SOFT))


# ---------------------------------------------------------------- Sun (Solar Beam)

def sun(px, side, f, n, rnd):
    """Sunlight gathering: only the small core is opaque; around it, layers of
    translucent glow that breathe (they grow and shrink over the strip), soft rays of
    changing length and motes of light circling in."""
    c = (side - 1) / 2.0
    breath = 0.5 + 0.5 * math.sin(f / n * math.tau)
    r = side * 0.2
    # Glow layers, from the outside in.
    ring(px, side, 0, r + 4.0 + 2.0 * breath, hexc("ffd34a", ALPHA_SOFT))
    ring(px, side, 0, r + 1.5 + 1.0 * breath, hexc("ffe680", ALPHA_MID))
    ring(px, side, 0, r, hexc("fff3a0", ALPHA_STRONG))
    # Soft rays: eight, their length changing frame to frame.
    turn = f / n * (math.tau / 16)
    for i in range(8):
        a = turn + i / 8 * math.tau
        length = r + 4 + (3 if (i + f) % 2 == 0 else 1) + 2 * breath
        for d in range(int(r + 1), int(length) + 1):
            layer(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("fff7c8", ALPHA_MID))
    # Motes of light circling in toward the core.
    for k in range(5):
        a = k / 5 * math.tau - f / n * math.tau * 0.5
        d = (r + 6) * (1.0 - ((f / n + k / 5) % 1.0) * 0.6)
        put(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("fffef0"))
    # The opaque core.
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= r * 0.7:
                put(px, side, x, y, hexc("fffef0") if d <= r * 0.45 else hexc("fff3a0"))


# ---------------------------------------------------------------- Water Shuriken

def water_shuriken(px, side, f, n, rnd):
    """A four-bladed star of water with swept blades, drawn like pixel-art water: a deep
    blue outline, a mid body, a light core with checkerboard dithering and a white crest
    on the leading edge of each blade. The frames turn it a quarter of its symmetry."""
    c = (side - 1) / 2.0
    r_out, r_in = side * 0.48, side * 0.17
    turn = f / n * (math.pi / 2)

    def reach(a, d):
        # Blades sweep back as they go out, so the star reads as spinning.
        a2 = a - turn - 0.9 * d / r_out
        return r_in + (r_out - r_in) * abs(math.cos(2 * a2)) ** 3, math.sin(4 * a2)

    deep, mid, light, foam = hexc("1d4f9c"), hexc("2f80d8"), hexc("7cc4f5"), hexc("eef8ff")
    for y in range(side):
        for x in range(side):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            r, lead = reach(a, d)
            if d > r:
                continue
            depth = r - d
            if depth < 1.0:
                col = deep
            elif d < r_in * 0.55:
                col = light
            elif d < r_in * 0.95:
                col = light if (x + y) % 2 == 0 else mid
            else:
                col = mid
            # White crest along the leading side of each blade, just inside the outline.
            if 1.0 <= depth < 2.2 and lead > 0.25 and d > r_in:
                col = foam
            put(px, side, x, y, col)


# ---------------------------------------------------------------- Ice Beam (muzzle)

def ice_head(px, side, f, n, rnd):
    """The bright ball where the ice beam leaves the cannons: a white core, a light cyan
    ring, a dithered blue halo and a few glints, pulsing slightly."""
    c = (side - 1) / 2.0
    r = side * (0.3 + 0.03 * math.sin(f / n * math.tau))
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= r * 0.55:
                put(px, side, x, y, hexc("f4ffff"))
            elif d <= r * 0.85:
                put(px, side, x, y, hexc("9fe6ff"))
            elif d <= r:
                put(px, side, x, y, hexc("4fb2f0"))
            elif d <= r + 2.5 and (x + y + f) % 2 == 0:
                layer(px, side, x, y, hexc("4fb2f0", ALPHA_MID))
    for _ in range(3):
        a = rnd.uniform(0, math.tau)
        d = r + rnd.uniform(1.5, 4.0)
        put(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("f4ffff"))



# ---------------------------------------------------------------- Fire Blast

FIRE_WHITE = hexc("fff8d0")
FIRE_YELLOW = hexc("ffd23a")
FIRE_ORANGE = hexc("ff8a1a")
FIRE_RED = hexc("d23c14")


# The strokes of the character, on a 64 px grid: the bar, the left sweep (from the top,
# through the crossing, down to the left) and the right sweep.
DAI = [
    [(9, 26), (55, 24)],
    [(32, 5), (32, 26), (29, 38), (21, 49), (8, 58)],
    [(33, 29), (39, 40), (47, 50), (57, 57)],
]


def _dist_seg(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    k = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / (ax * ax + ay * ay)))
    return math.dist(p, (a[0] + ax * k, a[1] + ay * k))


def dai_open(px, side, f, n, rnd):
    """It forms in front of the user: opening from the crossing outward."""
    daimonji(px, side, f, (f + 1) / n, 0.0, rnd)


def dai_fly(px, side, f, n, rnd):
    """Burning as it flies (a loop)."""
    daimonji(px, side, f, 1.0, 0.0, rnd)


def dai_end(px, side, f, n, rnd):
    """Where it lands: breaking up into embers."""
    daimonji(px, side, f, 1.0, (f + 1) / n, rnd)


def daimonji(px, side, f, grow, fade, rnd):
    """Fire Blast's character, made of fire: ragged edges and flame tongues rising off
    the strokes (thinner at their ends, like a brush). "grow" opens it from the crossing
    outward; "fade" breaks it up into embers."""
    c = (32, 27)
    reach = 40 * grow
    base = 3.4 + 0.5 * math.sin(f * 1.7)
    # Ragged edge: a coarse noise (cells of 3 px) that changes every frame.
    noise = {}
    for y in range(-1, side // 3 + 2):
        for x in range(-1, side // 3 + 2):
            noise[x, y] = rnd.uniform(-1.0, 1.4)
    for y in range(side):
        for x in range(side):
            dc = math.dist((x, y), c)
            if dc > reach:
                continue
            d = min(_dist_seg((x, y), a, b) for s in DAI for a, b in zip(s, s[1:]))
            width = base * (1.0 - 0.4 * min(1.0, dc / 34.0)) + noise[x // 3, y // 3] * 0.8
            if d > width + 1.0:
                continue
            if fade > 0 and rnd.random() < fade * 0.75 + (0.25 if noise[x // 3, y // 3] < -0.3 else 0.0) * fade:
                continue
            if d <= width * 0.28 and fade < 0.6:
                col = FIRE_WHITE
            elif d <= width * 0.6:
                col = FIRE_YELLOW if fade < 0.6 else FIRE_ORANGE
            elif d <= width:
                col = FIRE_ORANGE if fade < 0.9 else FIRE_RED
            else:
                col = FIRE_RED
            put(px, side, x, y, col)
    # Flame tongues rising off the strokes, two pixels wide, yellow inside.
    if grow >= 1.0 and fade < 0.9:
        for s in DAI:
            for a, b in zip(s, s[1:]):
                steps = int(math.dist(a, b) / 2.5)
                for i in range(steps + 1):
                    if rnd.random() < 0.5 + fade * 0.4:
                        continue
                    k = i / max(1, steps)
                    x = round(a[0] + (b[0] - a[0]) * k)
                    y0 = round(a[1] + (b[1] - a[1]) * k - base * 0.8)
                    h = rnd.randint(3, 10)
                    for jj in range(h):
                        w = 2 if jj < h * 0.6 else 1
                        for dx in range(w):
                            if jj < h * 0.3:
                                cc = FIRE_YELLOW
                            elif jj < h * 0.7:
                                cc = hexc("ff9a20", ALPHA_STRONG)
                            else:
                                cc = hexc("ff5a10", ALPHA_MID)
                            layer(px, side, x + dx, y0 - jj, cc)
    # Embers rising off it as it goes.
    if fade > 0:
        for _ in range(int(40 * fade)):
            s = DAI[rnd.randrange(3)]
            a, b = s[rnd.randrange(len(s) - 1)], None
            put(px, side, round(a[0] + rnd.uniform(-8, 8)), round(a[1] - rnd.uniform(0, 14) * fade), hexc("ffd23a") if rnd.random() < 0.6 else FIRE_ORANGE)


# ---------------------------------------------------------------- Shadow Claw

def shadow_claw(px, side, f, n, rnd):
    """A giant shadow claw's swipe: three curved slashes side by side, black-violet with
    a light violet edge and a pale core, drawn in as they sweep (frames 0-1), whole with
    wisps (2), then breaking up (3)."""
    sweep = min(1.0, (f + 1) / 2.0)
    fade = 0.0 if f < n - 1 else 0.55
    cx, cy = side * 1.0, side * 1.1          # center of the arcs, low right: they curve
    a0, a1 = math.radians(192), math.radians(266)
    radii = (side * 0.5, side * 0.72, side * 0.94)
    for y in range(side):
        for x in range(side):
            dx, dy = x - cx, y - cy
            dist = math.hypot(dx, dy)
            a = math.atan2(dy, dx) % math.tau
            t = (a - a0) / (a1 - a0)
            if t < 0.0 or t > sweep:
                continue
            w = 0.6 + 2.4 * math.sin(min(1.0, t) * math.pi)   # thick in the middle, sharp ends
            for r in radii:
                d = abs(dist - r)
                if d > w:
                    continue
                if fade and rnd.random() < fade:
                    break
                if d > w - 1.0:
                    col = hexc("b98cff")
                elif d <= 0.7 and f < 2:
                    col = hexc("f0e6ff")
                else:
                    col = hexc("2a1240")
                put(px, side, x, y, col)
                break
    # Shadow wisps trailing off the slashes.
    if f >= 2:
        for _ in range(18):
            a = math.radians(rnd.uniform(196, 262))
            r = rnd.choice(radii)
            x = round(cx + math.cos(a) * r + rnd.uniform(-1, 1))
            y = round(cy + math.sin(a) * r + rnd.uniform(-4, 0))
            layer(px, side, x, y, hexc("3a1a5a", ALPHA_MID))



# ---------------------------------------------------------------- Energy Ball

def energy_ball(px, side, f, n, rnd):
    """Nature's energy, like in the DS games, made of light like Electro Ball: a
    see-through green ball with a stronger rim, a translucent halo that breathes, two
    arms of light swirling inside and only a small core opaque (it pulses)."""
    c = (side - 1) / 2.0
    r = side * 0.3
    turn = f / n * math.tau
    breath = 0.5 + 0.5 * math.sin(turn)
    ring(px, side, r, r + 2.5 + 1.5 * breath, hexc("8cf060", ALPHA_SOFT))
    # The ball: translucent inside, a stronger shell at the rim.
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            if d > r - 1.0:
                layer(px, side, x, y, hexc("c8ff8a", ALPHA_STRONG))
            elif d > r - 2.2:
                layer(px, side, x, y, hexc("6fe04a", ALPHA_MID))
            else:
                layer(px, side, x, y, hexc("8cf060", ALPHA_SOFT))
    # Two arms of light swirling from the core to the rim.
    for arm in range(2):
        for i in range(14):
            k = i / 13.0
            a = turn + arm * math.pi + k * 2.6
            d = 1.5 + (r - 2.0) * k
            layer(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d),
                  hexc("eaffc8", ALPHA_STRONG if k < 0.6 else ALPHA_MID))
    # Motes drifting in from the halo.
    for k in range(4):
        a = k / 4 * math.tau + turn * 0.5
        d = (r + 3) * (1.0 - ((f / n + k / 4) % 1.0) * 0.5)
        layer(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("f4ffd8", ALPHA_STRONG))
    # The opaque core.
    core = r * (0.3 if f % 2 == 0 else 0.24)
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= core:
                put(px, side, x, y, hexc("fbffee") if d <= core - 1.0 else hexc("d6ff9a"))


def dragon_ball(px, side, f, n, rnd):
    """Dragon Pulse's ball, held like a kamehameha: see-through violet energy with a cyan
    shell, a jagged aura that flickers, two coils of light and a white core that pulses."""
    c = (side - 1) / 2.0
    r = side * 0.3
    turn = f / n * math.tau
    jitter = [rnd.uniform(-0.5, 2.5) for _ in range(14)]
    ring(px, side, r, r + 3.0, hexc("7f5cff", ALPHA_SOFT), lambda a: jitter[int((a + math.pi) / math.tau * 14) % 14])
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            if d > r - 1.0:
                layer(px, side, x, y, hexc("8fe6ff", ALPHA_STRONG))
            elif d > r - 2.2:
                layer(px, side, x, y, hexc("8a6aff", ALPHA_MID))
            else:
                layer(px, side, x, y, hexc("6b4ae0", ALPHA_SOFT))
    for arm in range(2):
        for i in range(16):
            k = i / 15.0
            a = -turn + arm * math.pi + k * 3.0
            d = 1.5 + (r - 1.5) * k
            layer(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d),
                  hexc("b8f2ff", ALPHA_STRONG if k < 0.7 else ALPHA_MID))
    core = r * (0.36 if f % 2 == 0 else 0.29)
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= core:
                put(px, side, x, y, hexc("ffffff") if d <= core - 1.0 else hexc("b8f2ff"))


def focus_blast(px, side, f, n, rnd):
    """Focus Blast, like in the DS games and the anime: a big ball of fighting spirit,
    orange shading to yellow, see-through with a strong rim, waves of energy running round
    it (arcs that turn), flickering flame tongues on the outside and a white-hot core."""
    c = (side - 1) / 2.0
    r = side * 0.32
    turn = f / n * math.tau
    tongues = [rnd.uniform(0.0, 3.5) for _ in range(16)]
    ring(px, side, r, r + 2.0, hexc("ff7a1a", ALPHA_MID), lambda a: tongues[int((a + math.pi) / math.tau * 16) % 16])
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            if d > r - 1.2:
                layer(px, side, x, y, hexc("ffd25a", ALPHA_STRONG))
            elif d > r - 2.6:
                layer(px, side, x, y, hexc("ff8c2a", ALPHA_MID))
            else:
                layer(px, side, x, y, hexc("ff9a3a", ALPHA_SOFT))
    # Arcs of energy wrapping round it.
    for arm in range(3):
        a0 = turn + arm * math.tau / 3
        for i in range(10):
            a = a0 + i * 0.13
            d = r - 1.6 - 0.25 * i
            layer(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d * 0.55), hexc("fff0b0", ALPHA_STRONG))
    core = r * (0.38 if f % 2 == 0 else 0.32)
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= core:
                put(px, side, x, y, hexc("fffbe8") if d <= core - 1.2 else hexc("ffe27a"))


def flash_ball(px, side, f, n, rnd):
    """Flash Cannon's ball of light: a white core in a silver, see-through shell and a
    four-pointed glint turning slowly over it, its points longer every other frame."""
    c = (side - 1) / 2.0
    r = side * 0.22
    turn = f / n * (math.pi / 2)
    ring(px, side, 0, r + 3.0, hexc("c8d4ea", ALPHA_SOFT))
    ring(px, side, 0, r + 1.0, hexc("e4ecfa", ALPHA_MID))
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= r * 0.75:
                put(px, side, x, y, hexc("ffffff") if d <= r * 0.5 else hexc("eef4ff"))
    reach = side * (0.48 if f % 2 == 0 else 0.4)
    for k in range(4):
        a = turn + k * math.pi / 2
        for dd in range(int(r), int(reach)):
            fade = ALPHA_STRONG if dd < reach * 0.7 else ALPHA_MID
            layer(px, side, round(c + math.cos(a) * dd), round(c + math.sin(a) * dd), hexc("f4f8ff", fade))


def poke_ball(px, side, f, n, rnd):
    """A Poké Ball spinning in the air: red over white, the black band and its button
    turning a quarter of a turn over the strip, a white glint on the red."""
    c = (side - 1) / 2.0
    r = side * 0.44
    a = f / n * math.pi
    nx, ny = -math.sin(a), math.cos(a)          # the band's normal: which side is red
    for y in range(side):
        for x in range(side):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy)
            if d > r:
                continue
            along = dx * nx + dy * ny
            if d > r - 1.0 or abs(along) < 0.9:
                col = hexc("1a1a1e")
            elif along < 0:
                col = hexc("e8383a") if d < r - 2.0 else hexc("b8262a")
            else:
                col = hexc("f2f2f2") if d < r - 2.0 else hexc("c8c8cc")
            put(px, side, x, y, col)
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= 2.2:
                put(px, side, x, y, hexc("1a1a1e") if d > 1.4 else hexc("ffffff"))
    gx, gy = c - nx * r * 0.5 - ny * r * 0.3, c - ny * r * 0.5 + nx * r * 0.3
    put(px, side, round(gx), round(gy), hexc("ffd0d0"))


def _glob(px, side, f, n, bands):
    """A lumpy blob that wobbles (Mud Shot, Acid Spray: only their colors differ)."""
    c = (side - 1) / 2.0
    phase = f / n * math.tau

    def lumps(x, y):
        a = math.atan2(y - c, x - c)
        return 1.0 * math.sin(a * 3 + phase) + 0.6 * math.sin(a * 2 - phase)

    disc(px, side, side * 0.34, bands, rim_noise=lumps)


def mud_shot(px, side, f, n, rnd):
    _glob(px, side, f, n, [(0.25, hexc("b58a58")), (0.55, hexc("8a6238")), (0.9, hexc("664625")), (2.0, hexc("3e2a15"))])


def acid_spray(px, side, f, n, rnd):
    _glob(px, side, f, n, [(0.25, hexc("d7e86a")), (0.55, hexc("a5c23c")), (0.9, hexc("9152b8")), (2.0, hexc("4c1f6b"))])


def chilling_water(px, side, f, n, rnd):
    _glob(px, side, f, n, [(0.25, hexc("e6fbff")), (0.55, hexc("9fdcf5")), (0.9, hexc("4f9fe0")), (2.0, hexc("23549c"))])


def psyshock_shard(px, side, f, n, rnd):
    """One long shard of pink crystal, on the diagonal: a pale core, a band of pink and a dark
    rim, with a glint walking along it."""
    c = (side - 1) / 2
    glint = (f / n) * 2.0 - 1.0
    for y in range(side):
        for x in range(side):
            along = ((x - c) - (y - c)) / (side * 0.5)
            across = abs((x - c) + (y - c)) / (side * 0.5)
            width = 0.42 * (1.0 - abs(along)) if abs(along) < 1.0 else -1.0
            if across > width:
                continue
            k = across / max(width, 0.01)
            if abs(along - glint) < 0.12 and k < 0.6:
                put(px, side, x, y, hexc("ffffff"))
            elif k < 0.35:
                put(px, side, x, y, hexc("ffd8f4"))
            elif k < 0.72:
                put(px, side, x, y, hexc("f06ec8"))
            else:
                put(px, side, x, y, hexc("8a2c86"))


def moonblast_ball(px, side, f, n, rnd):
    """A ball of moonlight: a pale core in a see-through purple ball with a strong rim, a halo that
    breathes, a crescent of white light turning on it and motes drifting off."""
    c = (side - 1) / 2.0
    r = side * 0.3
    turn = f / n * math.tau
    breath = 0.5 + 0.5 * math.sin(turn)
    ring(px, side, r, r + 2.5 + 1.5 * breath, hexc("a06aff", ALPHA_SOFT))
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d > r:
                continue
            if d > r - 1.0:
                layer(px, side, x, y, hexc("e8d4ff", ALPHA_STRONG))
            elif d > r - 2.2:
                layer(px, side, x, y, hexc("a772ff", ALPHA_MID))
            else:
                layer(px, side, x, y, hexc("8a55e8", ALPHA_SOFT))
    # The crescent: the part of a disc outside another one, off to one side.
    ox, oy = math.cos(turn) * r * 0.45, math.sin(turn) * r * 0.45
    for y in range(side):
        for x in range(side):
            if math.hypot(x - c, y - c) <= r * 0.72 and math.hypot(x - c - ox, y - c - oy) > r * 0.62:
                layer(px, side, x, y, hexc("ffffff", ALPHA_STRONG))
    core = r * (0.34 if f % 2 == 0 else 0.28)
    for y in range(side):
        for x in range(side):
            d = math.hypot(x - c, y - c)
            if d <= core:
                put(px, side, x, y, hexc("fbf6ff") if d <= core - 1.0 else hexc("d9c2ff"))
    for k in range(4):
        a = k / 4 * math.tau - turn * 0.5
        d = (r + 2) * (1.0 + ((f / n + k / 4) % 1.0) * 0.4)
        layer(px, side, round(c + math.cos(a) * d), round(c + math.sin(a) * d), hexc("f0e4ff", ALPHA_STRONG))


def swift_star(px, side, f, n, rnd):
    """Swift's five-pointed star, gold with a pale middle and a darker rim, turning a fifth of a turn
    (its symmetry) over the strip so it loops."""
    c = (side - 1) / 2.0
    r_out, r_in = side * 0.48, side * 0.2
    turn = f / n * (math.tau / 5) - math.pi / 2
    for y in range(side):
        for x in range(side):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy)
            # How far the star reaches this way: straight edges between its points and notches.
            a = (math.atan2(dy, dx) - turn) % (math.tau / 5)
            k = abs(a - math.tau / 10) / (math.tau / 10)
            reach = r_in + (r_out - r_in) * k ** 1.5
            if d > reach:
                continue
            if reach - d < 1.0:
                col = hexc("d68a14")
            elif d < r_in * 0.7:
                col = hexc("fffbe0")
            else:
                col = hexc("ffd84a")
            put(px, side, x, y, col)


def gleam_band(px, side, f, n, rnd):
    """Dazzling Gleam's sheet, stretched across the wave's front: a curtain of pink light, highest in
    the middle and lower toward its ends, in stepped bands fading upward. A bright line runs along its
    foot and its top edge, with shafts of pale light rising through it and a few sparkles, all shifting
    along it so it loops."""
    c = (side - 1) / 2.0
    turn = f / n * math.tau

    def top(x):
        # How high the curtain reaches over this column (0 to 1), rippling.
        u = (x - c) / c
        return (1.0 - 0.75 * abs(u) ** 3) * (0.92 + 0.08 * math.sin(u * 9.0 + turn))

    for x in range(side):
        reach = top(x)
        for y in range(side):
            up = (side - 1 - y) / (side - 1)
            if up > reach:
                continue
            if reach - up < 0.04 or y >= side - 2:
                put(px, side, x, y, hexc("fff0fa", ALPHA_STRONG))
            elif up < reach * 0.4:
                put(px, side, x, y, hexc("ff9ad8", ALPHA_MID))
            else:
                put(px, side, x, y, hexc("ffb4e2", ALPHA_SOFT))
    for s in range(7):
        x0 = (s * side / 7 + f / n * side * (1 if s % 2 else -1)) % side
        for w in range(2 + s % 2):
            x = int(x0 + w) % side
            for y in range(side):
                up = (side - 1 - y) / (side - 1)
                if up <= top(x) * (0.55 + 0.1 * (s % 3)):
                    layer(px, side, x, y, hexc("fff4fb", ALPHA_SOFT))
    for _ in range(6):
        x = rnd.randrange(8, side - 8)
        y = side - 1 - int(rnd.uniform(0.15, 0.8) * top(x) * (side - 1))
        star(px, side, x, y, rnd.randint(1, 2), hexc("ffffff"))


def voice_arc(px, side, f, n, rnd):
    """Hyper Voice's shock front, stretched across the wave: an arch standing on the ground, in
    stepped see-through bands that are strongest on the outside. It has no dark in it, so whoever
    stands behind it can still be seen."""
    c = (side - 1) / 2.0
    bands = ((0.9, 1.0, hexc("ffffff", ALPHA_STRONG)), (0.8, 0.9, hexc("e4e0ff", ALPHA_MID)), (0.68, 0.8, hexc("c9c2ff", ALPHA_SOFT)))
    for y in range(side):
        for x in range(side):
            d = math.hypot((x - c) / c, (side - 1 - y) / (side - 1))
            for low, high, color in bands:
                if low <= d < high:
                    put(px, side, x, y, color)


def grassknot_tuft(px, side, f, n, rnd):
    """The tuft of grass Grass Knot raises where it passes: blades shoot up from the ground, lean over
    and sink back (rise over the first half of the strip, fall over the second)."""
    k = math.sin((f + 0.5) / n * math.pi)          # growing, at the top, sunk again
    blades = [(side * 0.06, 0.5, -0.14), (side * 0.2, 0.8, -0.1), (side * 0.34, 0.65, -0.04), (side * 0.46, 1.0, 0.0),
        (side * 0.58, 0.7, 0.06), (side * 0.72, 0.95, 0.1), (side * 0.86, 0.55, 0.16)]
    for bx, hmax, lean in blades:
        h = int(round(side * 0.7 * hmax * k))
        for i in range(h):
            t = i / max(h - 1, 1)
            x = int(round(bx + lean * i * (1 + t)))
            y = side - 1 - i
            for w in (0, 1, 2):
                col = hexc("0f7a1e") if w == 2 else hexc("2bd92b") if t < 0.7 else hexc("7dff2e")
                if (t > 0.85 and w > 0) or (t > 0.6 and w == 2):
                    continue
                put(px, side, x + w, y, col)


if __name__ == "__main__":
    os.makedirs(OUTPUT, exist_ok=True)
    strip(6, 30, electro_ball, "electroball.png", 7)
    strip(8, 40, aura_sphere, "aurasphere_ball.png", 11)
    strip(8, 64, aura_burst, "aurasphere_burst.png", 19)
    strip(6, 24, shadow_ball, "shadowball.png", 13)
    strip(6, 32, sun, "sun_ball.png", 17)
    strip(8, 28, sludge_bomb, "sludgebomb.png", 23)
    strip(4, 24, water_shuriken, "watershuriken.png", 29)
    strip(4, 20, ice_head, "icebeam_head.png", 31)
    strip(3, 64, dai_open, "daimonji_open.png", 41)
    strip(4, 64, dai_fly, "daimonji_fly.png", 43)
    strip(4, 64, dai_end, "daimonji_end.png", 47)
    strip(4, 48, shadow_claw, "shadow_claw.png", 53)
    strip(6, 32, energy_ball, "energyball.png", 61)
    strip(6, 36, dragon_ball, "dragonpulse_ball.png", 67)
    strip(6, 40, focus_blast, "focusblast.png", 71)
    strip(4, 32, flash_ball, "flashcannon_ball.png", 73)
    strip(4, 14, poke_ball, "pokeball.png", 79)
    strip(6, 20, mud_shot, "mudshot_ball.png", 83)
    strip(6, 20, acid_spray, "acidspray_ball.png", 89)
    strip(6, 20, chilling_water, "chillingwater_ball.png", 97)
    strip(4, 24, psyshock_shard, "psyshock_shard.png", 101)
    strip(8, 32, moonblast_ball, "moonblast_ball.png", 103)
    strip(4, 16, swift_star, "swift_star.png", 107)
    strip(4, 64, gleam_band, "gleam_band.png", 109)
    strip(1, 96, voice_arc, "voice_arc.png", 113)
    strip(6, 32, grassknot_tuft, "grassknot_tuft.png", 127)
