import { createHash, randomBytes, randomUUID } from 'node:crypto';

export type Clock = () => number;
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type Result<T = unknown> = { ok: boolean; code: string; message: string; data: T };
export const success = <T>(data: T): Result<T> => ({ ok: true, code: 'OK', message: '', data });

export class DomainError extends Error {
  constructor(public code: string, message: string, public status = 400) { super(message); }
}

export function requireCondition(condition: unknown, code: string, message: string, status = 400): asserts condition {
  if (!condition) throw new DomainError(code, message, status);
}

export const id = (prefix: string) => `${prefix}_${randomUUID()}`;
export const secret = () => randomBytes(32).toString('base64url');
export const digest = (value: string) => createHash('sha256').update(value).digest('hex');

// 幂等内容按键排序，避免 JSON 字段顺序变化被误认为不同请求。
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.entries(value).sort(([left], [right]) => left.localeCompare(right)).map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export const dayKey = (seconds: number) => new Date((seconds + 8 * 3600) * 1000).toISOString().slice(0, 10);
export const dayStart = (date: string) => Date.parse(`${date}T00:00:00+08:00`) / 1000;
export function parseTime(value: string): number {
  requireCondition(/T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value), 'INVALID_TIME', '时间必须包含时区');
  const seconds = Date.parse(value) / 1000;
  requireCondition(Number.isFinite(seconds), 'INVALID_TIME', '时间无效');
  return seconds;
}
