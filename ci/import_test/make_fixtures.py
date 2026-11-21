"""Writes small made-up reading orders in every supported format, for the importer test."""
import sys, os
from openpyxl import Workbook
from openpyxl.styles import PatternFill, Font
import docx
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

out = sys.argv[1]
os.makedirs(out, exist_ok=True)

# Google Docs style HTML: legend, colored table cells, rowspans, notes, a one-shot, gray optional issues,
# a second part, and a release-order list that repeats everything.
rows = [
    ("Questions", "Hero #001, Questions, Part 1", "(Note: Year is 1992.)", "#000000"),
    ("", "Hero #002, Questions, Part 2", "", "#000000"),
    ("One-Shot", "Hero/Bat (Image) (A.K.A. The Red Scare) (One-Shot)", "(Note: leads into Hero #3.)", "#38761d"),
    ("Optional", "Curse of the Hero #23, Overt", "", "#666666"),
    ("Optional", "Curse of the Hero #24", "", "#666666"),
    ("The World", "Villain #1, The World, Part 1", "", "#cc0000"),
    ("", "Villain #2-4", "", "#cc0000"),
    ("", "Hero #3 Hero #4", "", "#000000"),
]
cells = "".join(
    f'<tr><td class="c1" style="background-color:{bg}"><p><span class="c9">{a}</span></p></td>'
    f'<td class="c1" style="background-color:{bg}"><p><span class="c9">{b}</span></p></td>'
    f'<td style="background-color:{bg}"><p><span>{c}</span></p></td></tr>'
    for a, b, c, bg in rows)
release = "".join(f'<tr><td><p><span>{t} #{n}</span></p></td></tr>' for t in ("Hero", "Villain") for n in range(1, 5))
html = f"""<html><head><title>Hero Reading Order</title><style>.c9{{color:#ffffff}} .c1{{padding:2pt}}
.c4{{background-color:#990000}}</style></head><body>
<p class="c2"><span>HERO READING ORDER</span></p>
<p><span>Black = Main Series, Essential</span></p><p><span>Gray = Non-essential</span></p>
<table><tr><td style="background-color:#ff0000"><p><span>TITLE / ARC</span></p></td><td><p><span>ISSUE</span></p></td><td><p><span>NOTES</span></p></td></tr>
{cells}
<tr><td class="c4"><p><span>Sidekick &amp; Friends #1&ndash;2</span></p></td></tr>
</table>
<h2>RELEASE ORDER</h2><table>{release}</table>
</body></html>"""
open(f"{out}/hero.html", "w").write(html)

# Excel: header row, colored fills, a year column, a range, two sheets.
wb = Workbook()
ws = wb.active
ws.title = "Main"
ws.append(["#", "Series", "Issue", "Year", "Notes"])
data = [(1, "Daredevil", "1", 1964, ""), (2, "Daredevil", "2-3", 1964, "x"), (3, "Daredevil", "#4", 1964, ""),
        (4, "Spider-Man", "5", 1963, "crossover"), (5, "What If", "7", 1977, "optional")]
for i, row in enumerate(data, start=2):
    ws.append(list(row))
    color = {4: "FFCC0000", 5: "FF999999"}.get(row[0])
    if color:
        for col in range(1, 6):
            ws.cell(row=i, column=col).fill = PatternFill("solid", fgColor=color)
ws2 = wb.create_sheet("Later")
ws2.append(["Title", "No."])
ws2.append(["Daredevil Vol. 2", 1])
ws2.append(["Elektra", 2])
wb.save(f"{out}/order.xlsx")

# Word: a heading, plain paragraphs, red text, and a table with gray shading.
d = docx.Document()
d.add_heading("Batman Reading Order", 1)
d.add_paragraph("1. Batman (2016) #1")
p = d.add_paragraph()
r = p.add_run("Batman Annual #2")
r.font.color.rgb = docx.shared.RGBColor(0xCC, 0x00, 0x00)
d.add_paragraph("Detective Comics #1000, #1001 & #1003")
t = d.add_table(rows=2, cols=2)
t.cell(0, 0).text = "Nightwing #5"
t.cell(1, 0).text = "Robin #9"
for c in (t.cell(1, 0), t.cell(1, 1)):
    shd = OxmlElement("w:shd"); shd.set(qn("w:val"), "clear"); shd.set(qn("w:fill"), "B7B7B7")
    c._tc.get_or_add_tcPr().append(shd)
d.save(f"{out}/order.docx")

# CSV with quotes and a semicolon-free comma layout.
open(f"{out}/order.csv", "w").write('Title,Issue,Notes\n"Saga",1,"Start, here"\n"Saga",2-3,\nPaper Girls,1,\n')

# Plain text, like something pasted from a forum post.
open(f"{out}/order.txt", "w").write("""## Phase One
- Invincible #1-3
- Invincible Issue 4
Tech Jacket No. 1
Invincible: Battle Beast (One-Shot)
Notes: read in this order
## Phase Two
Invincible #5, 6
""")
print("fixtures written")
