# 老人端“健康管理助手”接入方案（OpenClaw Weixin + 健康侧车）

> 仓库内对应路径：本文档里的 `prototype/` 即本仓库的 `wechat-sidecar/`；`game_task_bridge.py` 在 `wechat-bridge/`。

## 0. 先把边界说清楚

老人端和年轻人游戏端是两套体验：

- 老人端只出现聊天、拍照、说话、提醒、确认和“联系家人/医生”。不出现游戏、修仙、灵气、攻击力、任务或分数。
- 游戏端如需使用健康事件，只从后台的结构化事件流读取，不能把游戏字段反向发给老人。
- 老人看到的每条记录都先是“候选”，只有老人回复“是/确认”才会进入已确认事件表。
- 健康助手不是诊断工具：不改药、不停药、不猜剂量；严重症状先走急救分流。

## 1. 这次接入的分层

```text
老人微信私聊
  │ 文字 / 语音转写 / 图片
  ▼
Tencent openclaw-weixin（通道、登录、媒体 staging、会话路由）
  ▼  before_dispatch typed hook
openclaw-health-hook（只做转发与 fail-closed）
  ▼
Flask 健康侧车（本目录 elder_assistant.py）
  ├─ 红旗症状拦截（模型之前）
  ├─ OCR / 视觉模型：报告、病历、药盒只做候选识别
  ├─ 轻量 RAG：权威资料版本、引用和禁区
  ├─ OpenClaw Gateway 对话润色（可选）
  ├─ “请确认”状态机与 SQLite 结构化记录
  ├─ 提醒配置 / 家庭绑定
  └─ 可选 HEALTH_EVENT_SINK_URL（后台家庭端/其它服务）
```

OpenClaw Weixin 是消息通道和媒体适配层，不是医疗知识库，也不会自动替你做药品判断。医疗安全规则、识别提示词、RAG 和事件状态机都在健康侧车里，便于审计和替换模型。

## 2. 为什么用 Tencent/openclaw-weixin

