#!/bin/sh
# Captures the screenshots in ../shots/ at 1920x1080 with headless Chrome, from ../index.html.
# A copy of the page (shot.html, deleted afterwards) hides the top bar, turns animations off and
# opens each screen from a state given in the URL. Run from anywhere: sh source/shots.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
port=8799

python3 - "$root" <<'EOF'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
page = (root / 'index.html').read_text()
hook = '''<script>
(() => { const q = new URLSearchParams(location.search);
  const css = document.createElement('style');
  css.textContent = '*,*::before,*::after{transition:none!important;animation:none!important}.bar{display:none!important}.bp-panel{background:#161618!important}#stage{top:0!important;left:0!important;transform:none!important}';
  document.head.appendChild(css);
  if (q.has('state')) comp.setState(Object.assign({input: 'pad'}, JSON.parse(q.get('state'))));
})();
</script>
</body>'''
(root / 'shot.html').write_text(page.replace('</body>', hook, 1))
EOF

python3 -m http.server "$port" --directory "$root" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -f "$root/shot.html"; rm -rf "$here/.chrome"' EXIT
sleep 1

shot() {
  state=$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$2")
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=1920,1080 --virtual-time-budget=4000 \
    --user-data-dir="$here/.chrome" --screenshot="$root/shots/$1.png" "http://localhost:$port/shot.html?state=$state" >/dev/null 2>&1
  echo "shots/$1.png"
}

mkdir -p "$root/shots"
shot 1-home '{}'
shot 2-game '{"screen":"game","gameId":1,"gameIdx":0,"from":"home"}'
shot 3-launch-options '{"screen":"launchopts","gameId":1,"loZone":"rows","loIdx":1}'
shot 4-main-menu '{"screen":"library","layer":"main","mainIdx":1,"zone":"grid"}'
