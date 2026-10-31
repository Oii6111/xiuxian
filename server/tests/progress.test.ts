import test from 'node:test';
import assert from 'node:assert/strict';
import { secret } from '../src/core.js';
import { defaultProviders } from '../src/game/rules.js';
import { fixture } from './helpers.js';

// A 的战斗与生命周期在 C 上执行：确认令牌、首通唯一、出战资格，战斗不产生资源。
async function setup(context: test.TestContext) {
  const app = await fixture(context, { providers: defaultProviders });
  const account = await app.account();
  const elder = await app.command(account.token, 'growth.create_member', { role: 'elder', name: '张建国', request_id: secret(), profile: { title: '青松', avatar: 'male', relation: '父亲', age: 68, sex: '男', mode: 'family', consent: true } });
  const run = (command: string, payload: unknown) => app.request('/api/v2/commands', { version: 1, command, payload }, account.token);
  return { app, account, elder, run };
}

test('生命周期：确认令牌、飞升二次确认、非法迁移与过期', async context => {
  const { app, account, elder, run } = await setup(context);
  const id = elder.cultivator_id;
  assert.equal((await run('lifecycle.request_change', { cultivator_id: id, target_state: 'ascended' })).body.code, 'INVALID_TRANSITION');
  const ticket = (await run('lifecycle.request_change', { cultivator_id: id, target_state: 'tribulation' })).body.data;
  assert.equal(ticket.confirmations_required, 1);
  const confirm = { cultivator_id: id, confirmation_token: ticket.confirmation_token, request_id: 'confirm-1' };
  const done = (await run('lifecycle.confirm_change', confirm)).body.data;
  assert.deepEqual([done.complete, done.state, done.version], [true, 'tribulation', 1]);
  assert.deepEqual((await run('lifecycle.confirm_change', confirm)).body.data, done);
  assert.equal((await run('lifecycle.update_stage', { cultivator_id: id, stage_id: 'cardio.admission', confirmation_token: 'stage-1' })).body.data.version, 2);
  assert.equal((await run('lifecycle.update_stage', { cultivator_id: id, stage_id: 'fracture.preop', confirmation_token: 'stage-2' })).body.code, 'INVALID_STAGE');
  const ascend = (await run('lifecycle.request_change', { cultivator_id: id, target_state: 'ascended' })).body.data;
  assert.equal(ascend.confirmations_required, 2);
  const first = (await run('lifecycle.confirm_change', { cultivator_id: id, confirmation_token: ascend.confirmation_token, request_id: 'a1' })).body.data;
  assert.deepEqual([first.complete, first.remaining], [false, 1]);
  assert.equal((await app.command(account.token, 'growth.snapshot', { cultivator_id: id })).lifecycle, 'tribulation');
  app.advance(301);
  assert.equal((await run('lifecycle.confirm_change', { cultivator_id: id, confirmation_token: ascend.confirmation_token, request_id: 'a2' })).body.code, 'TOKEN_EXPIRED');
  const other = await app.account('other_user');
  assert.equal((await app.request('/api/v2/commands', { version: 1, command: 'lifecycle.request_change', payload: { cultivator_id: id, target_state: 'cultivating' } }, other.token)).body.code, 'NOT_FOUND');
});

test('战斗会话：只允许修行状态出战，首通唯一，重复提交返回原战果，不产生资源', async context => {
  const { app, account, elder, run } = await setup(context);
  const id = elder.cultivator_id;
  assert.equal((await run('combat.start', { cultivator_id: id, encounter_id: 'b99' })).body.code, 'ENCOUNTER_UNAVAILABLE');
  const session = (await run('combat.start', { cultivator_id: id, encounter_id: 'b00' })).body.data;
  assert.equal((await run('combat.finish', { session_id: session.session_id, won: true, duration_seconds: 30 })).body.code, 'INVALID_RESULT');
  app.advance(40);
  assert.equal((await run('combat.finish', { session_id: session.session_id, won: true, duration_seconds: 1 })).body.code, 'INVALID_RESULT');
  const result = (await run('combat.finish', { session_id: session.session_id, won: true, duration_seconds: 32.5 })).body.data;
  assert.deepEqual([result.first_clear, result.cleared_count, result.replayed], [true, 1, false]);
  assert.equal((await run('combat.finish', { session_id: session.session_id, won: true, duration_seconds: 32.5 })).body.data.replayed, true);
  assert.equal((await run('combat.finish', { session_id: session.session_id, won: false, duration_seconds: 32.5 })).body.code, 'SESSION_CONFLICT');
  const again = (await run('combat.start', { cultivator_id: id, encounter_id: 'b00' })).body.data;
  app.advance(30);
  const replay = (await run('combat.finish', { session_id: again.session_id, won: true, duration_seconds: 20 })).body.data;
  assert.deepEqual([replay.first_clear, replay.cleared_count], [false, 1]);
  const snapshot = await app.command(account.token, 'growth.snapshot', { cultivator_id: id });
  assert.deepEqual(snapshot.progress.cleared_bosses, [{ boss_id: 'b00', best_seconds: 20 }]);
  assert.deepEqual(snapshot.resources, { spirit_stones: 0, realm_xp: 0, materials: 0, seals: 0 });
  const ticket = (await run('lifecycle.request_change', { cultivator_id: id, target_state: 'tribulation' })).body.data;
  await run('lifecycle.confirm_change', { cultivator_id: id, confirmation_token: ticket.confirmation_token, request_id: secret() });
  assert.equal((await run('combat.start', { cultivator_id: id, encounter_id: 'b01' })).body.code, 'NOT_ALLOWED');
});
