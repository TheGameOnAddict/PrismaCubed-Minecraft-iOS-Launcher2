"""Package simulator captures into an offline side-by-side screen picker."""
import base64
import json
import sys
from pathlib import Path

SCREENS = {
    "home": "My Profiles", "browse": "Browse Modpacks", "profile": "Active Profile",
    "mods": "Add Mods", "menu": "Account Menu", "accounts": "Manage Accounts",
    "create": "New Profile", "import": "Import",
}
folder = Path(sys.argv[1])
screens = {}
for route, label in SCREENS.items():
    images = {}
    for orientation in ("portrait", "landscape"):
        image = (folder / f"cubic-{route}-{orientation}.png").read_bytes()
        width = int.from_bytes(image[16:20], "big")
        height = int.from_bytes(image[20:24], "big")
        if not image.startswith(b"\x89PNG") or (width < height) != (orientation == "portrait"):
            raise ValueError(f"Unexpected capture for {route} in {orientation}")
        images[orientation] = "data:image/png;base64," + base64.b64encode(image).decode()
    screens[label] = images

html = """<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>PrismaCubic native previews</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#18181a;color:#f5f3ef;font:16px system-ui,sans-serif}
main{max-width:1440px;margin:auto;padding:clamp(16px,3vw,44px)}h1{font-size:clamp(24px,4vw,40px);margin:0 0 14px}
nav{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:20px}button{font:inherit;border:1px solid #46464a;border-radius:8px;background:#27272a;color:inherit;padding:7px 12px;cursor:pointer}
button[aria-pressed=true]{background:#ff944e;color:#151516;border-color:transparent}button:focus-visible{outline:3px solid white}
section{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,2.15fr);gap:18px;align-items:start}figure{margin:0}figcaption{color:#ccc;margin:0 0 6px}img{width:100%;height:auto;display:block;border-radius:10px;border:1px solid #444}
@media(max-width:650px){section{grid-template-columns:1fr}figure:first-child{max-width:320px}}
</style><main><h1>PrismaCubic native previews</h1><nav aria-label="Screens"></nav>
<section><figure><figcaption>Portrait</figcaption><img id="portrait"></figure>
<figure><figcaption>Landscape</figcaption><img id="landscape"></figure></section></main>
<script>const screens=SCREEN_DATA;
const nav=document.querySelector('nav');
function show(label){for(const id of ['portrait','landscape']){
 const img=document.getElementById(id);img.src=screens[label][id];img.alt=label+' in '+id;}
 for(const btn of nav.children)btn.setAttribute('aria-pressed',String(btn.textContent===label));}
for(const label of Object.keys(screens)){const btn=document.createElement('button');btn.textContent=label;
 btn.onclick=()=>show(label);nav.append(btn);}show(Object.keys(screens)[0]);</script></html>"""
(folder / "PrismaCubic-previews.html").write_text(html.replace("SCREEN_DATA", json.dumps(screens)), encoding="utf-8")
