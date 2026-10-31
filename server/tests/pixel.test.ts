import test from 'node:test';
import assert from 'node:assert/strict';
import { dayKey, secret } from '../src/core.js';
import { defaultProviders, initialScore, pixelRules, pixelWeights, rollPixelRarity } from '../src/game/rules.js';
import { fixture } from './helpers.js';

// B 的像素玩法跑在 C 的账本上：默认规则 pixel-local-v1。
const pixel = { providers: defaultProviders };
const selfProfile = { title: '松风', avatar: 'male' };
const elderProfile = (relation = '父亲', age = 68) => ({ title: '守山人', avatar: 'male', relation, age, sex: '男', mode: 'family', consent: true });
const state = (value: number) => ({ hp_max: value, hp_current: value, attack: value, defense: value, spirit: value, stamina: value, insight: 50, mind: 50, speed: 50, luck: 50 });

async function family(context: test.TestContext, options = {}) {
  const app = await fixture(context, { ...pixel, ...options });
  const account = await app.account();
  const create = (role: string, name: string, profile: unknown) => app.command(account.token, 'growth.create_member', { role, name, profile, request_id: secret() });
  const baseline = async (cultivarId: string, value = 50, baselineId = secret()) => {
    const ticket = await app.ok('/api/v2/baselines/tickets', { cultivator_id: cultivarId }, account.token);
    return app.ok('/internal/v1/baselines', { baseline_ticket: ticket.baseline_ticket, baseline_id: baselineId, projection: { projection_version: 'legacy-pixel-v1', mapping_version: 'body_system_v2', recognition_mode: 'text', character_state: state(value), readiness: 60 } }, app.token);
  };
  const fund = (cultivarId: string, amount: number) => app.db.transaction(() => app.game.ledger.change(account.account_id, cultivarId, 'spirit_stones', amount, secret(), 'test_only'));
  const snapshot = (cultivarId: string) => app.command(account.token, 'growth.snapshot', { cultivator_id: cultivarId });
  return { app, account, create, baseline, fund, snapshot };
}

test('本人 + 最多两位老人，资料白名单与重复家人拒绝', async context => {
  const { app, account, create } = await family(context);
  const self = await create('self', '松风', selfProfile);
  assert.equal(self.role, 'self');
  assert.deepEqual(self.resources, { spirit_stones: 0, realm_xp: 0, materials: 0, seals: 0 });
  assert.equal(self.days, 0);
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.create_member', payload: { role: 'self', name: '另一个我', profile: selfProfile, request_id: secret() } }, account.token)).body.code, 'SELF_EXISTS');
  await create('elder', '王大山', elderProfile());
  const duplicate = await app.request('/api/v2/commands', { version: 1, command: 'growth.create_member', payload: { role: 'elder', name: '王大山', profile: elderProfile(), request_id: secret() } }, account.token);
  assert.equal(duplicate.body.code, 'MEMBER_EXISTS');
  await create('elder', '李秀英', { ...elderProfile('母亲', 66), sex: '女', avatar: 'female' });
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.create_member', payload: { role: 'elder', name: '第三位', profile: elderProfile('外公', 80), request_id: secret() } }, account.token)).body.code, 'MEMBER_LIMIT');
  for (const profile of [{ ...elderProfile(), relation: '本人' }, { ...elderProfile(), consent: false }, { ...elderProfile(), blood_pressure: 140 }]) {
    const code = (await app.request('/api/v2/commands', { version: 1, command: 'growth.update_member', payload: { cultivator_id: self.cultivator_id, name: 'x', profile, request_id: secret() } }, account.token)).body.code;
    assert.ok(['INVALID_MEMBER', 'CONSENT_REQUIRED'].includes(code), code);
  }
  const list = await app.command(account.token, 'growth.list', {});
  assert.deepEqual(list.cultivators.map((item: { role: string }) => item.role), ['self', 'elder', 'elder']);
});

