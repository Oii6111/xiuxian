import { requireCondition } from '../core.js';

export const elements = ['wood', 'fire', 'earth', 'metal', 'water'] as const;
export const slots = ['weapon', 'armor', 'accessory', 'artifact'] as const;
export const rarities = ['common', 'spirit', 'immortal', 'divine'] as const;
// 像素版（B 的玩法设计）：五档品质、四个槽位。与联调版 integration-v1 并存，旧任务和旧装备继续引用旧版本。
export const pixelSlots = ['weapon', 'robe', 'boots', 'amulet'] as const;
export const pixelRarities = ['common', 'fine', 'epic', 'legendary', 'mythic'] as const;
export const allSlots: readonly string[] = [...slots, ...pixelSlots];
// 像素玩法与灵根无关；新角色接口使用约定的兼容默认值，不新增灵根选择流程。
export const profileElement = 'earth';
export type Rarity = typeof rarities[number];
export type Verification = 'device' | 'photo' | 'family_confirm' | 'self_report';
export type Character = {
  id: string; account_id: string; name: string; element: string; lifecycle: string; realm: string;
  spirit_stones: number; realm_xp: number; materials: number; pity: number; created_at: number;
  role: string; profile: string; seals: number; draw_count: number; initial_score: number | null; initial_profile_id: string;
};
export type Template = {
  id: string; version: string; title: string; requirement: string; event_type: string;
  verification_levels: Verification[]; base_stones: number; base_xp: number;
  // 同组任务按北京时间自然日只结算一次奖励；未设置时沿用逐任务结算。
  reward_group?: string;
};
export type CatalogueItem = { id: string; slot: string; rarity: Rarity };
export type RulePack = {
  version: string; daily_limit: number; draw_cost: number;
  verification_percent: Record<Verification, number>; compensation_percent: readonly number[];
  pity_limits: readonly number[]; rarity_weights: readonly number[];
  duplicate_materials: Record<Rarity, number>;
};
export type PixelTemplate = { slot: typeof pixelSlots[number]; stat: 'life' | 'attack' | 'defense' | 'spirit' | 'stamina'; names: readonly string[]; values: readonly number[] };
export type PixelRulePack = {
  model: 'pixel'; version: string; catalogue_version: string; draw_cost: number; ten_cost: number;
  // 百分比；按首份已确认五项属性均值在两组权重间连续插值。
  high_weights: readonly number[]; low_weights: readonly number[];
  ten_guarantee_index: number; templates: readonly PixelTemplate[];
  daily_reward: { spirit_stones: number; realm_xp: number; seals: number };
};
export type AnyRulePack = RulePack | PixelRulePack;
export const isPixel = (pack: AnyRulePack): pack is PixelRulePack => 'model' in pack && pack.model === 'pixel';

// 联调配置不是最终数值策划。修改计算或目录时必须换版本，已派发任务继续引用旧版本。
export const integrationRules: RulePack = {
  version: 'integration-v1', daily_limit: 30, draw_cost: 10,
  verification_percent: { device: 100, photo: 80, family_confirm: 60, self_report: 30 },
  compensation_percent: [100, 110, 120, 130], pity_limits: [80, 70, 60, 50],
  rarity_weights: [6000, 3000, 900, 100],
  duplicate_materials: { common: 1, spirit: 3, immortal: 10, divine: 30 },
};

export const integrationTemplates: Template[] = [
  { id: 'daily_step_record', version: 'integration-v1', title: '上传今日步数记录', requirement: '提交带当日日期的步数记录；不据此证明散步时长。', event_type: 'step_record', verification_levels: ['photo', 'device', 'family_confirm', 'self_report'], base_stones: 8, base_xp: 20 },
  { id: 'daily_measurement_record', version: 'integration-v1', title: '上传计划内测量记录', requirement: '仅记录既有计划中的一次测量，不要求额外测量，不按读数高低奖励。', event_type: 'measurement_record', verification_levels: ['photo', 'device', 'family_confirm'], base_stones: 12, base_xp: 20 },
];

