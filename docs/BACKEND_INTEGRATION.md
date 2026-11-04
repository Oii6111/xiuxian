# C 本地后端与 A/B/D 合并指南

产品语义以 [设计 v2](../家族修真录-设计文档-v2.md) 和 [微信入口方案](WECHAT_ILINK_ENTRY.md) 为准。C 的本地实现已可运行；微信、AI、战斗、界面仍由各负责人接入。本轮没有部署远程服务器。

## 1. 所有权与合并顺序

| 负责人 | 主要维护范围 | 交给 C 的内容 |
|---|---|---|
| A | combat、lifecycle、战斗和渡劫场景 | 领域规则、状态迁移表、战果和会话契约、输出白名单与失败测试 |
| B | growth、quests、social、年轻人界面 | 游戏状态、快照投影、请求调用、模块存档迁移与交互测试 |
| C | 公共内核、网络、season、server 核心、共享契约 | 本地服务、权威账本、接口、合并门禁与运行说明 |
| D | 微信、健康识别与核验、story、内容 | 经真实授权的身份与最小验证事实、版本化规则/内容、通知消费者 |

每人自己的功能分支，通过 PR 合并；一个 `.tscn` 场景由一人主写。公共契约、运行时装配和数据库迁移由 C 协调，不复制公共服务到业务目录。

建议顺序：C 契约与服务 → B 账号/角色/任务/抽卡投影 → D 绑定与核验 → A 战斗和生命周期 → 剧情、社交与后续联机。B 和 D 可先使用本地模拟接口独立开发。

每个 PR 附请求/响应样例、失败状态、内容版本及测试命令。新增字段先更新契约；破坏性修改提供兼容版本，避免各组分别重命名字段。数据库迁移只追加，由 C 分配编号；旧迁移内容变化会使启动拒绝。Godot 状态变更同步更新模块版本和迁移测试。

## 2. 账号与统一协议

业务 API 返回 `{ok, code, message, data}`，失败时 data 为空对象。完整 OpenAPI 由 `/openapi.json` 提供。共享命令输入唯一来源为 `data/kernel/contracts.json`，后端从该文件构建验证器。

| 接口 | 内容 |
|---|---|
| `POST /api/v2/auth/register` | `{username,password}`；注册后另行登录 |
| `POST /api/v2/auth/login` | 返回账号 ID、用户名、会话 token、到期时间 |
| `GET /api/v2/auth/me` | 当前会话 |
| `POST /api/v2/auth/logout` | 空对象，退出当前会话 |
| `POST /api/v2/auth/logout-all` | 空对象，撤销账号全部会话 |

用户名经 NFKC、去除首尾空白和小写处理，允许 3–32 位字母/数字/下划线。密码 12–128 位，scrypt 加随机盐。会话有效期 7 天；令牌只在客户端内存使用，不进入 Store、日志或版本库。本轮没有密码找回、邮箱或第三方登录。

注册和登录每 IP 每分钟最多 10 次；每用户名 15 分钟内失败 5 次后限制继续登录。正式多进程部署时需共享限速存储，本轮按单进程本地服务验证。

## 3. B：角色、任务与客户端

| 命令 | 输入 |
|---|---|
| `growth.create` | name, element；另传 Idempotency-Key 请求头 |
| `growth.list` | 空对象，当前账号完整游戏快照 |
| `growth.snapshot` / `growth.select` | cultivator_id |
| `growth.draw` | cultivator_id, count, request_id |
| `growth.equip` | cultivator_id, equipment_id, slot；另传 Idempotency-Key |
| `quests.templates` | 空对象 |
| `quests.assign` | cultivator_id, template_id, date, request_id；date 为 UTC+8 的 YYYY-MM-DD |
| `quests.list` | cultivator_id |
| `quests.claim` | cultivator_id, quest_id, request_id；quest_id 是实例 ID |
| `season.refresh` | cultivator_id |

只安排当日至未来 30 天内的任务。模板定义允许证据，客户端不能改变奖励。实例保存时间窗和规则版本；同一角色、模板、周期重复安排返回已有实例。健康任务自动结算，claim 返回原结果，不重复奖励。growth.select 只校验并读取快照，当前选中角色由客户端管理。

```gdscript
const GameApi = preload("res://scripts/net/game_api.gd")
var api := GameApi.new()
add_child(api)
api.base_url = "http://127.0.0.1:8080"
var logged_in: Dictionary = await api.login(username, password)
if logged_in.ok:
    GameKernel.configure_backend(api)
    var created: Dictionary = await api.invoke("growth.create",
        {"name": "清荷真人", "element": "water"}, stable_creation_key)
```

