import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Database } from '../src/database.js';
import { defaultProviders, integrationRules, integrationTemplates, calculateReward } from '../src/game/rules.js';
import { commands, contract } from '../src/contracts.js';
import { dayKey, dayStart, secret } from '../src/core.js';
import { buildApp, healthScopes } from '../src/app.js';
import { fixture } from './helpers.js';

test('账号规范化、密码摘要、统一登录失败及会话撤销', async context => {
  const app = await fixture(context);
  const account = await app.account('Test_User');
  assert.equal(account.username, 'test_user');
  assert.equal((await app.request('/api/v2/auth/register', { username: ' TEST_USER ', password: 'different-password-123' })).status, 409);
  const wrong = await app.request('/api/v2/auth/login', { username: 'test_user', password: 'wrong-password-123' });
  const missing = await app.request('/api/v2/auth/login', { username: 'missing_user', password: 'wrong-password-123' });
  assert.deepEqual(wrong.body, missing.body);
  const raw = JSON.stringify(app.db.all('SELECT * FROM accounts')) + JSON.stringify(app.db.all('SELECT * FROM sessions'));
  assert.ok(!raw.includes('a-secure-password-123') && !raw.includes(account.token));
  const otherSession = await app.ok('/api/v2/auth/login', { username: 'test_user', password: 'a-secure-password-123' });
  await app.ok('/api/v2/auth/logout', {}, account.token);
  assert.equal((await app.request('/api/v2/auth/me', undefined, account.token)).status, 401);
  await app.ok('/api/v2/auth/logout-all', {}, otherSession.token);
  assert.equal((await app.request('/api/v2/auth/me', undefined, otherSession.token)).status, 401);
});

test('密码长度、登录限速和会话到期', async context => {
  const app = await fixture(context);
  assert.equal((await app.request('/api/v2/auth/register', { username: 'short', password: 'short' })).body.code, 'INVALID_PASSWORD');
  const account = await app.account();
  for (let index = 0; index < 5; index++) assert.equal((await app.request('/api/v2/auth/login', { username: 'tester', password: 'incorrect' })).status, 401);
  assert.equal((await app.request('/api/v2/auth/login', { username: 'tester', password: 'incorrect' })).status, 429);
  app.advance(7 * 86400 + 1);
  assert.equal((await app.request('/api/v2/auth/me', undefined, account.token)).status, 401);
});

test('共享命令登记、严格字段检查、未知业务不伪造成功', async context => {
  const app = await fixture(context);
  const account = await app.account();
  assert.equal(contract.modules.length, 7);
  for (const module of contract.modules) for (const command of Object.keys(module.commands)) assert.ok(command.startsWith(`${module.id}.`));
  assert.ok(app.app.swagger().paths?.['/api/v2/commands']);
  assert.ok(commands['quests.assign']);
  const leaked = await app.request('/api/v2/commands', { version: 1, command: 'growth.create', payload: { name: 'sample', element: 'water', blood_glucose: 8 } }, account.token, 'POST', 'create');
  assert.equal(leaked.status, 400);
  const unsupported = await app.request('/api/v2/commands', { version: 1, command: 'combat.start', payload: { cultivator_id: 'sample', encounter_id: 'sample' } }, account.token);
  assert.equal(unsupported.body.code, 'NOT_IMPLEMENTED');
  assert.equal((await app.request('/api/v2/snapshot')).status, 401);
});

test('写操作幂等、同键冲突与角色归属校验', async context => {
  const app = await fixture(context);
  const first = await app.account('first_user');
  const second = await app.account('second_user');
  const character = await app.character(first.token, 'creation');
  assert.deepEqual(await app.character(first.token, 'creation'), character);
  const conflict = await app.request('/api/v2/commands', { version: 1, command: 'growth.create', payload: { name: 'different', element: 'wood' } }, first.token, 'POST', 'creation');
  assert.equal(conflict.body.code, 'IDEMPOTENCY_CONFLICT');
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.snapshot', payload: { cultivator_id: character.cultivator_id } }, second.token)).status, 404);
  assert.equal((await app.command(first.token, 'growth.list', {})).cultivators.length, 1);
});

test('D 内部接口拒绝玩家会话并检查服务作用域', async context => {
  const readToken = secret();
  const app = await fixture(context, { services: [{ id: 'reader', token: readToken, scopes: ['task:read'] }] });
  const account = await app.account();
  assert.equal((await app.request('/internal/v1/notifications/claim', { limit: 1 }, account.token)).status, 401);
  assert.equal((await app.request('/internal/v1/notifications/claim', { limit: 1 }, readToken)).status, 403);
});