你补充的仓库是 [Tencent/openclaw-weixin](https://github.com/Tencent/openclaw-weixin)。它正好解决微信通道和媒体收发，但医疗识别、知识检索和安全策略仍应由本项目侧车负责。

插件负责微信登录、收发文字与媒体、长轮询和会话路由。安装后，OpenClaw 会把微信私聊交给指定 agent；我们再用 `before_dispatch` 在普通模型之前接管老人健康消息。健康侧车不可用时，hook 默认 `failClosed=true`，只返回“请联系家人/医生”，不会让普通聊天模型自由给医疗建议。

当前仓库已经放入可挂载插件：

```text
prototype/openclaw-health-hook/
├─ package.json
├─ openclaw.plugin.json
├─ index.ts
├─ README.md
└─ ELDER_AGENT_SYSTEM_PROMPT.md
```

## 3. 安装与登录

在运行 OpenClaw Gateway 的机器上（Node 需满足仓库当前要求）：

```bash
npx -y @tencent-weixin/openclaw-weixin-cli install
openclaw plugins install "@tencent-weixin/openclaw-weixin"
openclaw config set plugins.entries.openclaw-weixin.enabled true
openclaw channels login --channel openclaw-weixin
openclaw gateway restart
openclaw channels status
```

然后安装本项目的本地 hook：

```bash
openclaw plugins install --link ./prototype/openclaw-health-hook --force
openclaw plugins enable elder-health-sidecar
```

如果要让侧车调用 OpenClaw 的文本 agent，还要在 Gateway 开启兼容接口（默认关闭）：

```json5
{
  gateway: { http: { endpoints: { chatCompletions: { enabled: true } } } }
}
```

只把 Gateway 绑定在回环地址/内网，并使用令牌；这个接口等同于 Gateway 操作权限，不要暴露到公网。

侧车也支持 `ELDER_SIDECAR_TOKEN`。设置后，hook 配置里的 `sidecarToken` 必须一致；本地开发可以留空，演示/部署建议开启。

在 OpenClaw 配置中启用健康 hook（只在自己的 Gateway 上）：

```json
{
  "plugins": {
    "entries": {
      "elder-health-sidecar": {
        "enabled": true,
        "config": {
          "sidecarUrl": "http://127.0.0.1:8000",
          "sidecarToken": "与 ELDER_SIDECAR_TOKEN 相同的内部令牌",
          "defaultElderId": "elder_demo_001",
          "elderIdMap": { "wx_user_xxx": "elder_demo_001" },
          "familyShareDefault": false,
          "allowRemoteMedia": false,
          "failClosed": true
        },
        "hooks": { "allowConversationAccess": true }
      }
    }
  }
}
```

注意：当前 Weixin 插件版本的 DM 配对/撤销能力可能与 OpenClaw 标准 pairing 不一致，不能把“扫过二维码”当成完整的家庭授权。演示时用白名单/一次性家庭绑定码；上线前必须在 Gateway、侧车和家庭端各做一层身份校验。

校验：

```bash
openclaw plugins inspect elder-health-sidecar --runtime --json
openclaw plugins reload elder-health-sidecar
```

`openclaw-health-hook/index.ts` 优先读取 OpenClaw 已 staging 的本地媒体文件，不默认抓取任意远程 URL。不同 OpenClaw 版本若媒体字段有差异，只需调整 `mediaToAttachment`，不要把医疗判断挪进 hook。

## 4. 模型怎么选

建议采用“专职 OCR/视觉 + RAG 对话 + 确定性安全规则”的组合，而不是让一个大模型直接负责一切。

| 环节 | Demo 推荐 | 作用 | 不能做什么 |
|---|---|---|---|
| 体检报告/病历 OCR 与表格 | PaddleOCR-VL / PP-StructureV3 | 版面、表格、文字、页码和原文坐标 | 不负责诊断 |
| 模糊照片/药盒文字补识别 | Qwen3-VL 或 Qwen-VL-OCR（OpenAI 兼容接口） | 低清、倾斜、多页图片的候选抄录 | 不推断剂量、适应证 |
| 中文白话对话 | OpenClaw 选择的文本模型；可接百炼/自建 vLLM | 把已检索证据说成人话 | 不创建事件、不改药 |
| 医疗专项自建实验 | MedGemma 或其它医疗模型 | 研究/离线评估 | 不能直接当生产医疗产品，必须验证和适配 |

当前原型已经沿用 `.env` 的 OpenAI 兼容视觉接口：

```dotenv
LLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
LLM_MODEL=qwen3-vl-plus
LLM_API_KEY=填写你们自己的密钥
```

现在侧车是一个**多模型智能体**，文本回复按意图路由（不再是固定话术）：

| 触发 | 模型 | 温度 |
|---|---|---|
| 图片（体检/病历/药盒）OCR/视觉 | Qwen-VL（`.env` 的 `LLM_MODEL=qwen3-vl-plus`） | 视觉 |
| 医疗文本（症状、报告、药盒文字） | DeepSeek（`MEDICAL_*`，谨慎、不诊断） | 0.2 |
| 闲聊 / 生活建议 | DeepSeek（`HEALTH_CHAT_*`，像家人聊天） | 0.7 |

配置（`.env`）：`HEALTH_CHAT_ENABLED=true`，再填 `HEALTH_CHAT_BASE_URL` / `HEALTH_CHAT_API_KEY` / `HEALTH_CHAT_MODEL=deepseek-chat`；`MEDICAL_*` 留空则复用同一把 DeepSeek Key。模型仍只负责把已经过规则/RAG 约束的内容说成人话，不创建健康事件、不改药。

同时侧车带**记忆**：`memory_facts`（长期事实，确认事件后自动抽取，如「最近血压」「在吃的药」）+ `chat_history`（最近对话轮次），二者都会注入模型提示词，让对话能接上上下文、不用每次都重新自我介绍。

不配模型 Key 时，侧车退回安全但偏固定的兜底话术——所以想解决「太刻意」的观感，前提是把 DeepSeek Key 配好。

药盒识别的输出是 `medication_candidate`，字段包含药名、规格、厂家、批准文号、可见用法原文和每项置信度；任何字段不清晰都返回 `null`，并要求重拍或让家属/药师核对。**药盒照片不是处方核验。**

## 5. RAG 知识库怎么建

`prototype/knowledge/health_policy_demo.json` 只是演示规则，不可直接当临床知识库。正式版建议每条资料保存：

```json
{
  "id": "drug_xxx_2026_01",
  "title": "药品说明书/指南标题",
  "source": "官方来源 URL 或文档编号",
  "publisher": "来源机构",
  "version": "发布日期/版本",
  "effective_from": "2026-01-01",
  "scope": ["用药提醒", "饮食建议"],
  "text": "可引用原文或经审核的白话摘要",
  "do_not": ["不得改剂量", "不得替代急诊"]
}
```

检索使用关键词 + 向量混合；生成回复时把 `source/version` 一起传给模型。优先收录：国家药监部门批准说明书、国家卫生健康部门发布的指南、医院药师教育材料和团队审核过的本地规则。每次回复都要能追溯到资料版本，找不到可靠来源时宁可给保守建议。

## 6. 老人端的对话状态机

### 6.1 拍照

老人只需发一张照片，系统自动判断是“体检/病历”还是“药盒/说明书”。返回示例：

```text
我先把照片里的字整理成一条候选记录。
药名或规格看不清时，我不会猜，也不会替你改药。
请回复“识别没问题”或“不对”。
```

### 6.2 服药

```text
老人：我今天吃完药了
助手：收到。请点“是，已吃”；如果还没吃就点“还没吃”。
老人：是
助手：记好了。之后像平常聊天一样告诉我，不用填表。
```

### 6.3 生活建议

用户说“今天想吃火锅”时，不输出红牌或医学术语，而是给一个马上能做的小动作：

```text
可以吃一点：先吃蔬菜和清汤，蘸料少放盐，慢慢吃。
如果医生交代过限盐、限水或特殊饮食，就按医生的方案来。
```

这类建议必须经过 RAG 规则和安全模板；模型只能把它说得自然，不能自由扩展成诊断或处方。

侧车只会把**已经确认的结构化摘要**带入下一次生活建议。例如最近确认过血压偏高，火锅建议会变成“汤和蘸料少一点、先吃蔬菜”；它不会凭药盒照片猜出利尿药，也不会据此改变饮水量或药量。

### 6.4 危险症状

“胸口很痛、喘不上气、叫不醒、嘴歪、单侧无力”等先由本地规则拦截：

```text
先别等聊天回复，马上请身边的人联系 120 或到急诊；不要自己开车。
```

此分支不调用普通模型，也不等照片识别。

## 7. 侧车 API

### `POST /api/v1/elder/message`

请求（OpenClaw hook 已完成归一化）：

```json
{
  "elder_id": "elder_demo_001",
  "sender_id": "wx_user_xxx",
  "channel": "openclaw-weixin",
  "text": "我今天吃完药了",
  "attachments": [],
  "consent": { "family_share": true }
}
```

返回重点字段：

```json
{
  "mode": "elder_only",
  "reply": "收到，你是在说今天已经吃过药了……",
  "risk_level": "routine",
  "needs_confirmation": true,
  "pending_event": {
    "event_id": "pending_...",
    "summary": "记录今天已按你说的完成服药"
  },
  "recognition": { "status": "not_requested" },
  "privacy": { "family_share": true, "raw_media_stored": false }
}
```

### `POST /api/v1/elder/confirm`

```json
{ "event_id": "pending_...", "decision": "confirm" }
```

确认后侧车才写入 `health_events`。若配置 `HEALTH_EVENT_SINK_URL`，再把通用事件转给家庭端/编排服务；这个事件里没有游戏属性。

字段和幂等规则见 [HEALTH_EVENT_CONTRACT.md](./HEALTH_EVENT_CONTRACT.md)。

### `POST /api/v1/elder/reminders`

```json
{
  "elder_id": "elder_demo_001",
  "label": "早上的药",
  "schedule": { "times": ["08:00"], "repeat": "daily", "timezone": "Asia/Shanghai" },
  "enabled": true
}
```

侧车负责保存提醒配置；真正的定时触达可由 OpenClaw cron、Gateway 调度器或你们自己的消息服务执行。这样提醒系统可替换，不把调度逻辑绑死在微信插件里。

调度器每分钟轮询 `GET /api/v1/elder/reminders/due?elder_id=elder_demo_001`，拿到当前应触达的提醒后，再通过 OpenClaw Weixin 的出站发送能力给老人发一句短消息；发送成功后由调度器自己做幂等去重。

### `POST /api/v1/elder/family-link`

后台生成一次性绑定码，子女端确认后再开启摘要共享；没有 `consent.family_share` 时默认不转发。

子女端拿到 `link_id + code` 后调用 `POST /api/v1/elder/family-link/confirm`，绑定码 30 分钟过期。

## 8. 数据和隐私

- SQLite 只保存结构化摘要、候选/确认状态、时间和图片哈希，不保存原始图片。
- OpenClaw 侧应使用一对一私聊；群聊默认不进健康侧车。
- 正式部署必须加 HTTPS、Gateway 令牌、侧车内部令牌、访问控制、审计、备份和删除策略。
- 家属收到“摘要”而不是整份原始病历，除非用户明确同意。
- 语音只保留插件提供的转写结果；原始音频是否保存要单独取得同意。

## 9. 现在能演示什么

1. 启动 `python prototype/server.py`。
2. 用 `POST /api/v1/elder/message` 模拟微信文字/照片消息。
3. 展示“服药 → 询问确认 → 写入事件”的完整链路。
4. 展示“火锅 → 一个生活交换建议”的白话输出。
5. 展示“胸痛/呼吸困难 → 直接急救提示，不调用模型”。
6. 配好 OpenClaw 后，再用真实微信私聊发同样的消息；hook 会把它转给同一个侧车。

生产前必须补齐：权威知识库审核、药品身份二次核验、账号与家庭关系验证、真实消息调度、监控告警、人工复核和合规评审。

## 10. 本机安装结果与下一步

当前工作区已经完成：

- `.tools/node-v26.13.0-win-x64`：兼容 OpenClaw 的便携 Node，不替换系统 Node 24。
- `.tools/npm-global`：OpenClaw CLI `2026.10.9`。
- OpenClaw Weixin 插件 `2.4.10`，已启用。
- `elder-health-sidecar` 本地 hook，`before_dispatch` 已加载。
- Gateway 已注册为当前用户的 Windows 启动项，监听 `127.0.0.1:18789`；Chat Completions 回环接口已开启。
- 健康侧车使用 `127.0.0.1:8001`，避免占用现有 8000 端口。

还需要你们在手机上扫码登录一次：

```powershell
prototype\openclaw.bat channels login --channel openclaw-weixin
```

模型密钥仍按你们选择的供应商配置。当前 OpenClaw 的默认 OpenAI 模型没有可用凭证，因此未登录模型时侧车会使用安全的确定性 demo 回复；现有 `prototype/.env` 的视觉模型配置可继续用于报告/药盒识别。