// 数值与 B 的 scripts/equipment_rules.gd、data/pixel-game-rules.v1.json 保持一致；改动必须换版本。
export const pixelRules: PixelRulePack = {
  model: 'pixel', version: 'pixel-local-v1', catalogue_version: 'pixel-equipment-v1', draw_cost: 70, ten_cost: 700,
  high_weights: [55, 30, 11, 3.5, 0.5], low_weights: [35, 33, 22, 8, 2], ten_guarantee_index: 2,
  templates: [
    { slot: 'weapon', stat: 'attack', names: ['青竹剑', '听风剑', '流云剑', '太初剑', '九霄神剑'], values: [3, 6, 10, 16, 24] },
    { slot: 'robe', stat: 'defense', names: ['素布衣', '云纹衣', '玄羽袍', '金霞仙衣', '太虚神袍'], values: [3, 6, 10, 16, 24] },
    { slot: 'robe', stat: 'life', names: ['护身衫', '青玉衫', '长生衣', '不灭仙衣', '万象神衣'], values: [8, 16, 26, 40, 60] },
    { slot: 'boots', stat: 'stamina', names: ['布履', '踏风靴', '逐月靴', '凌霄仙履', '踏虚神履'], values: [5, 10, 15, 22, 30] },
    { slot: 'amulet', stat: 'spirit', names: ['凝气佩', '凝神佩', '星河佩', '天元仙佩', '混元神佩'], values: [5, 10, 15, 22, 30] },
  ],
  daily_reward: { spirit_stones: 100, realm_xp: 10, seals: 1 },
};

// 两项家人计划记录共享一个日奖励组；步数/测量记录也属于“个人计划记录”，与 D 已接入的模板保持兼容。
const dailyPlan = { version: pixelRules.version, base_stones: 0, base_xp: 0, reward_group: 'daily_plan' } as const;
export const pixelTemplates: Template[] = [
  { ...dailyPlan, id: 'daily_medication_record', title: '记录今日既有用药安排', requirement: '仅在老人已确认当前用药计划后启用；本人在微信明确反馈后记录，不识别药名或剂量。', event_type: 'medication_record', verification_levels: ['self_report', 'family_confirm'] },
  { ...dailyPlan, id: 'daily_planned_record', title: '记录今日个人计划', requirement: '按已确认的作息、饮食等个人计划记录一次。', event_type: 'planned_record', verification_levels: ['self_report', 'family_confirm', 'photo', 'device'] },
  { ...dailyPlan, id: 'daily_step_record', title: '上传今日步数记录', requirement: '提交带当日日期的步数记录；不据此证明散步时长。', event_type: 'step_record', verification_levels: ['photo', 'device', 'family_confirm', 'self_report'] },
  { ...dailyPlan, id: 'daily_measurement_record', title: '上传计划内测量记录', requirement: '仅记录既有计划中的一次测量，不要求额外测量，不按读数高低奖励。', event_type: 'measurement_record', verification_levels: ['photo', 'device', 'family_confirm'] },
];

// A/B/D 通过这些提供方替换内容与计算；HTTP 输入不能提供奖励、概率或补偿档位。
export interface RuleProviders {
  currentVersion: string;
  getRules(version: string): AnyRulePack;
  templates(): Template[];
  compensation(character: Character): number;
  catalogue(element: string, rarity: Rarity, version: string): CatalogueItem[];
}

const packs: Record<string, AnyRulePack> = { [integrationRules.version]: integrationRules, [pixelRules.version]: pixelRules };
const sharedProviders = {
  getRules(version: string) {
    const pack = packs[version];
    requireCondition(pack, 'RULE_VERSION_UNAVAILABLE', '规则版本尚未接入', 409);
    return structuredClone(pack);
  },
  compensation: () => 0,
  catalogue: (element: string, rarity: Rarity) => slots.map(slot => ({ id: `${element}_${slot}_${rarity}`, slot, rarity })),
};

// 正式默认：像素版规则。integration-v1 仍可读取，供已派发的旧任务结算。
export const defaultProviders: RuleProviders = { ...sharedProviders, currentVersion: pixelRules.version, templates: () => structuredClone(pixelTemplates) };
// 联调版：保留给旧数据和原有回归测试。
export const integrationProviders: RuleProviders = { ...sharedProviders, currentVersion: integrationRules.version, templates: () => structuredClone(integrationTemplates) };

