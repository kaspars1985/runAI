#!/usr/bin/env python3
"""Ģenerē runAI lietotnes ikonu — gan .iconset, gan gatavo .icns (bez iconutil)."""
import io
import os
import struct
import sys
from PIL import Image, ImageDraw

S = 1024
TOP = (43, 92, 255)      # #2B5CFF
BOTTOM = (139, 92, 246)  # #8B5CF6
WHITE = (255, 255, 255, 255)

# Nosaukums -> ICNS tipa kods (PNG dati, macOS 10.7+)
ICNS_TYPES = {
    "icon_16x16.png": "icp4",
    "icon_16x16@2x.png": "ic11",
    "icon_32x32.png": "icp5",
    "icon_32x32@2x.png": "ic12",
    "icon_128x128.png": "ic07",
    "icon_128x128@2x.png": "ic13",
    "icon_256x256.png": "ic08",
    "icon_256x256@2x.png": "ic14",
    "icon_512x512.png": "ic09",
    "icon_512x512@2x.png": "ic10",
}
SPEC = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}


def rounded_rect_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def make_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    for y in range(size):
        t = y / max(1, size - 1)
        c = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)

    img.putalpha(rounded_rect_mask(size, int(size * 0.22)))

    cx = size // 2
    head_w = int(size * 0.28)
    head_h = int(size * 0.34)
    head_y0 = int(size * 0.22)
    head_y1 = head_y0 + head_h
    d.rounded_rectangle([cx - head_w // 2, head_y0, cx + head_w // 2, head_y1],
                        radius=head_w // 2, fill=WHITE)

    stem_w = int(size * 0.10)
    stem_y0 = head_y1 - int(size * 0.02)
    stem_y1 = int(size * 0.74)
    d.rounded_rectangle([cx - stem_w // 2, stem_y0, cx + stem_w // 2, stem_y1],
                        radius=stem_w // 2, fill=WHITE)

    base_w = int(size * 0.34)
    base_y0 = stem_y1
    base_y1 = stem_y1 + int(size * 0.05)
    d.rounded_rectangle([cx - base_w // 2, base_y0, cx + base_w // 2, base_y1],
                        radius=int(size * 0.025), fill=WHITE)

    return img


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def build_icns(chunks):
    body = b""
    for type_code, data in chunks:
        body += type_code.encode("latin1") + struct.pack(">I", 8 + len(data)) + data
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    master_path = os.path.join(os.path.dirname(__file__), "AppIcon_master.png")
    if os.path.exists(master_path):
        base = Image.open(master_path).convert("RGBA")
    else:
        base = make_icon(S)

    chunks = []
    for name, px in SPEC.items():
        img = base if (px == base.width and px == base.height) else base.resize((px, px), Image.LANCZOS)
        img.save(os.path.join(out_dir, name))
        chunks.append((ICNS_TYPES[name], png_bytes(img)))

    chunks.sort(key=lambda c: SPEC[[n for n, t in ICNS_TYPES.items() if t == c[0]][0]])

    icns_path = os.path.join(os.path.dirname(out_dir), "AppIcon.icns")
    
    # Mēģinām izmantot sistēmas iconutil labākai saderībai
    import subprocess
    ret = subprocess.run(["iconutil", "-c", "icns", out_dir, "-o", icns_path], capture_output=True)
    if ret.returncode != 0:
        with open(icns_path, "wb") as f:
            f.write(build_icns(chunks))
            
    print(f"Ikona ģenerēta: {out_dir} un {icns_path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset")
