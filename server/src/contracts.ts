import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { requireCondition } from './core.js';

let root = dirname(fileURLToPath(import.meta.url));
while (!existsSync(join(root, 'data/kernel/contracts.json'))) {
  const parent = dirname(root);
  if (parent === root) throw new Error('找不到共享 data/kernel/contracts.json');
  root = parent;
}
export const repositoryRoot = root;
export type Contract = { version: number; modules: { id: string; commands: Record<string, Record<string, string>> }[] };
export const contract = JSON.parse(readFileSync(join(root, 'data/kernel/contracts.json'), 'utf8')) as Contract;
export const commands = Object.fromEntries(contract.modules.flatMap(module => Object.entries(module.commands)));

export function validateCommand(command: string, payload: Record<string, unknown>) {
  const fields = commands[command];
  requireCondition(fields, 'UNKNOWN_COMMAND', '未登记的命令', 404);
  requireCondition(Object.keys(fields).length === Object.keys(payload).length, 'INVALID_PAYLOAD', '命令字段与共享契约不符');
  for (const [name, kind] of Object.entries(fields)) {
    const value = payload[name];
    const valid = kind === 'string' ? typeof value === 'string' && value.trim().length > 0 && value.length <= 1024
      : kind === 'integer' ? Number.isSafeInteger(value)
      : kind === 'number' ? typeof value === 'number' && Number.isFinite(value)
      : kind === 'bool' ? typeof value === 'boolean'
      : kind === 'array' ? Array.isArray(value)
      : kind === 'object' ? value !== null && typeof value === 'object' && !Array.isArray(value) : false;
    requireCondition(valid, 'INVALID_PAYLOAD', `字段无效：${name}`);
  }
}

export const stringField = { type: 'string', minLength: 1, maxLength: 128 };
export const boolField = { type: 'boolean' };
export const positiveInteger = { type: 'integer', minimum: 1, maximum: Number.MAX_SAFE_INTEGER };
export const enumField = (values: string[]) => ({ type: 'string', enum: values });
export const objectSchema = (properties: Record<string, unknown>) => ({ type: 'object', additionalProperties: false, required: Object.keys(properties), properties });
export const resultSchema = objectSchema({ ok: { type: 'boolean' }, code: { type: 'string' }, message: { type: 'string' }, data: {} });
