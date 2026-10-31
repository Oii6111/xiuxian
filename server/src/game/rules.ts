import { requireCondition } from '../core.js';

export const elements = ['wood', 'fire', 'earth', 'metal', 'water'] as const;
export const slots = ['weapon', 'armor', 'accessory', 'artifact'] as const;
export const rarities = ['common', 'spirit', 'immortal', 'divine'] as const;
export type Rarity = typeof rarities[number];
export type Verification = 'device' | 'photo' | 'family_confirm' | 'self_report';
export type Character = {
  id: string; account_id: string; name: string; element: string; lifecycle: string; realm: string;
  spirit_stones: number; realm_xp: number; materials: number; pity: number; created_at: number;
};
export type Template = {
  id: string; version: string; title: string; requirement: string; event_type: string;
  verification_levels: Verification[]; base_stones: number; base_xp: number;
};
export type CatalogueItem = { id: string; slot: string; rarity: Rarity };
export type RulePack = {
  version: string; daily_limit: number; draw_cost: number;
  verification_percent: Record<Verification, number>; compensation_percent: readonly number[];
  pity_limits: readonly number[]; rarity_weights: readonly number[];
  duplicate_materials: Record<Rarity, number>;
};

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

// A/B/D 通过这些提供方替换内容与计算；HTTP 输入不能提供奖励、概率或补偿档位。
export interface RuleProviders {
  currentVersion: string;
  getRules(version: string): RulePack;
  templates(): Template[];
  compensation(character: Character): number;
  catalogue(element: string, rarity: Rarity, version: string): CatalogueItem[];
}

export const defaultProviders: RuleProviders = {
  currentVersion: integrationRules.version,
  getRules(version) {
    requireCondition(version === integrationRules.version, 'RULE_VERSION_UNAVAILABLE', '规则版本尚未接入', 409);
    return structuredClone(integrationRules);
  },
  templates: () => structuredClone(integrationTemplates),
  compensation: () => 0,
  catalogue: (element, rarity) => slots.map(slot => ({ id: `${element}_${slot}_${rarity}`, slot, rarity })),
};

export function checkedRules(providers: RuleProviders, version: string): RulePack {
  const pack = providers.getRules(version);
  const positive = (value: number) => Number.isSafeInteger(value) && value > 0;
  requireCondition(pack.version === version && positive(pack.daily_limit) && positive(pack.draw_cost)
    && pack.rarity_weights.length === 4 && pack.rarity_weights.every(positive)
    && pack.rarity_weights.reduce((sum, value) => sum + value, 0) === 10000
    && pack.compensation_percent.length === 4 && pack.compensation_percent.every(positive)
    && pack.pity_limits.length === 4 && pack.pity_limits.every(positive)
    && Object.values(pack.verification_percent).every(positive)
    && Object.values(pack.duplicate_materials).every(positive), 'INVALID_RULES', '规则配置不合法', 500);
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