test('邀请一次性、过期、身份冲突及授权分离', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  const invite = await app.ok('/api/v2/bindings/invitations', { cultivator_id: character.cultivator_id }, account.token);
  const body = { invite_token: invite.invite_token, channel: 'wechat_ilink', channel_account_id: 'bot', sender_id: 'elder', elder_ref: 'elder-ref', consent_proof_id: 'proof', consent_scope: 'family_game', health_processing: true, ai_processing: true };
  assert.equal((await app.request('/internal/v1/bindings/confirm', { ...body, health_processing: false }, app.token)).body.code, 'CONSENT_REQUIRED');
  const binding = await app.ok('/internal/v1/bindings/confirm', body, app.token);
  assert.deepEqual(await app.ok('/internal/v1/bindings/confirm', body, app.token), binding);
  assert.equal((await app.request('/internal/v1/bindings/confirm', { ...body, sender_id: 'changed' }, app.token)).body.code, 'INVITE_INVALID');
  await app.ok(`/internal/v1/bindings/${binding.binding_id}/connection`, { connected: false }, app.token);
  const listed = await app.ok(`/api/v2/bindings?cultivator_id=${character.cultivator_id}`, undefined, account.token);
  assert.equal(listed.bindings[0].connected, false);
  assert.equal(listed.bindings[0].consent_status, 'active');
  assert.ok(!JSON.stringify(listed).includes('elder-ref'));
  const other = await app.character(account.token);
  const otherInvite = await app.ok('/api/v2/bindings/invitations', { cultivator_id: other.cultivator_id }, account.token);
  assert.equal((await app.request('/internal/v1/bindings/confirm', { ...body, invite_token: otherInvite.invite_token }, app.token)).body.code, 'BINDING_CONFLICT');
  app.advance(601);
  assert.equal((await app.request('/internal/v1/bindings/confirm', { ...body, invite_token: otherInvite.invite_token, sender_id: 'another' }, app.token)).body.code, 'INVITE_INVALID');
});

test('健康闭环：重复派发、重复事件、跨渠道和手动领取均只结算一次', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  const other = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const task = await app.assign(account.token, character.cultivator_id);
  assert.equal((await app.assign(account.token, character.cultivator_id)).task_instance_id, task.task_instance_id);
  const verified = app.verified(binding, task);
  const settlement = await app.settle(verified);
  assert.equal(settlement.spirit_stones, 6);
  assert.equal(settlement.realm_xp, 16);
  assert.deepEqual(await app.settle(verified), settlement);
  assert.deepEqual(await app.settle({ ...verified, event_id: secret(), channel: 'family_web' }), settlement);
  const claimed = await app.command(account.token, 'quests.claim', { cultivator_id: character.cultivator_id, quest_id: task.task_instance_id, request_id: secret() });
  assert.equal(claimed.settlement.settlement_id, settlement.settlement_id);
  assert.equal((await app.command(account.token, 'growth.snapshot', { cultivator_id: character.cultivator_id })).resources.spirit_stones, 6);
  assert.equal((await app.command(account.token, 'growth.snapshot', { cultivator_id: other.cultivator_id })).resources.spirit_stones, 0);
  assert.equal(app.db.all('SELECT * FROM settlements').length, 1);
  assert.equal(app.db.all('SELECT * FROM outbox').length, 1);
  assert.equal((await app.request('/internal/v1/task-results', { ...verified, verification_level: 'family_confirm', source: 'family_confirm' }, app.token)).body.code, 'EVENT_CONFLICT');
});

test('验证窗口、规则版本、设备照片及敏感字段拒绝', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const task = await app.assign(account.token, character.cultivator_id);
  const verified = app.verified(binding, task);
  for (const change of [{ verification_level: 'device' }, { source: 'device', verification_level: 'device' }, { rule_version: 'future' }]) assert.equal((await app.request('/internal/v1/task-results', { ...verified, ...change }, app.token)).body.code, 'VERIFICATION_INVALID');
  assert.equal((await app.request('/internal/v1/task-results', { ...verified, observed_at: '2026-11-01T00:00:00+08:00' }, app.token)).body.code, 'TASK_WINDOW');
  assert.equal((await app.request('/internal/v1/task-results', { ...verified, source_document: { diagnosis: 'private' } }, app.token)).status, 400);
  assert.equal(app.db.all('SELECT * FROM verified_results').length, 0);
});

