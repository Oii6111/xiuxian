import { Database } from '../database.js';
import { type Clock, dayKey, id, requireCondition, secret } from '../core.js';
import { idempotent } from '../game/ledger.js';

const visibility = ['public', 'friends', 'private'] as const;
const reactionKinds = ['like', 'support', 'cheer'] as const;
const pvpModes = ['friendly_duel_v1'] as const;
type Visibility = typeof visibility[number];
type ReactionKind = typeof reactionKinds[number];
type PvpMode = typeof pvpModes[number];

type Community = {
  id: string; owner_account_id: string; name: string; visibility: Visibility; max_members: number;
  created_at: number; updated_at: number; members_count: number; joined: number; role: string | null;
};
type Match = {
  id: string; community_id: string; host_account_id: string; guest_account_id: string | null;
  room_code: string; mode: PvpMode; status: 'waiting' | 'active' | 'finished' | 'cancelled';
  winner_account_id: string | null; reason: string; result_summary: string | null;
  created_at: number; started_at: number | null; finished_at: number | null;
};

export class SocialService {
  constructor(private db: Database, private now: Clock) {}

  commands() {
    return {
      'social.visit': { execute: (accountId: string, payload: Record<string, unknown>) => this.visit(accountId, this.text(payload, 'cultivator_id')), validateOutput: (value: unknown) => this.isObject(value) },
      'social.bless': { execute: (accountId: string, payload: Record<string, unknown>) => this.bless(accountId, this.text(payload, 'cultivator_id'), this.key(payload)), validateOutput: (value: unknown) => this.isObject(value) },
      'social.set_visibility': { execute: (accountId: string, payload: Record<string, unknown>) => this.setVisibility(accountId, this.text(payload, 'cultivator_id'), this.text(payload, 'scope') as Visibility), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.list': { execute: (accountId: string) => this.listCommunities(accountId), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.create': { execute: (accountId: string, payload: Record<string, unknown>) => this.createCommunity(accountId, this.text(payload, 'name'), this.text(payload, 'visibility') as Visibility, this.integer(payload, 'max_members'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.join': { execute: (accountId: string, payload: Record<string, unknown>) => this.joinCommunity(accountId, this.text(payload, 'community_id'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.leave': { execute: (accountId: string, payload: Record<string, unknown>) => this.leaveCommunity(accountId, this.text(payload, 'community_id'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.members': { execute: (accountId: string, payload: Record<string, unknown>) => ({ members: this.members(accountId, this.text(payload, 'community_id')) }), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.feed': { execute: (accountId: string, payload: Record<string, unknown>) => this.feed(accountId, this.text(payload, 'community_id'), this.integer(payload, 'limit')), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.post': { execute: (accountId: string, payload: Record<string, unknown>) => this.createPost(accountId, this.text(payload, 'community_id'), this.text(payload, 'body'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.comment': { execute: (accountId: string, payload: Record<string, unknown>) => this.createComment(accountId, this.text(payload, 'community_id'), this.text(payload, 'post_id'), this.text(payload, 'body'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.community.react': { execute: (accountId: string, payload: Record<string, unknown>) => this.react(accountId, this.text(payload, 'community_id'), this.text(payload, 'post_id'), this.text(payload, 'kind') as ReactionKind, this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.pvp.create': { execute: (accountId: string, payload: Record<string, unknown>) => this.createMatch(accountId, this.text(payload, 'community_id'), this.text(payload, 'mode') as PvpMode, this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.pvp.join': { execute: (accountId: string, payload: Record<string, unknown>) => this.joinMatch(accountId, this.text(payload, 'match_id'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.pvp.list': { execute: (accountId: string, payload: Record<string, unknown>) => ({ matches: this.matches(accountId, this.text(payload, 'community_id')) }), validateOutput: (value: unknown) => this.isObject(value) },
      'social.pvp.finish': { execute: (accountId: string, payload: Record<string, unknown>) => this.finishMatch(accountId, this.text(payload, 'match_id'), payload.snapshot, this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.world.list': { execute: (accountId: string, payload: Record<string, unknown>) => this.worldFeed(accountId, this.integer(payload, 'limit')), validateOutput: (value: unknown) => this.isObject(value) },
      'social.world.post': { execute: (accountId: string, payload: Record<string, unknown>) => this.worldPost(accountId, this.text(payload, 'body'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
      'social.world.boss': { execute: (accountId: string) => this.worldBoss(accountId), validateOutput: (value: unknown) => this.isObject(value) },
      'social.world.boss.contribute': { execute: (accountId: string, payload: Record<string, unknown>) => this.worldBossContribute(accountId, this.text(payload, 'boss_id'), this.integer(payload, 'damage'), this.key(payload), payload), validateOutput: (value: unknown) => this.isObject(value) },
    };
  }

  listCommunities(accountId: string) {
    return { communities: this.db.all<Community>(`
      SELECT c.*, COUNT(DISTINCT m.account_id) AS members_count,
        MAX(CASE WHEN m.account_id = ? THEN 1 ELSE 0 END) AS joined,
        MAX(CASE WHEN m.account_id = ? THEN m.role ELSE NULL END) AS role
      FROM communities c
      LEFT JOIN community_members m ON m.community_id = c.id
      WHERE c.visibility = 'public' OR EXISTS (SELECT 1 FROM community_members own WHERE own.community_id = c.id AND own.account_id = ?)
      GROUP BY c.id ORDER BY c.updated_at DESC, c.id`, accountId, accountId, accountId).map(item => this.communityView(item)) };
  }

  createCommunity(accountId: string, name: string, scope: Visibility, maxMembers: number, key: string | undefined, payload: unknown = {}) {
    const cleanName = name.normalize('NFKC').trim();
    requireCondition(cleanName.length >= 2 && cleanName.length <= 48, 'INVALID_COMMUNITY_NAME', '社群名称长度必须为 2–48 个字符');
    requireCondition(visibility.includes(scope), 'INVALID_VISIBILITY', '社群可见范围无效');
    requireCondition(Number.isSafeInteger(maxMembers) && maxMembers >= 2 && maxMembers <= 200, 'INVALID_MEMBER_LIMIT', '成员上限必须为 2–200');
    return idempotent(this.db, this.now, accountId, 'social.community.create', key, payload, () => {
      const communityId = id('community');
      const timestamp = this.now();
      this.db.run('INSERT INTO communities (id, owner_account_id, name, visibility, max_members, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)', communityId, accountId, cleanName, scope, maxMembers, timestamp, timestamp);
      this.db.run('INSERT INTO community_members (community_id, account_id, role, joined_at) VALUES (?, ?, ?, ?)', communityId, accountId, 'owner', timestamp);
      this.db.touch(accountId);
      return { community: this.community(accountId, communityId) };
    });
  }

  joinCommunity(accountId: string, communityId: string, key: string | undefined, payload: unknown = {}) {
    return idempotent(this.db, this.now, accountId, 'social.community.join', key, payload, () => {
      const community = this.rawCommunity(communityId);
      requireCondition(community, 'NOT_FOUND', '社群不存在', 404);
      const current = this.db.get('SELECT account_id FROM community_members WHERE community_id = ? AND account_id = ?', communityId, accountId);
      if (current) return { community: this.community(accountId, communityId), joined: true };
      requireCondition(community.visibility !== 'private', 'COMMUNITY_INVITE_REQUIRED', '私密社群需要邀请才能加入', 403);
      const count = this.db.get<{ count: number }>('SELECT COUNT(*) AS count FROM community_members WHERE community_id = ?', communityId)!.count;
      requireCondition(count < community.max_members, 'COMMUNITY_FULL', '社群成员已满', 409);
      this.db.run('INSERT INTO community_members (community_id, account_id, role, joined_at) VALUES (?, ?, ?, ?)', communityId, accountId, 'member', this.now());
      this.db.run('UPDATE communities SET updated_at = ? WHERE id = ?', this.now(), communityId);
      this.db.touch(accountId);
      return { community: this.community(accountId, communityId), joined: true };
    });
  }

  leaveCommunity(accountId: string, communityId: string, key: string | undefined, payload: unknown = {}) {
    return idempotent(this.db, this.now, accountId, 'social.community.leave', key, payload, () => {
      const membership = this.db.get<{ role: string }>('SELECT role FROM community_members WHERE community_id = ? AND account_id = ?', communityId, accountId);
      requireCondition(membership, 'NOT_MEMBER', '你不是该社群成员', 403);
      const community = this.rawCommunity(communityId);
      requireCondition(community, 'NOT_FOUND', '社群不存在', 404);
      this.db.run('DELETE FROM community_members WHERE community_id = ? AND account_id = ?', communityId, accountId);
      if (membership.role === 'owner') {
        const successor = this.db.get<{ account_id: string }>('SELECT account_id FROM community_members WHERE community_id = ? ORDER BY joined_at, account_id LIMIT 1', communityId);
        if (successor) this.db.run("UPDATE community_members SET role = 'owner' WHERE community_id = ? AND account_id = ?", communityId, successor.account_id);
        else this.db.run('DELETE FROM communities WHERE id = ?', communityId);
      }
      this.db.touch(accountId);
      return { community_id: communityId, left: true, deleted: !successorExists(this.db, communityId) };
    });
  }

  members(accountId: string, communityId: string) {
    this.requireVisible(accountId, communityId);
    return this.db.all<{ account_id: string; username: string; role: string; joined_at: number; cultivator_name: string | null; realm: string | null }>(`
      SELECT m.account_id, a.username, m.role, m.joined_at, c.name AS cultivator_name, c.realm
      FROM community_members m JOIN accounts a ON a.id = m.account_id
      LEFT JOIN cultivators c ON c.account_id = m.account_id
      WHERE m.community_id = ? ORDER BY m.role = 'owner' DESC, m.joined_at, m.account_id`, communityId);
  }

  feed(accountId: string, communityId: string, limit = 30) {
    this.requireVisible(accountId, communityId);
    const size = Math.min(50, Math.max(1, Number.isSafeInteger(limit) ? limit : 30));
    const posts = this.db.all<{ id: string; account_id: string; username: string; body: string; created_at: number }>(`
      SELECT p.id, p.account_id, a.username, p.body, p.created_at
      FROM community_posts p JOIN accounts a ON a.id = p.account_id
      WHERE p.community_id = ? ORDER BY p.created_at DESC, p.id DESC LIMIT ?`, communityId, size).map(post => ({
      post_id: post.id, author: { account_id: post.account_id, username: post.username }, body: post.body, created_at: post.created_at,
      reactions: this.reactionCounts(post.id), comments: this.comments(post.id),
    }));
    return { community: this.community(accountId, communityId), posts, pvp_matches: this.matches(accountId, communityId).slice(0, 20) };
  }

  createPost(accountId: string, communityId: string, body: string, key: string | undefined, payload: unknown = {}) {
    const cleanBody = body.normalize('NFKC').trim();
    requireCondition(cleanBody.length >= 1 && cleanBody.length <= 1000, 'INVALID_POST', '动态内容长度必须为 1–1000 个字符');
    return idempotent(this.db, this.now, accountId, 'social.community.post', key, payload, () => {
      this.requireMember(accountId, communityId);
      const postId = id('post');
      this.db.run('INSERT INTO community_posts (id, community_id, account_id, body, created_at) VALUES (?, ?, ?, ?, ?)', postId, communityId, accountId, cleanBody, this.now());
      this.db.run('UPDATE communities SET updated_at = ? WHERE id = ?', this.now(), communityId);
      this.db.touch(accountId);
      return { post: { post_id: postId, community_id: communityId, body: cleanBody, created_at: this.now() } };
    });
  }

  createComment(accountId: string, communityId: string, postId: string, body: string, key: string | undefined, payload: unknown = {}) {
    const cleanBody = body.normalize('NFKC').trim();
    requireCondition(cleanBody.length >= 1 && cleanBody.length <= 500, 'INVALID_COMMENT', '评论长度必须为 1–500 个字符');
    return idempotent(this.db, this.now, accountId, 'social.community.comment', key, payload, () => {
      this.requireMember(accountId, communityId);
      requireCondition(this.db.get('SELECT id FROM community_posts WHERE id = ? AND community_id = ?', postId, communityId), 'NOT_FOUND', '动态不存在', 404);
      const commentId = id('comment');
      this.db.run('INSERT INTO community_comments (id, post_id, account_id, body, created_at) VALUES (?, ?, ?, ?, ?)', commentId, postId, accountId, cleanBody, this.now());
      this.db.touch(accountId);
      return { comment: { comment_id: commentId, post_id: postId, body: cleanBody, created_at: this.now() } };
    });
  }

  react(accountId: string, communityId: string, postId: string, kind: ReactionKind, key: string | undefined, payload: unknown = {}) {
    requireCondition(reactionKinds.includes(kind), 'INVALID_REACTION', '互动类型无效');
    return idempotent(this.db, this.now, accountId, 'social.community.react', key, payload, () => {
      this.requireMember(accountId, communityId);
      requireCondition(this.db.get('SELECT id FROM community_posts WHERE id = ? AND community_id = ?', postId, communityId), 'NOT_FOUND', '动态不存在', 404);
      this.db.run('INSERT OR IGNORE INTO community_reactions (post_id, account_id, kind, created_at) VALUES (?, ?, ?, ?)', postId, accountId, kind, this.now());
      this.db.touch(accountId);
      return { post_id: postId, kind, reactions: this.reactionCounts(postId) };
    });
  }

  createMatch(accountId: string, communityId: string, mode: PvpMode, key: string | undefined, payload: unknown = {}) {
    requireCondition(pvpModes.includes(mode), 'INVALID_PVP_MODE', 'PVP 模式无效');
    return idempotent(this.db, this.now, accountId, 'social.pvp.create', key, payload, () => {
      this.requireMember(accountId, communityId);
      const matchId = id('pvp');
      const timestamp = this.now();
      this.db.run('INSERT INTO pvp_matches (id, community_id, host_account_id, room_code, mode, status, reason, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', matchId, communityId, accountId, secret().slice(0, 8).toUpperCase(), mode, 'waiting', '', timestamp);
      this.db.touch(accountId);
      return { match: this.matchView(this.match(matchId)) };
    });
  }

  joinMatch(accountId: string, matchId: string, key: string | undefined, payload: unknown = {}) {
    return idempotent(this.db, this.now, accountId, 'social.pvp.join', key, payload, () => {
      const match = this.match(matchId);
      this.requireMember(accountId, match.community_id);
      requireCondition(match.status === 'waiting', 'PVP_NOT_JOINABLE', '该 PVP 房间当前不可加入', 409);
      requireCondition(match.host_account_id !== accountId, 'PVP_SELF_JOIN', '房主不能重复加入自己的房间', 409);
      this.db.run('UPDATE pvp_matches SET guest_account_id = ?, status = ?, started_at = ? WHERE id = ? AND status = \'waiting\'', accountId, 'active', this.now(), matchId);
      this.db.touch(accountId);
      return { match: this.matchView(this.match(matchId)) };
    });
  }

  matches(accountId: string, communityId: string) {
    this.requireVisible(accountId, communityId);
    return this.db.all<Match>('SELECT * FROM pvp_matches WHERE community_id = ? ORDER BY created_at DESC, id DESC', communityId).map(item => this.matchView(item));
  }

  finishMatch(accountId: string, matchId: string, rawSnapshot: unknown, key: string | undefined, payload: unknown = {}) {
    const summary = this.summary(rawSnapshot);
    return idempotent(this.db, this.now, accountId, 'social.pvp.finish', key, payload, () => {
      const match = this.match(matchId);
      requireCondition(match.host_account_id === accountId, 'FORBIDDEN', '只有房主可以提交好友房结果', 403);
      requireCondition(match.status === 'active', 'PVP_NOT_ACTIVE', '该 PVP 房间不在进行中', 409);
      const winner = summary.winner === 0 ? match.host_account_id : summary.winner === 1 ? match.guest_account_id : null;
      this.db.run('UPDATE pvp_matches SET status = ?, winner_account_id = ?, reason = ?, result_summary = ?, finished_at = ? WHERE id = ?', 'finished', winner, summary.reason, JSON.stringify(summary), this.now(), matchId);
      this.db.touch(accountId);
      return { match: this.matchView(this.match(matchId)), contribution: summary.contribution };
    });
  }

  worldFeed(accountId: string, limit = 30) {
    const size = Math.min(50, Math.max(1, Number.isSafeInteger(limit) ? limit : 30));
    return {
      messages: this.db.all<{ id: string; account_id: string; username: string; body: string; created_at: number }>(`
        SELECT w.id, w.account_id, a.username, w.body, w.created_at
        FROM world_messages w JOIN accounts a ON a.id = w.account_id
        ORDER BY w.created_at DESC, w.id DESC LIMIT ?`, size).map(message => ({ message_id: message.id, author: { account_id: message.account_id, username: message.username }, body: message.body, created_at: message.created_at })),
      boss: this.worldBoss(accountId),
    };
  }

  worldPost(accountId: string, body: string, key: string | undefined, payload: unknown = {}) {
    const cleanBody = body.normalize('NFKC').trim();
    requireCondition(cleanBody.length >= 1 && cleanBody.length <= 500, 'INVALID_WORLD_MESSAGE', '世界频道消息长度必须为 1–500 个字符');
    return idempotent(this.db, this.now, accountId, 'social.world.post', key, payload, () => {
      const messageId = id('world_message');
      this.db.run('INSERT INTO world_messages (id, account_id, body, created_at) VALUES (?, ?, ?, ?)', messageId, accountId, cleanBody, this.now());
      this.db.touch(accountId);
      return { message: { message_id: messageId, body: cleanBody, created_at: this.now() } };
    });
  }

  worldBoss(accountId: string) {
    const boss = this.ensureWorldBoss();
    return {
      boss: { boss_id: boss.id, name: boss.name, status: boss.status, hp_total: boss.hp_total, hp_remaining: boss.hp_remaining, starts_at: boss.starts_at, ends_at: boss.ends_at, updated_at: boss.updated_at },
      contributions: this.db.all<{ account_id: string; username: string; damage: number; attempts: number }>(`SELECT c.account_id, a.username, c.damage, c.attempts FROM world_boss_contributions c JOIN accounts a ON a.id = c.account_id WHERE c.boss_id = ? ORDER BY c.damage DESC, c.account_id LIMIT 50`, boss.id),
      my_contribution: this.db.get<{ damage: number; attempts: number }>('SELECT damage, attempts FROM world_boss_contributions WHERE boss_id = ? AND account_id = ?', boss.id, accountId) ?? { damage: 0, attempts: 0 },
    };
  }

  worldBossContribute(accountId: string, bossId: string, damage: number, key: string | undefined, payload: unknown = {}) {
    requireCondition(Number.isSafeInteger(damage) && damage >= 1 && damage <= 5000, 'INVALID_BOSS_DAMAGE', '世界 Boss 单次贡献必须为 1–5000 的整数');
    return idempotent(this.db, this.now, accountId, 'social.world.boss.contribute', key, payload, () => {
      const boss = this.db.get<{ id: string; status: string; hp_remaining: number }>('SELECT id, status, hp_remaining FROM world_bosses WHERE id = ?', bossId);
      requireCondition(boss, 'NOT_FOUND', '世界 Boss 不存在', 404);
      requireCondition(boss.status === 'active', 'BOSS_NOT_ACTIVE', '世界 Boss 当前不可挑战', 409);
      const timestamp = this.now();
      this.db.run(`INSERT INTO world_boss_contributions (boss_id, account_id, damage, attempts, updated_at) VALUES (?, ?, ?, 1, ?)
        ON CONFLICT(boss_id, account_id) DO UPDATE SET damage = damage + excluded.damage, attempts = attempts + 1, updated_at = excluded.updated_at`, bossId, accountId, damage, timestamp);
      const remaining = Math.max(0, boss.hp_remaining - damage);
      this.db.run('UPDATE world_bosses SET hp_remaining = ?, status = ?, updated_at = ? WHERE id = ?', remaining, remaining === 0 ? 'defeated' : 'active', timestamp, bossId);
      this.db.touch(accountId);
      return { boss: this.worldBoss(accountId), recorded_damage: damage, source: 'world_boss_contribution_v1' };
    });
  }

  visit(accountId: string, cultivatorId: string) {
    const cultivator = this.db.get<{ id: string; account_id: string; name: string; realm: string }>('SELECT id, account_id, name, realm FROM cultivators WHERE id = ?', cultivatorId);
    requireCondition(cultivator, 'NOT_FOUND', '修仙者不存在', 404);
    const profile = this.profile(cultivator.account_id);
    if (cultivator.account_id !== accountId) {
      const sameCommunity = Boolean(this.db.get('SELECT 1 FROM community_members mine JOIN community_members target ON target.community_id = mine.community_id WHERE mine.account_id = ? AND target.account_id = ?', accountId, cultivator.account_id));
      requireCondition(profile.visibility === 'public' || (profile.visibility === 'friends' && sameCommunity), 'PROFILE_PRIVATE', '该名片当前不可见', 403);
    }
    return { cultivator_id: cultivator.id, name: cultivator.name, realm: cultivator.realm, visibility: profile.visibility, blessings: profile.blessings };
  }

  bless(accountId: string, cultivatorId: string, key: string | undefined) {
    return idempotent(this.db, this.now, accountId, 'social.bless', key, { cultivator_id: cultivatorId }, () => {
      const cultivator = this.db.get<{ account_id: string }>('SELECT account_id FROM cultivators WHERE id = ?', cultivatorId);
      requireCondition(cultivator, 'NOT_FOUND', '修仙者不存在', 404);
      requireCondition(cultivator.account_id !== accountId, 'INVALID_BLESSING', '不能给自己祈福');
      const today = dayKey(this.now());
      this.db.run('INSERT OR IGNORE INTO social_blessings (id, from_account_id, cultivator_id, day, created_at) VALUES (?, ?, ?, ?, ?)', id('blessing'), accountId, cultivatorId, today, this.now());
      const blessings = this.db.get<{ count: number }>('SELECT COUNT(*) AS count FROM social_blessings WHERE cultivator_id = ?', cultivatorId)!.count;
      this.db.run('INSERT OR IGNORE INTO social_profiles (account_id, visibility, blessings, updated_at) VALUES (?, ?, 0, ?)', cultivator.account_id, 'public', this.now());
      this.db.run('UPDATE social_profiles SET blessings = ?, updated_at = ? WHERE account_id = ?', blessings, this.now(), cultivator.account_id);
      this.db.touch(accountId);
      return { cultivator_id: cultivatorId, blessings };
    });
  }

  setVisibility(accountId: string, cultivatorId: string, scope: Visibility) {
    requireCondition(visibility.includes(scope), 'INVALID_VISIBILITY', '名片可见范围无效');
    requireCondition(this.db.get('SELECT id FROM cultivators WHERE id = ? AND account_id = ?', cultivatorId, accountId), 'FORBIDDEN', '角色不属于此账号', 403);
    this.db.run('INSERT INTO social_profiles (account_id, visibility, blessings, updated_at) VALUES (?, ?, 0, ?) ON CONFLICT(account_id) DO UPDATE SET visibility = excluded.visibility, updated_at = excluded.updated_at', accountId, scope, this.now());
    this.db.touch(accountId);
    return { cultivator_id: cultivatorId, visibility: scope };
  }

  private community(accountId: string, communityId: string) {
    const item = this.rawCommunityView(accountId, communityId);
    requireCondition(item, 'NOT_FOUND', '社群不存在', 404);
    return this.communityView(item);
  }

  private rawCommunity(communityId: string) {
    return this.db.get<{ id: string; owner_account_id: string; name: string; visibility: Visibility; max_members: number; created_at: number; updated_at: number }>('SELECT * FROM communities WHERE id = ?', communityId);
  }

  private rawCommunityView(accountId: string, communityId: string) {
    return this.db.get<Community>(`SELECT c.*, COUNT(DISTINCT m.account_id) AS members_count,
      MAX(CASE WHEN m.account_id = ? THEN 1 ELSE 0 END) AS joined,
      MAX(CASE WHEN m.account_id = ? THEN m.role ELSE NULL END) AS role
      FROM communities c LEFT JOIN community_members m ON m.community_id = c.id
      WHERE c.id = ? GROUP BY c.id`, accountId, accountId, communityId);
  }

  private communityView(item: Community) {
    return { community_id: item.id, owner_account_id: item.owner_account_id, name: item.name, visibility: item.visibility, max_members: item.max_members, members_count: Number(item.members_count), joined: Boolean(item.joined), role: item.role, created_at: item.created_at, updated_at: item.updated_at };
  }

  private requireVisible(accountId: string, communityId: string) {
    const item = this.rawCommunity(communityId);
    requireCondition(item, 'NOT_FOUND', '社群不存在', 404);
    if (item.visibility !== 'public') this.requireMember(accountId, communityId);
    return item;
  }

  private requireMember(accountId: string, communityId: string) {
    this.requireVisibleRaw(accountId, communityId);
  }

  private requireVisibleRaw(accountId: string, communityId: string) {
    const community = this.rawCommunity(communityId);
    requireCondition(community, 'NOT_FOUND', '社群不存在', 404);
    requireCondition(this.db.get('SELECT 1 FROM community_members WHERE community_id = ? AND account_id = ?', communityId, accountId), 'NOT_MEMBER', '需要先加入社群', 403);
  }

  private comments(postId: string) {
    return this.db.all<{ id: string; account_id: string; username: string; body: string; created_at: number }>(`SELECT c.id, c.account_id, a.username, c.body, c.created_at FROM community_comments c JOIN accounts a ON a.id = c.account_id WHERE c.post_id = ? ORDER BY c.created_at, c.id`, postId).map(comment => ({ comment_id: comment.id, author: { account_id: comment.account_id, username: comment.username }, body: comment.body, created_at: comment.created_at }));
  }

  private reactionCounts(postId: string) {
    const rows = this.db.all<{ kind: ReactionKind; count: number }>('SELECT kind, COUNT(*) AS count FROM community_reactions WHERE post_id = ? GROUP BY kind', postId);
    return Object.fromEntries(reactionKinds.map(kind => [kind, Number(rows.find(row => row.kind === kind)?.count ?? 0)]));
  }

  private match(matchId: string) {
    const item = this.db.get<Match>('SELECT * FROM pvp_matches WHERE id = ?', matchId);
    requireCondition(item, 'NOT_FOUND', 'PVP 房间不存在', 404);
    return item;
  }

  private matchView(item: Match) {
    return { match_id: item.id, community_id: item.community_id, host_account_id: item.host_account_id, guest_account_id: item.guest_account_id, room_code: item.room_code, mode: item.mode, status: item.status, winner_account_id: item.winner_account_id, reason: item.reason, created_at: item.created_at, started_at: item.started_at, finished_at: item.finished_at };
  }

  private summary(raw: unknown) {
    requireCondition(this.isObject(raw), 'INVALID_PVP_RESULT', 'PVP 结果必须为对象');
    const snapshot = raw as Record<string, unknown>;
    requireCondition(snapshot.version === 'friendly_duel_v1' && snapshot.phase === 'match_end', 'INVALID_PVP_RESULT', '只接受 friendly_duel_v1 的结束快照');
    requireCondition(Number.isSafeInteger(snapshot.winner) && [0, 1, -1].includes(snapshot.winner as number), 'INVALID_PVP_RESULT', 'PVP 胜者字段无效');
    requireCondition(Array.isArray(snapshot.wins) && snapshot.wins.length === 2 && snapshot.wins.every(value => Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2), 'INVALID_PVP_RESULT', 'PVP 局分字段无效');
    requireCondition(Array.isArray(snapshot.fighters) && snapshot.fighters.length === 2, 'INVALID_PVP_RESULT', 'PVP 选手摘要缺失');
    const contribution = (snapshot.fighters as unknown[]).map((fighter, index) => {
      requireCondition(this.isObject(fighter), 'INVALID_PVP_RESULT', 'PVP 选手摘要无效');
      const row = fighter as Record<string, unknown>;
      requireCondition(row.id === index && Number.isSafeInteger(row.damage) && Number.isSafeInteger(row.perfect) && (row.damage as number) >= 0 && (row.perfect as number) >= 0, 'INVALID_PVP_RESULT', 'PVP 贡献字段无效');
      return { fighter_index: index, damage: row.damage as number, perfect: row.perfect as number };
    });
    const reason = typeof snapshot.reason === 'string' ? snapshot.reason.slice(0, 128) : '';
    return { version: 'friendly_duel_v1', round: Number.isSafeInteger(snapshot.round) ? snapshot.round : 0, wins: snapshot.wins as number[], winner: snapshot.winner as number, reason, contribution };
  }

  private profile(accountId: string) {
    this.db.run('INSERT OR IGNORE INTO social_profiles (account_id, visibility, blessings, updated_at) VALUES (?, ?, 0, ?)', accountId, 'public', this.now());
    return this.db.get<{ visibility: Visibility; blessings: number }>('SELECT visibility, blessings FROM social_profiles WHERE account_id = ?', accountId)!;
  }

  private ensureWorldBoss() {
    this.db.run("UPDATE world_bosses SET status = 'expired', updated_at = ? WHERE status = 'active' AND ends_at <= ?", this.now(), this.now());
    const existing = this.db.get<{ id: string; name: string; status: 'active' | 'defeated' | 'expired'; hp_total: number; hp_remaining: number; starts_at: number; ends_at: number; updated_at: number }>("SELECT * FROM world_bosses WHERE status = 'active' ORDER BY starts_at DESC LIMIT 1");
    if (existing) return existing;
    const timestamp = this.now();
    const boss = { id: 'world_boss_' + dayKey(timestamp), name: '九霄蚀日·世界 Boss', status: 'active' as const, hp_total: 100000, hp_remaining: 100000, starts_at: timestamp, ends_at: timestamp + 7 * 86400, updated_at: timestamp };
    this.db.run('INSERT OR IGNORE INTO world_bosses (id, name, status, hp_total, hp_remaining, starts_at, ends_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', boss.id, boss.name, boss.status, boss.hp_total, boss.hp_remaining, boss.starts_at, boss.ends_at, boss.updated_at);
    return this.db.get<typeof boss>('SELECT * FROM world_bosses WHERE id = ?', boss.id)!;
  }

  private key(payload: Record<string, unknown>) { return typeof payload.request_id === 'string' ? payload.request_id : undefined; }
  private text(payload: Record<string, unknown>, name: string) { const value = payload[name]; requireCondition(typeof value === 'string', 'INVALID_PAYLOAD', `字段无效：${name}`); return value; }
  private integer(payload: Record<string, unknown>, name: string) { const value = payload[name]; requireCondition(Number.isSafeInteger(value), 'INVALID_PAYLOAD', `字段无效：${name}`); return value as number; }
  private isObject(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value); }
}

function successorExists(db: Database, communityId: string) {
  return Boolean(db.get('SELECT id FROM communities WHERE id = ?', communityId));
}
