# 游戏侧对接说明

这份文档给游戏开发看：入口系统如何把长辈的健康资料换成游戏的初始角色状态，以及游戏怎么读这份数据。

## 1. 整体流程

```
上传体检报告 / 病历 / 用药单照片（可多张）+ 文字基本信息
   ↓  视觉模型识别（recognizer.py）
结构化健康指标 + 病史 + 用药（document）
   ↓  确定性规则引擎（rules.py）
初始角色状态（character_state）+ 守护准备度（readiness）
   ↓  用户确认、锁定
baseline JSON（锁定，不可手改）
   ↓  游戏读取
初始化角色 / 建立档案
```

游戏只需要读最后产出的 **baseline JSON**，不需要关心识别过程。

> 哪些健康数据会被采用、如何换算成属性，见 [MAPPING.md](./MAPPING.md)。

## 2. 游戏需要关心的字段

baseline JSON 里游戏真正要用的只有这几个：

- `character_state` —— 10 个角色属性
- `readiness` —— 守护准备度（0–100）
- `attribute_notes` —— 每个属性由哪些具体数据算出（可选，用于展示「为什么是这个值」）
- `evidence` —— 建模依据（资料完整度、活动能力等，可选）

其余字段（`baseline_id`、`provider`、`model`、`input_mode`、`recognition_mode`、`source_document`、`source_priority`、`synced_at`）都是元数据，游戏可忽略。

## 3. baseline JSON 结构（真实示例）

见同目录 [sample-baseline.json](./sample-baseline.json)。核心部分：

```json
{
  "character_state": {
    "hp_max": 80, "hp_current": 80,
    "attack": 50, "defense": 50, "spirit": 48,
    "stamina": 50, "insight": 51, "mind": 50,
    "speed": 50, "luck": 50
  },
  "attribute_notes": {
    "spirit": "灵力 = 48（高血压病史 −5、氨氯地平 +3）"
  },
  "readiness": 49
}
```

## 4. 属性映射表

| JSON 字段 | 游戏属性 | 含义 | 由什么决定 |
| --- | --- | --- | --- |
| `hp_max` | 气血 HP | 生命上限（上限 100） | 营养/血象（BMI、血常规、贫血） |
| `hp_current` | 当前 HP | 首日与 `hp_max` 相等 | — |
| `attack` | 攻击 ATK | 攻 | 活动能力 |
| `defense` | 防御 DEF | 防 | 呼吸系统（血氧、肺） |
| `spirit` | 灵力 SPIRIT | 灵力 | 心脑血管（血压、心率） |
| `stamina` | 体力 STA | 体力 | 泌尿骨骼（肾、肌酐、骨） |
| `insight` | 洞察 INSIGHT | 洞察 | 资料完整度 |
| `mind` | 心志 MIND | 心志 | 家族支持 |
| `speed` | 身法 SPD | 身法 | 代谢糖脂（血糖、血脂、肝） |
| `luck` | 气运 LUCK | 气运 | 固定 50 |

数值范围大致在 20–100 之间（气血 HP 上限 100）。

## 5. 两条重要约定（务必遵守）

1. **异常只小幅调整**：体检异常只把对应属性做 −6 这类小幅下调，**不把老人角色写成残血**——气血最低也在 40。
2. **锁定，只能补充**：`baseline_locked: true`、`supplementable: true`。用户只能继续补充资料生成新 baseline，不能直接改属性数值。

## 6. 游戏如何拿到 baseline（两种方式）

### 方式 A：读文件（最简单）

入口后端把每次确认的 baseline 存到 `health-entry/baselines/{baseline_id}.json`。游戏在创建角色时读最新一个文件即可。

### 方式 B：HTTP 实时推送

入口前端支持注入一个游戏地址：

```js
window.XIUXIAN_GAME_API = 'http://localhost:8080'
```

确认后前端会向 `POST http://localhost:8080/api/v1/game/baseline` 发送完整 baseline JSON。游戏侧起一个 HTTP 接收端监听即可。

## 7. Godot 4 接入示例（GDScript）

```gdscript
# 示例：把 baseline JSON 读进游戏状态（Godot 4）
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

    readiness  = int(data.get("readiness", 50))
```

## 8. 联调最小步骤

1. 起入口：`python server.py`，浏览器打开 http://127.0.0.1:8000 上传报告，点「确认并锁定初始状态」。
2. 去 `health-entry/baselines/` 看有没有生成 `baseline_*.json`。
3. 用 [sample-baseline.json](./sample-baseline.json) 先跑通游戏的初始化逻辑，再替换成实时数据。
