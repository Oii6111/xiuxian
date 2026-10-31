import { Database } from '../database.js';
import { type Clock, canonical, digest, id, requireCondition, secret } from '../core.js';
import type { Character } from './rules.js';

// A 的规则：迁移表与阶段模板与 scripts/systems/lifecycle/lifecycle_rules.gd 一致；二十 Boss 来自 data/trial_bosses.json。
export const transitions: Record<string, string[]> = {
  cultivating: ['tribulation'], tribulation: ['cultivating', 'seclusion', 'ascended'], seclusion: ['cultivating', 'ascended'], ascended: [],
};
export const stageTemplates: Record<string, string[]> = {
  cardio: ['admission', 'emergency', 'monitoring', 'ward', 'discharge'],
  fracture: ['admission', 'preop', 'surgery', 'recovery', 'discharge'],
  pneumonia: ['admission', 'acute', 'stable', 'improving', 'discharge'],
};
export const bossIds = Array.from({ length: 20 }, (_, index) => `b${String(index).padStart(2, '0')}`);
const tokenSeconds = 300;
// 战果只接受会话边界的合理时长：少于 3 秒或超出会话实际经过时间的胜利不入账。
const minimumWinSeconds = 3;

type Session = { id: string; cultivator_id: string; encounter_id: string; started_at: number; finished_at: number | null; won: number | null; duration_seconds: number | null };

export class ProgressService {
  constructor(private db: Database, private now: Clock, private own: (accountId: string, cultivarId: string) => Character) {}

  view(character: Character) {
    return {
      state: character.lifecycle, version: character.lifecycle_version, template_id: character.stage_template, stage_index: character.stage_index,
      cleared_bosses: this.db.all<{ boss_id: string; best_seconds: number }>('SELECT boss_id, best_seconds FROM boss_clears WHERE cultivator_id = ? ORDER BY cleared_at, rowid', character.id),
    };
  }

  // 家属发起状态变化：返回确认令牌；飞升需要两次确认。令牌绑定角色、目标、版本和时效。
  requestChange(accountId: string, cultivarId: string, target: string) {
    const character = this.own(accountId, cultivarId);
    requireCondition(transitions[character.lifecycle]?.includes(target), 'INVALID_TRANSITION', '当前状态不能进入该阶段', 409);
    const token = secret();
    this.db.run('DELETE FROM lifecycle_tokens WHERE cultivator_id = ? OR expires_at <= ?', cultivarId, this.now());
    this.db.run('INSERT INTO lifecycle_tokens VALUES (?, ?, ?, ?, 0, ?)', digest(token), cultivarId, target, character.lifecycle_version, this.now() + tokenSeconds);
    return { confirmation_token: token, confirmations_required: target === 'ascended' ? 2 : 1, target_state: target, expires_at: this.now() + tokenSeconds };
  }

  confirmChange(accountId: string, cultivarId: string, token: string) {
    const character = this.own(accountId, cultivarId);
    const ticket = this.db.get<{ target_state: string; from_version: number; confirmations: number; expires_at: number }>('SELECT * FROM lifecycle_tokens WHERE token_hash = ? AND cultivator_id = ?', digest(token), cultivarId);
    requireCondition(ticket, 'FORBIDDEN', '确认令牌无效或不属于该修仙者', 403);
    requireCondition(ticket.expires_at > this.now(), 'TOKEN_EXPIRED', '确认已过期，请重新发起', 409);
    requireCondition(ticket.from_version === character.lifecycle_version, 'STALE_STATE', '确认期间状态已更新，请重新发起', 409);
    const needed = ticket.target_state === 'ascended' ? 2 : 1;
    if (ticket.confirmations + 1 < needed) {
      this.db.run('UPDATE lifecycle_tokens SET confirmations = confirmations + 1 WHERE token_hash = ?', digest(token));
      return { complete: false, state: ticket.target_state, remaining: needed - ticket.confirmations - 1 };
    }
    const version = character.lifecycle_version + 1;
    this.db.run("UPDATE cultivators SET lifecycle = ?, lifecycle_version = ?, stage_index = -1, stage_template = CASE WHEN ? = 'tribulation' THEN stage_template ELSE '' END WHERE id = ?", ticket.target_state, version, ticket.target_state, cultivarId);
    this.db.run('DELETE FROM lifecycle_tokens WHERE token_hash = ?', digest(token));
    this.db.run('INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?)', id('lifecycle'), cultivarId, 'state', ticket.target_state, version, this.now());
    this.db.touch(accountId);
    return { complete: true, state: ticket.target_state, version };
  }

