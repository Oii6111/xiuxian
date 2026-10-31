import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildApp } from '../src/app.js';
import { repositoryRoot } from '../src/contracts.js';

const executable = process.argv[2] ?? process.env.GODOT4;
if (!executable || !existsSync(executable)) throw new Error('设置 GODOT4 或通过 npm run test:godot -- <Godot控制台程序路径> 指定 Godot 4.7.2');
const server = await buildApp({ worker: false, now: () => Date.parse('2026-10-31T10:00:00+08:00') / 1000 });
try {
  await server.app.listen({ host: '127.0.0.1', port: 0 });
  const outputDirectory = join(repositoryRoot, 'work/backend');
  mkdirSync(outputDirectory, { recursive: true });
  const log = join(outputDirectory, 'godot-network.log');
  const child = spawn(executable, ['--headless', '--path', repositoryRoot, '--script', 'res://tests/backend_integration_test.gd', '--log-file', log, '--', '--kernel-ephemeral'], {
    windowsHide: true, env: { ...process.env, XIUXIAN_TEST_BASE_URL: server.app.listeningOrigin }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; process.stdout.write(chunk); });
  child.stderr.on('data', chunk => { output += chunk; process.stderr.write(chunk); });
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; child.kill(); }, 45000);
  let code: number | null;
  try { code = await new Promise<number | null>((resolve, reject) => { child.once('exit', resolve); child.once('error', reject); }); }
  finally { clearTimeout(timer); }
  const content = existsSync(log) ? readFileSync(log, 'utf8') : output;
  const errors = content.split(/\r?\n/).filter(line => /SCRIPT ERROR:|^ERROR:|FAIL:/.test(line) && line.trim() !== 'ERROR: Failed to read the root certificate store.');
  if (timedOut || code !== 0 || errors.length || !/BACKEND_INTEGRATION_TEST: \d+ assertions; 0 failures/.test(content)) throw new Error(`Godot 本地网络验证失败：${log}`);
  if (content.includes('Failed to read the root certificate store')) console.log('宿主证书库警告：本轮验证使用回环 HTTP，HTTPS 尚未验证。');
} finally { await server.app.close(); }
