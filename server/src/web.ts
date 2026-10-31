import type { FastifyInstance } from 'fastify';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';

// 一台服务器两部分：本服务托管 Godot 网页导出，并把 D 的扫码绑定与健康入口同源转发。浏览器只访问这一个地址。
const types: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.json': 'application/json', '.css': 'text/css',
};
export type WebOptions = { root?: string; wechatUrl?: string; healthEntryUrl?: string };

export function registerWeb(app: FastifyInstance, options: WebOptions) {
  const proxies: [string, string | undefined][] = [
    ['/wechat/bind/', options.wechatUrl], ['/api/v1/wechat/', options.wechatUrl],
    ['/api/v1/health', options.healthEntryUrl], ['/api/v1/game/projections/', options.healthEntryUrl],
  ];
  for (const [prefix, target] of proxies) {
    if (!target) continue;
    app.all(`${prefix}*`, { schema: { hide: true }, bodyLimit: 45 * 1024 * 1024 }, async (request, reply) => {
      const upstream = await fetch(target.replace(/\/$/, '') + request.url, {
        method: request.method, headers: { 'content-type': String(request.headers['content-type'] ?? 'application/json') },
        body: ['GET', 'HEAD'].includes(request.method) ? undefined : JSON.stringify(request.body ?? {}), signal: AbortSignal.timeout(130000),
      }).catch(() => null);
      if (!upstream) return reply.code(502).send({ ok: false, code: 'UPSTREAM_UNAVAILABLE', message: '健康服务暂时不可用', data: {} });
      return reply.code(upstream.status).type(upstream.headers.get('content-type') ?? 'application/json').send(Buffer.from(await upstream.arrayBuffer()));
    });
  }
  const root = options.root ? resolve(options.root) : '';
  if (!root || !existsSync(join(root, 'index.html'))) return;
  app.get('/*', { schema: { hide: true } }, async (request, reply) => {
    const path = decodeURIComponent(request.url.split('?')[0]!);
    const file = normalize(join(root, path === '/' ? 'index.html' : path));
    if (!(file + sep).startsWith(root + sep) && file !== root || !existsSync(file) || !statSync(file).isFile()) return reply.code(404).send({ ok: false, code: 'NOT_FOUND', message: '接口不存在', data: {} });
    return reply.type(types[extname(file)] ?? 'application/octet-stream').header('Cache-Control', file.endsWith('.html') ? 'no-cache' : 'public, max-age=3600').send(readFileSync(file));
  });
}
