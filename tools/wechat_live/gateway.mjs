/** Tencent iLink QR login + durable inbound/outbound transport for the local demo. */
import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { deflateSync } from 'node:zlib';
import { pathToFileURL } from 'node:url';

const API = 'https://ilinkai.weixin.qq.com';
const version = '2.4.10';
const appHeaders = { 'iLink-App-Id': 'bot', 'iLink-App-ClientVersion': '132106' };
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
export function trustedBase(value) {
  const url = new URL(value.includes('://') ? value : `https://${value}`);
  if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443') ||
      !url.hostname.endsWith('.weixin.qq.com') || url.pathname !== '/' || url.search || url.hash) throw new Error('Untrusted Weixin host');
  return url.origin;
}
export function parseWire(text) {
  return JSON.parse(text, (key, value, context) => key === 'message_id' && typeof value === 'number' ? context.source : value);
}
export function replyPayload(message, text, clientId) {
  if (!message.context_token || !message.from_user_id) throw new Error('Missing reply scope');
  return { msg: { from_user_id: '', to_user_id: message.from_user_id, client_id: clientId, message_type: 2,
    message_state: 2, context_token: message.context_token, item_list: [{ type: 1, text_item: { text } }] } };
}
export function qrPng(text) {
  const require = createRequire(import.meta.url);
  let QR;
  try { QR = require('qrcode-terminal/vendor/QRCode'); }
  catch { QR = require(path.join(path.dirname(process.execPath), 'node_modules/npm/node_modules/qrcode-terminal/vendor/QRCode')); }
  const qr = new QR(-1, 0); qr.addData(text); qr.make();
  const n = qr.getModuleCount(), size = (n + 8) * 8, pixels = Buffer.alloc(size * (size + 1), 255);
  for (let y = 0; y < size; y++) {
    pixels[y * (size + 1)] = 0;
    for (let x = 0; x < size; x++) {
      const r = Math.floor(y / 8) - 4, c = Math.floor(x / 8) - 4;
      if (r >= 0 && r < n && c >= 0 && c < n && qr.isDark(r, c)) pixels[y * (size + 1) + x + 1] = 0;
    }
  }
  function chunk(type, data) {
    const bytes = Buffer.concat([Buffer.from(type), data]); let crc = 0xffffffff;
    for (const byte of bytes) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
    const length = Buffer.alloc(4), checksum = Buffer.alloc(4);
    length.writeUInt32BE(data.length); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([length, bytes, checksum]);
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(size); header.writeUInt32BE(size, 4); header[8] = 8;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}

export function createGateway({ data, secret, accountUrl, fetcher = fetch }) {
  if (!secret || secret.length < 32 || !/^http:\/\/127\.0\.0\.1:\d+$/.test(accountUrl)) throw new Error('Local service configuration required');
  mkdirSync(data, { recursive: true });
  const db = new DatabaseSync(path.join(data, 'wechat-private.sqlite3'));
  db.exec(`PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS channels(link_id TEXT PRIMARY KEY,bot_id TEXT,user_id TEXT,token TEXT,base TEXT,cursor TEXT,status TEXT);
    CREATE TABLE IF NOT EXISTS inbox(link_id TEXT,message_id TEXT,payload TEXT,reply TEXT,status TEXT,PRIMARY KEY(link_id,message_id));`);
  const jobs = new Map(), monitors = new Set();
  const lifecycle = new AbortController();
  let stopping = false;
  const internalHeaders = { 'Content-Type': 'application/json', 'X-Wechat-Service-Token': secret };
  async function accountCall(endpoint, body) {
    const r = await fetcher(accountUrl + endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15_000), headers: internalHeaders, body: JSON.stringify(body) });
    const data = await r.json();
    if (!r.ok || !data.ok) { const e = new Error(data.message || 'Local service unavailable'); e.status = r.status; throw e; }
    return data;
  }
  async function botCall(base, endpoint, body, token, timeout = 40_000) {
    const headers = { ...appHeaders, 'Content-Type': 'application/json', AuthorizationType: 'ilink_bot_token',
      'X-WECHAT-UIN': Buffer.from(String(randomBytes(4).readUInt32BE())).toString('base64') };
    if (token) headers.Authorization = 'Bearer ' + token;
    const r = await fetcher(trustedBase(base) + endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.any([lifecycle.signal, AbortSignal.timeout(timeout)]), headers,
      body: JSON.stringify(token ? { ...body, base_info: { channel_version: version, bot_agent: 'Xiuxian/1.0' } } : body) });
    if (!r.ok) throw new Error('Weixin HTTP failure');
    const value = parseWire(await r.text());
    if (value.ret || value.errcode) { const error = new Error('Weixin API failure'); error.code = value.ret || value.errcode; throw error; }
    return value;
  }
  async function begin(job) {
    const generation = ++job.generation;
    job.status = 'starting'; job.image = null; job.code = ''; job.credentials = null;
    try {
      const tokens = db.prepare('SELECT token FROM channels ORDER BY rowid DESC LIMIT 10').all().map(row => row.token);
      const value = await botCall(API, '/ilink/bot/get_bot_qrcode?bot_type=3', { local_token_list: tokens }, null, 20_000);
      if (job.generation !== generation) return;
      if (!value.qrcode || typeof value.qrcode_img_content !== 'string') throw new Error('QR missing');
      job.image = qrPng(value.qrcode_img_content); job.status = 'wait';
      void pollLogin(job, generation, value.qrcode);
    } catch { if (job.generation === generation) job.status = 'error'; }
  }
  async function pollLogin(job, generation, qr) {
    let base = API;
    const deadline = Date.now() + 5 * 60_000;
    while (!stopping && job.generation === generation && Date.now() < deadline) {
      try {
        const url = new URL('/ilink/bot/get_qrcode_status', base); url.searchParams.set('qrcode', qr);
        if (job.code) { url.searchParams.set('verify_code', job.code); job.code = ''; }
        const r = await fetcher(url, { headers: appHeaders, redirect: 'error', signal: AbortSignal.any([lifecycle.signal, AbortSignal.timeout(35_000)]) });
        if (!r.ok) throw new Error();
        const value = await r.json(); if (job.generation !== generation) return;
        if (value.status === 'confirmed') {
          if (!value.bot_token || !value.ilink_bot_id || !value.ilink_user_id) throw new Error();
          job.credentials = { token: value.bot_token, bot: value.ilink_bot_id, user: value.ilink_user_id, base: trustedBase(value.baseurl || API) };
          job.status = 'awaiting_consent'; return;
        }
        if (value.status === 'scaned_but_redirect' && value.redirect_host) base = trustedBase(value.redirect_host);
        job.status = value.status || 'wait';
        if (['expired', 'verify_code_blocked', 'binded_redirect'].includes(job.status)) return;
      } catch {}
      await pause(1500);
    }
    if (job.generation === generation) job.status = 'expired';
  }
  async function activate(job) {
    if (job.status !== 'awaiting_consent' || !job.credentials) throw new Error('Scan and confirm first');
    const c = job.credentials;
    await accountCall('/internal/wechat/confirmed', { link_id: job.id, bot_id: c.bot, sender_id: c.user, share_tasks: true });
    db.exec('BEGIN IMMEDIATE');
    try {
      db.prepare("UPDATE channels SET status='replaced' WHERE bot_id=? OR user_id=?").run(c.bot, c.user);
      db.prepare("INSERT OR REPLACE INTO channels VALUES(?,?,?,?,?,'','active')").run(job.id, c.bot, c.user, c.token, c.base);
      db.exec('COMMIT');
    } catch (error) { db.exec('ROLLBACK'); throw error; }
    job.status = 'connected'; job.credentials = null;
    void monitor(job.id);
  }
  function deliver(row, message) {
    const mid = String(message.message_id || message.client_id || '');
    if (!mid || message.from_user_id !== row.user_id || message.message_type !== 1 || message.group_id) return;
    db.prepare("INSERT OR IGNORE INTO inbox VALUES(?,?,?,'','pending')").run(row.link_id, mid, JSON.stringify(message));
  }
  async function drain(row) {
    const pending = db.prepare("SELECT * FROM inbox WHERE link_id=? AND status!='sent' ORDER BY rowid LIMIT 20").all(row.link_id);
    for (const item of pending) {
      const message = JSON.parse(item.payload);
      let reply = item.reply;
      if (!reply) {
        const text = (message.item_list || []).map(item => item.type === 1 ? item.text_item?.text : item.type === 3 ? item.voice_item?.text : '').filter(Boolean).join('\n').slice(0, 4000);
        // The service rechecks binding even for unsupported media, so a revoke stops replies.
        const result = await accountCall('/internal/wechat/inbound', { link_id: row.link_id, bot_id: row.bot_id, sender_id: row.user_id, message_id: item.message_id, text: text || '【暂不支持的媒体】' });
        reply = text ? result.reply : '照片和文件收到了。当前现场版先支持文字记录，请用文字说明已有安排或完成情况。';
        db.prepare("UPDATE inbox SET reply=?,status='ready' WHERE link_id=? AND message_id=?").run(reply, row.link_id, item.message_id);
      } else {
        // Do not send a queued reply after authorization was revoked.
        await accountCall('/internal/wechat/check', { link_id: row.link_id, bot_id: row.bot_id, sender_id: row.user_id });
      }
      const id = 'xiuxian_' + createHash('sha256').update(row.link_id + ':' + item.message_id).digest('hex').slice(0, 32);
      await botCall(row.base, '/ilink/bot/sendmessage', replyPayload(message, reply, id), row.token, 15_000);
      db.prepare("UPDATE inbox SET status='sent' WHERE link_id=? AND message_id=?").run(row.link_id, item.message_id);
    }
  }
  async function monitor(id) {
    if (monitors.has(id)) return; monitors.add(id);
    try {
      while (!stopping) {
        const row = db.prepare("SELECT * FROM channels WHERE link_id=? AND status='active'").get(id); if (!row) return;
        try {
          await accountCall('/internal/wechat/check', { link_id: row.link_id, bot_id: row.bot_id, sender_id: row.user_id });
          await drain(row);
          const value = await botCall(row.base, '/ilink/bot/getupdates', { get_updates_buf: row.cursor }, row.token);
          db.exec('BEGIN IMMEDIATE');
          try {
            for (const message of value.msgs || []) deliver(row, message);
            if (value.get_updates_buf) db.prepare('UPDATE channels SET cursor=? WHERE link_id=?').run(value.get_updates_buf, id);
            db.exec('COMMIT');
          } catch (error) { db.exec('ROLLBACK'); throw error; }
        } catch (error) {
          if (stopping) return;
          if (error.status === 403 || error.code === -14) {
            db.prepare("UPDATE channels SET status=? WHERE link_id=?").run(error.code === -14 ? 'needs_login' : 'revoked', id); return;
          }
          await pause(3000);
        }
      }
    } finally { monitors.delete(id); }
  }
  const page = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>微信 · 灵宠连接</title><style>body{background:#eef3ed;color:#284638;font:17px system-ui,'Microsoft YaHei';display:grid;min-height:100vh;margin:0;place-items:center}main{background:white;width:min(520px,86vw);padding:32px;border-radius:24px;text-align:center;box-shadow:0 18px 80px #1c493515}h1{font-size:27px}img{width:280px;max-width:90%;image-rendering:pixelated}p{line-height:1.7}button{font:inherit;background:#37694f;color:white;border:0;border-radius:10px;padding:12px 20px;margin:8px;cursor:pointer}label{display:block;line-height:1.8}small{color:#748278}input{font:inherit;padding:8px}</style><main><h1>扫码连接微信与灵宠</h1><p>对应游戏角色：<b id="label"></b><br>打开手机微信扫一扫，并在手机确认。</p><img id="qr"><p id="status">正在加载…</p><div id="consent" hidden><label><input id="agree" type="checkbox">我是这位角色对应的体验者，同意将任务安排与完成记录共享到这个游戏账号。</label><button onclick="connect()">确认角色并连接</button></div><div id="verify" hidden><input id="code" placeholder="手机显示的配对码"><button onclick="verify()">提交配对码</button></div><button onclick="refresh()">刷新二维码</button><p id="error"></p><small>微信聊天原文与登录凭证不进入游戏。<br>连接后可发送“今日任务”开始体验。</small></main><script>let gen=-1;const labels={starting:'正在申请二维码…',wait:'等待扫码',scaned:'已扫码，请在手机确认',scaned_but_redirect:'正在确认连接…',awaiting_consent:'扫码成功，请核对角色并确认共享',connected:'已连接！请在微信给机器人发送“今日任务”。',expired:'二维码已过期，请刷新',error:'微信连接失败，请刷新重试',need_verifycode:'请填写手机显示的配对码',verify_code_blocked:'尝试次数过多，请刷新',binded_redirect:'微信提示已绑定，请核对原连接'};async function call(route,data){const r=await fetch('./'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data||{})});const j=await r.json();if(!r.ok)throw Error(j.message||'连接失败');return j}async function tick(){try{const s=await(await fetch('./state')).json();document.getElementById('label').textContent=s.label;document.getElementById('status').textContent=labels[s.status]||s.status;document.getElementById('consent').hidden=s.status!=='awaiting_consent';document.getElementById('verify').hidden=s.status!=='need_verifycode';if(s.ready&&s.generation!==gen){gen=s.generation;document.getElementById('qr').src='./qr.png?v='+gen}}catch{}setTimeout(tick,1000)}async function connect(){if(!document.getElementById('agree').checked)return;try{await call('agree',{share_tasks:true})}catch(e){document.getElementById('error').textContent=e.message}}async function refresh(){try{await call('refresh')}catch{}}async function verify(){await call('verify',{code:document.getElementById('code').value});document.getElementById('code').value=''}tick()</script></html>`;
  let origin;
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('Referrer-Policy', 'no-referrer'); res.setHeader('X-Frame-Options', 'DENY'); res.setHeader('X-Content-Type-Options', 'nosniff');
    const pathname = new URL(req.url, 'http://127.0.0.1').pathname;
    function json(status, value) { res.writeHead(status, { 'Content-Type': 'application/json;charset=utf-8' }); res.end(JSON.stringify(value)); }
    async function body() { let text = ''; for await (const chunk of req) { text += chunk; if (text.length > 8192) throw new Error('Request too large'); } return JSON.parse(text || '{}'); }
    try {
      if (req.method === 'POST' && req.headers.origin && req.headers.origin !== origin) return json(403, { message: 'Origin mismatch' });
      if (['/internal/login', '/internal/status'].includes(pathname) && req.method === 'POST') {
        const provided = Buffer.from(String(req.headers['x-wechat-service-token'] || '')), expected = Buffer.from(secret);
        if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) return json(401, {});
        if (pathname === '/internal/status') return json(200, { channels: db.prepare('SELECT link_id,status FROM channels').all() });
        const input = await body();
        if (!/^[a-f0-9]{48}$/.test(input.link_id)) return json(400, {});
        const job = { id: input.link_id, label: String(input.label || '当前角色').slice(0, 24), generation: 0, status: 'starting' };
        jobs.set(job.id, job); void begin(job);
        return json(200, { login_url: origin + '/login/' + job.id + '/' });
      }
      const match = /^\/login\/([a-f0-9]{48})\/(.*)$/.exec(pathname), job = match && jobs.get(match[1]);
      if (!job) return json(404, {});
      const route = match[2];
      if (!route && req.method === 'GET') { res.writeHead(200, { 'Content-Type': 'text/html;charset=utf-8' }); return res.end(page); }
      if (route === 'state' && req.method === 'GET') return json(200, { label: job.label, status: job.status, generation: job.generation, ready: Boolean(job.image) });
      if (route === 'qr.png' && job.image) { res.writeHead(200, { 'Content-Type': 'image/png' }); return res.end(job.image); }
      if (route === 'refresh' && req.method === 'POST') { void begin(job); return json(200, {}); }
      if (route === 'verify' && req.method === 'POST') { const input = await body(); if (!/^\d{4,16}$/.test(input.code)) return json(400, {}); job.code = input.code; return json(200, {}); }
      if (route === 'agree' && req.method === 'POST') { if ((await body()).share_tasks !== true) return json(400, {}); await activate(job); return json(200, { ok: true }); }
      return json(404, {});
    } catch (error) { return json(error.status && error.status < 500 ? error.status : 503, { message: error.status ? error.message : '连接暂未完成，请稍后重试。' }); }
  });
  return { server, db, jobs,
    async start(port = 8020) {
      await new Promise(resolve => server.listen(port, '127.0.0.1', resolve)); origin = `http://127.0.0.1:${server.address().port}`;
      for (const row of db.prepare("SELECT link_id FROM channels WHERE status='active'").all()) void monitor(row.link_id);
      return origin;
    },
    async close() { stopping = true; lifecycle.abort(); await new Promise(resolve => server.close(resolve)); }
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const gateway = createGateway({ data: process.env.WECHAT_LIVE_DATA, secret: process.env.WECHAT_LIVE_SERVICE_TOKEN, accountUrl: process.env.WECHAT_LIVE_ACCOUNT_URL });
  console.log(JSON.stringify({ service: 'xiuxian-wechat-gateway', origin: await gateway.start(Number(process.env.WECHAT_LIVE_GATEWAY_PORT || 8020)) }));
}
