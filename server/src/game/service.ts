import { Database } from '../database.js';
import { type Clock, dayKey, dayStart, id, requireCondition } from '../core.js';
import { Ledger, idempotent } from './ledger.js';
import { type Character, type RuleProviders, type Template, allSlots, checkedRules, compensationTier, elements, initialScore, isPixel, legacyRules, pixelRarities, pixelRules, pixelSlots, profileElement, rollPixelRarity, rollRarity, slots } from './rules.js';

export type Task = { id: string; cultivator_id: string; template_id: string; template_version: string; rule_version: string; period: string; window_start: number; window_end: number; template_snapshot: string; status: string; created_at: number };
export type Season = { id: string; starts_at: string; ends_at: string };
export interface GameExtensions {
  // A 后续注册战斗与生命周期服务；默认没有处理器，路由不会伪造成功。
  commands?: Record<string, {
    execute(accountId: string, payload: Record<string, unknown>): unknown;
    // 提供方必须严格校验输出字段；未经校验的数据不能进入游戏客户端。
    validateOutput(result: unknown): boolean;
  }>;
}

export type MemberProfile = { title: string; avatar: 'male' | 'female'; relation?: string; age?: number; sex?: string; mode?: string; consent?: boolean };
const memberRoles = ['self', 'elder'] as const;
export const maxElders = 2;
export const isMember = (character: Character) => (memberRoles as readonly string[]).includes(character.role);

// 家族角色资料白名单：只保存游戏展示所需字段，拒绝健康资料等额外内容。
export function checkedProfile(role: string, name: string, profile: Record<string, unknown>): MemberProfile {
  requireCondition((memberRoles as readonly string[]).includes(role), 'INVALID_MEMBER', '角色类型无效');
  const trimmed = name.trim();
  requireCondition(trimmed.length >= 1 && [...trimmed].length <= 10, 'INVALID_MEMBER', '姓名为 1–10 个字');
  const allowed = role === 'self' ? ['title', 'avatar'] : ['title', 'avatar', 'relation', 'age', 'sex', 'mode', 'consent'];
  requireCondition(Object.keys(profile).every(key => allowed.includes(key)) && allowed.every(key => key in profile), 'INVALID_MEMBER', '角色资料字段不符合契约');
  const title = profile.title;
  requireCondition(typeof title === 'string' && title.trim().length > 0 && [...title.trim()].length <= 10, 'INVALID_MEMBER', '称号为 1–10 个字');
  requireCondition(profile.avatar === 'male' || profile.avatar === 'female', 'INVALID_MEMBER', '形象无效');
  const clean: MemberProfile = { title: title.trim(), avatar: profile.avatar };
  if (role === 'elder') {
    const relation = typeof profile.relation === 'string' ? profile.relation.trim() : '';
    requireCondition(relation.length > 0 && [...relation].length <= 30 && !['本人', '自己', '我', 'self'].includes(relation), 'INVALID_MEMBER', '请填写与本人的关系；家人位置只用于老人');
    requireCondition(Number.isInteger(profile.age) && (profile.age as number) >= 1 && (profile.age as number) <= 120, 'INVALID_MEMBER', '年龄为 1–120 的整数');
    requireCondition(profile.sex === '男' || profile.sex === '女', 'INVALID_MEMBER', '性别无效');
    requireCondition(profile.mode === 'family' || profile.mode === 'self', 'INVALID_MEMBER', '填写方式无效');
    requireCondition(profile.consent === true, 'CONSENT_REQUIRED', '需要本人同意或已获家人同意后代填');
    Object.assign(clean, { relation, age: profile.age, sex: profile.sex, mode: profile.mode, consent: true });
  }
  return clean;
}

const defaultCalendar: Season[] = [
  { id: 'integration-2026-h2', starts_at: '2026-07-01T00:00:00+08:00', ends_at: '2027-01-01T00:00:00+08:00' },
  { id: 'integration-2027-h1', starts_at: '2027-01-01T00:00:00+08:00', ends_at: '2027-07-01T00:00:00+08:00' },
];

