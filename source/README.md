# Console mode prototype: sources

The page at the root of this branch (`index.html`, served at https://koshindai.github.io/NX2Apple/) is the playable phase 1 prototype of the console mode redesign, proposed in LNPANDY/NX2Apple#816. This folder holds what it is made from.

- `canvas/`: a copy of the design canvas (one `.dc.html` file per screen, `bp.css` for the shared styles, `canvas.json` for the layout and notes, and the launcher design system's `bundle.css`). `canvas/Prototype.dc.html` is the interactive prototype. The canvas itself is a private Claude Design artifact; this copy is what was published on 2026-11-06.
- `build.py`: turns `canvas/Prototype.dc.html` into `../index.html`, a single page with no dependencies but the Manrope font. It includes a small stand-in for the canvas runtime (`{{holes}}`, `sc-if`, `sc-for`, and a DOM patch so the CSS transitions run).
- `shots.sh`: captures the screenshots in `../shots/` with headless Chrome.

To change the prototype: edit `canvas/Prototype.dc.html` (and the canvas, so the two stay the same), run `python3 source/build.py`, check the page locally (`python3 -m http.server` at the root, then open http://localhost:8000/), run `sh source/shots.sh` if the screens changed, then commit and push this branch.

The notes in `canvas/canvas.json` (s3, s6, s7) hold the navigation rules, the focus, motion and glyph spec, and the data the Mac launcher does not have yet.
