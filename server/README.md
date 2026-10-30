# v2 服务端接入边界

本轮只实现 Godot 客户端内核。这里定义后端团队的接缝，尚无可启动的 Node.js 服务、SQLite 数据库或 WebSocket 服务。

依据设计文档 v2 第 19、20 节，服务端后续采用 Node.js + Fastify/Express + SQLite，原生 WebSocket；客户端不持有 AI 密钥。

## 模块边界

| 预留目录 | 责任 | 输出 |
|---|---|---|
| `health/` | 原始报告、设备事件、识别结果、家属确认、单独授权与撤回 | 向规则层输出经授权的事实 |
| `rules/` | 体检评级、任务判定、验证倍率、补偿、限额、奖励资格 | 游戏等级与结算请求，不带原始读数 |
| `game/` | 账号/角色、唯一资源账本、抽卡、任务、状态机、赛季 | 权威游戏快照和明确事件 |
| `realtime/` | 主城位置、队伍、战果汇总、世界进度、庆典广播 | 经过可见性校验的原生 WS 消息 |

健康域和游戏域分开存表、分开模块。当前 `health-entry/` 是既有独立原型，接入时需要健康域适配器；不能将它的原始响应直接送入游戏 Store、EventBus、社交名片或日志。

## 游戏命令接口（待实现）

`POST /api/v2/commands`，`Content-Type: application/json`，会话通过 `Authorization: Bearer ...` 传递。客户端适配器为 `scripts/net/game_api.gd`，挂到场景树、设置 `base_url` 后才能调用。

```json
{
  "version": 1,
  "command": "growth.draw",
  "payload": {"cultivator_id": "c_001", "count": 1, "request_id": "request_001"}
}
```

命令字段见 `data/kernel/contracts.json`。成功与失败均返回统一 Result：

```json
{"ok": false, "code": "NOT_IMPLEMENTED", "message": "抽卡尚未实现", "data": {}}
```

服务端必须校验会话及修仙者归属、枚举与数值范围、确认令牌、幂等键和业务资格；客户端字段校验只是帮助联调，不是信任依据。`request_id` 的去重记录、扣费、奖励、装备与保底变更应处于同一个 SQLite 事务。HTTP 重试复用同一键，返回原结算结果。未接入时明确失败，不偷偷在客户端发奖。

`lifecycle.request_change` 用于签发有时效、绑定账号/角色/目标状态的确认令牌；`confirm_change` 消费令牌并验证确认步骤。客户端不能仅提交 `confirmed: true` 就完成飞升。具体状态迁移表与二次确认流程由该系统负责人实现。

## 健康事件（独立接口，待实现）

统一格式遵循设计文档 v2 §19.2：`event_id`、`cultivator_id`、`event_type`、`task_id`、带时区的 `observed_at`、`source`、`verification_level`、`payload`、`confidence`、`consent_scope`。原始 payload 只在健康域使用，不能复用游戏命令端点上传。

游戏侧只接收白名单结果，如角色 id、赛季 id、五方面等级、已验证任务 id 或已确认状态。报告识别不直接决定奖励；规则代码负责可复现计算。缺失等级的中品兜底、属性下限等规则在后续规则层实现。

## 后续联调顺序

1. 实现会话与角色归属校验，确认上述命令/Result 格式。
2. 实现事务账本和任务结算，再接抽卡/背包/境界投影。
3. 单独接入健康域授权、识别与规则转换。
4. 实现原生 WebSocket、事件版本、重连后的完整快照，以及可见性过滤。
5. 接远端存档同步；本地 `kernel_v2.json` 只作游戏缓存，不能上传余额覆盖权威账本。
