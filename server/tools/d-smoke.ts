import { spawn } from 'node:child_process';
import { buildApp, healthScopes } from '../src/app.js';
import { secret } from '../src/core.js';

const token = secret();
const server = await buildApp({ worker: false, services: [{ id: 'health', token, scopes: [...healthScopes] }] });
try {
  const base = await server.app.listen({ host: '127.0.0.1', port: 0 });
  const status = await new Promise<number | null>((resolve, reject) => {
    const child = spawn(process.env.PYTHON ?? 'python', ['../wechat-bridge/tests/http_smoke.py'], {
      stdio: 'inherit', env: { ...process.env, GAME_API_BASE: base, HEALTH_SERVICE_TOKEN: token, OPENCLAW_DRY_RUN: '0', PYTHONUTF8: '1' },
    });
    child.once('error', reject);
    child.once('exit', resolve);
  });
  if (status !== 0) throw new Error(`D integration failed: ${status}`);
} finally {
  await server.app.close();
}
