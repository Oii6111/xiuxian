import { Database } from '../database.js';
import { type Clock, DomainError, canonical, dayKey, digest, id, parseTime, requireCondition } from '../core.js';
import { GameService, type Task } from '../game/service.js';
import { type Template, type Verification, calculateReward, checkedRules, compensationTier, isPixel } from '../game/rules.js';
import { BindingService } from './bindings.js';

export type VerifiedResult = {
  event_id: string; task_instance_id: string; cultivator_id: string; binding_id: string;
  consent_version: number; verification_level: Verification; observed_at: string; rule_version: string;
  source: Verification; channel: 'wechat_ilink' | 'family_web' | 'device';
};
export type SubmissionUpdate = { submission_id: string; task_instance_id: string; binding_id: string; consent_version: number; sequence: number; status: 'received' | 'needs_supplement' | 'pending_confirmation' | 'rejected' };
type StoredResult = { service_id: string; event_id: string; task_id: string; binding_id: string; consent_version: number; fingerprint: string; payload: string; status: string; error_code: string; attempts: number };
export type Settlement = { id: string; task_id: string; cultivator_id: string; event_type: string; rule_version: string; verification_level: string; spirit_stones: number; realm_xp: number; settled_at: number; day: string; reason: string; seals: number };

export class HealthBridge {
  // 故障注入仅供构造时的测试依赖使用，不从 HTTP 或环境变量接收。
  constructor(readonly db: Database, readonly now: Clock, readonly game: GameService, readonly bindings: BindingService, private beforeSettlementCommit: () => void = () => {}) {}

  pending(bindingId: string) {
    const binding = this.bindings.active(bindingId);
    return { binding: this.bindings.publicView(binding), tasks: this.db.all<Task>("SELECT * FROM tasks WHERE cultivator_id = ? AND status != 'settled' AND window_end > ? ORDER BY window_start", binding.cultivator_id, this.now()).map(task => this.game.taskView(task)) };
  }

  submission(serviceId: string, input: SubmissionUpdate) {
    return this.db.transaction(() => {
      const task = this.game.task(input.task_instance_id);
      const binding = this.bindings.active(input.binding_id, task.cultivator_id, input.consent_version);
      const previous = this.db.get<{ task_id: string; binding_id: string; consent_version: number; sequence: number; status: string }>('SELECT * FROM submission_status WHERE service_id = ? AND submission_id = ?', serviceId, input.submission_id);
      if (previous) {
        requireCondition(previous.task_id === task.id && previous.binding_id === binding.id && previous.consent_version === input.consent_version, 'SUBMISSION_CONFLICT', '提交标识不能改变归属或授权版本', 409);
        if (input.sequence <= previous.sequence) {
          requireCondition(input.sequence < previous.sequence || input.status === previous.status, 'SUBMISSION_CONFLICT', '相同状态序号内容冲突', 409);
          return this.game.taskView(task);
        }
      }
      this.db.run('INSERT INTO submission_status VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(service_id, submission_id) DO UPDATE SET sequence = excluded.sequence, status = excluded.status, updated_at = excluded.updated_at', serviceId, input.submission_id, task.id, binding.id, input.consent_version, input.sequence, input.status, this.now());
      if (!['settled', 'verified'].includes(task.status)) this.db.run('UPDATE tasks SET status = ? WHERE id = ?', input.status, task.id);
      this.db.touch(binding.account_id);
      return this.game.taskView(this.game.task(task.id));
    });
  }

  // 第一阶段只接收最小验证事实并持久化。服务端崩溃时，pending 记录可继续结算。
  receive(serviceId: string, input: VerifiedResult) {
    return this.db.transaction(() => {
      const fingerprint = digest(canonical(input));
      const previous = this.db.get<StoredResult>('SELECT * FROM verified_results WHERE service_id = ? AND event_id = ?', serviceId, input.event_id);
      if (previous) {
        requireCondition(previous.fingerprint === fingerprint, 'EVENT_CONFLICT', '相同事件 ID 的内容发生变化', 409);
        return { event_id: input.event_id, status: previous.status };
      }
      const task = this.game.task(input.task_instance_id);
      const binding = this.validate(input, task);
      this.db.run('INSERT INTO verified_results (service_id, event_id, task_id, binding_id, consent_version, fingerprint, payload, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', serviceId, input.event_id, task.id, binding.id, input.consent_version, fingerprint, JSON.stringify(input), this.now());
      if (task.status !== 'settled') this.db.run("UPDATE tasks SET status = 'verified' WHERE id = ?", task.id);
      this.db.touch(binding.account_id);
      return { event_id: input.event_id, status: 'pending' };
    });
  }

