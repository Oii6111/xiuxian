# 老人端已确认事件契约（内部）

游戏接入以 [C/D 桥接说明](../docs/TASK_REMINDER_BRIDGE.md) 为准。本契约含健康事实，只能在 D 域或另行授权的健康服务流转，不能直接发送到 C 的 `/internal/v1/task-results`。游戏审核适配器仅投影任务、绑定、授权和验证引用。

这是老人端到家庭端/其它内部服务的边界。它不是老人端 UI，也不包含游戏数值；下游服务是否把它映射到游戏，由服务端另行授权和建模。

```json
{
  "event_id": "health_20261031_abc123",
  "elder_id": "elder_demo_001",
  "event_type": "medication_taken",
  "facts": { "statement": "用户表示已服药" },
  "risk_level": "routine",
  "family_share": true,
  "source": "openclaw-weixin",
  "occurred_at": "2026-10-31T08:00:00+00:00"
}
```

约束：

- 只有 `POST /api/v1/elder/confirm` 成功后才发送；重复投递以 `event_id` 幂等。
- `family_share=false` 的事件不得推送给家属或游戏端。
- 不包含原始图片、药盒照片 URL、模型密钥、LLM 原始长回复。
- 下游必须再次做鉴权、审计和授权校验，不能把 `facts` 当处方或诊断。

配置：

```dotenv
HEALTH_EVENT_SINK_URL=http://internal-health-orchestrator/v1/events
HEALTH_EVENT_SINK_TOKEN=内部服务令牌
```
