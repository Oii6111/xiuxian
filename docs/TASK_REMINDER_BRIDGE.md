# D 接入：以本地 C 契约为准

更新：2026-10-31。基线 C：`1c1eb44`；D 上游：`d585785`、`bf5ad85`。
D 两次提交只新增 19 个文件，没有覆盖 C。接入改动保留在本地，未部署。

## 所有权与契约

- C：`data/kernel/contracts.json`、`server/src/integration/*`、账号、任务实例、授权、账本、抽卡。
- D：`wechat-sidecar/` 的识别/聊天/健康资料、`wechat-bridge/` 的任务适配和通知。
- 原 `health-entry/` 原型保留；侧车使用自己的健康数据库，不复制到游戏存档。
- `HEALTH_EVENT_CONTRACT.md` 是健康域内部事件，不能直接 POST 给 C。
- C 仅收 10 个最小事实字段，奖励始终由 C 算。五属性/十属性转换仍未发布。
- 本轮不修改任何 C 命令参数、模板数值、规则版本或迁移。

## 本轮适配差异

| D 原提交 | 当前接入 |
| --- | --- |
| 给唯一/最近待办自动归因；有图即完成 | 明确任务 ID，已确认健康事件，再由独立 D 审核器核验证据 |
| event_id 包含今天日期；重试重建时间 | 固定事件 ID/完成时间，SQLite 队列保存原请求 |
| 所有通知发往同一 target | binding_id 精确匹配独立账号、发送者、接收地址 |
| dry-run 仍领取/确认通知 | dry-run 不提交、不领取、不确认、不写投递状态 |
| 缺失授权版本默认 1 | 必须配置绑定确认返回的真实版本；每次提交/发送重新检查 |
| 桥接器读取另一份健康数据库 | ELDER_DB_PATH 默认指向 sidecar 的 bot_data |
| 六个未发布模板要求直接修改 integration-v1 | 仅消费 C 已发布的步数和计划内测量模板 |

药物、喝水、复诊等 D 聊天能力继续留在健康域；它们暂不自动成为有奖游戏任务。
不要把识别到药盒等同于服药完成，不要依据读数高低发奖。新增模板另行发布版本。
`elder_scheduler.py` 是 D 的独立健康提醒器，本轮不启动它，也不与游戏提醒同时启用。

## 本地配置与启动

Node.js 24；Python 3.11+。侧车依赖安装：`python -m pip install -r wechat-sidecar/requirements.txt`。
C 按 `server/README.md` 启动，默认 127.0.0.1:8080。侧车 `python wechat-sidecar/server.py`，默认 8000，
复制其 .env.example 后使用模板中的 8001。仅配置本机，不连接远程服务器。

三个凭证必须不同：
- HEALTH_SERVICE_TOKEN：C 和 D 桥接器共享，只允许 D 内部 API。
- ELDER_SIDECAR_TOKEN：微信 hook 调用侧车，未配置时拒收健康数据。
- GAME_REVIEW_TOKEN：可信 D 审核器调用侧车游戏审核接口，不交给聊天模型、hook 或浏览器。

先由游戏生成邀请，再由 D 核验真实身份和授权，调用 C 的绑定确认接口。
随后在受保护环境变量 ELDER_BINDINGS 中写入数组，不能照抄模拟身份用于真实用户：

```json
[{
  "binding_id": "binding_from_C",
  "elder_id": "opaque_health_reference",
  "sender_id": "verified_wechat_sender",
  "channel_account_id": "verified_bot_account",
  "target": "verified_delivery_address",
  "consent_version": 1
}]
```

不再接受旧的 elder_id → binding_id 简写或单一默认收件人。
hook 的 elderIdMap 键为 `JSON.stringify([channel_account_id, sender_id])`；
未知账号/发送者不回退到 defaultElderId。媒体只按账号、发送者、消息 ID 精确关联。
配置地址必须是受信任的 C 地址；本地联调使用 loopback HTTP。

侧车会读取自己的 .env；单独运行桥接器时需将相同配置导出为环境变量。
OPENCLAW_DRY_RUN 默认 1；本地测试以模拟发送器替代真实 OpenClaw。
只有明确安排真实联调后才设置 0，并配置本机可直接执行的 OPENCLAW_BIN（不拼 shell 命令）。
运行单轮：`python wechat-bridge/game_task_bridge.py --once`。

## 确认与审核流程

1. hook 将真实身份引用及消息交给侧车。原图、病史、识别候选只进入 D。
2. 老人确认候选后，侧车原子保存 health_events 和来源身份引用。过期候选拒绝确认。
3. D 的确定性审核器/人工审核确认某个事件满足某个任务，调用以下接口。
4. 侧车核验事件归属、分享许可、来源身份及允许的证据等级，向 C 提交最小事实。
5. C 返回 pending，异步结算；只有收到结算通知才向老人确认游戏同步。

`POST http://127.0.0.1:8001/internal/v1/game/verified-events`
头：`Authorization: Bearer <GAME_REVIEW_TOKEN>`

```json
{
  "binding_id": "binding_from_C",
  "task_instance_id": "task_from_C",
  "event_id": "confirmed_health_event",
  "verification_level": "photo",
  "evidence_confirmed": true
}
```

审核器必须核对照片内容、任务要求及完成时间；evidence_confirmed 是可信审核结果，不是客户端勾选框。
当前照片审核入口不支持 device/family_confirm 升档；需 D 后续提供真实设备/家属证据适配器。
旧记录若没有来源身份，拒绝补猜身份。失败重试原事件、原任务、原时间；不同内容冲突。
独立桥接器轮询持久队列。重试不自动采用新授权，撤回/解绑立即阻断后续提交。

## 通知与边界

通知一次领取一条 30 秒租约，发送前复查绑定、授权版本和通道。
未知绑定或发送失败 nack；本地持久化发送成功记录后 ack，ack 失败重试不再发送。
C 保证结算幂等；微信发送成功至本地落盘之间仍有崩溃窗口，不宣称外部消息严格 exactly-once。
运行单个桥接进程；多实例需 D 增加分布式发送锁/通道幂等能力。
提醒按 UTC+8，仅在任务时间窗内发送；原型每分钟轮询，不补发错过的提醒。
普通闲聊、任意照片及失败识别均不能触发游戏奖励。
完整 baseline 接口仅作 D 本地归档，返回 health_archive_only，不能解释为已同步游戏。

## 检查命令

在仓库根目录：
```powershell
python -m unittest discover -s wechat-bridge/tests -v
python -m unittest discover -s wechat-sidecar/tests -v
cd server
npm run check
npm run test:d
```

test:d 启动随机本地端口和隔离内存数据库，用 Python 真 HTTP 调用 C，
覆盖双账号、任务验证、重复提交、通知归属、抽卡和撤回；没有真实微信发送或 AI 调用。
Godot 继续使用 C 原接口，内核回归命令见 tools/test_kernel.ps1。

真实 iLink SDK 事件字段、OpenClaw 插件运行、AI 识别准确率、老人授权取证、
自动证据审核策略和用药提醒规则仍由 D 验证；本轮测试不冒充这些能力已接通。