  settle(serviceId: string, eventId: string) {
    return this.db.transaction(() => {
      const record = this.db.get<StoredResult>('SELECT * FROM verified_results WHERE service_id = ? AND event_id = ?', serviceId, eventId);
      requireCondition(record, 'NOT_FOUND', '验证结果不存在', 404);
      const previous = this.db.get<Settlement>('SELECT * FROM settlements WHERE task_id = ?', record.task_id);
      // 已到账结果可重复查询；无需再次授权，更不能再次扣减额度或发奖。
      if (previous) {
        this.db.run("UPDATE verified_results SET status = 'settled', error_code = '' WHERE service_id = ? AND event_id = ?", serviceId, eventId);
        return this.view(previous);
      }
      const input = JSON.parse(record.payload) as VerifiedResult;
      const task = this.game.task(record.task_id);
      const binding = this.validate(input, task);
      const character = this.game.own(binding.account_id, binding.cultivator_id);
      requireCondition(character.lifecycle === 'cultivating', 'TASK_NOT_APPLICABLE', '当前生命周期不结算健康任务', 409);
      const template = JSON.parse(task.template_snapshot) as Template;
      const rules = checkedRules(this.game.rules, task.rule_version);
      const today = dayKey(this.now());
      const settlementId = id('settlement');
      let reward = { spirit_stones: 0, realm_xp: 0, seals: 0 };
      let reason: string;
      if (isPixel(rules)) {
        // B 的日奖励组：同角色、同组、同一北京时间任务日只发一次；另一项任务仍记为完成。核验级别只决定能否成立，不改奖励量。
        requireCondition(template.reward_group, 'INVALID_RULES', '像素任务模板缺少奖励组', 500);
        const claimed = this.db.get('SELECT settlement_id FROM reward_groups WHERE cultivator_id = ? AND reward_group = ? AND day = ?', character.id, template.reward_group, task.period);
        reason = claimed ? 'daily_group_claimed' : 'daily_group_reward';
        if (!claimed) reward = { ...rules.daily_reward };
      } else {
        const used = this.db.get<{ amount: number }>('SELECT COALESCE(SUM(spirit_stones), 0) AS amount FROM settlements WHERE cultivator_id = ? AND day = ?', character.id, today)!.amount;
        // 用服务端结算时间计算滚动窗口，客户端不能通过修改图片日期绕过限额。
        const sameType = this.db.get("SELECT id FROM settlements WHERE cultivator_id = ? AND event_type = ? AND settled_at > ? AND reason != 'same_type_limit'", character.id, template.event_type, this.now() - 86400);
        reward = { ...(sameType ? { spirit_stones: 0, realm_xp: 0 } : calculateReward(rules, template, input.verification_level, compensationTier(this.game.rules, character), Math.max(0, rules.daily_limit - used))), seals: 0 };
        reason = sameType ? 'same_type_limit' : used >= rules.daily_limit ? 'daily_stone_limit' : 'verified_task';
      }
      this.db.run('INSERT INTO settlements (id, task_id, cultivator_id, event_type, rule_version, verification_level, spirit_stones, realm_xp, settled_at, day, reason, seals) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', settlementId, task.id, character.id, template.event_type, rules.version, input.verification_level, reward.spirit_stones, reward.realm_xp, this.now(), isPixel(rules) ? task.period : today, reason, reward.seals);
      if (reason === 'daily_group_reward') this.db.run('INSERT INTO reward_groups VALUES (?, ?, ?, ?)', character.id, template.reward_group!, task.period, settlementId);
      this.game.ledger.change(binding.account_id, character.id, 'spirit_stones', reward.spirit_stones, settlementId, reason);
      this.game.ledger.change(binding.account_id, character.id, 'realm_xp', reward.realm_xp, settlementId, reason);
      if (reward.seals) this.game.ledger.change(binding.account_id, character.id, 'seals', reward.seals, settlementId, reason);
      this.db.run("UPDATE tasks SET status = 'settled' WHERE id = ?", task.id);
      this.db.run("UPDATE verified_results SET status = 'settled', error_code = '' WHERE service_id = ? AND event_id = ?", serviceId, eventId);
      const settlement = this.db.get<Settlement>('SELECT * FROM settlements WHERE id = ?', settlementId)!;
      const view = this.view(settlement);
      this.db.run('INSERT INTO outbox (id, binding_id, consent_version, settlement_id, payload, available_at) VALUES (?, ?, ?, ?, ?, ?)', id('notification'), binding.id, input.consent_version, settlementId, JSON.stringify(view), this.now());
      this.db.touch(binding.account_id);
      this.beforeSettlementCommit();
      return view;
    });
  }

