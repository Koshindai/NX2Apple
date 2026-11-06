"""Builds ../index.html, the playable console mode prototype, from the canvas files in canvas/.

Run: python3 build.py (no dependencies). canvas/Prototype.dc.html is the source of truth."""
import re, pathlib
here = pathlib.Path(__file__).parent
src = (here/'canvas/Prototype.dc.html').read_text()
bp = (here/'canvas/bp.css').read_text()
ds = (here/'canvas/ds/nx2apple-launcher/components/bundle.css').read_text()

ds = re.sub(r'@import[^;]+;', '', ds)
style = re.search(r'<helmet>.*?<style>(.*?)</style>', src, re.S).group(1)
markup = re.search(r'(<div class="proto".*?)\n</x-dc>', src, re.S).group(1)
markup = re.sub(r'<div class="proto"[^>]*>', '<div class="proto">', markup, 1)
markup = markup.rsplit('</div>', 1)[0]  # drop the proto wrapper's closing tag
markup = markup.split('<div class="proto">', 1)[1]
script = re.search(r'<script type="text/x-dc"[^>]*>(.*?)</script>', src, re.S).group(1)
script = script.replace("b: '⌫',", "b: 'esc',")
page = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NX2Apple Console mode prototype</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Manrope:wght@200..800&display=swap">
<style>
{bp}
{ds}
{style}
html,body{{margin:0;height:100%;background:#000;color:#fff;font-family:Manrope,system-ui,sans-serif;overflow:hidden}}
.bar{{position:fixed;left:0;right:0;top:0;height:56px;box-sizing:border-box;padding:0 16px 0 20px;display:flex;align-items:center;gap:12px;background:#121214;border-bottom:1px solid rgba(255,255,255,.08);font:500 13px/1 Manrope,sans-serif;color:rgba(235,235,245,.6);z-index:10;white-space:nowrap}}
.brand{{overflow:hidden;text-overflow:ellipsis;min-width:0}}
.brand b{{color:#fff;font-weight:800;margin-right:6px}}
.sp{{flex:1}}
.pad-pill{{display:inline-flex;align-items:center;gap:8px;height:32px;padding:0 14px;border-radius:999px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);max-width:300px;overflow:hidden;text-overflow:ellipsis}}
.pad-pill i{{width:8px;height:8px;border-radius:50%;background:#ffc73d;flex:none}}
.pad-pill.on{{color:rgba(255,255,255,.88)}}
.pad-pill.on i{{background:#40d678}}
.seg{{display:inline-flex;gap:2px;padding:3px;border-radius:999px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08)}}
.seg button,.help>button,.icon{{border:0;background:none;color:rgba(255,255,255,.75);font:600 13px/1 Manrope,sans-serif;padding:8px 13px;border-radius:999px;cursor:pointer}}
.seg button[aria-pressed="true"]{{background:#fff0d6;color:#000;font-weight:800}}
.help{{position:relative}}
.help>button,.icon{{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);height:32px;padding:0 13px}}
.icon{{width:32px;padding:0;display:inline-flex;align-items:center;justify-content:center}}
.seg button:hover,.help>button:hover,.icon:hover{{color:#fff}}
.pop{{position:absolute;right:0;top:42px;width:280px;padding:16px 18px;border-radius:14px;background:#1a1a1c;border:1px solid rgba(255,255,255,.12);box-shadow:0 16px 40px rgba(0,0,0,.5);white-space:normal;font:500 13px/1.45 Manrope,sans-serif;color:rgba(235,235,245,.7)}}
.pop b{{display:block;color:#fff;font-weight:800;margin:0 0 8px}}
.pop dl{{display:grid;grid-template-columns:auto 1fr;gap:6px 14px;margin:0 0 14px}}
.pop dt{{color:#fff0d6;font-weight:700}}
.pop dd{{margin:0}}
.pop p{{margin:0}}
@media (max-width:760px){{.brand{{display:none}}}}
.stage{{position:fixed;left:0;top:56px;width:1920px;height:1080px;transform-origin:0 0}}
.proto{{outline:none}}
</style>
</head>
<body>
<div class="bar">
  <span class="brand"><b>NX2Apple</b> Console mode · prototype</span>
  <span class="sp"></span>
  <span class="pad-pill" id="padpill" title=""><i></i><span id="padinfo">No controller · press a button</span></span>
  <span class="seg" role="group" aria-label="Button glyphs"><button data-fam="xbox">Xbox</button><button data-fam="ps">PlayStation</button><button data-fam="nintendo">Nintendo</button></span>
  <span class="help"><button id="helpbtn" aria-expanded="false">Keys</button>
    <div class="pop" id="help" hidden>
      <b>Keyboard</b>
      <dl><dt>← ↑ → ↓</dt><dd>Move</dd><dt>return</dt><dd>A</dd><dt>esc</dt><dd>B</dd><dt>X · Y</dt><dd>X · Y</dd><dt>Q · E</dt><dd>L · R</dd><dt>M</dt><dd>Main menu</dd><dt>V</dt><dd>Quick menu</dd><dt>H</dt><dd>Home</dd></dl>
      <b>Controller</b>
      <p>Use Chrome or Safari and press any button once. Firefox-based browsers may not receive the buttons on a Mac.</p>
    </div>
  </span>
  <button class="icon" id="reset" title="Restart" aria-label="Restart"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7M3 4v5h5"></path></svg></button>
</div>
<div class="stage" id="stage"><div class="proto" id="proto" tabindex="0"></div></div>
<template id="tpl">{markup}</template>
<script>
// A small stand-in for the design canvas runtime: {{{{path}}}} holes, sc-if, sc-for, and a DOM patch so CSS transitions still run.
class DCLogic {{
  constructor(props) {{ this.props = props; }}
  setState(p) {{ Object.assign(this.state, typeof p === 'function' ? p(this.state) : p); schedule(); }}
}}
{script}
const tpl = document.getElementById('tpl').content, root = document.getElementById('proto');
const HOLE = /\\{{\\{{\\s*([^}}]+?)\\s*\\}}\\}}/g;
function look(path, scopes) {{
  if (path === 'true') return true; if (path === 'false') return false;
  const parts = path.split('.');
  for (const sc of scopes) if (sc && parts[0] in sc) return parts.slice(1).reduce((o, k) => o == null ? o : o[k], sc[parts[0]]);
  return undefined;
}}
function fill(str, scopes) {{
  const m = str.match(/^\\{{\\{{\\s*([^}}]+?)\\s*\\}}\\}}$/);
  if (m) {{ const v = look(m[1], scopes); return v == null ? '' : String(v); }}
  return str.replace(HOLE, (_, p) => {{ const v = look(p, scopes); return v == null ? '' : String(v); }});
}}
function hole(attr, scopes) {{ const m = (attr || '').match(/\\{{\\{{\\s*([^}}]+?)\\s*\\}}\\}}/); return m ? look(m[1], scopes) : undefined; }}
function build(nodes, scopes, out) {{
  for (const n of nodes) {{
    if (n.nodeType === 3) {{ out.push(document.createTextNode(fill(n.nodeValue, scopes))); continue; }}
    if (n.nodeType !== 1) continue;
    const tag = n.localName;
    if (tag === 'sc-if') {{ if (hole(n.getAttribute('value'), scopes)) build(n.childNodes, scopes, out); continue; }}
    if (tag === 'sc-for') {{
      const list = hole(n.getAttribute('list'), scopes) || [], as = n.getAttribute('as');
      list.forEach((item) => build(n.childNodes, [{{[as]: item}}].concat(scopes), out)); continue;
    }}
    const el = n.cloneNode(false);
    for (const a of Array.from(n.attributes)) {{
      if (a.name.startsWith('hint-placeholder')) {{ el.removeAttribute(a.name); continue; }}
      if (a.value.indexOf('{{{{') >= 0) el.setAttribute(a.name, fill(a.value, scopes));
    }}
    const kids = []; build(n.childNodes, scopes, kids); kids.forEach((k) => el.appendChild(k));
    out.push(el);
  }}
  return out;
}}
function patch(parent, fresh) {{
  const old = Array.from(parent.childNodes);
  fresh.forEach((f, i) => {{
    const o = old[i];
    if (!o) {{ parent.appendChild(f); return; }}
    if (o.nodeType !== f.nodeType || o.nodeName !== f.nodeName) {{ parent.replaceChild(f, o); return; }}
    if (o.nodeType === 3) {{ if (o.nodeValue !== f.nodeValue) o.nodeValue = f.nodeValue; return; }}
    for (const a of Array.from(o.attributes)) if (!f.hasAttribute(a.name)) o.removeAttribute(a.name);
    for (const a of Array.from(f.attributes)) if (o.getAttribute(a.name) !== a.value) o.setAttribute(a.name, a.value);
    patch(o, Array.from(f.childNodes));
  }});
  for (let i = old.length - 1; i >= fresh.length; i--) parent.removeChild(old[i]);
}}
let family = 'xbox';
try {{ family = new URLSearchParams(location.search).get('pad') || localStorage.getItem('nx-bp-family') || 'xbox'; }} catch (e) {{}}
const comp = new Component({{family}});
let vals = null, queued = false;
function render() {{ queued = false; vals = comp.renderVals(); patch(root, build(tpl.childNodes, [vals], [])); }}
function schedule() {{ if (!queued) {{ queued = true; requestAnimationFrame(render); }} }}
function setFamily(f) {{
  family = f; comp.props = {{family: f}}; try {{ localStorage.setItem('nx-bp-family', f); }} catch (e) {{}}
  document.querySelectorAll('[data-fam]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.fam === f)));
  schedule();
}}
document.querySelectorAll('[data-fam]').forEach((b) => b.addEventListener('click', () => {{ setFamily(b.dataset.fam); b.blur(); }}));
document.getElementById('reset').addEventListener('click', (e) => {{ vals && vals.reset(); e.currentTarget.blur(); }});
window.addEventListener('keydown', (e) => {{ if (e.metaKey || e.ctrlKey || e.altKey) return; vals && vals.onKey(e); }});
function fit() {{
  const s = Math.min(innerWidth / 1920, (innerHeight - 56) / 1080), st = document.getElementById('stage');
  st.style.transform = 'scale(' + s + ')'; st.style.left = Math.max(0, (innerWidth - 1920 * s) / 2) + 'px';
}}
addEventListener('resize', fit); fit();
// What the browser reports, so a tester can say what it sees
const info = document.getElementById('padinfo'), pill = document.getElementById('padpill');
setInterval(() => {{
  let pads = [];
  try {{ pads = Array.from(navigator.getGamepads ? navigator.getGamepads() : []).filter(Boolean); }} catch (e) {{ info.textContent = 'Controllers blocked here'; pill.className = 'pad-pill'; return; }}
  if (!pads.length) {{ info.textContent = 'No controller · press a button'; pill.className = 'pad-pill'; pill.title = ''; return; }}
  const p = pads[0], down = p.buttons.map((b, i) => b.pressed ? i : -1).filter((i) => i >= 0);
  info.textContent = p.id.replace(/^[0-9a-f]{{4}}-[0-9a-f]{{4}}-/i, '').replace(/\\s*\\(.*$/, '');
  pill.className = 'pad-pill on';
  pill.title = 'mapping: ' + (p.mapping || 'none') + ' · buttons ' + (down.join(',') || '–') + ' · axes ' + Array.from(p.axes).map((a) => a.toFixed(1)).join(' ');
}}, 150);
const helpBtn = document.getElementById('helpbtn'), help = document.getElementById('help');
helpBtn.addEventListener('click', (e) => {{ help.hidden = !help.hidden; helpBtn.setAttribute('aria-expanded', String(!help.hidden)); e.stopPropagation(); helpBtn.blur(); }});
document.addEventListener('click', (e) => {{ if (!help.hidden && !help.contains(e.target)) {{ help.hidden = true; helpBtn.setAttribute('aria-expanded', 'false'); }} }});
setFamily(family); render(); comp.componentDidMount && comp.componentDidMount();
</script>
</body>
</html>
'''
(here.parent/'index.html').write_text(page)
print(len(page))