export function checkedRules(providers: RuleProviders, version: string): AnyRulePack {
  const pack = providers.getRules(version);
  const positive = (value: number) => Number.isSafeInteger(value) && value > 0;
  if (isPixel(pack)) {
    const weightsValid = (weights: readonly number[]) => weights.length === pixelRarities.length && weights.every(value => Number.isFinite(value) && value >= 0)
      && Math.abs(weights.reduce((sum, value) => sum + value, 0) - 100) < 1e-9;
    requireCondition(pack.version === version && positive(pack.draw_cost) && positive(pack.ten_cost)
      && weightsValid(pack.high_weights) && weightsValid(pack.low_weights)
      && Number.isInteger(pack.ten_guarantee_index) && pack.ten_guarantee_index >= 0 && pack.ten_guarantee_index < pixelRarities.length
      && pixelSlots.every(slot => pack.templates.some(template => template.slot === slot))
      && pack.templates.every(template => pixelSlots.includes(template.slot) && template.names.length === pixelRarities.length && template.values.length === pixelRarities.length && template.values.every(positive))
      && Object.values(pack.daily_reward).every(value => Number.isSafeInteger(value) && value >= 0), 'INVALID_RULES', '规则配置不合法', 500);
    return pack;
  }
  requireCondition(pack.version === version && positive(pack.daily_limit) && positive(pack.draw_cost)
    && pack.rarity_weights.length === 4 && pack.rarity_weights.every(positive)
    && pack.rarity_weights.reduce((sum, value) => sum + value, 0) === 10000
    && pack.compensation_percent.length === 4 && pack.compensation_percent.every(positive)
    && pack.pity_limits.length === 4 && pack.pity_limits.every(positive)
    && Object.values(pack.verification_percent).every(positive)
    && Object.values(pack.duplicate_materials).every(positive), 'INVALID_RULES', '规则配置不合法', 500);
  return pack;
}

export function legacyRules(providers: RuleProviders, version: string): RulePack {
  const pack = checkedRules(providers, version);
  requireCondition(!isPixel(pack), 'RULE_VERSION_UNAVAILABLE', '该规则版本不支持此计算', 409);
  return pack;
}

export function compensationTier(providers: RuleProviders, character: Character): number {
  const tier = providers.compensation(character);
  requireCondition(Number.isInteger(tier) && tier >= 0 && tier <= 3, 'INVALID_RULES', '补偿提供方返回无效档位', 500);
  return tier;
}

export function calculateReward(rules: RulePack, template: Template, level: Verification, tier: number, remaining: number) {
  const percent = rules.verification_percent[level];
  const compensation = rules.compensation_percent[tier];
  requireCondition(percent !== undefined && compensation !== undefined, 'INVALID_RULES', '验证方式或补偿档位无效', 500);
  const stones = Math.floor(template.base_stones * percent * compensation / 10000);
  return { spirit_stones: Math.max(0, Math.min(stones, remaining)), realm_xp: Math.floor(template.base_xp * percent / 100) };
}

export function rollRarity(rules: RulePack, roll: number): Rarity {
  requireCondition(Number.isInteger(roll) && roll >= 0 && roll < 10000, 'INVALID_RANDOM', '随机提供方越界', 500);
  let boundary = 0;
  for (let index = 0; index < rarities.length; index++) {
    boundary += rules.rarity_weights[index]!;
    if (roll < boundary) return rarities[index]!;
  }
  throw new Error('Unreachable rarity');
}

// 首份五项属性各自限制到 0–100 后取均值；均值越低，高品质概率越高。
export function initialScore(state: { hp_max: number; attack: number; defense: number; spirit: number; stamina: number }) {
  const values = [state.hp_max, state.attack, state.defense, state.spirit, state.stamina];
  return values.reduce((sum, value) => sum + Math.min(100, Math.max(0, value)), 0) / values.length;
}

export function pixelWeights(rules: PixelRulePack, score: number) {
  const support = 1 - Math.min(100, Math.max(0, score)) / 100;
  return rules.high_weights.map((high, index) => high + (rules.low_weights[index]! - high) * support);
}

// roll 为 0–999999 的整数，对应 0–100 的百分位。
export function rollPixelRarity(rules: PixelRulePack, score: number, roll: number): number {
  requireCondition(Number.isInteger(roll) && roll >= 0 && roll < 1_000_000, 'INVALID_RANDOM', '随机提供方越界', 500);
  const point = roll / 10000;
  let cumulative = 0;
  const weights = pixelWeights(rules, score);
  for (let index = 0; index < weights.length; index++) {
    cumulative += weights[index]!;
    if (point < cumulative) return index;
  }
  return weights.length - 1;
}