  result(serviceId: string, eventId: string) {
    const record = this.db.get<StoredResult>('SELECT * FROM verified_results WHERE service_id = ? AND event_id = ?', serviceId, eventId);
    requireCondition(record, 'NOT_FOUND', '验证结果不存在', 404);
    const settlement = this.db.get<Settlement>('SELECT * FROM settlements WHERE task_id = ?', record.task_id);
    return { event_id: record.event_id, task_instance_id: record.task_id, status: settlement ? 'settled' : record.status, error_code: record.error_code, settlement: settlement ? this.view(settlement) : null };
  }

  processPending() {
    const pending = this.db.all<StoredResult>("SELECT * FROM verified_results WHERE status = 'pending' AND next_attempt_at <= ? ORDER BY next_attempt_at, created_at LIMIT 50", this.now());
    for (const record of pending) {
      try { this.settle(record.service_id, record.event_id); }
      catch (error) {
        const code = error instanceof DomainError ? error.code : 'SETTLEMENT_RETRY';
        const blocked = ['CONSENT_REVOKED', 'TASK_NOT_APPLICABLE', 'VERIFICATION_INVALID', 'TASK_WINDOW'].includes(code);
        this.db.run('UPDATE verified_results SET status = ?, error_code = ?, attempts = attempts + 1, next_attempt_at = ? WHERE service_id = ? AND event_id = ?', blocked ? 'blocked' : 'pending', code, this.now() + Math.min(300, 2 ** Math.min(record.attempts + 1, 8)), record.service_id, record.event_id);
      }
    }
  }

  private validate(input: VerifiedResult, task: Task) {
    requireCondition(input.cultivator_id === task.cultivator_id && input.rule_version === task.rule_version, 'VERIFICATION_INVALID', '角色或规则版本与任务实例不符', 409);
    const binding = this.bindings.active(input.binding_id, task.cultivator_id, input.consent_version);
    const template = JSON.parse(task.template_snapshot) as Template;
    requireCondition(template.verification_levels.includes(input.verification_level) && input.source === input.verification_level && (input.verification_level !== 'device' || input.channel === 'device'), 'VERIFICATION_INVALID', '证据来源、验证方式或渠道不匹配');
    const observed = parseTime(input.observed_at);
    requireCondition(observed >= task.window_start && observed < task.window_end && observed <= this.now(), 'TASK_WINDOW', '完成时间不在任务窗口内或晚于当前时间', 409);
    return binding;
  }

  private view(settlement: Settlement) {
    return { settlement_id: settlement.id, task_instance_id: settlement.task_id, cultivator_id: settlement.cultivator_id, spirit_stones: settlement.spirit_stones, realm_xp: settlement.realm_xp, seals: settlement.seals, rule_version: settlement.rule_version, verification_level: settlement.verification_level, settled_at: settlement.settled_at, reason: settlement.reason };
  }
}