export class GameService {
  readonly ledger: Ledger;
  constructor(readonly db: Database, readonly now: Clock, readonly rules: RuleProviders, private randomInt: (maximum: number) => number, readonly calendar = defaultCalendar, private extensions: GameExtensions = {}) {
    this.ledger = new Ledger(db, now);
    checkedRules(rules, rules.currentVersion);
    const sorted = [...calendar].sort((left, right) => Date.parse(left.starts_at) - Date.parse(right.starts_at));
    requireCondition(new Set(calendar.map(season => season.id)).size === calendar.length && sorted.every((season, index) => {
      const start = Date.parse(season.starts_at); const end = Date.parse(season.ends_at);
      return Number.isFinite(start) && Number.isFinite(end) && start < end && (index === 0 || Date.parse(sorted[index - 1]!.ends_at) <= start);
    }), 'INVALID_CALENDAR', '赛季日历无效或重叠', 500);
  }

  own(accountId: string, cultivatorId: string): Character {
    const character = this.db.get<Character>('SELECT * FROM cultivators WHERE id = ? AND account_id = ?', cultivatorId, accountId);
    requireCondition(character, 'NOT_FOUND', '修仙者不存在或不属于当前账号', 404);
    return character;
  }

  task(taskId: string): Task {
    const task = this.db.get<Task>('SELECT * FROM tasks WHERE id = ?', taskId);
    requireCondition(task, 'NOT_FOUND', '任务实例不存在', 404);
    return task;
  }

  season() {
    const current = this.calendar.find(season => Date.parse(season.starts_at) / 1000 <= this.now() && this.now() < Date.parse(season.ends_at) / 1000);
    return { calendar_version: 'integration-calendar-v1', current: current ?? null };
  }

  characterSnapshot(accountId: string, cultivarId: string) {
    const character = this.own(accountId, cultivarId);
    const baseline = this.db.get<{ baseline_id: string; projection: string; created_at: number }>('SELECT baseline_id, projection, created_at FROM baselines WHERE cultivator_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1', character.id);
    return {
      cultivator_id: character.id, name: character.name, element: character.element, lifecycle: character.lifecycle, realm: character.realm,
      role: character.role, profile: JSON.parse(character.profile) as MemberProfile | Record<string, never>,
      resources: { spirit_stones: character.spirit_stones, realm_xp: character.realm_xp, materials: character.materials, seals: character.seals },
      // 累计有效日：日奖励组每成立一天加一，漏记不清零。
      days: this.db.get<{ days: number }>('SELECT COUNT(*) AS days FROM reward_groups WHERE cultivator_id = ?', character.id)!.days,
      pity: character.pity, compensation_tier: compensationTier(this.rules, character), draw_count: character.draw_count,
      initial_score: character.initial_score, initial_profile_id: character.initial_profile_id,
      baseline: baseline ? { baseline_id: baseline.baseline_id, confirmed_at: baseline.created_at, ...JSON.parse(baseline.projection) } : null,
      equipment: this.db.all('SELECT id AS equipment_id, catalogue_id, catalogue_version, slot, rarity, equipped FROM equipment WHERE cultivator_id = ? ORDER BY created_at, rowid', character.id),
    };
  }

  snapshot(accountId: string) {
    const account = this.db.get<{ revision: number; merit: number }>('SELECT revision, merit FROM accounts WHERE id = ?', accountId)!;
    const characters = this.db.all<{ id: string }>('SELECT id FROM cultivators WHERE account_id = ? ORDER BY created_at, rowid', accountId);
    return { revision: account.revision, merit: account.merit, cultivators: characters.map(character => this.characterSnapshot(accountId, character.id)), season: this.season() };
  }

  templates() {
    return this.rules.templates().map(template => ({ template_id: template.id, template_version: template.version, title: template.title, requirement: template.requirement, verification_levels: template.verification_levels, rule_version: this.rules.currentVersion }));
  }

  taskView(task: Task) {
    const template = JSON.parse(task.template_snapshot) as Template;
    return { task_instance_id: task.id, cultivator_id: task.cultivator_id, template_id: task.template_id, template_version: task.template_version, rule_version: task.rule_version, period: task.period, window_start: task.window_start, window_end: task.window_end, status: task.status, title: template.title, requirement: template.requirement, verification_levels: template.verification_levels,
      reward_group: template.reward_group ?? null,
      settlement: this.db.get('SELECT id AS settlement_id, spirit_stones, realm_xp, seals, settled_at, reason FROM settlements WHERE task_id = ?', task.id) ?? null,
      submissions: this.db.all('SELECT submission_id, status, sequence FROM submission_status WHERE task_id = ? ORDER BY updated_at', task.id),
      completion_method: this.db.get<{ level: string }>("SELECT json_extract(payload, '$.verification_level') AS level FROM verified_results WHERE task_id = ? ORDER BY created_at, rowid LIMIT 1", task.id)?.level ?? null,
    };
  }

