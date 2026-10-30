# 游戏侧对接说明

这份文档给游戏开发看：入口系统如何把长辈的健康资料换成游戏的初始角色状态，以及游戏怎么读这份数据。

## 1. 整体流程

```
上传体检报告照片
   ↓  视觉模型识别（recognizer.py）
结构化健康指标（document）
   ↓  确定性规则引擎（rules.py）
初始角色状态（game_projection）
   ↓  用户确认、锁定
baseline JSON（锁定，不可手改）
   ↓  游戏读取
初始化角色 / 建立档案
```

游戏只需要读最后产出的 **baseline JSON**，不需要关心识别过程。

## 2. 游戏需要关心的字段

baseline JSON 里游戏真正要用的只有这几个：

- `character_state` —— 10 个角色属性
- `five_elements` —— 五行主题状态 + 共鸣值
- `tasks` —— 需要护持的任务（异常指标触发）
- `readiness` —— 守护准备度（0–100）
- `evidence` —— 建模依据（资料完整度等，可选）

其余字段（`baseline_id`、`provider`、`model`、`input_mode`、`recognition_mode`、`source_document`、`source_priority`、`synced_at`）都是元数据，游戏可忽略。

## 3. baseline JSON 结构（真实示例）

见同目录 [sample-baseline.json](./sample-baseline.json)。核心部分：

```json
{
  "character_state": {
    "hp_max": 103, "hp_current": 103,
    "attack": 48, "defense": 50, "spirit": 58,
    "stamina": 48, "insight": 61, "mind": 50,
    "speed": 48, "luck": 50
  },
  "five_elements": {
    "metal":  { "state": "unknown",    "resonance": 50 },
    "wood":   { "state": "needs_care", "resonance": 48 },
    "water":  { "state": "stable",     "resonance": 58 },
    "fire":   { "state": "stable",     "resonance": 58 },
    "earth":  { "state": "needs_care", "resonance": 48 }
  },
  "tasks": [
    { "task_id": "care_wood_001",  "title": "木·舒展 护持", "detail": "核对 3 项相关指标，整理复诊问题", "status": "pending" },
    { "task_id": "care_earth_001", "title": "土·纳养 护持", "detail": "核对 1 项相关指标，整理复诊问题", "status": "pending" }
  ],
  "readiness": 58
}
```

## 4. 属性映射表

| JSON 字段 | 游戏属性 | 含义 |
| --- | --- | --- |
| `hp_max` | 气血 HP | 生命上限 |
| `hp_current` | 当前 HP | 首日与 `hp_max` 相等 |
| `attack` | 攻击 ATK | 攻 |
| `defense` | 防御 DEF | 防 |
| `spirit` | 灵力 SPIRIT | 灵力 |
| `stamina` | 体力 STA | 体力 |
| `insight` | 洞察 INSIGHT | 洞察 |
| `mind` | 心志 MIND | 心志 |
| `speed` | 身法 SPD | 身法 |
| `luck` | 气运 LUCK | 气运 |

数值范围大致在 20–130 之间，未知项用中性值 50。

## 5. 五行

| key | 名称 | 对应方向 |
| --- | --- | --- |
| `metal` | 金 · 护息 | 防御 / 呼吸 |
| `wood` | 木 · 舒展 | 身法 / 糖脂代谢 |
| `water` | 水 · 藏养 | 体力 / 肾 |
| `fire` | 火 · 心脉 | 灵力 / 血压心电 |
| `earth` | 土 · 纳养 | 气血 / 营养体重 |

每个元素的 `state` 取值：

- `stable` —— 相关指标在参考范围内
- `needs_care` —— 有异常指标，需要护持（会生成对应的 `task`）
- `unknown` —— 没有相关资料

`resonance`（共鸣值）0–100，供 UI / 主题表现使用。

## 6. 两条重要约定（务必遵守）

1. **异常不扣属性**：体检异常只把对应五行标成 `needs_care` 并生成护持任务，**不降低 HP / 攻击等数值**——避免把长辈角色写成残血。
2. **锁定，只能补充**：`baseline_locked: true`、`supplementable: true`。用户只能继续补充资料生成新 baseline，不能直接改属性或五行数值。

## 7. 游戏如何拿到 baseline（两种方式）

### 方式 A：读文件（最简单）

入口后端把每次确认的 baseline 存到 `health-entry/baselines/{baseline_id}.json`。游戏在创建角色时读最新一个文件即可（每个文件都是完整、自包含的 JSON）。

### 方式 B：HTTP 实时推送

入口前端支持注入一个游戏地址：

```js
window.XIUXIAN_GAME_API = 'http://localhost:8080'
```

确认后前端会向 `POST http://localhost:8080/api/v1/game/baseline` 发送完整 baseline JSON。游戏侧起一个 HTTP 接收端监听即可。

## 8. Godot 4 接入示例（GDScript）

```gdscript
# 示例：把 baseline JSON 读进游戏状态（Godot 4）
# 请按你的项目结构放到角色创建/初始化处；game_state 需新增对应字段。

func apply_health_baseline(path: String) -> void:
    if not FileAccess.file_exists(path):
        return
    var data = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary:
        return

    var cs: Dictionary = data.get("character_state", {})
    hp_max     = int(cs.get("hp_max", 100))
    hp_current = int(cs.get("hp_current", hp_max))
    attack     = int(cs.get("attack", 50))
    defense    = int(cs.get("defense", 50))
    spirit     = int(cs.get("spirit", 50))
    stamina    = int(cs.get("stamina", 50))
    insight    = int(cs.get("insight", 50))
    mind       = int(cs.get("mind", 50))
    speed      = int(cs.get("speed", 50))
    luck       = int(cs.get("luck", 50))

    # 五行
    var five: Dictionary = data.get("five_elements", {})
    for key in ["metal", "wood", "water", "fire", "earth"]:
        var e: Dictionary = five.get(key, {})
        elements[key] = {
            "state": str(e.get("state", "unknown")),
            "resonance": int(e.get("resonance", 50)),
        }

    # 护持任务 + 准备度
    tasks     = data.get("tasks", [])
    readiness = int(data.get("readiness", 50))
```

## 9. 联调最小步骤

1. 起入口：`python server.py`，浏览器打开 http://127.0.0.1:8000 上传报告，点「确认并锁定初始状态」。
2. 去 `health-entry/baselines/` 看有没有生成 `baseline_*.json`。
3. 用 [sample-baseline.json](./sample-baseline.json) 先跑通游戏的初始化逻辑，再替换成实时数据。
