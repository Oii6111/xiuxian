import test from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { fixture } from './helpers.js';

function messages(socket: WebSocket) {
  const queue: Record<string, any>[] = [];
  const listeners: (() => void)[] = [];
  socket.on('message', raw => { queue.push(JSON.parse(raw.toString())); for (const notify of listeners.splice(0)) notify(); });
  return {
    queue,
    async next() {
      if (!queue.length) await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('WebSocket message timeout')), 3000);
        listeners.push(() => { clearTimeout(timer); resolve(); });
      });
      return queue.shift()!;
    },
  };
}

async function rejected(address: string, expected: number) {
  await new Promise<void>((resolve, reject) => {
    const socket = new WebSocket(address);
    const timer = setTimeout(() => { socket.terminate(); reject(new Error('Upgrade timeout')); }, 3000);
    socket.on('unexpected-response', (_request, response) => {
      clearTimeout(timer);
      response.resume();
      socket.terminate();
      try { assert.equal(response.statusCode, expected); resolve(); } catch (error) { reject(error); }
    });
    socket.on('open', () => { clearTimeout(timer); socket.terminate(); reject(new Error('Unexpected authorized socket')); });
    socket.on('error', () => {});
  });
}

test('WebSocket 拒绝无效、过期、重放票据与未授权来源', async context => {
  const app = await fixture(context);
  await app.app.listen({ host: '127.0.0.1', port: 0 });
  const base = app.app.listeningOrigin.replace('http:', 'ws:');
  await rejected(`${base}/api/v2/realtime?ticket=invalid`, 401);
  const account = await app.account();
  const expired = await app.ok('/api/v2/realtime/ticket', {}, account.token);
  app.advance(61);
  await rejected(`${base}/api/v2/realtime?ticket=${expired.ticket}`, 401);
  const ticket = await app.ok('/api/v2/realtime/ticket', {}, account.token);
  const socket = new WebSocket(`${base}/api/v2/realtime?ticket=${ticket.ticket}`);
  context.after(() => socket.terminate());
  assert.equal((await messages(socket).next()).type, 'snapshot');
  await rejected(`${base}/api/v2/realtime?ticket=${ticket.ticket}`, 401);
  const originTicket = await app.ok('/api/v2/realtime/ticket', {}, account.token);
  await new Promise<void>((resolve, reject) => {
    const foreign = new WebSocket(`${base}/api/v2/realtime?ticket=${originTicket.ticket}`, { origin: 'https://untrusted.invalid' });
    foreign.on('unexpected-response', (_request, response) => { response.resume(); foreign.terminate(); try { assert.equal(response.statusCode, 403); resolve(); } catch (error) { reject(error); } });
    foreign.on('error', () => {});
    foreign.on('open', () => { foreign.terminate(); reject(new Error('Untrusted origin accepted')); });
  });
});

test('个人推送隔离、版本缺口快照恢复、心跳、重连与会话撤销', async context => {
  const app = await fixture(context);
  await app.app.listen({ host: '127.0.0.1', port: 0 });
  const base = app.app.listeningOrigin.replace('http:', 'ws:');
  const first = await app.account('first_user');
  const second = await app.account('second_user');
  const firstTicket = await app.ok('/api/v2/realtime/ticket', {}, first.token);
  const secondTicket = await app.ok('/api/v2/realtime/ticket', {}, second.token);
  const firstSocket = new WebSocket(`${base}/api/v2/realtime?ticket=${firstTicket.ticket}`);
  const secondSocket = new WebSocket(`${base}/api/v2/realtime?ticket=${secondTicket.ticket}`);
  context.after(() => { firstSocket.terminate(); secondSocket.terminate(); });
  const firstMessages = messages(firstSocket);
  const secondMessages = messages(secondSocket);
  assert.equal((await firstMessages.next()).data.cultivators.length, 0);
  assert.equal((await secondMessages.next()).data.cultivators.length, 0);
  const character = await app.character(first.token);
  assert.equal((await firstMessages.next()).type, 'state_changed');
  firstSocket.send(JSON.stringify({ type: 'resync' }));
  const snapshot = await firstMessages.next();
  assert.equal(snapshot.data.cultivators[0].cultivator_id, character.cultivator_id);
  assert.equal(secondMessages.queue.length, 0);
  assert.ok(!JSON.stringify(snapshot).includes('password_hash'));
  firstSocket.send(JSON.stringify({ type: 'ping' }));
  assert.equal((await firstMessages.next()).type, 'pong');
  firstSocket.terminate();
  await app.character(first.token);
  const fresh = await app.ok('/api/v2/realtime/ticket', {}, first.token);
  const reconnect = new WebSocket(`${base}/api/v2/realtime?ticket=${fresh.ticket}`);
  context.after(() => reconnect.terminate());
  const reconnectMessages = messages(reconnect);
  assert.equal((await reconnectMessages.next()).data.cultivators.length, 2);
  const closed = new Promise<number>(resolve => reconnect.once('close', code => resolve(code)));
  await app.ok('/api/v2/auth/logout-all', {}, first.token);
  assert.equal(await closed, 4001);
});