  execute(accountId: string, command: string, payload: Record<string, unknown>, headerKey?: string): unknown {
    const text = (key: string) => payload[key] as string;
    const key = typeof payload.request_id === 'string' ? payload.request_id : headerKey;
    if (payload.request_id !== undefined && headerKey !== undefined) requireCondition(payload.request_id === headerKey, 'IDEMPOTENCY_CONFLICT', '请求头和正文幂等键不一致', 409);
    const mutate = <T>(work: () => T) => idempotent(this.db, this.now, accountId, command, key, payload, work);
    switch (command) {
      case 'growth.create': return mutate(() => {
        requireCondition(elements.includes(text('element') as typeof elements[number]) && text('name').trim().length <= 40, 'INVALID_CHARACTER', '灵根或角色名称无效');
        const cultivarId = id('cultivator');
        this.db.run('INSERT INTO cultivators (id, account_id, name, element, created_at) VALUES (?, ?, ?, ?, ?)', cultivarId, accountId, text('name').trim(), text('element'), this.now());
        this.db.touch(accountId);
        return this.characterSnapshot(accountId, cultivarId);
      });
      case 'growth.create_member': return mutate(() => this.createMember(accountId, text('role'), text('name'), payload.profile as Record<string, unknown>));
      case 'growth.update_member': return mutate(() => this.updateMember(accountId, text('cultivator_id'), text('name'), payload.profile as Record<string, unknown>));
      case 'growth.list': return this.snapshot(accountId);
      case 'growth.snapshot':
      case 'growth.select': return this.characterSnapshot(accountId, text('cultivator_id'));
      case 'growth.equip': return mutate(() => {
        this.own(accountId, text('cultivator_id'));
        requireCondition(allSlots.includes(text('slot')), 'INVALID_SLOT', '装备部位无效');
        const equipment = this.db.get<{ slot: string }>('SELECT slot FROM equipment WHERE id = ? AND cultivator_id = ?', text('equipment_id'), text('cultivator_id'));
        requireCondition(equipment?.slot === text('slot'), 'INVALID_EQUIPMENT', '装备归属或部位不匹配', 409);
        this.db.run('UPDATE equipment SET equipped = 0 WHERE cultivator_id = ? AND slot = ?', text('cultivator_id'), text('slot'));
        this.db.run('UPDATE equipment SET equipped = 1 WHERE id = ?', text('equipment_id'));
        this.db.touch(accountId);
        return this.characterSnapshot(accountId, text('cultivator_id'));
      });
      case 'growth.unequip': return mutate(() => {
        this.own(accountId, text('cultivator_id'));
        requireCondition(allSlots.includes(text('slot')), 'INVALID_SLOT', '装备部位无效');
        this.db.run('UPDATE equipment SET equipped = 0 WHERE cultivator_id = ? AND slot = ?', text('cultivator_id'), text('slot'));
        this.db.touch(accountId);
        return this.characterSnapshot(accountId, text('cultivator_id'));
      });
      case 'growth.draw': return mutate(() => {
        const character = this.own(accountId, text('cultivator_id'));
        return isMember(character) ? this.pixelDraw(accountId, character, payload.count as number, text('request_id')) : this.draw(accountId, text('cultivator_id'), payload.count as number);
      });
      case 'quests.family_today': return this.familyTasks(accountId, text('date'));
      case 'quests.templates': return { templates: this.templates() };
      case 'quests.assign': return mutate(() => this.assign(accountId, text('cultivator_id'), text('template_id'), text('date')));
      case 'quests.list': {
        this.own(accountId, text('cultivator_id'));
        return { tasks: this.db.all<Task>('SELECT * FROM tasks WHERE cultivator_id = ? ORDER BY created_at, id', text('cultivator_id')).map(task => this.taskView(task)) };
      }
      case 'quests.claim': return mutate(() => {
        const task = this.task(text('quest_id'));
        this.own(accountId, text('cultivator_id'));
        requireCondition(task.cultivator_id === text('cultivator_id'), 'NOT_FOUND', '任务不属于此修仙者', 404);
        const settlement = this.db.get('SELECT id AS settlement_id, spirit_stones, realm_xp, seals, settled_at, reason FROM settlements WHERE task_id = ?', task.id);
        requireCondition(settlement, 'NOT_CLAIMABLE', '健康任务核验后自动结算，尚无可领取结果', 409);
        return { task_instance_id: task.id, settlement };
      });
      case 'season.refresh': {
        this.own(accountId, text('cultivator_id'));
        const season = this.season();
        requireCondition(season.current, 'SEASON_UNAVAILABLE', '当前日期没有已发布的赛季', 409);
        return { ...season, cultivator_id: text('cultivator_id'), checkup_status: 'not_integrated', checkup_reminder: '本赛季体检基线接入后更新，现有积累保持不变' };
      }
      default:
        if (this.extensions.commands?.[command]) {
          const extension = this.extensions.commands[command];
          const validate = (value: unknown) => {
            requireCondition(extension.validateOutput(value), 'INVALID_PROJECTION', '模块输出不符合游戏投影契约', 500);
            return value;
          };
          const result = extension.execute(accountId, payload);
          return result instanceof Promise ? result.then(validate) : validate(result);
        }
        requireCondition(false, 'NOT_IMPLEMENTED', '该业务等待模块负责人接入', 501);
    }
  }

