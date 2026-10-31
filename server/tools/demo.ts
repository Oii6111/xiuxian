import assert from 'node:assert/strict';
import { buildApp, healthScopes } from '../src/app.js';
import { dayKey, secret } from '../src/core.js';
import { HealthClient } from '../src/integration/client.js';
import type { VerifiedResult } from '../src/integration/health.js';
import WebSocket from 'ws';

// 内存数据库 + 随机回环端口。所有人物、微信身份和验证结果都是显式联调数据。
const serviceToken = secret();
const server = await buildApp({ worker: false, services: [{ id: 'health', token: serviceToken, scopes: [...healthScopes] }] });
let socket: WebSocket | undefined;
try {
  await server.app.listen({ host: '127.0.0.1', port: 0 });
  const base = server.app.listeningOrigin;
  let bearer = '';
  const request = async (path: string, payload?: unknown, key?: string) => {
    const response = await fetch(`${base}${path}`, { method: payload === undefined ? 'GET' : 'POST', headers: { 'content-type': 'application/json', ...(bearer ? { authorization: `Bearer ${bearer}` } : {}), ...(key ? { 'idempotency-key': key } : {}) }, ...(payload !== undefined ? { body: JSON.stringify(payload) } : {}) });
    const result = await response.json() as { ok: boolean; code: string; data: any };
    assert.equal(result.ok, true, `${path}: ${result.code}`);
    return result.data;
  };
  const command = (name: string, payload: unknown, key?: string) => request('/api/v2/commands', { version: 1, command: name, payload }, key);
  await request('/api/v2/auth/register', { username: 'demo_family', password: 'local-demo-password-123' });
  bearer = (await request('/api/v2/auth/login', { username: 'demo_family', password: 'local-demo-password-123' })).token;
  // B 的家族结构：本账号下两位老人，各自独立钱包与装备。
  const elder = (name: string, relation: string, sex: string) => ({ title: name + '的化身', avatar: sex === '女' ? 'female' : 'male', relation, age: 70, sex, mode: 'family', consent: true });
  const first = await command('growth.create_member', { role: 'elder', name: '演示奶奶', profile: elder('演示奶奶', '祖母', '女'), request_id: 'create-first' });
  const second = await command('growth.create_member', { role: 'elder', name: '演示爷爷', profile: elder('演示爷爷', '祖父', '男'), request_id: 'create-second' });
  const ticket = await request('/api/v2/realtime/ticket', {});
  socket = new WebSocket(`${base.replace('http:', 'ws:')}/api/v2/realtime?ticket=${ticket.ticket}`);
  const messages: { type: string; revision: number }[] = [];
  socket.on('message', raw => messages.push(JSON.parse(raw.toString())));
  await new Promise<void>((resolve, reject) => { socket!.once('open', resolve); socket!.once('error', reject); });
  const health = new HealthClient(base, serviceToken);
  for (const [index, character] of [first, second].entries()) {
    const invite = await request('/api/v2/bindings/invitations', { cultivator_id: character.cultivator_id });
    const confirmed = await health.confirmBinding({ invite_token: invite.invite_token, channel: 'wechat_ilink', channel_account_id: 'SIMULATED_BOT', sender_id: `SIMULATED_ELDER_${index}`, elder_ref: `SIMULATED_PROFILE_${index}`, consent_proof_id: 'SIMULATED_CONSENT', consent_scope: 'family_game', health_processing: true, ai_processing: true });
    assert.equal(confirmed.ok, true);
    const binding = confirmed.data as { binding_id: string; consent_version: number };
    if (index === 1) continue;
    const ticket = await request('/api/v2/baselines/tickets', { cultivator_id: character.cultivator_id });
    const stats = { hp_max: 60, hp_current: 60, attack: 50, defense: 50, spirit: 50, stamina: 50, insight: 50, mind: 50, speed: 50, luck: 50 };
    assert.equal((await health.recordBaseline({ baseline_ticket: ticket.baseline_ticket, baseline_id: 'SIMULATED_BASELINE', projection: { projection_version: 'legacy-pixel-v1', mapping_version: 'body_system_v2', recognition_mode: 'sample', character_state: stats, readiness: 60 } })).ok, true);
    for (const templateId of ['daily_medication_record', 'daily_step_record']) {
      const now = Math.floor(Date.now() / 1000);
      const assigned = await health.assignTask(binding.binding_id, templateId, dayKey(now));
      assert.equal(assigned.ok, true);
      const task = assigned.data as { task_instance_id: string; rule_version: string };
      const input: VerifiedResult = { event_id: `SIMULATED_${templateId}`, task_instance_id: task.task_instance_id, cultivator_id: character.cultivator_id, binding_id: binding.binding_id, consent_version: binding.consent_version, verification_level: 'self_report', source: 'self_report', channel: 'wechat_ilink', observed_at: new Date(now * 1000).toISOString(), rule_version: task.rule_version };
      assert.equal((await health.verify(input)).ok, true);
      const settlement = await health.settle(input.event_id);
      assert.equal(settlement.ok, true);
      assert.deepEqual(await health.settle(input.event_id), settlement);
      assert.equal((await health.verify({ ...input, event_id: `${input.event_id}_WEB`, channel: 'family_web' })).ok, true);
      assert.deepEqual(await health.settle(`${input.event_id}_WEB`), settlement);
    }
  }
  const before = await command('growth.snapshot', { cultivator_id: first.cultivator_id });
  assert.equal(before.resources.spirit_stones, 100);
  assert.deepEqual([before.resources.realm_xp, before.resources.seals, before.days], [10, 1, 1]);
  const drawInput = { cultivator_id: first.cultivator_id, count: 1, request_id: 'draw-once' };
  const draw = await command('growth.draw', drawInput);
  assert.deepEqual(await command('growth.draw', drawInput), draw);
  assert.equal(draw.character.resources.spirit_stones, 30);
  assert.equal(draw.items.length, 1);
  assert.equal((await command('growth.snapshot', { cultivator_id: second.cultivator_id })).resources.spirit_stones, 0);
  const deliveries = await health.claimNotifications();
  assert.equal(deliveries.ok, true);
  for (const item of (deliveries.data as { notifications: { notification_id: string; lease_token: string }[] }).notifications) {
    assert.equal((await health.acknowledge(item.notification_id, item.lease_token)).ok, true);
  }
  assert.ok(messages.some(message => message.type === 'snapshot'));
  assert.ok(messages.some(message => message.type === 'state_changed'));
  console.log('LOCAL_DEMO_PASS：账号 → 两位老人隔离 → 模拟绑定 → 任务 → 模拟 D 核验 → 重复提交只结算一次 → 两项记录共享日奖励 100 灵气 → 单抽 70 后余 30 → WebSocket 同步 → 通知确认。');
  console.log('所有微信身份与核验均为模拟；没有连接真实微信或远程服务器。');
} finally { socket?.terminate(); await server.app.close(); }
