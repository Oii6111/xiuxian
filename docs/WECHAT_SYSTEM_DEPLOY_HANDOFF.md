# 微信灵宠联动：系统与网站部署交接

交付日期：2026-11-01。交付范围是微信扫码、账号/角色绑定、文字收发、任务状态同步及可复现检查。大模型API由用户后续接入，正式奖励账本另行对齐。

## 合并与同步

这次独立PR基于PR #4当前分支 `codex/gacha-family-accounts`，只增加本轮微信实机联动改动。PR #4仍未合并，因此本次PR以该分支为目标，避免再次提交整套抽卡、家族和战斗内容。

建议先将本次PR合入 `codex/gacha-family-accounts`，再按原计划将PR #4合入main。若PR #4先合并，先将本次PR的base调整为main并处理差异。不要用本机旧目录整份覆盖队友分支。

## 当前模块

| 文件 | 职责 |
|---|---|
| `tools/wechat_live/live_host.py` | 复用Python账号服务；管理邀请、扫码共享确认、绑定、消息回执与账号范围的任务读取 |
| `tools/wechat_live/gateway.mjs` | 腾讯iLink二维码、状态轮询、入站持久队列、游标、文字回复与重启恢复 |
| `tools/wechat_live/projection.py` | 最小计划/任务投影；任务编号稳定，事件防重，保留本人自述来源 |
| `tools/wechat_live/run.py` | 启动两个本机服务，可同时启动正常登录的Godot游戏；模型默认关闭 |
| `scripts/wechat_link_panel.gd` | 当前游戏账号/角色的连接、状态查询及断开入口 |
| `scripts/companion_task_client.gd` | 从已验证的游戏账号服务读取共享任务；前台约2秒刷新 |
| `scripts/companion_panel.gd`、`gameplay_interface.gd` | 灵宠连接按钮与界面装配 |
| `tests/test_wechat_live.py`、`wechat_gateway_test.mjs` | 服务/协议测试，包含身份隔离、共享确认、消息去重及解绑 |
| `tests/wechat_native_probe.gd`、`tools/wechat_live/test_native.py` | 真实Godot界面自动联测；通道消息由隔离夹具提供 |
| `tests/wechat_live_experience.gd` | 实机联测会话，普通账号登录、打开扫码入口并在实际状态变化时留图 |

账号验证复用 `server/account/server.py` 的 `Accounts`；老人消息处理默认复用固定版本 `tools/wechat_link_demo/sidecar/` 与其显式事件适配扩展。当前联动账号并非Node C后端的 `/api/v2/auth` 会话，两个会话体系不能直接互换。

## 接口

默认账号/任务服务 `127.0.0.1:8010`，微信通道 `127.0.0.1:8020`。一键启动见 [运行说明](WECHAT_LIVE_DEMO.md)。

| 接口 | 调用方与身份 | 用途 |
|---|---|---|
| `POST /api/v1/auth/register`、`login` | 游戏登录/注册 | 复用原Python账号字段与响应 |
| `GET /api/v1/auth/session` | 游戏会话 | 校验当前账号 |
| `POST /api/v1/wechat/invitations` | `Authorization: Bearer <游戏会话>` | 传 `game_member_id`、`label`，获得本机扫码页URL |
| `GET /api/v1/wechat/bindings` | 游戏会话 | 读取本账号的绑定与通道连接状态 |
| `POST /api/v1/wechat/bindings/revoke` | 游戏会话 | 按当前账号和 `game_member_id` 断开共享 |
| `GET /api/v1/companion/state` | 当前游戏会话，现有客户端使用 `X-Companion-Read-Token` | 返回 `schema_version=1, mode=live, account_id, revision, business_date, members` |
| `POST /internal/login`、`/internal/status` | 账号服务→Node通道，`X-Wechat-Service-Token` | 创建扫码会话、查看通道状态 |
| `POST /internal/wechat/confirmed`、`check`、`inbound` | Node通道→账号服务，同一内部凭证 | 绑定确认、权限复查、可信微信消息 |
| `POST /internal/wechat/events` | 老人模块→任务投影，`X-Health-Internal-Token` | 最小确认计划/完成事件 |

内部凭证由启动器生成并仅在服务器端使用。扫码bot token与context token保存在微信域，不能传给Godot、网站前端或大模型。

## 网站部署需要调整的具体位置

目前是现场本机宿主，还没有部署到公网。部署同学需接好以下接缝：

1. **统一公网根地址。** `run.py`构造的账号URL、`gateway.mjs`的扫码页面origin及监听地址目前固定回环。部署后由同机反向代理提供HTTPS，服务间仍可走回环；对外返回的 `login_url` 必须使用实际公网HTTPS域名，不能返回用户电脑的127.0.0.1。
2. **客户端地址校验。** `wechat_link_panel.gd`当前只接受本机扫码URL的正则；公网接入时改为你们明确配置的HTTPS扫码域名。`XIUXIAN_ACCOUNT_URL`指向对应HTTPS账号根地址。不要放开任意网络回复指定的URL。
3. **账号与角色归属。** 本轮按游戏账号隔离本地角色ID；网站系统若已有权威角色库，应在创建邀请时增加角色所属账号校验，完成游戏角色ID、C后端cultivator_id与老人档案的映射。
4. **统一会话。** 选择保留Python账号入口、适配C后端会话或做限权令牌交换；不能只把读取URL换成C的 `/api/v2/snapshot`。字段和权限须一起适配。
5. **持久化与进程。** 同一bot只运行一个轮询worker；使用固定持久卷保存私有数据库、游标和出站状态。当前Flask/Werkzeug宿主及同步SQLite锁用于本机联合演示，公网宿主、worker归属和连接生命周期由部署层接管。
6. **正式奖励。** 当前只投影任务和完成状态。接入C的结算服务时使用服务端绑定/任务实例及幂等回执，不在Godot中根据完成提示再加一次灵气。

## 后续大模型API

用户后续提供模型API配置。当前 `run.py` 默认移除外部模型配置并关闭调用；使用明确配置的服务环境加 `--allow-models` 后，未被确定规则处理的聊天继续走现有老人助手和 `model_provider.py` 接缝。

模型负责理解、候选提取和回复表达。绑定、共享权限、任务归属、日期、幂等与正式结算仍由服务层核验。修改模型实现时保留 `elder_id`、可信消息编号和会话隔离；游戏默认只读最小任务投影，不接收健康原文。模型密钥只进服务环境或部署平台的秘密配置。

## 验证结论与接手验收

- 自动：Python新增6项、Node通道2项、原账号4项；原生Godot图形界面10项，均已通过。
- 真实微信：扫码与共享确认成功；真实私聊能够接收和回复；真实散步计划已显示到实际游戏待办。
- 完成状态、同一任务编号、灵宠提示和解绑清除已通过原生界面自动检查；这轮没有保留真实完成的最终截图。
- 未交付：公网部署、大模型API配置、照片/文件完成核验和正式奖励账本。

部署后请再用两个不同微信/游戏账号跑一遍扫码、确认共享、发送日常安排、明确完成、刷新游戏、断开连接及重启恢复；确认两个账号互不串用。

本PR只上传源代码、测试、依赖清单和文档。`work/`内的真实微信凭证、二维码、聊天、账号数据库、玩家存档及本机引擎不提交。