  // 灵宠与微信记录页读取同一份：当日全部家族角色的任务、核验方式与结算。
  familyTasks(accountId: string, date: string) {
    requireCondition(/^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(dayStart(date)) && dayKey(dayStart(date)) === date, 'INVALID_DATE', '日期无效');
    const account = this.db.get<{ revision: number }>('SELECT revision FROM accounts WHERE id = ?', accountId)!;
    const characters = this.db.all<Character>('SELECT * FROM cultivators WHERE account_id = ? ORDER BY created_at, rowid', accountId);
    return { revision: account.revision, business_date: date, members: characters.map(character => ({
      cultivator_id: character.id, role: character.role,
      tasks: this.db.all<Task>('SELECT * FROM tasks WHERE cultivator_id = ? AND period = ? ORDER BY created_at, id', character.id, date).map(task => this.taskView(task)),
    })) };
  }

  private createMember(accountId: string, role: string, name: string, profile: Record<string, unknown>) {
    const clean = checkedProfile(role, name, profile);
    if (role === 'self') requireCondition(!this.db.get("SELECT id FROM cultivators WHERE account_id = ? AND role = 'self'", accountId), 'SELF_EXISTS', '本人角色已存在', 409);
    else {
      const elders = this.db.all<Character>("SELECT * FROM cultivators WHERE account_id = ? AND role = 'elder'", accountId);
      requireCondition(elders.length < maxElders, 'MEMBER_LIMIT', '当前最多照顾两位老人', 409);
      requireCondition(!elders.some(elder => this.sameElder(elder, name.trim(), clean)), 'MEMBER_EXISTS', '这位家人已有档案，请直接选择原来的角色', 409);
    }
    const cultivarId = id('cultivator');
    this.db.run('INSERT INTO cultivators (id, account_id, name, element, created_at, role, profile) VALUES (?, ?, ?, ?, ?, ?, ?)', cultivarId, accountId, name.trim(), profileElement, this.now(), role, JSON.stringify(clean));
    this.db.touch(accountId);
    return this.characterSnapshot(accountId, cultivarId);
  }

  private updateMember(accountId: string, cultivarId: string, name: string, profile: Record<string, unknown>) {
    const character = this.own(accountId, cultivarId);
    requireCondition(isMember(character), 'INVALID_MEMBER', '联调角色没有家族资料', 409);
    const clean = checkedProfile(character.role, name, profile);
    if (character.role === 'elder') {
      const others = this.db.all<Character>("SELECT * FROM cultivators WHERE account_id = ? AND role = 'elder' AND id != ?", accountId, cultivarId);
      requireCondition(!others.some(elder => this.sameElder(elder, name.trim(), clean)), 'MEMBER_EXISTS', '另一位家人已有相同基本资料', 409);
    }
    this.db.run('UPDATE cultivators SET name = ?, profile = ? WHERE id = ?', name.trim(), JSON.stringify(clean), cultivarId);
    this.db.touch(accountId);
    return this.characterSnapshot(accountId, cultivarId);
  }

  private sameElder(elder: Character, name: string, profile: MemberProfile) {
    const other = JSON.parse(elder.profile) as MemberProfile;
    return elder.name === name && other.age === profile.age && other.sex === profile.sex;
  }

