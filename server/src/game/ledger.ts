import { Database } from '../database.js';
import { type Clock, canonical, digest, id, requireCondition } from '../core.js';

export class Ledger {
  constructor(private db: Database, private now: Clock) {}

  // 调用者必须处在事务中；这是余额唯一写入口。operationId 关联一次完整业务操作。
  change(accountId: string, cultivatorId: string | null, resource: string, delta: number, operationId: string, reason: string) {
    requireCondition(this.db.connection.isTransaction, 'TRANSACTION_REQUIRED', '记账必须位于事务中', 500);
    requireCondition(Number.isSafeInteger(delta), 'INVALID_AMOUNT', '资源变化必须为安全整数');
    const allowed = cultivatorId ? ['spirit_stones', 'realm_xp', 'materials', 'seals'] : ['merit'];
    requireCondition(allowed.includes(resource), 'RESOURCE_OWNER', '资源归属不合法');
    const table = cultivatorId ? 'cultivators' : 'accounts';
    const ownerId = cultivatorId ?? accountId;
    if (cultivatorId) requireCondition(this.db.get('SELECT id FROM cultivators WHERE id = ? AND account_id = ?', cultivatorId, accountId), 'FORBIDDEN', '角色不属于此账号', 403);
    const row = this.db.get<Record<string, number>>(`SELECT ${resource} FROM ${table} WHERE id = ?`, ownerId);
    requireCondition(row, 'NOT_FOUND', '资源所有者不存在', 404);
    const balance = row[resource]! + delta;
    requireCondition(Number.isSafeInteger(balance) && balance >= 0, 'INSUFFICIENT_FUNDS', '资源不足或数值越界', 409);
    this.db.run(`UPDATE ${table} SET ${resource} = ? WHERE id = ?`, balance, ownerId);
    this.db.run('INSERT INTO ledger VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', id('entry'), operationId, accountId, cultivatorId, resource, delta, balance, reason, this.now());
    return balance;
  }
}

export function idempotent<T>(db: Database, now: Clock, principal: string, operation: string, key: string | undefined, payload: unknown, work: () => T): T {
  requireCondition(typeof key === 'string' && key.trim().length > 0 && key.length <= 128, 'IDEMPOTENCY_REQUIRED', '写操作需要稳定的 request_id 或 Idempotency-Key');
  const fingerprint = digest(canonical(payload));
  return db.transaction(() => {
    const previous = db.get<{ fingerprint: string; response: string }>('SELECT fingerprint, response FROM idempotency WHERE principal = ? AND operation = ? AND request_key = ?', principal, operation, key);
    if (previous) {
      requireCondition(previous.fingerprint === fingerprint, 'IDEMPOTENCY_CONFLICT', '相同幂等键不能用于不同请求', 409);
      return JSON.parse(previous.response) as T;
    }
    const response = work();
    db.run('INSERT INTO idempotency VALUES (?, ?, ?, ?, ?, ?)', principal, operation, key, fingerprint, JSON.stringify(response), now());
    return response;
  });
}
