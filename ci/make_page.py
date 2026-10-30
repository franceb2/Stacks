"""Writes site/index.html: the preview page with the tour video and screenshots."""
import html
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

out = Path(sys.argv[1])

captions = {
    "01-home": "Home",
    "02-library": "Comics library",
    "03-series": "Series page",
    "04-comic-reader": "Comic reader",
    "05-reader-menu": "Reader menu",
    "06-reader-settings": "Reading modes",
    "07-download-sheet": "Download pages",
    "08-manga-volumes": "Manga volumes",
    "09-book-reader": "Book reader",
    "10-book-menu": "Book menu",
    "11-downloads": "Downloads",
    "12-settings": "Settings",
}


def git(*args):
    try:
        return subprocess.check_output(["git", *args], text=True).strip()
    except Exception:
        return ""


commit = git("log", "-1", "--pretty=%s")
sha = git("rev-parse", "--short", "HEAD")
when = datetime.now(timezone.utc).strftime("%b %d, %Y %H:%M UTC")
repo = os.environ.get("GITHUB_REPOSITORY", "")


def shots(mode):
    cards = []
    for key, label in captions.items():
        name = f"{key}-{mode}.png"
        if (out / name).exists():
            cards.append(f'<figure><img src="{name}" alt="{html.escape(label)}" loading="lazy">'
                         f"<figcaption>{html.escape(label)}</figcaption></figure>")
    return "\n".join(cards) or "<p>No screenshots this time.</p>"


video = ('<video src="tour.mp4" controls playsinline muted preload="metadata"></video>'
         if (out / "tour.mp4").exists() else "<p>No video this time.</p>")

page = f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stacks preview</title>
<style>
:root {{ color-scheme: light dark; --bg:#f6f4ef; --fg:#1f1e1c; --muted:#6b6a65; --card:#fff; --line:#e3e0d8; --accent:#c96a12; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#141413; --fg:#efede6; --muted:#a3a19a; --card:#1f1e1c; --line:#2f2e2b; --accent:#f0a04b; }} }}
* {{ box-sizing: border-box; }}
body {{ margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 -apple-system, system-ui, sans-serif; }}
main {{ max-width:1100px; margin:0 auto; padding:24px 16px 64px; }}
h1 {{ font-size:28px; margin:0 0 4px; }}
h2 {{ font-size:19px; margin:36px 0 12px; }}
.meta {{ color:var(--muted); font-size:14px; }}
.meta b {{ color:var(--fg); font-weight:600; }}
video {{ display:block; width:100%; max-width:360px; border-radius:28px; border:1px solid var(--line); background:#000; }}
.tabs {{ display:flex; gap:8px; margin:0 0 14px; }}
.tabs button {{ font:inherit; font-size:14px; padding:6px 14px; border-radius:999px; border:1px solid var(--line);
  background:var(--card); color:var(--fg); cursor:pointer; }}
.tabs button[aria-pressed="true"] {{ background:var(--accent); border-color:var(--accent); color:#fff; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(min(100%, 230px), 1fr)); gap:18px; }}
figure {{ margin:0; }}
figure img {{ width:100%; border-radius:22px; border:1px solid var(--line); display:block; }}
figcaption {{ font-size:14px; color:var(--muted); margin-top:6px; text-align:center; }}
.hidden {{ display:none; }}
a {{ color:var(--accent); }}
</style></head>
<body><main>
<h1>Stacks preview</h1>
<p class="meta">Latest change: <b>{html.escape(commit or "unknown")}</b> · {html.escape(sha)} · built {when}</p>
<p class="meta">This is the newest version of the app running in Apple's iPhone simulator with sample books.
Your phone keeps the version you installed until you install a new one.</p>

<h2>Walkthrough</h2>
{video}

<h2>Screens</h2>
<div class="tabs" role="group" aria-label="Appearance">
  <button type="button" data-mode="light" aria-pressed="true">Light</button>
  <button type="button" data-mode="dark" aria-pressed="false">Dark</button>
</div>
<div class="grid" data-shots="light">{shots("light")}</div>
<div class="grid hidden" data-shots="dark">{shots("dark")}</div>

<h2>Install this version</h2>
<p class="meta">If you like it, download the newest Stacks.ipa from the
<a href="https://github.com/{html.escape(repo)}/actions/workflows/build.yml">Build iPhone app</a> page
and install it with Signulous.</p>
</main>
<script>
document.querySelectorAll('.tabs button').forEach(function (b) {{
  b.addEventListener('click', function () {{
    document.querySelectorAll('.tabs button').forEach(function (x) {{
      x.setAttribute('aria-pressed', String(x === b));
    }});
    document.querySelectorAll('[data-shots]').forEach(function (g) {{
      g.classList.toggle('hidden', g.getAttribute('data-shots') !== b.dataset.mode);
    }});
  }});
}});
</script>
</body></html>
"""
(out / "index.html").write_text(page)
print("wrote", out / "index.html")