  assign(accountId: string, cultivarId: string, templateId: string, date: string) {
    const character = this.own(accountId, cultivarId);
    requireCondition(character.lifecycle === 'cultivating', 'TASK_NOT_APPLICABLE', '当前生命周期不安排健康任务', 409);
    requireCondition(/^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(dayStart(date)) && dayKey(dayStart(date)) === date, 'INVALID_DATE', '日期无效');
    const start = dayStart(date);
    requireCondition(date >= dayKey(this.now()) && start < this.now() + 31 * 86400, 'INVALID_DATE', '仅安排今日至未来 30 天内任务');
    const template = this.rules.templates().find(item => item.id === templateId);
    requireCondition(template, 'TEMPLATE_UNAVAILABLE', '任务模板不存在', 404);
    requireCondition(Number.isSafeInteger(template.base_stones) && template.base_stones >= 0 && Number.isSafeInteger(template.base_xp) && template.base_xp >= 0, 'INVALID_RULES', '任务奖励配置无效', 500);
    const previous = this.db.get<Task>('SELECT * FROM tasks WHERE cultivator_id = ? AND template_id = ? AND period = ?', cultivarId, templateId, date);
    if (previous) return this.taskView(previous);
    const taskId = id('task');
    checkedRules(this.rules, this.rules.currentVersion);
    this.db.run('INSERT INTO tasks (id, cultivator_id, template_id, template_version, rule_version, period, window_start, window_end, template_snapshot, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', taskId, cultivarId, templateId, template.version, this.rules.currentVersion, date, start, start + 86400, JSON.stringify(template), this.now());
    this.db.touch(accountId);
    return this.taskView(this.task(taskId));
  }

  private draw(accountId: string, cultivarId: string, count: number) {
    requireCondition(count === 1 || count === 10, 'INVALID_DRAW_COUNT', '只支持单抽或十连');
    const character = this.own(accountId, cultivarId);
    requireCondition(character.lifecycle !== 'ascended', 'ACTION_UNAVAILABLE', '该修仙者当前仅可查看', 409);
    const current = this.rules.getRules(this.rules.currentVersion);
    const rules = legacyRules(this.rules, isPixel(current) ? 'integration-v1' : this.rules.currentVersion);
    const tier = compensationTier(this.rules, character);
    const operationId = id('draw');
    this.ledger.change(accountId, cultivarId, 'spirit_stones', -rules.draw_cost * count, operationId, 'draw');
    const items: unknown[] = [];
    let hasSpirit = false;
    let materials = 0;
    for (let index = 0; index < count; index++) {
      let rarity = rollRarity(rules, this.randomInt(10000));
      if (character.pity + 1 >= rules.pity_limits[tier]! && (rarity === 'common' || rarity === 'spirit')) rarity = 'immortal';
      if (count === 10 && index === 9 && !hasSpirit && rarity === 'common') rarity = 'spirit';
      hasSpirit ||= rarity !== 'common';
      character.pity = rarity === 'immortal' || rarity === 'divine' ? 0 : character.pity + 1;
      const catalogue = this.rules.catalogue(character.element, rarity, rules.version);
      requireCondition(catalogue.length > 0 && catalogue.every(item => item.rarity === rarity && slots.includes(item.slot as typeof slots[number])), 'CATALOGUE_UNAVAILABLE', '装备目录缺失或不匹配', 409);
      const selectedIndex = this.randomInt(catalogue.length);
      requireCondition(Number.isInteger(selectedIndex) && selectedIndex >= 0 && selectedIndex < catalogue.length, 'INVALID_RANDOM', '目录随机索引越界', 500);
      const item = catalogue[selectedIndex]!;
      const existing = this.db.get<{ id: string }>("SELECT id FROM equipment WHERE cultivator_id = ? AND catalogue_id = ? AND catalogue_version = 'integration-v1'", cultivarId, item.id);
      const equipmentId = existing?.id ?? id('equipment');
      const converted = existing ? rules.duplicate_materials[rarity] : 0;
      if (!existing) this.db.run('INSERT INTO equipment (id, cultivator_id, catalogue_id, slot, rarity, draw_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)', equipmentId, cultivarId, item.id, item.slot, rarity, operationId, this.now());
      materials += converted;
      items.push({ equipment_id: equipmentId, catalogue_id: item.id, slot: item.slot, rarity, duplicate: Boolean(existing), materials: converted });
    }
    if (materials) this.ledger.change(accountId, cultivarId, 'materials', materials, operationId, 'duplicate_equipment');
    this.db.run('UPDATE cultivators SET pity = ? WHERE id = ?', character.pity, cultivarId);
    this.db.touch(accountId);
    return { draw_id: operationId, rule_version: rules.version, items, character: this.characterSnapshot(accountId, cultivarId) };
  }

