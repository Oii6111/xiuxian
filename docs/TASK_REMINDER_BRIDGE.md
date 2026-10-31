# 任务提醒桥接：游戏任务板块 ↔ 老人微信

更新日期：2026-10-31。关联：[微信 iLink 入口方案](WECHAT_ILINK_ENTRY.md)、[团队合并指南](BACKEND_INTEGRATION.md)。

把「游戏里的健康任务」变成「给老人的定时提醒」，再把「老人的回复/照片」回传成「游戏里的任务完成」。提醒**不再由微信侧自己编**，来源是游戏的任务板块（`quests.assign`）；微信侧只负责到点推送和回传完成。

## 1. 闭环

```
年轻人在游戏里给修仙者安排今日任务(吃药/运动/量血压…)   quests.assign
        │
        ▼   微信侧每分钟拉一次待办
GET /internal/v1/bindings/:id/tasks  →  到点把提醒推给老人微信
        │
        ▼   老人回复/拍照
核对归属 → 匹配待办 → POST /internal/v1/task-results
        │
        ▼   游戏自动结算(发灵石)，出站通知
POST /internal/v1/notifications/claim → 回老人「今天的记录已记上」→ ack
```

老人端不用装新应用，照常聊天、拍照；灵石和任务进度只显示在游戏端。

## 2. 游戏侧要做的事（C/B 各一处）

### 2.1 补任务模板（`server/src/game/rules.ts`）

把下面这段加进 `integrationTemplates` 数组（与现有 `daily_step_record` 并列）：

```ts
  // —— 任务提醒桥接补充的健康行为模板（docs/TASK_REMINDER_BRIDGE.md）——
  { id: 'daily_medication_record', version: 'integration-v1', title: '按时吃药', requirement: '按家人设定的用药计划到点吃药并回复；不据此判断疗效或更改用药。', event_type: 'medication_record', verification_levels: ['self_report', 'photo', 'family_confirm'], base_stones: 6, base_xp: 15 },
  { id: 'daily_exercise_record', version: 'integration-v1', title: '出门活动', requirement: '完成一次出门散步/活动；可自述或发步数截图，不据此证明具体时长。', event_type: 'exercise_record', verification_levels: ['self_report', 'photo', 'device'], base_stones: 8, base_xp: 20 },
  { id: 'daily_move_reminder', version: 'integration-v1', title: '别久坐，起来活动', requirement: '久坐后起来活动一下；以老人自述为准。', event_type: 'move_record', verification_levels: ['self_report'], base_stones: 2, base_xp: 5 },
  { id: 'daily_bp_record', version: 'integration-v1', title: '量血压', requirement: '按既有测量计划量一次血压并发仪器屏幕照片；不按读数高低奖励。', event_type: 'bp_record', verification_levels: ['photo', 'device', 'family_confirm'], base_stones: 12, base_xp: 20 },
  { id: 'daily_hydration_reminder', version: 'integration-v1', title: '喝口水', requirement: '补充水分；以老人自述为准。', event_type: 'hydration_record', verification_levels: ['self_report'], base_stones: 2, base_xp: 5 },
  { id: 'followup_visit_record', version: 'integration-v1', title: '复查/复诊', requirement: '完成一次复查/复诊；可自述或发相关单据照片，不据此判断病情。', event_type: 'followup_record', verification_levels: ['self_report', 'photo', 'family_confirm'], base_stones: 15, base_xp: 30 },
```

每个模板的默认提醒时间由微信侧桥接器 `game_task_bridge.py` 里的 `TASK_TEMPLATES` 维护，两边的 `id` 必须一字不差。当前默认时间：

| 模板 | 默认提醒时间 |
|---|---|
| 按时吃药 | 08:00 / 12:00 / 18:00（仅聊天确认过在吃药才发，见下）|
| 出门活动 | 09:00 |
| 别久坐起来活动 | 10:30 / 15:00 / 16:30 |
| 量血压 | 08:00（一天一次）|
| 喝口水 | 11:00 / 14:00 |
| 复查/复诊 | 09:00（仅聊天得知要去看病才发，见下）|

> **提醒门槛（微信侧把关，因为游戏不能聊天）：** 游戏只派任务类别，但「这一刻要不要真的提醒」由微信侧据聊天得知的事实决定——
>
> - `按时吃药`：只有老人在聊天里说过「现在在吃某药」、并建成未结束的疗程（`medication_courses` 里 `status='active'`）才提醒；没说过就静默不发。
> - `复查/复诊`：只有老人在聊天里提到过「要去看病 / 复查 / 挂号」才提醒。
> - 其余（运动 / 久坐 / 量血压 / 喝水）：无门槛，到点即推。
>
> 判断在 `game_task_bridge.py` 的 `_gate()`，数据来自与 sidecar 共用的 `bot_data/elder_assistant.sqlite3`。游戏侧不需要为此做任何事。

### 2.2 配内部服务凭证

`server/.env` 里设一个至少 32 位的随机值，`server/src/main.ts` 会把它作为 D 的内部服务凭证：

```bash
# server/.env
HEALTH_SERVICE_TOKEN=<32位随机值>
```

生成方式：`node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"`。