test('提交状态序号防回退，已结算任务不能被迟到状态降级', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const task = await app.assign(account.token, character.cultivator_id);
  const body = { submission_id: 'submission1', task_instance_id: task.task_instance_id, binding_id: binding.binding_id, consent_version: 1, sequence: 2, status: 'pending_confirmation' };
  await app.ok('/internal/v1/submissions/status', body, app.token);
  assert.equal((await app.ok('/internal/v1/submissions/status', { ...body, sequence: 1, status: 'received' }, app.token)).status, 'pending_confirmation');
  await app.settle(app.verified(binding, task));
  assert.equal((await app.ok('/internal/v1/submissions/status', { ...body, sequence: 3, status: 'rejected' }, app.token)).status, 'settled');
});

test('授权撤回拦截待结算并取消未送达通知，已到账不消失', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const settledTask = await app.assign(account.token, character.cultivator_id);
  const pendingTask = await app.assign(account.token, character.cultivator_id, 'daily_measurement_record');
  await app.settle(app.verified(binding, settledTask));
  const pending = app.verified(binding, pendingTask);
  await app.ok('/internal/v1/task-results', pending, app.token);
  await app.ok(`/api/v2/bindings/${binding.binding_id}/revoke`, {}, account.token);
  assert.equal((await app.request(`/internal/v1/task-results/${pending.event_id}/settle`, {}, app.token)).body.code, 'CONSENT_REVOKED');
  app.health.processPending();
  assert.equal(app.health.result('health', pending.event_id).status, 'blocked');
  assert.equal((await app.ok('/internal/v1/notifications/claim', { limit: 20 }, app.token)).notifications.length, 0);
  assert.equal((await app.command(account.token, 'growth.snapshot', { cultivator_id: character.cultivator_id })).resources.spirit_stones, 6);
  assert.equal((await app.request('/internal/v1/task-results', { ...pending, event_id: secret() }, app.token)).body.code, 'CONSENT_REVOKED');
});

test('通知失败退避、租约重领、迟到确认及重复确认不影响账本', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  await app.settle(app.verified(binding, await app.assign(account.token, character.cultivator_id)));
  const first = (await app.ok('/internal/v1/notifications/claim', { limit: 20 }, app.token)).notifications[0];
  assert.equal((await app.ok('/internal/v1/notifications/claim', { limit: 20 }, app.token)).notifications.length, 0);
  await app.ok(`/internal/v1/notifications/${first.notification_id}/nack`, { lease_token: first.lease_token }, app.token);
  app.advance(3);
  const second = (await app.ok('/internal/v1/notifications/claim', { limit: 20 }, app.token)).notifications[0];
  app.advance(31);
  const third = (await app.ok('/internal/v1/notifications/claim', { limit: 20 }, app.token)).notifications[0];
  assert.equal((await app.request(`/internal/v1/notifications/${second.notification_id}/ack`, { lease_token: second.lease_token }, app.token)).body.code, 'LEASE_CONFLICT');
  for (let index = 0; index < 2; index++) await app.ok(`/internal/v1/notifications/${third.notification_id}/ack`, { lease_token: third.lease_token }, app.token);
  assert.equal(app.db.all('SELECT * FROM settlements').length, 1);
  assert.equal(app.db.all('SELECT * FROM ledger').length, 2);
});

test('奖励倍率、补偿、向下取整与上限顺序', () => {
  const template = integrationTemplates[0]!;
  for (const [level, expected] of [['device', 8], ['photo', 6], ['family_confirm', 4], ['self_report', 2]] as const) assert.equal(calculateReward(integrationRules, template, level, 0, 30).spirit_stones, expected);
  for (const tier of [0, 1, 2, 3]) assert.equal(calculateReward(integrationRules, template, 'photo', tier, 30).spirit_stones, Math.floor(8 * .8 * (1 + tier / 10)));
  assert.deepEqual(calculateReward(integrationRules, template, 'photo', 3, 2), { spirit_stones: 2, realm_xp: 16 });
  assert.equal(dayKey(dayStart('2026-11-01') - 1), '2026-10-31');
});