  // B 的聚宝阁规则：首份确认属性决定的连续概率、四槽等概率再槽内模板等概率、十连末件史诗保障、重复装备保留为独立实例。
  private pixelDraw(accountId: string, character: Character, count: number, requestId: string) {
    requireCondition(count === 1 || count === 10, 'INVALID_DRAW_COUNT', '只支持单抽或十连');
    requireCondition(character.lifecycle !== 'ascended', 'ACTION_UNAVAILABLE', '该修仙者当前仅可查看', 409);
    requireCondition(character.initial_score !== null, 'INITIAL_PROFILE_REQUIRED', '请先确认一份基础档案，再来聚宝阁祈愿', 409);
    const rules = checkedRules(this.rules, pixelRules.version);
    requireCondition(isPixel(rules), 'INVALID_RULES', '像素规则版本不可用', 500);
    const cost = count === 10 ? rules.ten_cost : rules.draw_cost;
    const operationId = id('draw');
    this.ledger.change(accountId, character.id, 'spirit_stones', -cost, operationId, 'draw');
    const pick = (maximum: number) => {
      const value = this.randomInt(maximum);
      requireCondition(Number.isInteger(value) && value >= 0 && value < maximum, 'INVALID_RANDOM', '随机提供方越界', 500);
      return value;
    };
    const rolled = Array.from({ length: count }, () => {
      const rarity = rollPixelRarity(rules, character.initial_score!, this.randomInt(1_000_000));
      const slot = pixelSlots[pick(pixelSlots.length)]!;
      const candidates = rules.templates.flatMap((template, index) => template.slot === slot ? [index] : []);
      return { rarity, template: candidates[pick(candidates.length)]! };
    });
    const guaranteed = count === 10 && rolled.every(item => item.rarity < rules.ten_guarantee_index);
    // 只升级末件；自然抽到的传说/神话不会被降级。
    if (guaranteed) rolled[rolled.length - 1]!.rarity = rules.ten_guarantee_index;
    const items = rolled.map(({ rarity, template }) => {
      const equipmentId = id('equipment');
      const info = rules.templates[template]!;
      this.db.run('INSERT INTO equipment (id, cultivator_id, catalogue_id, slot, rarity, catalogue_version, draw_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', equipmentId, character.id, `pixel:${template}`, info.slot, pixelRarities[rarity]!, rules.catalogue_version, operationId, this.now());
      return { equipment_id: equipmentId, catalogue_id: `pixel:${template}`, template, slot: info.slot, rarity: pixelRarities[rarity]!, rarity_index: rarity, name: info.names[rarity]!, stat: info.stat, amount: info.values[rarity]! };
    });
    this.db.run('UPDATE cultivators SET draw_count = draw_count + ? WHERE id = ?', count, character.id);
    this.db.touch(accountId);
    return { draw_id: operationId, request_id: requestId, rule_version: rules.version, catalogue_version: rules.catalogue_version, count, cost, guaranteed, items, character: this.characterSnapshot(accountId, character.id) };
  }

  // D 以服务身份提交的可信初始属性投影。首份确认冻结抽卡支持值；之后的补充报告只更新属性。
  recordBaseline(character: Character, serviceId: string, baselineId: string, projection: Record<string, unknown>, fingerprint: string) {
    const previous = this.db.get<{ id: string; cultivator_id: string; fingerprint: string }>('SELECT id, cultivator_id, fingerprint FROM baselines WHERE service_id = ? AND baseline_id = ?', serviceId, baselineId);
    if (previous) {
      requireCondition(previous.fingerprint === fingerprint && previous.cultivator_id === character.id, 'BASELINE_CONFLICT', '相同档案 ID 的内容或归属发生变化', 409);
      return false;
    }
    this.db.run('INSERT INTO baselines VALUES (?, ?, ?, ?, ?, ?, ?)', id('baseline'), character.id, serviceId, baselineId, fingerprint, JSON.stringify(projection), this.now());
    if (character.initial_score === null) {
      const state = projection.character_state as { hp_max: number; attack: number; defense: number; spirit: number; stamina: number };
      this.db.run('UPDATE cultivators SET initial_score = ?, initial_profile_id = ? WHERE id = ?', initialScore(state), baselineId, character.id);
    }
    this.db.touch(character.account_id);
    return true;
  }
}
