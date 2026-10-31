import assert from 'node:assert/strict';
import type { TestContext } from 'node:test';
import { buildApp, healthScopes, type AppOptions } from '../src/app.js';
import { integrationProviders } from '../src/game/rules.js';
import { dayKey, secret } from '../src/core.js';

export async function fixture(test: TestContext, options: AppOptions = {}) {
  let timestamp = Date.parse('2026-10-31T10:00:00+08:00') / 1000;
  const token = secret();
  const server = await buildApp({ now: () => timestamp, worker: false, services: [{ id: 'health', token, scopes: [...healthScopes] }], randomInt: () => 0, providers: integrationProviders, ...options });
  test.after(async () => { await server.app.close(); });
  const request = async (path: string, body?: unknown, bearer?: string, method?: 'GET' | 'POST' | 'DELETE', key?: string) => {
    const response = await server.app.inject({ method: method ?? (body === undefined ? 'GET' : 'POST'), url: path, headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...(bearer ? { authorization: `Bearer ${bearer}` } : {}), ...(key ? { 'idempotency-key': key } : {}) }, ...(body !== undefined ? { payload: JSON.stringify(body) } : {}) });
    return { status: response.statusCode, body: response.json() };
  };
  const ok = async (path: string, body?: unknown, bearer?: string, method?: 'GET' | 'POST' | 'DELETE', key?: string) => {
    const response = await request(path, body, bearer, method, key);
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assert.equal(response.body.ok, true);
    return response.body.data;
  };
  const account = async (username = 'tester') => {
    await ok('/api/v2/auth/register', { username, password: 'a-secure-password-123' });
    return ok('/api/v2/auth/login', { username, password: 'a-secure-password-123' });
  };
  const command = (bearer: string, name: string, payload: unknown, key?: string) => ok('/api/v2/commands', { version: 1, command: name, payload }, bearer, 'POST', key);
  const character = (bearer: string, key = secret()) => command(bearer, 'growth.create', { name: '联调修仙者', element: 'water' }, key);
  const bind = async (bearer: string, cultivarId: string, sender = secret()) => {
    const invite = await ok('/api/v2/bindings/invitations', { cultivator_id: cultivarId }, bearer);
    return ok('/internal/v1/bindings/confirm', { invite_token: invite.invite_token, channel: 'wechat_ilink', channel_account_id: 'local-bot', sender_id: sender, elder_ref: secret(), consent_proof_id: 'fixture-proof', consent_scope: 'family_game', health_processing: true, ai_processing: true }, token);
  };
  const assign = (bearer: string, cultivarId: string, templateId = 'daily_step_record') => command(bearer, 'quests.assign', { cultivator_id: cultivarId, template_id: templateId, date: dayKey(timestamp), request_id: secret() });
  const verified = (binding: { binding_id: string; consent_version: number }, task: { task_instance_id: string; cultivator_id: string; rule_version: string }, event = secret()) => ({ event_id: event, task_instance_id: task.task_instance_id, cultivator_id: task.cultivator_id, binding_id: binding.binding_id, consent_version: binding.consent_version, verification_level: 'photo', observed_at: new Date(timestamp * 1000).toISOString(), rule_version: task.rule_version, source: 'photo', channel: 'wechat_ilink' });
  const settle = async (input: unknown) => {
    const received = await ok('/internal/v1/task-results', input, token);
    return ok(`/internal/v1/task-results/${received.event_id}/settle`, {}, token);
  };
  return { ...server, request, ok, account, command, character, bind, assign, verified, settle, token, now: () => timestamp, advance: (seconds: number) => { timestamp += seconds; } };
}
