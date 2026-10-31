import Fastify, { type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import websocket from '@fastify/websocket';
import { randomInt, timingSafeEqual } from 'node:crypto';
import { Database } from './database.js';
import { AuthService } from './auth.js';
import { type Clock, DomainError, digest, requireCondition, success } from './core.js';
import { contract, commands, validateCommand, stringField, boolField, positiveInteger, enumField, objectSchema, resultSchema } from './contracts.js';
import { GameService, type GameExtensions, type Season } from './game/service.js';
import { type RuleProviders, defaultProviders } from './game/rules.js';
import { BindingService, type ConfirmBinding } from './integration/bindings.js';
import { HealthBridge, type SubmissionUpdate, type VerifiedResult } from './integration/health.js';
import { Outbox } from './integration/outbox.js';
import { RealtimeHub } from './realtime/hub.js';

export const healthScopes = ['binding:confirm', 'binding:connection', 'task:read', 'submission:write', 'result:write', 'notification:deliver'] as const;
export type ServiceCredential = { id: string; token: string; scopes: string[] };
export type AppOptions = {
  databasePath?: string; now?: Clock; randomInt?: (maximum: number) => number;
  providers?: RuleProviders; calendar?: Season[]; extensions?: GameExtensions;
  services?: ServiceCredential[]; origins?: string[]; worker?: boolean;
  beforeSettlementCommit?: () => void;
};

export async function buildApp(options: AppOptions = {}) {
  const now = options.now ?? (() => Math.floor(Date.now() / 1000));
  const services = options.services ?? [];
  requireCondition(services.every(service => service.token.length >= 32 && service.id.length > 0 && service.scopes.every(scope => healthScopes.includes(scope as typeof healthScopes[number]))) && new Set(services.map(service => service.id)).size === services.length && new Set(services.map(service => service.token)).size === services.length, 'INVALID_SERVICE_CONFIG', '内部服务凭证配置无效', 500);
  const origins = options.origins ?? ['http://127.0.0.1:8080', 'http://localhost:8080'];
  const app = Fastify({ logger: false, bodyLimit: 64 * 1024, ajv: { customOptions: { coerceTypes: false, removeAdditional: false, useDefaults: false } } });
  const db = new Database(options.databasePath ?? ':memory:');
  const auth = new AuthService(db, now);
  const game = new GameService(db, now, options.providers ?? defaultProviders, options.randomInt ?? randomInt, options.calendar, options.extensions);
  const bindings = new BindingService(db, now, game);
  const health = new HealthBridge(db, now, game, bindings, options.beforeSettlementCommit);
  const outbox = new Outbox(db, now, bindings);
  const realtime = new RealtimeHub(db, now, auth, game);
  let worker: NodeJS.Timeout | undefined;
  const session = (request: FastifyRequest) => auth.authenticate(request.headers.authorization);
  const internal = (request: FastifyRequest, scope: string) => {
    const supplied = request.headers.authorization?.startsWith('Bearer ') ? request.headers.authorization.slice(7) : '';
    const hashed = Buffer.from(digest(supplied), 'hex');
    const service = services.find(item => timingSafeEqual(Buffer.from(digest(item.token), 'hex'), hashed));
    requireCondition(service, 'UNAUTHORIZED', '需要内部服务凭证', 401);
    requireCondition(service.scopes.includes(scope), 'FORBIDDEN', '内部服务缺少所需作用域', 403);
    return service.id;
  };
  const routeSchema = (tag: string, summary: string, body?: unknown, internalAuth = false) => ({ tags: [tag], summary, ...(body ? { body } : {}), security: [{ [internalAuth ? 'healthService' : 'bearerAuth']: [] }], response: { 200: resultSchema } });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof DomainError) return reply.code(error.status).send({ ok: false, code: error.code, message: error.message, data: {} });
    const status = typeof error === 'object' && error !== null && 'statusCode' in error && typeof error.statusCode === 'number' ? error.statusCode : 500;
    const code = status === 429 ? 'RATE_LIMITED' : status < 500 ? 'INVALID_PAYLOAD' : 'INTERNAL_ERROR';
    return reply.code(status).send({ ok: false, code, message: status < 500 ? '请求无效或过于频繁' : '服务暂时不可用，请使用原请求标识重试', data: {} });
  });
  app.setNotFoundHandler((_request, reply) => reply.code(404).send({ ok: false, code: 'NOT_FOUND', message: '接口不存在', data: {} }));
  app.addHook('onResponse', async () => { realtime.flush(); });
  app.addHook('preClose', async () => { if (worker) clearInterval(worker); realtime.close(); });
  app.addHook('onClose', async () => { db.close(); });

  await app.register(cors, { origin: origins, methods: ['GET', 'POST', 'DELETE'], allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key'] });
  await app.register(rateLimit, { global: false });
  await app.register(swagger, { openapi: { info: { title: '家族修真录 C 本地服务', version: '0.1.0' }, components: { securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer' }, healthService: { type: 'http', scheme: 'bearer', description: 'D 的独立服务凭证，不得交给浏览器或模型' } } } } });
  await app.register(websocket, { options: { maxPayload: 16384 } });
  app.get('/healthz', { schema: { tags: ['operations'], summary: '进程和数据库存活检查' } }, async () => { db.get('SELECT 1'); return success({ service: 'xiuxian', contract_version: contract.version }); });
  app.get('/openapi.json', { schema: { hide: true } }, async () => app.swagger());

  const credentials = objectSchema({ username: { type: 'string', minLength: 1, maxLength: 128 }, password: { type: 'string', minLength: 1, maxLength: 128 } });
  app.post('/api/v2/auth/register', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } }, schema: { ...routeSchema('auth', '注册账号；用户名规范化，密码至少 12 位', credentials), security: [] } }, async request => success(await auth.register(request.body as { username: string; password: string })));
  app.post('/api/v2/auth/login', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } }, schema: { ...routeSchema('auth', '登录，返回 7 天有效会话令牌', credentials), security: [] } }, async request => success(await auth.login(request.body as { username: string; password: string })));
  app.get('/api/v2/auth/me', { schema: routeSchema('auth', '当前会话') }, async request => { const current = session(request); return success({ account_id: current.account_id, username: current.username, expires_at: current.expires_at }); });
  app.post('/api/v2/auth/logout', { schema: routeSchema('auth', '退出当前会话', objectSchema({})) }, async request => success(auth.logout(session(request))));
  app.post('/api/v2/auth/logout-all', { schema: routeSchema('auth', '撤销当前账号的全部会话', objectSchema({})) }, async request => success(auth.logout(session(request), true)));

  const commandVariants = Object.entries(commands).map(([command, fields]) => objectSchema({ version: { const: 1, type: 'integer' }, command: { const: command, type: 'string' }, payload: objectSchema(Object.fromEntries(Object.entries(fields).map(([field, kind]) => [field, kind === 'string' ? { type: 'string', minLength: 1, maxLength: 1024 } : { type: kind === 'bool' ? 'boolean' : kind }]))) }));
  app.post('/api/v2/commands', { schema: { ...routeSchema('game', '共享命令入口；写操作提供 request_id 或 Idempotency-Key', { oneOf: commandVariants }), headers: { type: 'object', properties: { 'idempotency-key': stringField } } } }, async request => {
    const current = session(request);
    const input = request.body as { version: number; command: string; payload: Record<string, unknown> };
    validateCommand(input.command, input.payload);
    return success(await game.execute(current.account_id, input.command, input.payload, request.headers['idempotency-key'] as string | undefined));
  });
  app.get('/api/v2/snapshot', { schema: routeSchema('game', '当前账号的权威游戏快照') }, async request => success(game.snapshot(session(request).account_id)));
  app.post('/api/v2/realtime/ticket', { schema: routeSchema('realtime', '签发 60 秒有效的一次性连接票据', objectSchema({})) }, async request => success(realtime.ticket(session(request))));
  realtime.register(app, origins);

  app.post('/api/v2/bindings/invitations', { schema: routeSchema('binding', '生成 10 分钟邀请；新邀请替换该角色旧邀请', objectSchema({ cultivator_id: stringField })) }, async request => success(bindings.invite(session(request).account_id, (request.body as { cultivator_id: string }).cultivator_id)));
  app.get('/api/v2/bindings', { schema: { ...routeSchema('binding', '读取绑定与独立授权状态'), querystring: objectSchema({ cultivator_id: stringField }) } }, async request => success(bindings.list(session(request).account_id, (request.query as { cultivator_id: string }).cultivator_id)));
  for (const [path, method, unbind] of [['/api/v2/bindings/:id/revoke', 'POST', false], ['/api/v2/bindings/:id', 'DELETE', true]] as const) {
    app.route({ method, url: path, schema: { ...routeSchema('binding', unbind ? '解除绑定并撤回授权' : '撤回资料处理授权'), params: objectSchema({ id: stringField }) }, handler: async request => success(bindings.revoke(session(request).account_id, (request.params as { id: string }).id, unbind)) });
  }

  const bindingInput = objectSchema({ invite_token: stringField, channel: enumField(['wechat_ilink']), channel_account_id: stringField, sender_id: stringField, elder_ref: stringField, consent_proof_id: stringField, consent_scope: enumField(['family_game']), health_processing: boolField, ai_processing: boolField });
  app.post('/internal/v1/bindings/confirm', { schema: routeSchema('internal', 'D 校验微信身份及老人授权后消费邀请', bindingInput, true) }, async request => { internal(request, 'binding:confirm'); return success(bindings.confirm(request.body as ConfirmBinding)); });
  app.post('/internal/v1/bindings/:id/connection', { schema: { ...routeSchema('internal', '更新通道连接状态，不改变资料授权', objectSchema({ connected: boolField }), true), params: objectSchema({ id: stringField }) } }, async request => { internal(request, 'binding:connection'); return success(bindings.connection((request.params as { id: string }).id, (request.body as { connected: boolean }).connected)); });
  app.get('/internal/v1/bindings/:id/tasks', { schema: { ...routeSchema('internal', '读取有效绑定的待办', undefined, true), params: objectSchema({ id: stringField }) } }, async request => { internal(request, 'task:read'); return success(health.pending((request.params as { id: string }).id)); });
  const submissionInput = objectSchema({ submission_id: stringField, task_instance_id: stringField, binding_id: stringField, consent_version: positiveInteger, sequence: positiveInteger, status: enumField(['received', 'needs_supplement', 'pending_confirmation', 'rejected']) });
  app.post('/internal/v1/submissions/status', { schema: routeSchema('internal', '同步游戏侧提交状态；不接收图片、识别文本或医疗说明', submissionInput, true) }, async request => success(health.submission(internal(request, 'submission:write'), request.body as SubmissionUpdate)));
  const verifiedInput = objectSchema({ event_id: stringField, task_instance_id: stringField, cultivator_id: stringField, binding_id: stringField, consent_version: positiveInteger, verification_level: enumField(['device', 'photo', 'family_confirm', 'self_report']), observed_at: { type: 'string', format: 'date-time' }, rule_version: stringField, source: enumField(['device', 'photo', 'family_confirm', 'self_report']), channel: enumField(['wechat_ilink', 'family_web', 'device']) });
  app.post('/internal/v1/task-results', { schema: routeSchema('internal', '持久化最小验证结果；随后由结算工作器或 settle 接口处理', verifiedInput, true) }, async request => success(health.receive(internal(request, 'result:write'), request.body as VerifiedResult)));
  app.get('/internal/v1/task-results/:id', { schema: { ...routeSchema('internal', '查询验证与结算结果', undefined, true), params: objectSchema({ id: stringField }) } }, async request => success(health.result(internal(request, 'result:write'), (request.params as { id: string }).id)));
  app.post('/internal/v1/task-results/:id/settle', { schema: { ...routeSchema('internal', '重试结算，重复调用返回同一结果', objectSchema({}), true), params: objectSchema({ id: stringField }) } }, async request => success(health.settle(internal(request, 'result:write'), (request.params as { id: string }).id)));
  app.post('/internal/v1/notifications/claim', { schema: routeSchema('internal', '领取 30 秒通知租约；最多 20 条', objectSchema({ limit: { type: 'integer', minimum: 1, maximum: 20 } }), true) }, async request => success(outbox.claim(internal(request, 'notification:deliver'), (request.body as { limit: number }).limit)));
  for (const action of ['ack', 'nack'] as const) app.post(`/internal/v1/notifications/:id/${action}`, { schema: { ...routeSchema('internal', action === 'ack' ? '确认通知已送达；重复确认安全' : '通知失败后退避重试', objectSchema({ lease_token: stringField }), true), params: objectSchema({ id: stringField }) } }, async request => success(outbox.complete(internal(request, 'notification:deliver'), (request.params as { id: string }).id, (request.body as { lease_token: string }).lease_token, action === 'ack')));

  await app.ready();
  if (options.worker !== false) {
    worker = setInterval(() => { health.processPending(); realtime.flush(); }, 1000);
    worker.unref();
  }
  return { app, db, auth, game, bindings, health, outbox, realtime };
}