同一串 token 填到微信侧桥接器的 `HEALTH_SERVICE_TOKEN` 环境变量，双方一致才能互认。不要写进 Godot、网页、模型提示词或提交到仓库。

### 2.3 建立一次绑定，拿到 `binding_id`

1. 年轻人在游戏里 `growth.create` 建修仙者。
2. `POST /api/v2/bindings/invitations` 传 `cultivator_id`，拿到 10 分钟有效的 `invite_token`。
3. 老人扫码授权后，微信侧用 `POST /internal/v1/bindings/confirm` 消费邀请（真实身份与授权由微信侧校验后填写），返回 `binding_id`。
4. 把这个 `binding_id` 填到桥接器环境变量里。

## 3. 微信侧桥接器怎么跑

代码在 `wechat-bridge/game_task_bridge.py`，独立于 sidecar 每分钟跑一轮。

```bash
# 环境变量
GAME_API_BASE=http://127.0.0.1:8080
HEALTH_SERVICE_TOKEN=<与游戏侧一致>
BINDING_ID=binding_...
OPENCLAW_SEND_TARGET=<老人微信 ilink_user_id>

# 试跑（只打印，不发送不提交）
OPENCLAW_DRY_RUN=1 python game_task_bridge.py --once

# 常驻
python game_task_bridge.py
```

三个动作都在这一个脚本里：

| 动作 | 游戏接口 | 说明 |
|---|---|---|
| 到点推提醒 | `GET /internal/v1/bindings/:id/tasks` | 按模板默认时间，每分钟比对一次 |
| 老人回复→完成 | `POST /internal/v1/task-results` | sidecar 在老人回复时调 `complete_task_from_reply()` |
| 「已记上」回执 | `claim` + `ack` | 领取结算通知，回推后 ack |

## 4. 内部接口速查（D 侧实际调用的四个）

统一返回 `{ok, code, message, data}`，认证用 `Authorization: Bearer <HEALTH_SERVICE_TOKEN>`。

### 4.1 查待办

```
GET /internal/v1/bindings/{binding_id}/tasks
```

返回 `data.tasks`，每条是任务实例视图：`task_instance_id`、`cultivator_id`、`template_id`、`status`（`pending`/`verified`/`settled`）、`window_start`/`window_end`、`title`、`requirement`、`verification_levels`、`rule_version`。桥接器只对 `status != 'settled'` 的任务推提醒。

### 4.2 提交验证结果

```
POST /internal/v1/task-results
```

```json
{
  "event_id": "evt_…（微信侧稳定生成，重发幂等）",
  "task_instance_id": "task_…",
  "cultivator_id": "cultivator_…",
  "binding_id": "binding_…",
  "consent_version": 1,
  "verification_level": "self_report",
  "source": "self_report",
  "channel": "wechat_ilink",
  "observed_at": "2026-10-31T08:30:00+08:00",
  "rule_version": "integration-v1"
}
```

只提交最小事实，不传原图、读数、诊断、药名。`verification_level` 由微信侧据「有照片=photo、纯文字=self_report」选择；游戏侧按该级别折算灵石（photo 80%、self_report 30%）。结算由游戏侧工作器每秒自动处理，也可 `POST /internal/v1/task-results/:id/settle` 立即触发。

### 4.3 领取结算通知

```
POST /internal/v1/notifications/claim   {"limit": 10}
POST /internal/v1/notifications/{id}/ack   {"lease_token": "…"}
POST /internal/v1/notifications/{id}/nack  {"lease_token": "…"}
```

`claim` 返回 30 秒租约（`notification_id`、`lease_token`、`payload`）。微信侧据此回老人「今天的记录已记上」，成功后 `ack`，失败 `nack` 让游戏退避重试。

## 5. 老人回复怎么算完成

桥接器 `complete_task_from_reply(binding_id, text, has_photo, message_id)` 的判定顺序：

1. 有照片 → `verification_level = photo`；纯文字 → `self_report`。
2. 匹配待办：先按关键词（「吃药/药」「血压」「血糖」「散步/走了/运动」「喝水」「复查/医院」）对到模板；对不上就取唯一待办或 `window_start` 最近的那条。
3. `event_id` 由 `binding_id + task_instance_id + message_id + 当天日期` 哈希生成，同一条消息重发不会重复记账。
4. 游戏侧对同一任务只结算一次（`settlements` 按 task_id 去重），不同 event 也不会重复发奖。

没有待办时老人发来的照片/文字，不擅自创建有奖任务，只按微信侧既有的资料归档/闲聊处理。

## 6. 「几点提醒」的两条路

- **当前（A）**：提醒时间由微信侧桥接器按模板 id 的默认值触发（见 `game_task_bridge.py` 的 `TASK_TEMPLATES`）。游戏侧零改动，只加模板就能联调。
- **后续（B）**：给 `quests.assign` 或模板加 `remind_at`/`schedule` 字段，游戏侧明确指定几点推。需要改 `data/kernel/contracts.json` + `server/src/game/service.ts`，属 C 的改动。

B 是正式方向（多老人、个性化时间表），A 足够路演。两条路互不影响，桥接器的接口不变。