上例供网络装配/账号控制器使用。常规界面仍通过 `GameKernel.dispatch()` 调用 B 的模块；模块内部使用 `request_backend(command,payload,key)`。本轮没有替 B 实现 growth/quests 客户端业务，直接 dispatch 这些占位命令仍返回 NOT_IMPLEMENTED。

成功响应后只写本模块 Store，再发事实事件。网络超时保留原幂等键；相同键不同内容返回 IDEMPOTENCY_CONFLICT。正文 request_id 与请求头同时存在时必须一致。

各模块实现 `on_backend_changed()` 清理账号相关投影。请求期间账号或地址变化返回 SESSION_CHANGED，旧响应不能写回 Store。C 的 season 已实现清理及 v1→v2 迁移。

绑定入口：`POST /api/v2/bindings/invitations` 传 cultivator_id；`GET /api/v2/bindings?cultivator_id=...` 查询；`POST /api/v2/bindings/:id/revoke` 撤回资料授权；`DELETE /api/v2/bindings/:id` 解绑。分别展示连接、绑定和资料授权。撤回后需先解绑，再通过新邀请确认，不能用连接恢复代替授权。

## 4. D：可信健康接缝

已接入 D 的桥接器与健康侧车，具体配置、审核入口和本地测试见 [C/D 任务桥接说明](TASK_REMINDER_BRIDGE.md)。游戏仍使用本节最小事实契约；健康域事件不能直接转发到游戏。

D 使用独立服务凭证，玩家会话不能调用。默认服务 ID 为 health；作用域为 binding:confirm、binding:connection、task:read、submission:write、result:write、notification:deliver。需要拆分服务时通过 `buildApp({services})` 配置最小权限。

`server/src/integration/client.ts` 提供 HealthClient。Python 原型也可以直接调用 HTTP，不要求迁移语言。内部令牌不能放在网页或模型上下文。

`POST /internal/v1/bindings/confirm`：

```json
{
  "invite_token": "来自游戏侧的邀请",
  "channel": "wechat_ilink",
  "channel_account_id": "D校验的Bot账号引用",
  "sender_id": "D校验的实际发送者引用",
  "elder_ref": "D健康档案的不透明引用",
  "consent_proof_id": "D保存的老人授权凭证引用",
  "consent_scope": "family_game",
  "health_processing": true,
  "ai_processing": true
}
```

这些字段来自真实身份验证与老人确认，不能让聊天模型填写。邀请有效期 10 分钟，新邀请替换该角色旧邀请；相同确认请求重试返回同一绑定，改变确认内容被拒绝。一位实际发送者只能有一条有效绑定。返回 binding_id 和 consent_version。

处理顺序：

1. D 从 iLink 收图，先在健康域持久保存消息/媒体，再推进轮询游标。
2. `GET /internal/v1/bindings/:id/tasks` 查询有效绑定的待办。
3. `POST /internal/v1/submissions/status` 提交 submission_id、task_instance_id、binding_id、consent_version、sequence、status。status 允许 received / needs_supplement / pending_confirmation / rejected。sequence 递增，相同序号内容不能冲突；迟到状态不覆盖已结算结果。
4. 确定性核验完成后提交最小事实。C 持久化后返回 pending，工作器每秒扫描待结算记录。
5. C 结算后生成通知，D 领取、回复并确认。接收成功不能提前回复“已记上”。

`POST /internal/v1/task-results`：

```json
{
  "event_id": "D持久化的稳定事件标识",
  "task_instance_id": "task_...",
  "cultivator_id": "cultivator_...",
  "binding_id": "binding_...",
  "consent_version": 1,
  "verification_level": "photo",
  "source": "photo",
  "channel": "wechat_ilink",
  "observed_at": "2026-10-31T08:30:00+08:00",
  "rule_version": "integration-v1"
}
```

初版 source 与 verification_level 一致；需家属复核才成立的结果按 family_confirm 提交，原图继续留在 D。可信设备验证必须使用 device 渠道，微信仪器照片按 photo。完成时间必须在任务窗口内且不晚于服务端当前时间。

