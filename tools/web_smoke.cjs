/* Actual Chrome DevTools Protocol smoke test, using Node 22+ built-ins only.
 * Start a dedicated headless Chrome on port 9449 and serve the webroot on 8915.
 * node bombbound/tools/web_smoke.cjs [url] [evidence_directory]
 */
const fs = require('node:fs');
const path = require('node:path');
const url = process.argv[2] || 'http://127.0.0.1:8915/';
const output = path.resolve(process.argv[3] || '.codex-tmp/web-browser-qa');
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));
fs.mkdirSync(output, { recursive: true });

(async () => {
  let target;
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      target = await fetch('http://127.0.0.1:9449/json/new?about:blank', { method: 'PUT' }).then(r => r.json());
      break;
    } catch (error) {
      if (attempt === 29) throw error;
      await delay(250);
    }
  }
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let sequence = 0;
  const pending = new Map();
  const errors = [];
  const messages = [];
  const requests = [];
  const networkFailures = [];
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else resolve(message.result);
    }
    if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
    if (message.method === 'Runtime.consoleAPICalled') {
      const record = { type: message.params.type, text: message.params.args.map(a => a.value ?? a.description ?? '').join(' ') };
      messages.push(record);
      if (record.type === 'error') errors.push(record);
    }
    if (message.method === 'Network.requestWillBeSent') requests.push(message.params.request.url);
    if (message.method === 'Network.loadingFailed') networkFailures.push(message.params);
  };
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++sequence;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
    setTimeout(() => { if (pending.delete(id)) reject(new Error(`CDP timeout: ${method}`)); }, 45000).unref();
  });
  const evaluate = async (expression) => {
    const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  const screenshot = async (name) => {
    const result = await call('Page.captureScreenshot', { format: 'png', fromSurface: true });
    fs.writeFileSync(path.join(output, name + '.png'), Buffer.from(result.data, 'base64'));
  };
  const closeScreenshot = async (name) => {
    const result = await call('Page.captureScreenshot', { format: 'png', fromSurface: true,
      clip: { x: 0, y: 470, width: 256, height: 180, scale: 3 } });
    fs.writeFileSync(path.join(output, name + '.png'), Buffer.from(result.data, 'base64'));
  };
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Network.enable');
  await call('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await call('Page.navigate', { url });
  let status = null;
  for (let attempt = 0; attempt < 80; attempt++) {
    await delay(500);
    status = await evaluate(`({gzip:window.IMPULSE_COMPACT_WEB||null,canvas:(()=>{const c=document.querySelector('canvas');return c?{width:c.width,height:c.height}:null})(),notice:document.querySelector('#status-notice')?.textContent||'',statusDisplay:document.querySelector('#status')?(document.querySelector('#status').style.display||'visible'):'none'})`);
    if (status.gzip?.loads && status.canvas?.width && status.statusDisplay === 'none') break;
  }
  await delay(1200);
  await screenshot('01-loaded');
  // True mouse input in the 60px range: abrupt targets show immediate arms and
  // pupils. A cursor buried in the floor must produce a free, visible ghost.
  await call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 160, y: 574 });
  await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: 160, y: 574, button: 'left', buttons: 1, clickCount: 1 });
  await delay(140);
  await screenshot('02-holding-arms');
  await closeScreenshot('02a-eyes-right-close');
  await call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 60, y: 574, buttons: 1 });
  await delay(70);
  await closeScreenshot('02b-eyes-left-close');
  await call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 110, y: 534, buttons: 1 });
  await delay(70);
  await closeScreenshot('02c-eyes-above-close');
  await call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 143, y: 635, buttons: 1 });
  await delay(100);
  await screenshot('02d-floor-autocorrect');
  await closeScreenshot('02d-floor-autocorrect-close');
  await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 143, y: 635, button: 'left', buttons: 0, clickCount: 1 });
  await delay(200);
  // A second charge is released from above so real gravity is also visible.
  await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: 110, y: 534, button: 'left', buttons: 1, clickCount: 1 });
  await delay(100);
  await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 110, y: 534, button: 'left', buttons: 0, clickCount: 1 });
  await delay(850);
  await screenshot('03-released-gravity');
  await call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'f', code: 'KeyF', windowsVirtualKeyCode: 70 });
  await delay(70);
  await call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'f', code: 'KeyF', windowsVirtualKeyCode: 70 });
  await delay(180);
  await screenshot('04-detonation');
  await delay(160);
  await screenshot('04b-detonation-late-no-rings');
  await delay(1000);
  // A real R restart and a stationary Space jump cover the other two burst
  // triggers. Sample two phases of each to reveal any expanding outline.
  await call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'r', code: 'KeyR', windowsVirtualKeyCode: 82 });
  await delay(25);
  await call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'r', code: 'KeyR', windowsVirtualKeyCode: 82 });
  await delay(45);
  await screenshot('05-respawn-early-no-rings');
  await delay(150);
  await screenshot('05b-respawn-late-no-rings');
  await delay(650);
  await call('Input.dispatchKeyEvent', { type: 'keyDown', key: ' ', code: 'Space', windowsVirtualKeyCode: 32 });
  await delay(20);
  await call('Input.dispatchKeyEvent', { type: 'keyUp', key: ' ', code: 'Space', windowsVirtualKeyCode: 32 });
  await delay(590);
  await screenshot('06-landing-early-no-rings');
  await delay(150);
  await screenshot('06b-landing-late-no-rings');
  const final = await evaluate(`({gzip:window.IMPULSE_COMPACT_WEB||null,canvas:(()=>{const c=document.querySelector('canvas');return c?{width:c.width,height:c.height}:null})(),notice:document.querySelector('#status-notice')?.textContent||'',statusDisplay:document.querySelector('#status')?(document.querySelector('#status').style.display||'visible'):'none',userAgent:navigator.userAgent})`);
  const report = { url, final, errors, networkFailures, requests, messages };
  fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ gzipLoads: final.gzip?.loads, canvas: final.canvas, status: final.statusDisplay,
    gzipRequested: requests.some(item => item.endsWith('/index.wasm.gz')), errors: errors.length,
    networkFailures: networkFailures.length, output }, null, 2));
  await call('Page.close');
  socket.close();
  if (!final.gzip?.loads || final.statusDisplay !== 'none' || errors.length || networkFailures.length) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
