#!/usr/bin/env python3
"""Génère les masques d'icônes/étiquettes de la Touch Bar et un aperçu PNG."""
import math, sys
import cairo
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
from PIL import Image, ImageDraw, ImageFont

ADW = "/usr/share/icons/Adwaita/symbolic/"
FONT = "/usr/share/fonts/opentype/inter/Inter-Medium.otf"
W, H = 2170, 60


def svg_mask(path, size):
    pb = GdkPixbuf.Pixbuf.new_from_file_at_size(ADW + path, size, size)
    w, h, n, rs = pb.get_width(), pb.get_height(), pb.get_n_channels(), pb.get_rowstride()
    data = pb.get_pixels()
    return w, h, [data[y * rs + x * n + 3] for y in range(h) for x in range(w)]


def _alpha(surf, w, h):
    surf.flush()
    data = surf.get_data()
    stride = surf.get_stride()
    return w, h, [data[y * stride + x * 4 + 3] for y in range(h) for x in range(w)]


def drawn(w, h, painter):
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surf)
    ctx.set_source_rgba(1, 1, 1, 1)
    painter(ctx)
    return _alpha(surf, w, h)


def sun(size, core, ray_in, ray_out, width):
    def p(ctx):
        c = size / 2
        ctx.arc(c, c, core, 0, 2 * math.pi)
        ctx.fill()
        ctx.set_line_width(width)
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        for i in range(8):
            a = i * math.pi / 4
            ctx.move_to(c + ray_in * math.cos(a), c + ray_in * math.sin(a))
            ctx.line_to(c + ray_out * math.cos(a), c + ray_out * math.sin(a))
        ctx.stroke()
    return drawn(size, size, p)


def kbd_light(w, h, rays):
    # bandeau type « rétroéclairage clavier » : barre arrondie + rayons au-dessus
    def p(ctx):
        bw, bh = 16, 5
        x0, y0 = (w - bw) / 2, h - bh - 2
        r = 2.5
        ctx.new_sub_path()
        ctx.arc(x0 + bw - r, y0 + r, r, -math.pi / 2, 0)
        ctx.arc(x0 + bw - r, y0 + bh - r, r, 0, math.pi / 2)
        ctx.arc(x0 + r, y0 + bh - r, r, math.pi / 2, math.pi)
        ctx.arc(x0 + r, y0 + r, r, math.pi, 3 * math.pi / 2)
        ctx.close_path()
        ctx.fill()
        ctx.set_line_width(2.2)
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        cx, cy = w / 2, y0 - 1
        for a_deg in (-90, -50, -130, -15, -165):
            a = math.radians(a_deg)
            ctx.move_to(cx + 9 * math.cos(a), cy + 7 * math.sin(a) - 2)
            ctx.line_to(cx + (9 + rays) * math.cos(a), cy + (7 + rays) * math.sin(a) - 2)
        ctx.stroke()
    return drawn(w, h, p)


def play_pause(size):
    def p(ctx):
        h = size * 0.62
        y0 = (size - h) / 2
        ctx.move_to(size * 0.10, y0)
        ctx.line_to(size * 0.10 + h * 0.85, y0 + h / 2)
        ctx.line_to(size * 0.10, y0 + h)
        ctx.close_path()
        ctx.fill()
        bw = size * 0.11
        for x in (size * 0.66, size * 0.84):
            ctx.rectangle(x - bw / 2, y0, bw, h)
        ctx.fill()
    return drawn(size, size, p)


def text_mask(text, px):
    font = ImageFont.truetype(FONT, px)
    l, t, r, b = font.getbbox(text)
    img = Image.new("L", (r - l + 2, b - t + 2), 0)
    ImageDraw.Draw(img).text((1 - l, 1 - t), text, fill=255, font=font)
    return img.width, img.height, list(img.getdata())