  // 渡劫阶段可前进或回退；confirmation_token 是家属这次点击的一次性标识，由幂等表去重。到出院不自动结束渡劫。
  updateStage(accountId: string, cultivarId: string, stageId: string) {
    const character = this.own(accountId, cultivarId);
    requireCondition(character.lifecycle === 'tribulation', 'INVALID_STATE', '只有渡劫中可以更新阶段', 409);
    const [template, stage] = stageId.split('.');
    const index = stageTemplates[template ?? '']?.indexOf(stage ?? '') ?? -1;
    requireCondition(index >= 0, 'INVALID_STAGE', '阶段不存在', 400);
    requireCondition(character.stage_template === '' || character.stage_template === template, 'INVALID_STAGE', '阶段与当前模板不一致', 409);
    requireCondition(index !== character.stage_index, 'INVALID_STAGE', '已处于该阶段', 409);
    const version = character.lifecycle_version + 1;
    this.db.run('UPDATE cultivators SET stage_template = ?, stage_index = ?, lifecycle_version = ? WHERE id = ?', template!, index, version, cultivarId);
    this.db.run('INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?)', id('lifecycle'), cultivarId, 'stage', stageId, version, this.now());
    this.db.touch(accountId);
    return { version, template_id: template, stage_index: index };
  }

  start(accountId: string, cultivarId: string, encounterId: string) {
    const character = this.own(accountId, cultivarId);
    requireCondition(character.lifecycle === 'cultivating', 'NOT_ALLOWED', '该修仙者不在修行状态', 409);
    requireCondition(bossIds.includes(encounterId), 'ENCOUNTER_UNAVAILABLE', '关卡不存在', 404);
    const sessionId = id('combat');
    this.db.run('INSERT INTO combat_sessions (id, cultivator_id, encounter_id, started_at) VALUES (?, ?, ?, ?)', sessionId, cultivarId, encounterId, this.now());
    return { session_id: sessionId, cultivator_id: cultivarId, encounter_id: encounterId };
  }

  finish(accountId: string, sessionId: string, won: boolean, duration: number) {
    const session = this.db.get<Session>('SELECT * FROM combat_sessions WHERE id = ?', sessionId);
    requireCondition(session, 'NOT_FOUND', '战斗会话不存在', 404);
    const character = this.own(accountId, session.cultivator_id);
    if (session.finished_at !== null) {
      requireCondition(Boolean(session.won) === won && session.duration_seconds === duration, 'SESSION_CONFLICT', '该会话已提交了不同战果', 409);
      return this.result(character, session, true);
    }
    requireCondition(duration >= 0 && duration <= this.now() - session.started_at + 5, 'INVALID_RESULT', '战斗时长与会话不符', 409);
    requireCondition(!won || duration >= minimumWinSeconds, 'INVALID_RESULT', '战斗时长过短', 409);
    this.db.run('UPDATE combat_sessions SET finished_at = ?, won = ?, duration_seconds = ? WHERE id = ?', this.now(), Number(won), duration, sessionId);
    if (won && character.lifecycle === 'cultivating') {
      this.db.run('INSERT INTO boss_clears VALUES (?, ?, ?, ?, ?) ON CONFLICT(cultivator_id, boss_id) DO UPDATE SET best_seconds = MIN(best_seconds, excluded.best_seconds)', character.id, session.encounter_id, sessionId, duration, this.now());
    }
    this.db.touch(accountId);
    return this.result(character, this.db.get<Session>('SELECT * FROM combat_sessions WHERE id = ?', sessionId)!, false);
  }

  private result(character: Character, session: Session, replayed: boolean) {
    const clear = this.db.get<{ first_session_id: string }>('SELECT first_session_id FROM boss_clears WHERE cultivator_id = ? AND boss_id = ?', character.id, session.encounter_id);
    return { session_id: session.id, cultivator_id: character.id, encounter_id: session.encounter_id, won: Boolean(session.won), duration_seconds: session.duration_seconds, replayed, first_clear: clear?.first_session_id === session.id, cleared_count: this.db.get<{ count: number }>('SELECT COUNT(*) AS count FROM boss_clears WHERE cultivator_id = ?', character.id)!.count };
  }
}

export const fingerprint = (value: unknown) => digest(canonical(value));
