"""Creates a small fake library (comics, manga, an EPUB and a PDF) for preview screenshots.

Usage: python make_samples.py OUTPUT_DIR
All titles and art are generated here, so nothing copyrighted ends up in the preview.
"""
import io
import random
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

out = Path(sys.argv[1])
random.seed(7)


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # very old Pillow
        return ImageFont.load_default()


def jpeg(img):
    b = io.BytesIO()
    img.save(b, "JPEG", quality=85)
    return b.getvalue()


def cover(title, subtitle, bg, accent, size=(800, 1200)):
    w, h = size
    img = Image.new("RGB", size, bg)
    d = ImageDraw.Draw(img)
    for _ in range(14):
        r = random.randint(40, 220)
        x, y = random.randint(-50, w), random.randint(250, h)
        d.ellipse((x - r, y - r, x + r, y + r), outline=accent, width=6)
    d.rectangle((0, 0, w, 230), fill=accent)
    d.text((40, 50), title, font=font(84), fill=bg)
    d.text((44, 150), subtitle, font=font(40), fill=bg)
    return img


def page(title, n, bg):
    """A comic page with a few panels and caption boxes."""
    w, h = 800, 1200
    img = Image.new("RGB", (w, h), (250, 248, 242))
    d = ImageDraw.Draw(img)
    rows = [(30, 420), (440, 760), (780, 1170)]
    for i, (top, bottom) in enumerate(rows):
        splits = [(30, 770)] if i != 1 else [(30, 390), (410, 770)]
        for left, right in splits:
            shade = tuple(min(255, c + random.randint(-30, 40)) for c in bg)
            d.rectangle((left, top, right, bottom), fill=shade, outline=(20, 20, 20), width=6)
            cx, cy = random.randint(left + 80, right - 80), random.randint(top + 80, bottom - 60)
            d.ellipse((cx - 50, cy - 50, cx + 50, cy + 50), fill=(240, 220, 190), outline=(20, 20, 20), width=4)
            d.rectangle((left + 16, top + 16, left + 300, top + 70), fill=(255, 250, 200), outline=(20, 20, 20), width=3)
            d.text((left + 28, top + 26), f"{title} p.{n}", font=font(26), fill=(20, 20, 20))
    return img


def cbz(path, title, subtitle, bg, accent, pages):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("000.jpg", jpeg(cover(title, subtitle, bg, accent)))
        for n in range(1, pages):
            z.writestr(f"{n:03d}.jpg", jpeg(page(title, n + 1, bg)))


# Comics: one folder per series, issue numbers in the file names.
comics = [
    ("Atlas Rising", (40, 60, 120), (245, 180, 60), 5),
    ("Iron Tide", (120, 40, 40), (240, 230, 220), 3),
    ("Starfall", (30, 30, 50), (120, 200, 255), 4),
    ("Night Market", (60, 30, 80), (255, 120, 170), 2),
]
for name, bg, accent, issues in comics:
    for i in range(1, issues + 1):
        cbz(out / "comics" / name / f"{name} #{i:03d}.cbz", name.upper(), f"Issue #{i}", bg, accent, 10)

# Manga: whole volumes plus a loose chapter.
for v in range(1, 4):
    cbz(out / "manga" / "Moon Garden" / f"Moon Garden Vol. {v:02d}.cbz", "MOON GARDEN", f"Volume {v}",
        (235, 235, 240), (60, 60, 90), 8)
cbz(out / "manga" / "Moon Garden" / "Moon Garden Ch. 031.cbz", "MOON GARDEN", "Chapter 31",
    (235, 235, 240), (60, 60, 90), 6)

# EPUB with a cover and a few chapters of original text.
book_dir = out / "books" / "The River Road"
book_dir.mkdir(parents=True, exist_ok=True)
paragraphs = [
    "The road followed the river the way a careful thought follows a feeling, never quite touching it, "
    "never quite letting it out of sight.",
    "Mara had walked it every autumn since she was nine. The willows knew her by now, or she liked to think "
    "they did, leaning a little closer as she passed with her satchel of letters.",
    "At the bend where the ferry once ran, she stopped to read the first of them again. The handwriting was "
    "older than she remembered, and the ink had gone the color of strong tea.",
    "Nobody had asked her to carry the letters. That was the strange part. They had simply been waiting on "
    "the kitchen table one morning, tied with blue string, addressed to towns that no longer existed.",
]
with zipfile.ZipFile(book_dir / "The River Road.epub", "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
    z.writestr("META-INF/container.xml",
               '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
               '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    chapters = 5
    items = "".join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(1, chapters + 1))
    spine = "".join(f'<itemref idref="c{i}"/>' for i in range(1, chapters + 1))
    z.writestr("OEBPS/content.opf",
               '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
               '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">river-road</dc:identifier>'
               '<dc:title>The River Road</dc:title><dc:creator>A. N. Author</dc:creator><dc:language>en</dc:language>'
               '<meta name="cover" content="cover"/></metadata>'
               '<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
               '<item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>'
               f'{items}</manifest><spine>{spine}</spine></package>')
    z.writestr("OEBPS/nav.xhtml",
               '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
               '<body><nav epub:type="toc"><ol>'
               + "".join(f'<li><a href="c{i}.xhtml">Chapter {i}</a></li>' for i in range(1, chapters + 1))
               + "</ol></nav></body></html>")
    for i in range(1, chapters + 1):
        body = "".join(f"<p>{p}</p>" for p in paragraphs * 3)
        z.writestr(f"OEBPS/c{i}.xhtml",
                   '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter</title></head>'
                   f"<body><h1>Chapter {i}</h1>{body}</body></html>")
    z.writestr("OEBPS/cover.jpg", jpeg(cover("THE RIVER ROAD", "A novel", (30, 70, 60), (230, 210, 150))))

# PDF
pdf_dir = out / "books" / "Field Guide to Clouds"
pdf_dir.mkdir(parents=True, exist_ok=True)
pages = [cover("FIELD GUIDE", "to Clouds", (90, 140, 200), (250, 250, 255))]
for n in range(2, 7):
    p = Image.new("RGB", (800, 1100), (252, 252, 250))
    d = ImageDraw.Draw(p)
    d.text((60, 60), f"Chapter {n - 1}", font=font(48), fill=(30, 30, 30))
    for line in range(14):
        d.rectangle((60, 160 + line * 52, 740 - random.randint(0, 200), 176 + line * 52), fill=(200, 200, 205))
    pages.append(p)
pages[0].save(pdf_dir / "Field Guide to Clouds.pdf", save_all=True, append_images=pages[1:])

print("samples written to", out)