ICON = 28
icons = {
    "DISPLAY_DOWN": sun(ICON, 4.0, 7.5, 9.5, 2.0),
    "DISPLAY_UP": sun(ICON, 5.0, 8.5, 12.5, 2.4),
    "KEYBOARD_DOWN": kbd_light(ICON, ICON, 2.5),
    "KEYBOARD_UP": kbd_light(ICON, ICON, 6.0),
    "PREVIOUS": svg_mask("actions/media-skip-backward-symbolic.svg", ICON),
    "PLAY_PAUSE": play_pause(ICON),
    "NEXT": svg_mask("actions/media-skip-forward-symbolic.svg", ICON),
    "MUTE": svg_mask("status/audio-volume-muted-symbolic.svg", ICON),
    "VOLUME_DOWN": svg_mask("status/audio-volume-low-symbolic.svg", ICON),
    "VOLUME_UP": svg_mask("status/audio-volume-high-symbolic.svg", ICON),
}
def apps_grid(size):
    # grille 3×3 de pastilles arrondies, façon lanceur d'applications
    def p(ctx):
        cell, dot = size / 3, size * 0.2
        for row in range(3):
            for col in range(3):
                x = col * cell + (cell - dot) / 2
                y = row * cell + (cell - dot) / 2
                r = dot * 0.3
                ctx.new_sub_path()
                ctx.arc(x + dot - r, y + r, r, -math.pi / 2, 0)
                ctx.arc(x + dot - r, y + dot - r, r, 0, math.pi / 2)
                ctx.arc(x + r, y + dot - r, r, math.pi / 2, math.pi)
                ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
                ctx.close_path()
        ctx.fill()
    return drawn(size, size, p)


def close_cross(size):
    def p(ctx):
        m = size * 0.22
        ctx.set_line_width(2.6)
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        ctx.move_to(m, m); ctx.line_to(size - m, size - m)
        ctx.move_to(size - m, m); ctx.line_to(m, size - m)
        ctx.stroke()
    return drawn(size, size, p)


icons["APPS"] = apps_grid(24)
icons["CLOSE"] = close_cross(24)
icons["PLAY"] = svg_mask("actions/media-playback-start-symbolic.svg", ICON)
icons["PAUSE"] = svg_mask("actions/media-playback-pause-symbolic.svg", ICON)
labels = {"ESC": text_mask("esc", 20)}
for i in range(1, 13):
    labels[f"F{i}"] = text_mask(f"F{i}", 20)

# --- géométrie (copie de stock_slice.rs) ---
CONTROLS = [194, 384, 602, 792, 1010, 1200, 1390, 1608, 1798, 1988]
ORDER = ["DISPLAY_DOWN", "DISPLAY_UP", "KEYBOARD_DOWN", "KEYBOARD_UP", "PREVIOUS",
         "PLAY_PAUSE", "NEXT", "MUTE", "VOLUME_DOWN", "VOLUME_UP"]
GROUPS = [(0, 2), (2, 4), (4, 7), (7, 10)]
ESC = (0, 0, 162, 60)