test('首份可信初始投影冻结抽卡支持值；补充报告只更新属性；玩家不能直接写入', async context => {
  const { app, account, create, baseline, snapshot } = await family(context);
  const elder = await create('elder', '王大山', elderProfile());
  assert.equal((await app.request('/internal/v1/baselines', {}, account.token)).status, 400);
  const ticket = await app.ok('/api/v2/baselines/tickets', { cultivator_id: elder.cultivator_id }, account.token);
  const body = { baseline_ticket: ticket.baseline_ticket, baseline_id: 'b-first', projection: { projection_version: 'legacy-pixel-v1', mapping_version: 'body_system_v2', recognition_mode: 'text', character_state: state(40), readiness: 60 } };
  assert.equal((await app.request('/internal/v1/baselines', body, account.token)).body.code, 'UNAUTHORIZED');
  assert.equal((await app.request('/internal/v1/baselines', { ...body, projection: { ...body.projection, attribute_notes: { hp_max: '高血压病史' } } }, app.token)).status, 400);
  await app.ok('/internal/v1/baselines', body, app.token);
  assert.deepEqual(await app.ok('/internal/v1/baselines', body, app.token), { cultivator_id: elder.cultivator_id, baseline_id: 'b-first', initial_profile_id: 'b-first' });
  assert.equal((await app.request('/internal/v1/baselines', { ...body, baseline_id: 'b-other' }, app.token)).body.code, 'TICKET_INVALID');
  let current = await snapshot(elder.cultivator_id);
  assert.equal(current.initial_score, 40);
  await baseline(elder.cultivator_id, 90, 'b-second');
  current = await snapshot(elder.cultivator_id);
  assert.equal(current.initial_score, 40);
  assert.equal(current.initial_profile_id, 'b-first');
  assert.equal(current.baseline.baseline_id, 'b-second');
  assert.equal(current.baseline.character_state.attack, 90);
});

test('日奖励组：两项记录共享一次 100 灵气、10 修为、1 灵印、1 累计日；跨日独立', async context => {
  const { app, account, create, snapshot } = await family(context);
  const elder = await create('elder', '王大山', elderProfile());
  const binding = await app.bind(account.token, elder.cultivator_id);
  const today = dayKey(app.now());
  const medication = await app.ok(`/internal/v1/bindings/${binding.binding_id}/tasks`, { template_id: 'daily_medication_record', date: today }, app.token);
  assert.equal(medication.rule_version, pixelRules.version);
  assert.deepEqual(await app.ok(`/internal/v1/bindings/${binding.binding_id}/tasks`, { template_id: 'daily_medication_record', date: today }, app.token), medication);
  const planned = await app.assign(account.token, elder.cultivator_id, 'daily_planned_record');
  const report = (task: typeof medication, level = 'self_report') => ({ ...app.verified(binding, task), verification_level: level, source: level });
  const [first, second] = await Promise.all([app.settle(report(medication)), app.settle(report(planned, 'family_confirm'))]);
  assert.deepEqual([first.spirit_stones, first.realm_xp, first.seals], [100, 10, 1]);
  assert.deepEqual([second.spirit_stones, second.realm_xp, second.seals, second.reason], [0, 0, 0, 'daily_group_claimed']);
  let current = await snapshot(elder.cultivator_id);
  assert.deepEqual([current.resources.spirit_stones, current.resources.realm_xp, current.resources.seals, current.days], [100, 10, 1, 1]);
  // 23:59 和次日 00:01 属于两个任务日，不被滚动 24 小时限制吞掉。
  app.advance(14 * 3600 - 60);
  const late = await app.assign(account.token, elder.cultivator_id, 'daily_step_record');
  app.advance(10);
  assert.equal((await app.settle(report(late))).reason, 'daily_group_claimed');
  app.advance(120);
  const tomorrow = await app.assign(account.token, elder.cultivator_id, 'daily_step_record');
  assert.equal(tomorrow.period, dayKey(app.now()));
  assert.equal((await app.settle(report(tomorrow, 'photo'))).spirit_stones, 100);
  current = await snapshot(elder.cultivator_id);
  assert.deepEqual([current.resources.spirit_stones, current.days], [200, 2]);
  const view = await app.command(account.token, 'quests.family_today', { date: dayKey(app.now()) });
  const own = view.members.find((member: { cultivator_id: string }) => member.cultivator_id === elder.cultivator_id);
  assert.equal(own.tasks[0].status, 'settled');
  assert.equal(own.tasks[0].completion_method, 'photo');
});

