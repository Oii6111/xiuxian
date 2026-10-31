import { loadEnvFile } from 'node:process';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { buildApp, healthScopes } from './app.js';
import { repositoryRoot } from './contracts.js';

const serverRoot = join(repositoryRoot, 'server');
if (existsSync(join(serverRoot, '.env'))) loadEnvFile(join(serverRoot, '.env'));
const token = process.env.HEALTH_SERVICE_TOKEN;
const server = await buildApp({
  databasePath: resolve(serverRoot, process.env.DATABASE_PATH ?? 'var/game.sqlite'),
  services: token ? [{ id: 'health', token, scopes: [...healthScopes] }] : [],
  origins: process.env.CORS_ORIGINS?.split(',').map(value => value.trim()).filter(Boolean),
});
const port = Number(process.env.PORT ?? 8080);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT 必须为有效端口');
await server.app.listen({ host: process.env.HOST ?? '127.0.0.1', port });
console.log(`本地服务已启动：${server.app.listeningOrigin}；OpenAPI：/openapi.json`);
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.once(signal, () => { void server.app.close(); });