- `POST /internal/v1/task-results/:id/settle`：空对象，立即执行或重试结算，返回稳定结算 ID 及实际资源增量。
- `GET /internal/v1/task-results/:id`：查询 pending / blocked / settled 和错误码。
- 同一事件改内容返回 EVENT_CONFLICT；同一任务不同事件仍返回同一结算。
- 临时结算失败指数退避，最多 300 秒；授权等业务失败进入 blocked。重新授权后重新核验，以新事件和授权版本提交，不自动恢复旧证据。
- 不接收原图、URL、健康读数、诊断、病史、药物名称、AI 解释或任意 payload；额外字段会被拒绝。

通知通过 `POST /internal/v1/notifications/claim` 传 `{limit:10}` 领取，返回 notification_id、binding_id、consent_version、lease_token、lease_until 和游戏结果。租约 30 秒；成功调用 `/:id/ack`，失败调用 `/:id/nack`，均传 `{lease_token:...}`。过期租约不能确认，重复 ack 安全；D 按 notification_id 持久去重。

D 发微信前再次确认授权和会话可用性。撤回授权会取消 C 未完成的通知，但无法撤销已到达微信的消息。通知重试不能创建新奖励。通道断开不等于资料授权撤回，可用 `POST /internal/v1/bindings/:id/connection` 单独更新 connected。

## 5. A 与规则/内容提供方

`GameExtensions.commands` 预留未实现命令的处理器，每个处理器同时提供 execute(accountId,payload) 和严格的 validateOutput(result)；输出不合格返回 INVALID_PROJECTION。A 仍需实现归属校验、生命周期确认令牌、迁移规则与幂等，不能信任客户端 confirmed=true。相关处理器本轮未注册。

涉及资源时只能通过 C 的 Ledger，在同一个数据库事务中完成；事务内禁止 await 或网络请求。战斗胜负不能产生康复或飞升结论。

`RuleProviders` 支持模板、奖励规则版本、补偿与装备目录。旧任务引用旧规则，发布新规则不能覆盖旧版本。正式动态补偿接入前默认 0 档，不接受客户端指定档位。

健康原型为十属性，产品 v2 为五属性；本轮不推测转换、不接收完整 baseline。D/B 明确游戏投影版本后，由 C 新增白名单接口。含病史和用药的属性原因说明留在健康域。

## 6. WebSocket 与恢复

1. 带玩家会话 `POST /api/v2/realtime/ticket`，获取 60 秒有效的一次性票据。
2. 连接 `ws://127.0.0.1:8080/api/v2/realtime?ticket=...`；HTTPS 环境对应 wss。长期会话令牌不放 URL。
3. 首包 `{type:"snapshot",version:1,revision:整数,data:游戏快照}`。
4. 变更包 `{type:"state_changed",version:1,revision:整数}` 仅作失效通知；发 `{type:"resync"}` 获取全量快照。版本缺口也走全量恢复。
5. 可发 `{type:"ping"}` 获取 pong；服务端另有标准 WebSocket 心跳。

仅推送当前账号，不能订阅任意账号。会话撤销或过期关闭连接；重连申请新票据并接收最新快照。

Godot 的 `scripts/net/game_realtime.gd` 提供 connect_stream(api)、disconnect_stream() 和 snapshot_received / snapshot_invalidated / connection_changed。网络断开指数退避自动重连，最多 30 秒；换账号时停止并清空旧数据，需要新登录后显式连接。B 消费快照信号更新自己的模块。

本轮不含主城 10 Hz 位置广播、队伍、房主战斗协议、公共庆典或假玩家；后续先定义可见性与会话归属。

## 7. 合并验收

- 后端运行 `npm run check`、`npm run demo`；公共内核变动再运行 Godot 网络测试及 `tools/test_kernel.ps1`。统一入口为 `tools/test_backend.ps1`。
- 验证两账号/两老人隔离、重复事件与幂等键、事务失败回滚、重启恢复、并发扣费、通知失败只重试通知。
- 验证证据级别、UTC+8 日界线、24 小时限制、撤回授权后的待结算拦截、断线快照恢复和换账号清理。
- 本地通过不代表 HTTPS、公网、真实微信和 AI 已验证。四部分合并后单独安排部署与真实渠道验收。

常见错误：INVALID_PAYLOAD、UNAUTHORIZED、IDEMPOTENCY_REQUIRED、IDEMPOTENCY_CONFLICT、CONSENT_REVOKED、EVENT_CONFLICT、TASK_WINDOW、NOT_CLAIMABLE、INSUFFICIENT_FUNDS、LEASE_CONFLICT、RULE_VERSION_UNAVAILABLE、SEASON_UNAVAILABLE、NOT_IMPLEMENTED。按错误码决定重试，不把网络失败当作业务成功。
