import { Database } from '../database.js';
import { type Clock, canonical, digest, id, requireCondition, secret } from '../core.js';
import { GameService } from '../game/service.js';

export type Binding = { id: string; account_id: string; cultivator_id: string; channel: string; channel_account_id: string; sender_id: string; elder_ref: string; status: string; connected: number; consent_status: string; consent_version: number; consent_scope: string; consent_proof_id: string; created_at: number };
export type ConfirmBinding = { invite_token: string; channel: string; channel_account_id: string; sender_id: string; elder_ref: string; consent_proof_id: string; consent_scope: string; health_processing: boolean; ai_processing: boolean };

export class BindingService {
  constructor(readonly db: Database, readonly now: Clock, readonly game: GameService) {}

  invite(accountId: string, cultivarId: string) {
    this.game.own(accountId, cultivarId);
    return this.db.transaction(() => {
      requireCondition(!this.db.get("SELECT id FROM bindings WHERE cultivator_id = ? AND status = 'active'", cultivarId), 'BINDING_CONFLICT', '请先解除已有绑定', 409);
      // 新邀请替换旧邀请；明文只返回一次，不写入幂等响应缓存或数据库。
      this.db.run('DELETE FROM invitations WHERE cultivator_id = ?', cultivarId);
      const token = secret();
      const expires = this.now() + 600;
      this.db.run('INSERT INTO invitations (token_hash, account_id, cultivator_id, expires_at) VALUES (?, ?, ?, ?)', digest(token), accountId, cultivarId, expires);
      return { invite_token: token, expires_at: expires, cultivator_id: cultivarId };
    });
  }

  confirm(input: ConfirmBinding) {
    requireCondition(input.channel === 'wechat_ilink' && input.consent_scope === 'family_game' && input.health_processing && input.ai_processing, 'CONSENT_REQUIRED', '需要老人确认资料处理、AI 识别和家庭游戏共享范围');
    return this.db.transaction(() => {
      const invite = this.db.get<{ account_id: string; cultivator_id: string; expires_at: number; used: number; result_binding_id: string; confirmation_fingerprint: string }>('SELECT * FROM invitations WHERE token_hash = ?', digest(input.invite_token));
      const fingerprint = digest(canonical(input));
      requireCondition(invite, 'INVITE_INVALID', '邀请已失效', 409);
      if (invite.used) {
        requireCondition(invite.confirmation_fingerprint === fingerprint, 'INVITE_INVALID', '邀请已用于其他确认内容', 409);
        return this.publicView(this.get(invite.result_binding_id));
      }
      requireCondition(invite.expires_at > this.now(), 'INVITE_INVALID', '邀请已过期', 409);
      requireCondition(!this.db.get("SELECT id FROM bindings WHERE status = 'active' AND (cultivator_id = ? OR (channel = ? AND channel_account_id = ? AND sender_id = ?))", invite.cultivator_id, input.channel, input.channel_account_id, input.sender_id), 'BINDING_CONFLICT', '发送者或修仙者已有有效绑定', 409);
      const bindingId = id('binding');
      this.db.run('INSERT INTO bindings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', bindingId, invite.account_id, invite.cultivator_id, input.channel, input.channel_account_id, input.sender_id, input.elder_ref, 'active', 1, 'active', 1, input.consent_scope, input.consent_proof_id, this.now());
      this.db.run('UPDATE invitations SET used = 1, result_binding_id = ?, confirmation_fingerprint = ? WHERE token_hash = ?', bindingId, fingerprint, digest(input.invite_token));
      this.db.touch(invite.account_id);
      return this.publicView(this.get(bindingId));
    });
  }

  get(bindingId: string): Binding {
    const binding = this.db.get<Binding>('SELECT * FROM bindings WHERE id = ?', bindingId);
    requireCondition(binding, 'NOT_FOUND', '绑定不存在', 404);
    return binding;
  }

  active(bindingId: string, cultivarId?: string, consentVersion?: number): Binding {
    const binding = this.get(bindingId);
    requireCondition(binding.status === 'active' && binding.consent_status === 'active' && (cultivarId === undefined || binding.cultivator_id === cultivarId) && (consentVersion === undefined || binding.consent_version === consentVersion), 'CONSENT_REVOKED', '绑定或资料授权无效，需要重新授权并复核', 409);
    return binding;
  }

  publicView(binding: Binding) {
    return { binding_id: binding.id, cultivator_id: binding.cultivator_id, channel: binding.channel, connected: Boolean(binding.connected), status: binding.status, consent_status: binding.consent_status, consent_version: binding.consent_version, consent_scope: binding.consent_scope };
  }

  list(accountId: string, cultivarId: string) {
    this.game.own(accountId, cultivarId);
    return { bindings: this.db.all<Binding>('SELECT * FROM bindings WHERE cultivator_id = ? ORDER BY created_at, id', cultivarId).map(binding => this.publicView(binding)) };
  }

  revoke(accountId: string, bindingId: string, unbind: boolean) {
    return this.db.transaction(() => {
      const binding = this.get(bindingId);
      requireCondition(binding.account_id === accountId, 'NOT_FOUND', '绑定不属于当前账号', 404);
      if (binding.consent_status === 'active' || (unbind && binding.status === 'active')) {
        this.db.run('UPDATE bindings SET status = ?, consent_status = ?, consent_version = consent_version + 1 WHERE id = ?', unbind ? 'revoked' : binding.status, 'revoked', bindingId);
        this.db.run("UPDATE outbox SET status = 'cancelled', lease_hash = NULL WHERE binding_id = ? AND status != 'acknowledged'", bindingId);
        this.db.touch(accountId);
      }
      return this.publicView(this.get(bindingId));
    });
  }

  connection(bindingId: string, connected: boolean) {
    const binding = this.get(bindingId);
    requireCondition(binding.status === 'active', 'BINDING_INACTIVE', '绑定已解除', 409);
    this.db.transaction(() => {
      this.db.run('UPDATE bindings SET connected = ? WHERE id = ?', Number(connected), bindingId);
      this.db.touch(binding.account_id);
    });
    return this.publicView(this.get(bindingId));
  }
}
