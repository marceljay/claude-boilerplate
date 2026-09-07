#!/usr/bin/env python3
"""Render the items that need the user's decision as a click-through page.

Source (first that exists):
  1. _planning/REVIEW.md — the overflow file: one `## Title` per item, free
     markdown under it. Lines `**Context:**`, `**Options:**`, `**To test:**`,
     `**Decision:**` are recognised as labelled fields but nothing requires them.
  2. The `## Needs input` section of _planning/STATUS.md (or ./STATUS.md):
     one `- **Title** — text` bullet per item.

Output: _planning/review.html (gitignored with STATUS.md). Static — no server,
no tokens: open it from the host (the workspace is bind-mounted) or run with
`--serve [PORT]` to serve _planning/ on 0.0.0.0 for a forwarded port. Each
card has Approve / Change / Reject / Skip plus a notes box; state lives in the
browser's localStorage, and "Copy decisions" produces a markdown block to
paste back into the chat so Claude can record the outcome. Nothing here
writes to the markdown files — that stays Claude's job, via update-status.

Gated by the `Review page: on | off` line in the project CLAUDE.md: when on,
the update-status skill re-runs this after editing Needs input / REVIEW.md;
when off, only `/review` runs it.
"""

import html
import os
import re
import sys
from datetime import date

ROOT = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
PLANNING = os.path.join(ROOT, "_planning")
REVIEW_MD = os.path.join(PLANNING, "REVIEW.md")
OUT = os.path.join(PLANNING, "review.html")


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def items_from_review_md(text):
    items, title, buf = [], None, []
    for line in text.splitlines():
        m = re.match(r"^##\s+(.*)", line)
        if m:
            if title:
                items.append((title, "\n".join(buf).strip()))
            title, buf = m.group(1).strip(), []
        elif title is not None and not line.startswith("# "):
            buf.append(line)
    if title:
        items.append((title, "\n".join(buf).strip()))
    return items


def items_from_status(text):
    sec = re.search(r"^## Needs input\s*\n(.*?)(?=^## |^# |^---|\Z)", text, re.S | re.M)
    if not sec:
        return []
    items, cur = [], None
    for line in sec.group(1).splitlines():
        m = re.match(r"^- \*\*(.+?)\*\*\s*(?:[—:-]\s*)?(.*)", line)
        if m:
            cur = [m.group(1), m.group(2)]
            items.append(cur)
        elif cur and line.strip():
            cur[1] += "\n" + line.strip()
    return [(t, b.strip()) for t, b in items if t.lower() != "none"]


def md(text):
    """Tiny markdown → HTML: paragraphs, bullets, bold, code, links, labels."""
    out, in_list = [], False
    for raw in text.splitlines() + [""]:
        line = html.escape(raw.strip())
        line = re.sub(r"`([^`]+)`", r"<code>\1</code>", line)
        line = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", line)
        line = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2" target="_blank">\1</a>', line)
        line = re.sub(r"(?<![\"'>])(https?://[^\s<]+)", r'<a href="\1" target="_blank">\1</a>', line)
        if line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{line[2:]}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if line:
            out.append(f"<p>{line}</p>")
    return "\n".join(out)


PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review — {project}</title>
<style>
:root{{--bg:#f7f7f5;--card:#fff;--ink:#1f1f1f;--muted:#6b6b6b;--line:#e2e2df;--ok:#2e7d32;--chg:#ef6c00;--no:#c62828}}
@media(prefers-color-scheme:dark){{:root{{--bg:#161615;--card:#1f1f1e;--ink:#ececea;--muted:#9a9a97;--line:#333}}}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,sans-serif}}
main{{max-width:820px;margin:0 auto;padding:24px 16px 80px}}
h1{{font-size:20px;margin:0 0 4px}} .sub{{color:var(--muted);margin:0 0 20px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px 18px;margin:0 0 14px}}
.card h2{{font-size:16px;margin:0 0 8px}} .card p{{margin:6px 0}} .card ul{{margin:6px 0 6px 20px;padding:0}}
code{{background:var(--bg);padding:1px 5px;border-radius:4px;font-size:13px}}
.dec{{display:flex;gap:6px;flex-wrap:wrap;margin:12px 0 8px}}
.dec label{{border:1px solid var(--line);border-radius:20px;padding:4px 12px;cursor:pointer;user-select:none}}
.dec input{{display:none}} .dec input:checked+span{{font-weight:600}}
.dec label:has(input[value=approve]:checked){{border-color:var(--ok);color:var(--ok)}}
.dec label:has(input[value=change]:checked){{border-color:var(--chg);color:var(--chg)}}
.dec label:has(input[value=reject]:checked){{border-color:var(--no);color:var(--no)}}
textarea{{width:100%;box-sizing:border-box;min-height:52px;border:1px solid var(--line);border-radius:6px;padding:8px;font:inherit;background:var(--bg);color:var(--ink)}}
.done{{opacity:.55}}
.bar{{position:fixed;bottom:0;left:0;right:0;background:var(--card);border-top:1px solid var(--line);padding:10px 16px;display:flex;gap:10px;align-items:center;justify-content:center}}
button{{font:inherit;padding:8px 14px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--ink);cursor:pointer}}
#out{{display:none;position:fixed;inset:10% 10%;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;z-index:9}}
#out textarea{{height:calc(100% - 50px)}}
</style></head><body><main>
<h1>Needs your input</h1>
<p class="sub">{project} · {n} item(s) · generated {today} from <code>{src}</code>. Decide, add notes, then <em>Copy decisions</em> and paste into the chat.</p>
{cards}
</main>
<div class="bar"><span id="count"></span><button onclick="exportMd()">Copy decisions</button><button onclick="reset()">Reset</button></div>
<div id="out"><p>Copied to clipboard (if allowed). Paste this into the chat:</p><textarea id="outta"></textarea><p><button onclick="document.getElementById('out').style.display='none'">Close</button></p></div>
<script>
const KEY='review:'+location.pathname;
let state={{}};try{{state=JSON.parse(localStorage.getItem(KEY)||'{{}}')}}catch(e){{}}
function save(){{try{{localStorage.setItem(KEY,JSON.stringify(state))}}catch(e){{}};paint()}}
function paint(){{let n=0;document.querySelectorAll('.card').forEach(c=>{{const id=c.dataset.id,s=state[id]||{{}};c.classList.toggle('done',!!s.d);if(s.d)n++;c.querySelectorAll('input[type=radio]').forEach(r=>r.checked=(r.value===s.d));c.querySelector('textarea').value=s.n||''}});document.getElementById('count').textContent=n+' / '+document.querySelectorAll('.card').length+' decided'}}
document.querySelectorAll('.card').forEach(c=>{{const id=c.dataset.id;c.querySelectorAll('input[type=radio]').forEach(r=>r.onchange=()=>{{(state[id]=state[id]||{{}}).d=r.value;save()}});c.querySelector('textarea').oninput=e=>{{(state[id]=state[id]||{{}}).n=e.target.value;save()}}}});
function exportMd(){{const lines=['## Review decisions ('+new Date().toISOString().slice(0,10)+')'];document.querySelectorAll('.card').forEach(c=>{{const s=state[c.dataset.id]||{{}};lines.push('- **'+c.dataset.title+'** — '+(s.d||'undecided')+(s.n?': '+s.n.replace(/\\n+/g,' '):''))}});const t=lines.join('\\n');document.getElementById('outta').value=t;document.getElementById('out').style.display='block';try{{navigator.clipboard.writeText(t)}}catch(e){{}}}}
function reset(){{if(confirm('Clear all decisions on this page?')){{state={{}};save()}}}}
paint();
</script></body></html>
"""

CARD = """<section class="card" data-id="{id}" data-title="{title_attr}">
<h2>{i}. {title}</h2>
{body}
<div class="dec">
<label><input type="radio" name="d{id}" value="approve"><span>Approve</span></label>
<label><input type="radio" name="d{id}" value="change"><span>Needs change</span></label>
<label><input type="radio" name="d{id}" value="reject"><span>Reject</span></label>
<label><input type="radio" name="d{id}" value="skip"><span>Skip</span></label>
</div>
<textarea placeholder="Notes for Claude (what to change, which option, what you saw)…"></textarea>
</section>"""


def main():
    if os.path.exists(REVIEW_MD):
        src, items = "_planning/REVIEW.md", items_from_review_md(read(REVIEW_MD))
    else:
        status = next((p for p in (os.path.join(PLANNING, "STATUS.md"), os.path.join(ROOT, "STATUS.md")) if os.path.exists(p)), None)
        if not status:
            print("no _planning/REVIEW.md or STATUS.md found", file=sys.stderr)
            return 1
        src, items = os.path.relpath(status, ROOT), items_from_status(read(status))
    cards = "\n".join(
        CARD.format(id=i, i=i + 1, title=html.escape(t), title_attr=html.escape(t, quote=True), body=md(b))
        for i, (t, b) in enumerate(items)
    ) or "<p class='sub'>Nothing needs input right now.</p>"
    os.makedirs(PLANNING, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(PAGE.format(project=html.escape(os.path.basename(ROOT)), n=len(items),
                            today=date.today().isoformat(), src=src, cards=cards))
    print(f"wrote {os.path.relpath(OUT, ROOT)} ({len(items)} item(s) from {src})")

    if "--serve" in sys.argv:
        import functools
        from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
        i = sys.argv.index("--serve")
        port = int(sys.argv[i + 1]) if i + 1 < len(sys.argv) and sys.argv[i + 1].isdigit() else 8765
        handler = functools.partial(SimpleHTTPRequestHandler, directory=PLANNING)
        print(f"serving _planning/ on http://0.0.0.0:{port}/review.html — open via the forwarded port; Ctrl-C stops")
        ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
