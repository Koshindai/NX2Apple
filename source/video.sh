#!/bin/sh
# Records the walkthrough video (../shots/console-mode.mp4) and its GIF preview (../shots/console-mode.gif)
# from ../index.html. Needs Google Chrome, Node 22+ and ffmpeg. The path through the prototype is the
# STEPS list in record.mjs. Run from anywhere: sh source/video.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
port=8798
frames=$(mktemp -d)

python3 - "$root" <<'PY'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
page = (root / 'index.html').read_text()
hook = '<style>.bar{display:none!important}.bp-panel{background:#161618!important}#stage{top:0!important;left:0!important;transform:none!important}</style>\n</body>'
(root / 'video.html').write_text(page.replace('</body>', hook, 1))
PY

python3 -m http.server "$port" --directory "$root" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -f "$root/video.html"; rm -rf "$frames"' EXIT
sleep 1

node "$here/record.mjs" "http://localhost:$port/video.html" "$frames"
mkdir -p "$root/shots"
ffmpeg -v error -y -f concat -safe 0 -i "$frames/frames.txt" -vf "fps=30,format=yuv420p" \
  -c:v libx264 -preset slow -crf 22 -movflags +faststart "$root/shots/console-mode.mp4"
ffmpeg -v error -y -i "$root/shots/console-mode.mp4" -vf "fps=12,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  "$root/shots/console-mode.gif"
echo "shots/console-mode.mp4 shots/console-mode.gif"