test('聚宝阁：70/700、独立重复实例、两段抽样、十连末件史诗保障，幂等且不透支', async context => {
  const { app, account, create, baseline, fund } = await family(context);
  const self = await create('self', '松风', selfProfile);
  const draw = (count: number, request_id = secret()) => app.request('/api/v2/commands', { version: 1, command: 'growth.draw', payload: { cultivator_id: self.cultivator_id, count, request_id } }, account.token);
  fund(self.cultivator_id, 770);
  assert.equal((await draw(1)).body.code, 'INITIAL_PROFILE_REQUIRED');
  await baseline(self.cultivator_id, 50);
  const ten = await draw(10, 'ten');
  assert.equal(ten.status, 200, JSON.stringify(ten.body));
  assert.equal(ten.body.data.cost, 700);
  assert.equal(ten.body.data.items.length, 10);
  // randomInt 恒为 0：九件普通 + 末件保障史诗；同模板多件仍各为独立实例。
  assert.deepEqual(ten.body.data.items.map((item: { rarity_index: number }) => item.rarity_index), [0, 0, 0, 0, 0, 0, 0, 0, 0, 2]);
  assert.equal(ten.body.data.guaranteed, true);
  assert.equal(new Set(ten.body.data.items.map((item: { equipment_id: string }) => item.equipment_id)).size, 10);
  assert.equal(ten.body.data.items[0].name, '青竹剑');
  assert.deepEqual((await draw(10, 'ten')).body, ten.body);
  assert.equal((await draw(1, 'ten')).body.code, 'IDEMPOTENCY_CONFLICT');
  const [one, two] = await Promise.all([draw(1), draw(1)]);
  assert.deepEqual([one.status, two.status].sort(), [200, 409]);
  const snapshot = app.game.characterSnapshot(account.account_id, self.cultivator_id);
  assert.equal(snapshot.resources.spirit_stones, 0);
  assert.equal(snapshot.equipment.length, 11);
  assert.equal(snapshot.resources.materials, 0);
  assert.equal(snapshot.draw_count, 11);
});

test('穿戴与卸下：归属、槽位互斥、幂等', async context => {
  const { app, account, create, baseline, fund } = await family(context);
  const self = await create('self', '松风', selfProfile);
  const other = await create('elder', '王大山', elderProfile());
  await baseline(self.cultivator_id);
  fund(self.cultivator_id, 140);
  const first = await app.command(account.token, 'growth.draw', { cultivator_id: self.cultivator_id, count: 1, request_id: 'a' });
  const second = await app.command(account.token, 'growth.draw', { cultivator_id: self.cultivator_id, count: 1, request_id: 'b' });
  const [a, b] = [first.items[0], second.items[0]];
  await app.command(account.token, 'growth.equip', { cultivator_id: self.cultivator_id, equipment_id: a.equipment_id, slot: a.slot }, 'equip-a');
  const equipped = await app.command(account.token, 'growth.equip', { cultivator_id: self.cultivator_id, equipment_id: b.equipment_id, slot: b.slot }, 'equip-b');
  assert.deepEqual(equipped.equipment.filter((item: { equipped: number }) => item.equipped).map((item: { equipment_id: string }) => item.equipment_id), [b.equipment_id]);
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.equip', payload: { cultivator_id: other.cultivator_id, equipment_id: a.equipment_id, slot: a.slot } }, account.token, 'POST', 'steal')).body.code, 'INVALID_EQUIPMENT');
  const payload = { cultivator_id: self.cultivator_id, slot: 'weapon', request_id: 'off' };
  const off = await app.command(account.token, 'growth.unequip', payload);
  assert.deepEqual(await app.command(account.token, 'growth.unequip', payload), off);
  assert.equal(off.equipment.filter((item: { equipped: number }) => item.equipped).length, 0);
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'growth.unequip', payload: { ...payload, slot: 'armor_x', request_id: 'bad' } }, account.token)).body.code, 'INVALID_SLOT');
});

test('像素概率与本地规则同一函数：均值越低高品质越多，十连之外不改结果', () => {
  assert.equal(initialScore(state(150)), 100);
  assert.deepEqual(pixelWeights(pixelRules, 100), [55, 30, 11, 3.5, 0.5]);
  assert.deepEqual(pixelWeights(pixelRules, 0), [35, 33, 22, 8, 2]);
  assert.equal(rollPixelRarity(pixelRules, 100, 549_999), 0);
  assert.equal(rollPixelRarity(pixelRules, 100, 550_000), 1);
  assert.equal(rollPixelRarity(pixelRules, 100, 999_999), 4);
  assert.throws(() => rollPixelRarity(pixelRules, 50, 1_000_000), /随机/);
});

test('旧存档指纹只归属一个账号', async context => {
  const app = await fixture(context, pixel);
  const first = await app.account('first_owner');
  const second = await app.account('second_owner');
  const fingerprint = 'a'.repeat(64);
  await app.ok('/api/v2/legacy/claim', { fingerprint }, first.token);
  await app.ok('/api/v2/legacy/claim', { fingerprint }, first.token);
  assert.equal((await app.request('/api/v2/legacy/claim', { fingerprint }, second.token)).body.code, 'LEGACY_CLAIMED');
});
