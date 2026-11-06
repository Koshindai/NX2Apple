// Records the prototype with headless Chrome's screencast, in real time, as JPEG frames plus
// frames.txt (an ffmpeg concat list with each frame's duration). No dependencies (Node 22+).
// Usage: node record.mjs <page url> <frames dir> [probe]
// "probe" saves one still after each step instead of every frame, to check the path.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';

const [url, out, mode] = process.argv.slice(2);
const probe = mode === 'probe';
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9333, profile = out + '/.chrome';

// [key, then wait in ms]. Keys are the prototype's: up down left right a b x y l r plus minus home.
const STEPS = [
  [null, 1600],                                   // Home
  ['right', 700], ['right', 700], ['right', 900], // browse Continue playing
  ['down', 900], ['right', 700], ['right', 900],  // Ready to play
  ['up', 600], ['left', 500], ['left', 500], ['left', 900],
  ['a', 1600],                                    // game page
  ['right', 700], ['right', 1100],                // Controls, Launch options
  ['a', 1400],                                    // Launch options
  ['down', 700], ['right', 600], ['right', 1000], // change a value
  ['b', 600], ['b', 1200],                        // back to the game page
  ['right', 1000], ['a', 1400],                   // Manage
  ['down', 600], ['down', 600], ['down', 900],
  ['b', 1100],                                    // close Manage
  ['plus', 1300],                                 // main menu
  ['down', 900], ['a', 1600],                     // Library
  ['r', 1100], ['r', 1100], ['l', 1100],          // filters
  ['right', 600], ['down', 600], ['right', 1000],
  ['x', 5200],                                    // play: Starting, then in game
  ['home', 2200],                                 // back on the game page
];

mkdirSync(out, { recursive: true });
const proc = spawn(chrome, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1920,1080',
  `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page'); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map(), waiters = [];
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method) waiters.filter((w) => w.method === m.method).forEach((w) => { waiters.splice(waiters.indexOf(w), 1); w.r(m.params); });
});
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); })
  .then((m) => { if (m.error) throw new Error(method + ': ' + m.error.message); return m.result; });
const once = (method) => new Promise((r) => waiters.push({ method, r }));

await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
const loaded = once('Page.loadEventFired');
await send('Page.navigate', { url });
await loaded;
await sleep(1500); // fonts and artwork
await send('Runtime.evaluate', { expression: "comp.setState({input: 'pad'})" });

const shoot = async (name) => {
  const { data } = await send('Page.captureScreenshot', { format: 'jpeg', quality: 92 });
  writeFileSync(`${out}/${name}.jpg`, Buffer.from(data, 'base64'));
};
const frames = [];
if (!probe) {
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data);
    if (m.method !== 'Page.screencastFrame') return;
    const name = String(frames.length).padStart(5, '0') + '.jpg';
    writeFileSync(`${out}/${name}`, Buffer.from(m.params.data, 'base64'));
    frames.push([name, m.params.metadata.timestamp]);
    send('Page.screencastFrameAck', { sessionId: m.params.sessionId });
  });
  await send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });
  await sleep(300);
}
for (const [i, [key, ms]] of STEPS.entries()) {
  if (key) await send('Runtime.evaluate', { expression: `comp.press(${JSON.stringify(key)})` });
  await sleep(ms);
  if (probe) await shoot(`step-${String(i).padStart(2, '0')}-${key || 'start'}`);
}
if (!probe) {
  await send('Page.stopScreencast');
  // The screencast only sends a frame when the page changes: each frame lasts until the next one.
  const end = frames.at(-1)[1] + 0.5;
  const list = frames.map(([n, t], i) => `file '${n}'\nduration ${((i + 1 < frames.length ? frames[i + 1][1] : end) - t).toFixed(4)}`);
  writeFileSync(`${out}/frames.txt`, list.join('\n') + `\nfile '${frames.at(-1)[0]}'\n`);
}
ws.close(); proc.kill();
await sleep(300); rmSync(profile, { recursive: true, force: true });
console.log(probe ? `${STEPS.length} stills in ${out}` : `${frames.length} frames over ${(frames.at(-1)[1] - frames[0][1]).toFixed(1)} s in ${out}`);
