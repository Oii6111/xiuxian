# C：本地游戏后端

本目录实现 Node.js 24 + TypeScript + Fastify + SQLite 服务，默认监听 `127.0.0.1:8080`。本轮用于四人本地联调，没有连接或部署远程服务器。A/B/D 的战斗、UI、微信与 AI 功能通过接口接入。

## 启动与验证

要求 Node.js **24.13 或以上的 24.x**、npm；Godot 联调使用 4.7.2。当前使用 Node 内置 `node:sqlite`，Node 24 会输出实验性 API 提示；依赖与运行时版本须保持锁定。

```powershell
cd server
npm ci
Copy-Item .env.example .env
npm run migrate
npm run dev
```

`.env` 已忽略。D 联调时为 `HEALTH_SERVICE_TOKEN` 设置至少 32 字符的随机值；缺省时内部接口拒绝访问。可用 `node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"` 在本机生成，交给 D 的可信服务端保存。不要写入 Godot、网页、模型提示词或版本库。

- `GET /healthz`：存活检查。
- `GET /openapi.json`：从运行路由生成 OpenAPI 3 文档。
- `npm run build`、`npm start`：编译并启动本地服务。
- `npm run check`：TypeScript 编译、HTTP/数据库/权限/WebSocket 自动测试。
- `npm run demo`：独立内存数据库和随机回环端口的完整联调演示，不改变开发数据库。
- `npm run openapi`：将 OpenAPI 输出到标准输出。
- `npm run test:godot -- 'Godot控制台程序路径'`：启动隔离服务，执行真实 Godot HTTP/WebSocket 联调。
- 仓库根目录运行 `powershell -ExecutionPolicy Bypass -File tools/test_backend.ps1 -Godot 'Godot控制台程序路径'`：后端、演示、Godot 网络和现有内核回归的统一入口。

数据库默认位于 `server/var/game.sqlite`，迁移在启动时自动执行。`npm run migrate` 可单独验证迁移。测试使用内存或临时数据库，不载入玩家存档。版本高于程序或历史迁移校验不符时停止启动，禁止自动覆盖。

## 已实现与待合并

| 能力 | 状态 |
|---|---|
| 注册、登录、会话撤销、角色归属 | 已实现；密码 scrypt，数据库仅保存会话摘要 |
| 角色、资源快照、装备与抽卡 | 已实现后端；B 的界面和属性玩法待合并 |
| 任务模板、实例、状态与幂等结算 | 已实现；D 提供实际验证事实 |
| 邀请、业务绑定、独立授权、撤回 | 已实现 C 服务；实际微信身份和授权交互由 D 提供 |
| 通知租约、确认、退避重试 | 已实现；D 消费并调用 iLink 回复 |
| 个人 WebSocket 快照与变更通知 | 已实现；主城位置、组队和战斗同步后续接入 |
| 赛季日历查询、客户端同步和旧存档迁移 | 已实现；体检基线状态明确为 not_integrated |
| 战斗、生命周期、剧情、社交业务 | 默认 NOT_IMPLEMENTED，等待对应负责人 |
| 微信通道、AI 识别、真实健康核验 | 本目录不实现；本地演示明确使用模拟 D |

## 模块结构

| 位置 | 职责与维护人 |
|---|---|
| `src/app.ts` | C：HTTP 装配、校验、认证和 OpenAPI |
| `src/auth.ts`、`src/database.ts` | C：账号会话、事务与数据库迁移 |
| `src/game/` | C：任务实例、账本、抽卡、快照、赛季及版本化规则接口 |
| `src/integration/` | C：绑定、D 接缝、通知；附 D 可使用的 HealthClient |
| `src/realtime/` | C：标准 WebSocket、一次性票据、个人状态隔离 |
| `tests/`、`tools/` | C：隔离测试、本地演示、Godot 联调工具 |

D 合并时可新增 `server/channels/wechat_ilink/`、`server/health/`、`server/rules/`，或保留 Python 健康服务并调用内部 HTTP 接口。无需为了接入重写现有识别原型。原始报告、图片、聊天和识别说明不得进入游戏数据库与网络快照。

## HTTP 与幂等

公共游戏请求沿用 `POST /api/v2/commands`：

```json
{
  "version": 1,
  "command": "growth.draw",
  "payload": {"cultivator_id": "c_001", "count": 1, "request_id": "draw_001"}
}
```

所有业务接口返回统一结构，失败时 data 为空对象：

```json
{"ok": false, "code": "INSUFFICIENT_FUNDS", "message": "资源不足或数值越界", "data": {}}
```

通过 `Authorization: Bearer <session>` 认证。新任务命令见共享 `data/kernel/contracts.json`。`growth.create`、`growth.equip` 使用 `Idempotency-Key` 请求头；已有 request_id 的命令沿用正文键，两处同时提供时必须相同。重试返回最初结果，同键改内容返回 IDEMPOTENCY_CONFLICT。`growth.select` 只校验并返回角色快照，客户端自行保存当前选择。

注册、登录、邀请及 WebSocket 票据签发不缓存明文秘密到幂等表。新邀请替换该角色旧邀请；确认成功后相同内容重试返回同一绑定，不重新激活已撤回授权。相同邀请不能改换微信身份。退出、解绑和撤回按其当前状态处理。

`quests.claim.quest_id` 表示**任务实例 ID**。健康任务已自动结算时返回原结算记录，不再次增加资源；尚未结算返回 NOT_CLAIMABLE。

## 联调规则与限制

`src/game/rules.ts` 中的 integration-v1 是可替换的联调规则，非最终平衡方案：

- 照片/家属确认/自述/设备验证分别为 80%/60%/30%/100%。验证级别由可信 D 提供，不能由玩家发送。
- 灵石先乘验证与补偿倍率，再向下取整，最后截断到 UTC+8 当日剩余额度；每日暂定 30。经验只乘验证倍率。
- 同类事件以服务端结算时间计算滚动 24 小时限制；再次完成保留记录，资源为零。日灵石达到上限仍记录完成与应得经验。
- 角色创建没有已确认的健康与战力输入，补偿默认 0 档。动态补偿由后续可信 RuleProviders.compensation 接入。
- 单抽 10 灵石、十连 100；概率 60/30/9/1；十连至少灵品；仙品及以上清零仙品保底，保底阈值 80/70/60/50。
- 联调池按角色灵根生成四部位、四稀有度；同目录 ID 重复分别转换 1/3/10/30 材料。没有正式装备词条、属性或分解 UI。
- 初版日历明确发布 2026 下半年与 2027 上半年，按日历边界切季。未配置后续赛季时返回 SEASON_UNAVAILABLE，不擅自重置永久积累。

模板及规则版本随任务实例固定。新增规则必须保留旧版本提供方，不能修改旧版本语义。结算故障保存待处理事实并指数退避重试；授权失效等业务错误进入 blocked，必须重新授权、复核并提交新事件，不能静默恢复旧证据。

详细接口样例、A/B/D 合并步骤、WebSocket 协议与测试标准见 [团队合并指南](../docs/BACKEND_INTEGRATION.md)。