test('日上限、同类滚动 24 小时和完成零奖励仍被记录', async context => {
  const templates = [0, 1, 2, 3].map(index => ({ ...integrationTemplates[0]!, id: `template_${index}`, event_type: index === 3 ? 'type_0' : `type_${index}`, base_stones: 25 }));
  const app = await fixture(context, { providers: { ...defaultProviders, templates: () => templates } });
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const rewards = [];
  for (const template of templates) rewards.push(await app.settle(app.verified(binding, await app.assign(account.token, character.cultivator_id, template.id))));
  assert.deepEqual(rewards.map(item => item.spirit_stones), [20, 10, 0, 0]);
  assert.equal(rewards[3].reason, 'same_type_limit');
  app.advance(15 * 3600);
  assert.equal((await app.settle(app.verified(binding, await app.assign(account.token, character.cultivator_id, 'template_0')))).spirit_stones, 0);
  app.advance(9 * 3600);
  assert.equal((await app.settle(app.verified(binding, await app.assign(account.token, character.cultivator_id, 'template_3')))).spirit_stones, 20);
});

test('结算事务失败全回滚，重试及并发请求只提交一次', async context => {
  let fail = true;
  const app = await fixture(context, { beforeSettlementCommit: () => { if (fail) throw new Error('injected'); } });
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const verified = app.verified(binding, await app.assign(account.token, character.cultivator_id));
  await app.ok('/internal/v1/task-results', verified, app.token);
  assert.equal((await app.request(`/internal/v1/task-results/${verified.event_id}/settle`, {}, app.token)).status, 500);
  for (const table of ['ledger', 'settlements', 'outbox']) assert.equal(app.db.all(`SELECT * FROM ${table}`).length, 0);
  assert.equal(app.game.own(account.account_id, character.cultivator_id).spirit_stones, 0);
  fail = false;
  const results = await Promise.all(Array.from({ length: 8 }, () => app.ok(`/internal/v1/task-results/${verified.event_id}/settle`, {}, app.token)));
  assert.equal(new Set(results.map(result => result.settlement_id)).size, 1);
  assert.equal(app.db.all('SELECT * FROM settlements').length, 1);
});

test('抽卡事务、十连保底、重复转换和幂等并发扣费', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  app.db.transaction(() => app.game.ledger.change(account.account_id, character.cultivator_id, 'spirit_stones', 100, 'fixture', 'test_only'));
  const payload = { cultivator_id: character.cultivator_id, count: 10, request_id: 'draw-once' };
  const [draw, replay] = await Promise.all([app.command(account.token, 'growth.draw', payload), app.command(account.token, 'growth.draw', payload)]);
  assert.deepEqual(draw, replay);
  assert.equal(draw.items[9].rarity, 'spirit');
  assert.equal(draw.character.resources.spirit_stones, 0);
  assert.equal(draw.character.resources.materials, 8);
  assert.equal(draw.character.equipment.length, 2);
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.draw', payload: { ...payload, request_id: 'another' } }, account.token)).body.code, 'INSUFFICIENT_FUNDS');
  const equipment = draw.character.equipment[0];
  const equipped = await app.command(account.token, 'growth.equip', { cultivator_id: character.cultivator_id, equipment_id: equipment.equipment_id, slot: equipment.slot }, 'equip');
  assert.equal(equipped.equipment.filter((item: { equipped: number }) => item.equipped).length, 1);
});

test('仙品保底四档和角色保底隔离', async context => {
  for (const tier of [0, 1, 2, 3]) {
    const app = await fixture(context, { providers: { ...defaultProviders, compensation: () => tier } });
    const account = await app.account();
    const character = await app.character(account.token);
    const other = await app.character(account.token);
    app.db.transaction(() => {
      app.game.ledger.change(account.account_id, character.cultivator_id, 'spirit_stones', 10, 'fixture', 'test_only');
      app.db.run('UPDATE cultivators SET pity = ? WHERE id = ?', integrationRules.pity_limits[tier]! - 1, character.cultivator_id);
    });
    const draw = await app.command(account.token, 'growth.draw', { cultivator_id: character.cultivator_id, count: 1, request_id: 'pity' });
    assert.equal(draw.items[0].rarity, 'immortal');
    assert.equal(draw.character.pity, 0);
    assert.equal(app.game.own(account.account_id, other.cultivator_id).pity, 0);
  }
});

