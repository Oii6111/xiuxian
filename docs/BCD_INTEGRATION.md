# A / B / C / D 整合说明

更新日期：2026-10-31。合并依据：[C 合并指南](BACKEND_INTEGRATION.md)。玩法和数值采用 B 的设计（PR #4）；所有资源、奖励和身份由 C 的服务端确认；微信与健康资料由 D 负责。

## 产品形态

- **年轻人**在网页上玩游戏。游戏服务（C）同时托管网页版客户端，同一个地址提供游戏和 API。
- **老人**不需要任何客户端。年轻人在游戏里点“绑定老人微信（扫码）”，老人用自己的微信扫 iLink 二维码，就绑定到系统的 AI Bot。之后老人在微信里报告每天的完成情况。
- 游戏内不再让老人填写记录。B 原来的“家属确认今日服药”页面已经改为只读的“微信记录”页。

## 部署结构（一台服务器）

| 进程 | 默认端口 | 职责 |
|---|---|---|
| C `server/`（`npm run dev`） | 8080 | 账号、家族角色、账本、抽卡、任务、结算、WebSocket；托管 `build/web`；把 `/wechat/bind/*`、`/api/v1/wechat/*` 转给 D，把 `/api/v1/health`、`/api/v1/game/projections/*` 转给健康入口 |
| D `wechat-sidecar/server.py` | 8000 | 微信 Bot 侧车：扫码绑定、老人对话、事件路由，经 `wechat-bridge` 调用 C 的内部接口 |
| `health-entry/server.py` | 8001 | 体检报告识别；确认后用服务凭证把最小属性投影写入 C |

C 的环境变量：`HEALTH_SERVICE_TOKEN`、`WEB_ROOT`（默认 `build/web`）、`WECHAT_SERVICE_URL`、`HEALTH_ENTRY_URL`。D 和健康入口的环境变量：`GAME_API_BASE=http://127.0.0.1:8080`、`HEALTH_SERVICE_TOKEN`（与 C 相同）、`HEALTH_EVENT_SINK_URL=http://127.0.0.1:8000/internal/v1/game/health-events`。网页导出：`Godot --headless --export-release Web build/web/index.html`。本轮没有部署到服务器。

## 统一后的规则（C `pixel-local-v1`，按 B 的设计）

| 项目 | 规则 |
|---|---|
| 家族 | 一个账号有一个本人角色和最多两位老人：`growth.create_member` / `growth.update_member`，资料字段白名单 |
| 钱包 | 每个角色独立：`spirit_stones`（游戏里叫灵气）、`realm_xp`（修为）、`seals`（灵印），累计有效日 `days`；全部经 Ledger 写入 |
| 每日奖励 | 同一角色、同一北京时间自然日的日奖励组 `daily_plan` 只结算一次：灵气 +100、修为 +10、灵印 +1、累计日 +1。核验方式只决定能否成立，不影响奖励数量 |
| 抽卡 | `growth.draw`：单抽 70，十连 700；五档品质；武器、衣服、鞋子、饰品四个槽位；按首份初始属性连续插值的概率；先等概率选槽位，再在槽内等概率选模板；十连没有史诗时只把末件升为史诗；重复装备保留为独立实例 |
| 穿戴 | `growth.equip` / `growth.unequip`，按角色校验归属 |
| 初始属性 | 年轻人在网页健康入口上传报告。确认时先向 C 申请角色票据 `POST /api/v2/baselines/tickets`，健康入口再以服务身份写入 `POST /internal/v1/baselines`。首份档案冻结抽卡支持值 |
| 任务读取 | `quests.family_today`：当日全部角色的任务、核验方式和结算；灵宠与微信记录页使用同一份数据 |

`integration-v1` 保留给已经派发的旧任务和 C 原有的回归测试。

## A：战斗与生命周期（分支 codex/gacha-family-accounts）

A 的四技能战斗、二十 Boss 招式与阶段、AI 陪练、渡劫台/闭关/飞升界面原样合入。战斗手感、数值与画面不变。正式账号的持久结果改由 C 确认：

| 命令 | C 的行为 |
|---|---|
| `lifecycle.request_change` | 按 A 的迁移表（修行→渡劫；渡劫→修行/闭关/飞升；闭关→修行/飞升）签发 5 分钟确认令牌，绑定角色、目标和版本；飞升需要两次确认 |
| `lifecycle.confirm_change` | 用令牌确认，`request_id` 幂等；过期返回 `TOKEN_EXPIRED`，确认期间状态已变化返回 `STALE_STATE` |
| `lifecycle.update_stage` | 渡劫阶段（cardio/fracture/pneumonia 模板）可前进或回退，`confirmation_token` 作为一次性点击标识；到出院不会自动结束渡劫 |
| `combat.start` | 只有修行状态的角色能开具名 Boss（b00–b19）会话 |
| `combat.finish` | 会话唯一；胜利时长不能短于 3 秒，也不能超过会话实际经过时间；首通按（角色, Boss）唯一，保留最快时间。战斗不产生灵气或其他资源，也不改变生命周期 |

角色快照新增 `progress`：`{state, version, template_id, stage_index, cleared_bosses}`。Godot 端的 `family_gateway` 对正式账号把确认转给 C，未登录的演示模式仍使用 A 原来的本机确认；`combat_view` 在具名 Boss 开始和结束时调用 C，再从快照同步首通与境界。护法灯、时间线、庆典卡片是纯画面数据，仍保存在本地。练习模式不调用服务端。

## 微信链路（D）

1. 游戏向 C 申请一次性业务凭据，不向任何人展示，然后调用 D 的 `POST /api/v1/wechat/bind`。D 调用 iLink `get_bot_qrcode` 并打开二维码页。
2. 老人扫码确认后，D 用 iLink 返回的 `ilink_bot_id` / `ilink_user_id` 调用 C 的 `/internal/v1/bindings/confirm` 并保存路由。Bot 凭证只保存在 D 侧（`bot_data/ilink_accounts.json`）。
3. 老人在微信里确认当前的用药安排，侧车把它记为进行中的疗程。之后老人说已经完成，确认后的 `medication_taken` 事件进入 `/internal/v1/game/health-events`。D 只在存在已确认计划时，经 `POST /internal/v1/bindings/:id/tasks` 启用当日 `daily_medication_record`，再按 `self_report` 提交结果。C 结算后，游戏和 Bot 回执同步。
4. 没有扫码绑定的发送者不进入健康处理：hook 会先调用 `/api/v1/elder/bound` 检查。

## 已移除

B 的 Python 账号服务 `server/account`、`account_client.gd`、本地文字联调夹具 `tools/wechat_link_demo` 及其测试都已删除，账号统一使用 C 的 `/api/v2/auth/*`。仍然保留的本地演示模式（未登录、`--preview`）不会写入正式账本。

## 验证

```bash
cd server && npm run check && npm run demo && npm run test:d
```

```bash
cd server && npm run test:godot -- <Godot控制台路径> && npm run test:godot-b -- <Godot控制台路径> && npm run test:godot-b -- <Godot控制台路径> a_backend_test
```

微信消息收发改为 sidecar 内置的 iLink 长轮询网关（`wechat-sidecar/ilink_gateway.py`）：`getupdates` 游标与去重状态持久化在 `bot_data/ilink_state.json`，入站消息交给 `elder_assistant.handle_message`，回复走 `sendmessage`；任务提醒也从 openclaw CLI 改为同一网关发送。`openclaw-health-hook` 已删除，不再需要外部插件。尚未验证：真实账号扫码后的长时间收发与限流表现。实时联机战斗、全服庆典仍未实现。
