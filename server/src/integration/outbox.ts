import { Database } from '../database.js';
import { type Clock, digest, requireCondition, secret } from '../core.js';
import { BindingService } from './bindings.js';

type Notification = { id: string; binding_id: string; consent_version: number; payload: string; status: string; attempts: number; available_at: number; lease_until: number | null; lease_hash: string | null; lease_owner: string | null; acknowledged_hash: string | null };

export class Outbox {
  constructor(private db: Database, private now: Clock, private bindings: BindingService) {}

  claim(serviceId: string, limit: number) {
    return this.db.transaction(() => {
      const rows = this.db.all<Notification>("SELECT * FROM outbox WHERE (status = 'pending' AND available_at <= ?) OR (status = 'leased' AND lease_until <= ?) ORDER BY available_at LIMIT ?", this.now(), this.now(), limit);
      const notifications = [];
      for (const row of rows) {
        try { this.bindings.active(row.binding_id, undefined, row.consent_version); }
        catch { this.db.run("UPDATE outbox SET status = 'cancelled', lease_hash = NULL WHERE id = ?", row.id); continue; }
        const token = secret();
        this.db.run("UPDATE outbox SET status = 'leased', attempts = attempts + 1, lease_until = ?, lease_hash = ?, lease_owner = ? WHERE id = ?", this.now() + 30, digest(token), serviceId, row.id);
        notifications.push({ notification_id: row.id, binding_id: row.binding_id, consent_version: row.consent_version, lease_token: token, lease_until: this.now() + 30, payload: JSON.parse(row.payload) });
      }
      return { notifications };
    });
  }

  complete(serviceId: string, notificationId: string, token: string, acknowledge: boolean) {
    return this.db.transaction(() => {
      const row = this.db.get<Notification>('SELECT * FROM outbox WHERE id = ?', notificationId);
      requireCondition(row, 'NOT_FOUND', '通知不存在', 404);
      const tokenHash = digest(token);
      if (acknowledge && row.status === 'acknowledged' && row.acknowledged_hash === tokenHash && row.lease_owner === serviceId) return { acknowledged: true };
      requireCondition(row.status === 'leased' && row.lease_owner === serviceId && row.lease_hash === tokenHash && row.lease_until! > this.now(), 'LEASE_CONFLICT', '通知租约无效或已过期', 409);
      this.bindings.active(row.binding_id, undefined, row.consent_version);
      if (acknowledge) this.db.run("UPDATE outbox SET status = 'acknowledged', acknowledged_hash = ?, lease_hash = NULL WHERE id = ?", tokenHash, notificationId);
      else this.db.run("UPDATE outbox SET status = 'pending', available_at = ?, lease_hash = NULL WHERE id = ?", this.now() + Math.min(300, 2 ** Math.min(row.attempts, 8)), notificationId);
      return { acknowledged: acknowledge };
    });
  }
}
