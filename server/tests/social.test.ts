import assert from 'node:assert/strict';
import test from 'node:test';
import { fixture } from './helpers.js';

test('社群创建、加入、动态、评论和互动幂等', async context => {
  const app = await fixture(context);
  const owner = await app.account('social_owner');
  const guest = await app.account('social_guest');
  const created = await app.ok('/api/v2/social/communities', { name: '松风切磋社', visibility: 'public', max_members: 10, request_id: 'community-create' }, owner.token);
  const communityId = created.community.community_id;
  assert.equal((await app.request('/api/v2/social/communities', undefined, guest.token)).body.data.communities.length, 1);
  await app.ok(`/api/v2/social/communities/${communityId}/join`, { request_id: 'join-1' }, guest.token);
  const post = await app.ok(`/api/v2/social/communities/${communityId}/posts`, { body: '今晚演武台见。', request_id: 'post-1' }, owner.token);
  const repeated = await app.ok(`/api/v2/social/communities/${communityId}/posts`, { body: '今晚演武台见。', request_id: 'post-1' }, owner.token);
  assert.deepEqual(repeated, post);
  await app.ok(`/api/v2/social/communities/${communityId}/posts/${post.post.post_id}/comments`, { body: '收到。', request_id: 'comment-1' }, guest.token);
  await app.ok(`/api/v2/social/communities/${communityId}/posts/${post.post.post_id}/reactions`, { kind: 'like', request_id: 'reaction-1' }, guest.token);
  await app.ok(`/api/v2/social/communities/${communityId}/posts/${post.post.post_id}/reactions`, { kind: 'like', request_id: 'reaction-1' }, guest.token);
  const feed = await app.ok(`/api/v2/social/communities/${communityId}/feed?limit=10`, undefined, guest.token);
  assert.equal(feed.posts.length, 1);
  assert.equal(feed.posts[0].comments.length, 1);
  assert.equal(feed.posts[0].reactions.like, 1);
  assert.equal(feed.posts[0].body.includes('健康'), false);
});

test('私密社群隔离成员，退出时转移房主', async context => {
  const app = await fixture(context);
  const owner = await app.account('private_owner');
  const guest = await app.account('private_guest');
  const created = await app.ok('/api/v2/social/communities', { name: '闭关社', visibility: 'private', max_members: 2, request_id: 'private-create' }, owner.token);
  const id = created.community.community_id;
  assert.equal((await app.request(`/api/v2/social/communities/${id}/feed?limit=10`, undefined, guest.token)).body.code, 'NOT_MEMBER');
  assert.equal((await app.request(`/api/v2/social/communities/${id}/join`, { request_id: 'private-join' }, guest.token)).body.code, 'COMMUNITY_INVITE_REQUIRED');
  // 私密社群没有邀请端点时，先验证公开成员退出路径不会删除仍有成员的社群。
  const publicCreated = await app.ok('/api/v2/social/communities', { name: '轮值社', visibility: 'public', max_members: 2, request_id: 'rotation-create' }, owner.token);
  const publicId = publicCreated.community.community_id;
  await app.ok(`/api/v2/social/communities/${publicId}/join`, { request_id: 'rotation-join' }, guest.token);
  await app.ok(`/api/v2/social/communities/${publicId}/leave`, { request_id: 'rotation-leave' }, owner.token);
  const members = await app.ok(`/api/v2/social/communities/${publicId}/members`, undefined, guest.token);
  assert.equal(members.members[0].role, 'owner');
});

test('社群 PVP 房间复用 friendly_duel_v1 摘要并保留贡献', async context => {
  const app = await fixture(context);
  const host = await app.account('pvp_host');
  const guest = await app.account('pvp_guest');
  const created = await app.ok('/api/v2/social/communities', { name: '好友房', visibility: 'public', max_members: 10, request_id: 'pvp-community' }, host.token);
  const communityId = created.community.community_id;
  await app.ok(`/api/v2/social/communities/${communityId}/join`, { request_id: 'pvp-join-community' }, guest.token);
  const room = await app.ok(`/api/v2/social/communities/${communityId}/pvp`, { mode: 'friendly_duel_v1', request_id: 'pvp-room' }, host.token);
  assert.equal(room.match.status, 'waiting');
  const active = await app.ok(`/api/v2/social/pvp/${room.match.match_id}/join`, { request_id: 'pvp-enter' }, guest.token);
  assert.equal(active.match.status, 'active');
  const snapshot = { version: 'friendly_duel_v1', phase: 'match_end', round: 3, wins: [2, 1], winner: 0, reason: 'hp_zero', fighters: [{ id: 0, damage: 120, perfect: 2 }, { id: 1, damage: 90, perfect: 1 }] };
  const finished = await app.ok(`/api/v2/social/pvp/${room.match.match_id}/finish`, { snapshot, request_id: 'pvp-result' }, host.token);
  assert.equal(finished.match.status, 'finished');
  assert.equal(finished.match.winner_account_id, host.account_id);
  assert.deepEqual(finished.contribution[0], { fighter_index: 0, damage: 120, perfect: 2 });
  assert.equal(JSON.stringify(finished).includes('hp'), false);
});

test('世界频道和世界 Boss 贡献榜可用且贡献幂等', async context => {
  const app = await fixture(context);
  const first = await app.account('world_first');
  const second = await app.account('world_second');
  await app.ok('/api/v2/social/world/messages', { body: '世界 Boss 开门了。', request_id: 'world-message' }, first.token);
  const world = await app.ok('/api/v2/social/world?limit=10', undefined, second.token);
  assert.equal(world.messages.length, 1);
  const boss = world.boss.boss;
  const contribution = await app.ok('/api/v2/social/world/boss/contributions', { boss_id: boss.boss_id, damage: 250, request_id: 'boss-hit' }, first.token);
  const replay = await app.ok('/api/v2/social/world/boss/contributions', { boss_id: boss.boss_id, damage: 250, request_id: 'boss-hit' }, first.token);
  assert.deepEqual(replay, contribution);
  assert.equal(contribution.boss.my_contribution.damage, 250);
  assert.equal(contribution.boss.contributions[0].damage, 250);
});