test('抽卡中途随机提供方出错时扣费和已生成装备全部回滚', async context => {
  let calls = 0;
  const app = await fixture(context, { randomInt: () => { calls++; return calls <= 2 ? 0 : 10000; } });
  const account = await app.account();
  const character = await app.character(account.token);
  app.db.transaction(() => app.game.ledger.change(account.account_id, character.cultivator_id, 'spirit_stones', 100, 'fixture', 'test_only'));
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.draw', payload: { cultivator_id: character.cultivator_id, count: 10, request_id: 'failure' } }, account.token)).body.code, 'INVALID_RANDOM');
  assert.equal(app.game.own(account.account_id, character.cultivator_id).spirit_stones, 100);
  assert.equal(app.db.all('SELECT * FROM equipment').length, 0);
  assert.equal(app.db.all("SELECT * FROM ledger WHERE reason = 'draw'").length, 0);
});

test('服务重启保留会话、幂等结果、待结算事实和通知', async context => {
  const folder = mkdtempSync(join(tmpdir(), 'xiuxian-backend-'));
  context.after(() => rmSync(folder, { recursive: true, force: true }));
  const token = secret();
  const options = { databasePath: join(folder, 'game.sqlite'), now: () => Date.parse('2026-10-31T10:00:00+08:00') / 1000, worker: false, services: [{ id: 'health', token, scopes: [...healthScopes] }] };
  const first = await buildApp(options);
  const account = await first.auth.register({ username: 'persist', password: 'secure-password-123' });
  const login = await first.auth.login({ username: 'persist', password: 'secure-password-123' });
  const character = first.game.execute(account.account_id, 'growth.create', { name: 'persistent', element: 'water' }, 'create') as { cultivator_id: string };
  const invite = first.bindings.invite(account.account_id, character.cultivator_id);
  const binding = first.bindings.confirm({ invite_token: invite.invite_token, channel: 'wechat_ilink', channel_account_id: 'bot', sender_id: 'sender', elder_ref: 'elder', consent_proof_id: 'proof', consent_scope: 'family_game', health_processing: true, ai_processing: true });
  const task = first.game.execute(account.account_id, 'quests.assign', { cultivator_id: character.cultivator_id, template_id: 'daily_step_record', date: '2026-10-31', request_id: 'task' }) as { task_instance_id: string };
  first.health.receive('health', { event_id: 'persisted', task_instance_id: task.task_instance_id, cultivator_id: character.cultivator_id, binding_id: binding.binding_id, consent_version: 1, verification_level: 'photo', source: 'photo', channel: 'wechat_ilink', observed_at: '2026-10-31T10:00:00+08:00', rule_version: 'integration-v1' });
  await first.app.close();
  const second = await buildApp(options);
  second.auth.authenticate(`Bearer ${login.token}`);
  second.health.processPending();
  assert.equal(second.health.result('health', 'persisted').status, 'settled');
  assert.equal(second.db.all('SELECT * FROM outbox').length, 1);
  assert.deepEqual(second.game.execute(account.account_id, 'growth.create', { name: 'persistent', element: 'water' }, 'create'), character);
  await second.app.close();
});

test('未来数据库版本及迁移内容变化停止启动', () => {
  const folder = mkdtempSync(join(tmpdir(), 'xiuxian-migration-'));
  try {
    const path = join(folder, 'game.sqlite');
    const initial = new Database(path); initial.close();
    const raw = new DatabaseSync(path);
    raw.exec('PRAGMA user_version = 999'); raw.close();
    assert.throws(() => new Database(path), /数据库版本/);
    const changed = new DatabaseSync(path);
    changed.exec("PRAGMA user_version = 1; UPDATE schema_migrations SET checksum = 'changed'"); changed.close();
    assert.throws(() => new Database(path), /迁移被修改/);
  } finally { rmSync(folder, { recursive: true, force: true }); }
});

test('赛季日历边界与永久积累保持', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const character = await app.character(account.token);
  app.db.transaction(() => app.game.ledger.change(account.account_id, character.cultivator_id, 'materials', 12, 'fixture', 'test_only'));
  const before = app.game.characterSnapshot(account.account_id, character.cultivator_id);
  const oldSeason = app.game.execute(account.account_id, 'season.refresh', { cultivator_id: character.cultivator_id }) as { current: { id: string } };
  app.advance(dayStart('2027-01-01') - app.now());
  const newSeason = app.game.execute(account.account_id, 'season.refresh', { cultivator_id: character.cultivator_id }) as { current: { id: string } };
  assert.notEqual(newSeason.current.id, oldSeason.current.id);
  assert.deepEqual(app.game.characterSnapshot(account.account_id, character.cultivator_id), before);
});

