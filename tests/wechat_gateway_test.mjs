import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createGateway, parseWire, trustedBase, replyPayload, qrPng } from '../tools/wechat_live/gateway.mjs';
const delay = ms => new Promise(r => setTimeout(r, ms));
async function until(fn) { for (let i = 0; i < 150; i++) { if (fn()) return; await delay(25); } assert.fail('Timed out waiting for expected state'); }

test('wire IDs, reply scope, QR and trusted hosts', () => {
  assert.equal(parseWire('{"message_id":18446744073709551614,"text":"message_id: 123"}').message_id, '18446744073709551614');
  assert.throws(() => trustedBase('https://ilinkai.weixin.qq.com.attacker.example'));
  assert.throws(() => trustedBase('http://ilinkai.weixin.qq.com'));
  assert.throws(() => replyPayload({ from_user_id: 'user' }, 'text', 'id'));
  assert.equal(qrPng('https://weixin.qq.com/test').subarray(1, 4).toString(), 'PNG');
});

test('QR consent -> real transport paths -> durable inbox -> reply to scanner only', async () => {
  const data = mkdtempSync(path.join(tmpdir(), 'xiuxian-gateway-'));
  const secret = 'test-channel-secret-0000000000000000000';
  let confirmed = 0, inbound = 0, sent = [], updates = 0;
  const ownerMessage = { message_id: '18446744073709551614', message_type: 1, from_user_id: 'scanner-a', context_token: 'context-a', item_list: [{ type: 1, text_item: { text: '今日任务' } }] };
  const foreignMessage = { ...ownerMessage, message_id: 'foreign', from_user_id: 'another-person' };
  const fixtureFetch = async (target, options = {}) => {
    const url = new URL(target), body = options.body ? JSON.parse(options.body) : {};
    const ok = data => new Response(JSON.stringify(data), { status: 200 });
    if (url.hostname === '127.0.0.1') {
      assert.equal(options.headers['X-Wechat-Service-Token'], secret);
      if (url.pathname.endsWith('/confirmed')) { confirmed++; assert.equal(body.sender_id, 'scanner-a'); return ok({ ok: true }); }
      if (url.pathname.endsWith('/inbound')) { inbound++; assert.equal(body.sender_id, 'scanner-a'); return ok({ ok: true, reply: '对应游戏任务已同步' }); }
      if (url.pathname.endsWith('/check')) return ok({ ok: true });
      assert.fail('Unexpected account call');
    }
    if (url.pathname.endsWith('/get_bot_qrcode')) return ok({ qrcode: 'opaque-qr', qrcode_img_content: 'https://weixin.qq.com/test-qr' });
    if (url.pathname.endsWith('/get_qrcode_status')) return ok({ status: 'confirmed', bot_token: 'private-bot-token', ilink_bot_id: 'bot-a', ilink_user_id: 'scanner-a', baseurl: 'https://ilinkai.weixin.qq.com' });
    assert.equal(options.headers.Authorization, 'Bearer private-bot-token');
    if (url.pathname.endsWith('/getupdates')) {
      if (++updates <= 2) return ok({ ret: 0, msgs: [ownerMessage, foreignMessage], get_updates_buf: 'cursor-' + updates });
      return new Promise((resolve, reject) => {
        if (options.signal.aborted) return reject(new Error('aborted'));
        options.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
      });
    }
    if (url.pathname.endsWith('/sendmessage')) { sent.push(body); return ok({ ret: 0 }); }
    assert.fail('Unexpected Weixin endpoint');
  };
  const gateway = createGateway({ data, secret, accountUrl: 'http://127.0.0.1:8010', fetcher: fixtureFetch });
  try {
    const origin = await gateway.start(0), linkId = 'a'.repeat(48);
    assert.equal((await fetch(origin + '/internal/login', { method: 'POST', body: '{}' })).status, 401);
    const created = await (await fetch(origin + '/internal/login', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Wechat-Service-Token': secret }, body: JSON.stringify({ link_id: linkId, label: '本人' }) })).json();
    await until(() => gateway.jobs.get(linkId).status === 'awaiting_consent');
    assert.equal(confirmed, 0); assert.equal(inbound, 0);
    const stateText = await (await fetch(created.login_url + 'state')).text();
    assert.ok(!stateText.includes('private-bot-token'));
    assert.equal((await fetch(created.login_url + 'agree', { method: 'POST', body: '{}' })).status, 400);
    assert.equal((await fetch(created.login_url + 'agree', { method: 'POST', body: JSON.stringify({ share_tasks: true }) })).status, 200);
    await until(() => sent.length === 1 && updates >= 3);
    assert.equal(confirmed, 1); assert.equal(inbound, 1); assert.equal(sent[0].msg.to_user_id, 'scanner-a');
    assert.equal(sent[0].msg.context_token, 'context-a');
    assert.equal(gateway.db.prepare('SELECT count(*) AS n FROM inbox').get().n, 1);
    assert.equal(gateway.db.prepare('SELECT status FROM inbox').get().status, 'sent');
    assert.equal(gateway.db.prepare('SELECT cursor FROM channels').get().cursor, 'cursor-2');
  } finally {
    await gateway.close(); await delay(100); gateway.db.close();
    assert.ok(path.resolve(data).startsWith(path.resolve(tmpdir()) + path.sep));
    rmSync(data, { recursive: true, force: true });
  }
});