def blit(img, x, y, w, h, mask, color):
    mw, mh, px = mask
    ox, oy = x + (w - mw) // 2, y + (h - mh) // 2
    base = img.load()
    for j in range(mh):
        for i in range(mw):
            a = px[j * mw + i]
            if a:
                r, g, b = base[ox + i, oy + j]
                base[ox + i, oy + j] = tuple((c * (255 - a) + t * a) // 255 for c, t in zip((r, g, b), color))


def plate(img, x, y, w, h, r, top, bottom):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255)
    grad = Image.new("RGB", (w, h))
    gd = ImageDraw.Draw(grad)
    for j in range(h):
        t = j / (h - 1)
        gd.line((0, j, w, j), fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    img.paste(grad, (x, y), m)


LABEL = (235, 235, 240)
TOP, BOTTOM = (60, 60, 64), (42, 42, 46)
PTOP, PBOTTOM = (98, 98, 104), (78, 78, 84)


def variant_keys(pressed=None):
    img = Image.new("RGB", (W, H), (0, 0, 0))
    plate(img, *ESC, 14, TOP, BOTTOM)
    blit(img, *ESC, labels["ESC"], LABEL)
    for k, x in enumerate(CONTROLS):
        t, b = (PTOP, PBOTTOM) if pressed == k else (TOP, BOTTOM)
        plate(img, x, 0, 182, 60, 14, t, b)
        blit(img, x, 0, 182, 60, icons[ORDER[k]], LABEL)
    return img


def variant_groups(pressed=None):
    img = Image.new("RGB", (W, H), (0, 0, 0))
    plate(img, *ESC, 30, TOP, BOTTOM)
    blit(img, *ESC, labels["ESC"], LABEL)
    for a, z in GROUPS:
        x0 = CONTROLS[a]
        x1 = CONTROLS[z - 1] + 182
        plate(img, x0, 0, x1 - x0, 60, 30, TOP, BOTTOM)
        for k in range(a, z):
            x = CONTROLS[k]
            if pressed == k:
                plate(img, x + 4, 4, 174, 52, 26, PTOP, PBOTTOM)
            if k > a:
                ImageDraw.Draw(img).line((x - 4, 16, x - 4, 44), fill=(72, 72, 78), width=2)
            blit(img, x, 0, 182, 60, icons[ORDER[k]], LABEL)
    return img


def fn_row():
    img = Image.new("RGB", (W, H), (0, 0, 0))
    for s in range(13):
        l = -(-s * W // 13)
        r = -(-(s + 1) * W // 13)
        li = 0 if s == 0 else 5
        x, w = l + li, r - l - li - 5
        plate(img, x, 0, w, 60, 14, TOP, BOTTOM)
        blit(img, x, 0, w, 60, labels["ESC" if s == 0 else f"F{s}"], LABEL)
    return img


def preview(out):
    rows = [("A — touches séparées", variant_keys(pressed=1)),
            ("B — groupes en capsules", variant_groups(pressed=1)),
            ("Rangée Fn", fn_row())]
    # aperçu lisible : chaque bande coupée en deux moitiés, agrandie x1
    half = W // 2 + 1
    font = ImageFont.truetype(FONT, 18)
    sheet = Image.new("RGB", (half + 40, len(rows) * (2 * H + 70) + 20), (24, 24, 27))
    d = ImageDraw.Draw(sheet)
    y = 15
    for title, img in rows:
        d.text((20, y), title, fill=(200, 200, 205), font=font)
        y += 30
        sheet.paste(img.crop((0, 0, half, H)), (20, y))
        sheet.paste(img.crop((W - half, 0, W, H)), (20, y + H + 8))
        y += 2 * H + 40
    sheet.save(out)


def emit_icons(path):
    out = ["//! Generated alpha masks: Adwaita symbolic icons (CC BY-SA 3.0) and cairo-drawn",
           "//! brightness glyphs, rendered at native Touch Bar size by `touchbar-icons.py`.", "",
           "use crate::stock_labels::AlphaMask;", ""]
    for name in ORDER + ["PLAY", "PAUSE", "APPS", "CLOSE"]:
        w, h, px = icons[name]
        out.append(f"const {name}_PIXELS: &[u8] = &[")
        for i in range(0, len(px), 24):
            out.append("    " + ", ".join(str(v) for v in px[i:i + 24]) + ",")
        out += ["];", "", f"pub(crate) const {name}: AlphaMask = AlphaMask {{",
                f"    width: {w},", f"    height: {h},", f"    pixels: {name}_PIXELS,", "};", ""]
    open(path, "w").write("\n".join(out).rstrip() + "\n")


if __name__ == "__main__":
    preview(sys.argv[1])
    if len(sys.argv) > 2:
        emit_icons(sys.argv[2])