test('扩展模块输出必须经过白名单验证', async context => {
  const app = await fixture(context, { extensions: { commands: { 'combat.start': {
    execute: () => ({ session_id: 'session', source_document: { blood_glucose: 9 } }),
    validateOutput: value => typeof value === 'object' && value !== null && Object.keys(value).length === 1 && 'session_id' in value,
  } } } });
  const account = await app.account();
  const response = await app.request('/api/v2/commands', { version: 1, command: 'combat.start', payload: { cultivator_id: 'test', encounter_id: 'test' } }, account.token);
  assert.equal(response.body.code, 'INVALID_PROJECTION');
  assert.ok(!JSON.stringify(response.body).includes('blood_glucose'));
});

test('不同请求并发抽卡不会超额扣款，神品不被保底降级', async context => {
  const app = await fixture(context, { randomInt: maximum => maximum === 10000 ? 9999 : 0 });
  const account = await app.account();
  const character = await app.character(account.token);
  app.db.transaction(() => {
    app.game.ledger.change(account.account_id, character.cultivator_id, 'spirit_stones', 10, 'fixture', 'test_only');
    app.db.run('UPDATE cultivators SET pity = 79 WHERE id = ?', character.cultivator_id);
  });
  const requests = await Promise.all(Array.from({ length: 5 }, (_, index) => app.request('/api/v2/commands', { version: 1, command: 'growth.draw', payload: { cultivator_id: character.cultivator_id, count: 1, request_id: `draw-${index}` } }, account.token)));
  const successful = requests.filter(response => response.body.ok);
  assert.equal(successful.length, 1);
  assert.equal(successful[0]!.body.data.items[0].rarity, 'divine');
  assert.equal(successful[0]!.body.data.character.pity, 0);
  assert.equal(app.game.own(account.account_id, character.cultivator_id).spirit_stones, 0);
});

test('账本强制事务和资源归属，功德只属于童子', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const other = await app.account('other_user');
  const character = await app.character(account.token);
  assert.throws(() => app.game.ledger.change(account.account_id, character.cultivator_id, 'spirit_stones', 1, 'outside', 'test'), /事务/);
  assert.throws(() => app.db.transaction(() => app.game.ledger.change(other.account_id, character.cultivator_id, 'spirit_stones', 1, 'wrong-owner', 'test')), /不属于/);
  assert.throws(() => app.db.transaction(() => app.game.ledger.change(account.account_id, character.cultivator_id, 'merit', 1, 'wrong-type', 'test')), /归属/);
  app.db.transaction(() => app.game.ledger.change(account.account_id, null, 'merit', 3, 'merit', 'test'));
  assert.equal(app.game.snapshot(account.account_id).merit, 3);
  assert.equal(app.game.snapshot(other.account_id).merit, 0);
});

test('结算工作器退避后自动恢复，不重发已结算任务', async context => {
  let fail = true;
  const app = await fixture(context, { beforeSettlementCommit: () => { if (fail) throw new Error('transient'); } });
  const account = await app.account();
  const character = await app.character(account.token);
  const binding = await app.bind(account.token, character.cultivator_id);
  const input = app.verified(binding, await app.assign(account.token, character.cultivator_id));
  await app.ok('/internal/v1/task-results', input, app.token);
  app.health.processPending();
  assert.equal(app.health.result('health', input.event_id).error_code, 'SETTLEMENT_RETRY');
  fail = false;
  app.health.processPending();
  assert.equal(app.health.result('health', input.event_id).status, 'pending');
  app.advance(3);
  app.health.processPending();
  app.health.processPending();
  assert.equal(app.health.result('health', input.event_id).status, 'settled');
  assert.equal(app.db.all('SELECT * FROM settlements').length, 1);
});

test('错误角色绑定、任务时间和版本不会进入结算', async context => {
  const app = await fixture(context);
  const account = await app.account();
  const first = await app.character(account.token);
  const second = await app.character(account.token);
  const firstBinding = await app.bind(account.token, first.cultivator_id);
  const secondBinding = await app.bind(account.token, second.cultivator_id);
  const task = await app.assign(account.token, first.cultivator_id);
  const input = app.verified(firstBinding, task);
  assert.equal((await app.request('/internal/v1/task-results', { ...input, binding_id: secondBinding.binding_id }, app.token)).body.code, 'CONSENT_REVOKED');
  assert.equal((await app.request('/internal/v1/task-results', { ...input, consent_version: 2 }, app.token)).body.code, 'CONSENT_REVOKED');
  assert.equal((await app.request('/internal/v1/task-results', { ...input, observed_at: '2026-10-30T10:00:00+08:00' }, app.token)).body.code, 'TASK_WINDOW');
});
