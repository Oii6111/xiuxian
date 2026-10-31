# 社交系统 v1

本版本落在 `xiuxian-a-combat-lifecycle`，复用已有账号、SQLite、命令入口、个人 WebSocket 和 `friendly_duel_v1` PVP。客户端入口是 `scripts/systems/social/module.gd`，服务端实现位于 `server/src/social/service.ts`。

## 能力

- **社群**：创建、加入、退出、成员列表、动态、评论和三种互动（`like`、`support`、`cheer`）。公开社群可发现；`friends` 社群只对成员开放；`private` 社群需要后续邀请能力。
- **世界频道**：全服动态，消息长度 1–500，按账号限流。公开投影只有账号名、正文和时间。
- **世界 Boss**：自动创建当前七日事件，保存共享血量、个人贡献和贡献榜。贡献是协作事实，第一版不直接改变灵石、修为或健康属性。
- **PVP 社群房间**：社群成员可以创建和加入 `friendly_duel_v1` 房间。房间状态为 `waiting → active → finished`，房主提交现有 `pvp_rules.gd` 的结束快照摘要，记录胜者、局分、伤害和完美格挡贡献。不会改动 PVP 数值、装备、账本或段位。

## 命令

新增命令已经写入 `data/kernel/contracts.json`，客户端通过原有 `GameApi.invoke` 调用：

`social.community.list/create/join/leave/members/feed/post/comment/react`、`social.pvp.create/join/list/finish`、`social.world.list/post/boss/boss.contribute`。

写操作必须带稳定的 `request_id` 或 `Idempotency-Key`。服务端通过 `idempotency` 表保证重试不会重复发动态、互动、加入记录或 Boss 贡献。公开 DTO 不包含健康资料、原图、授权记录或资源余额。

## PVP 快照边界

`pvp.finish` 只接受 `friendly_duel_v1` 且 `phase=match_end` 的快照，校验 `winner`、`wins` 和两位选手的 `damage/perfect` 字段。服务器只持久化这些摘要，不接受位置、HP、灵力、体力或客户端奖励字段。好友房仍由现有 `scripts/net/pvp_session.gd` 房主权威模拟；这一版的社群服务用于房间发现、成员权限和赛后活动记录。

## API 示例

```http
POST /api/v2/social/communities
Authorization: Bearer <token>
Content-Type: application/json

{"name":"松风切磋社","visibility":"public","max_members":50,"request_id":"community-1"}
```

```http
POST /api/v2/social/communities/<community_id>/pvp
Authorization: Bearer <token>
Content-Type: application/json

{"mode":"friendly_duel_v1","request_id":"room-1"}
```

```http
GET /api/v2/social/world?limit=30
Authorization: Bearer <token>
```

## 验证

服务端迁移版本从 1 追加到 2，`server/tests/social.test.ts` 覆盖社群权限、动态/评论/互动幂等、PVP 房间和结束摘要、世界频道与世界 Boss 协作。运行 `cd server; npm run check`。
