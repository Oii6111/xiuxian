# 家族修真录 · 像素仙村与五域归衡

在当前像素仙村上增加五域冒险：20 位山海祟兽、10 种散祟、6 位故事 NPC，7 张像素地图底图、9 个地区入口，以及独立的实时战斗和主线进度。默认场景仍是原有仙村。

## v2 内核与团队开发入口

新增统一内核 `GameKernel`，提供时间、事件、随机、配置、状态存档、迁移、命令路由与审计，以及七个独立系统入口。C 已接入赛季查询与网络依赖；其余客户端业务接口明确返回 `NOT_IMPLEMENTED`，供 A/B/D 逐项接入。

开发先读 [v2 内核与团队接入指南](docs/KERNEL_V2.md)。Godot 中打开 `scenes/kernel/workbench.tscn` 按 F6 可验证框架；运行 `tools/test_kernel.ps1 -Godot 'Godot可执行文件路径'` 检查内核契约。后端边界见 [server/README.md](server/README.md)。

产品方向更新：老人通过微信官方 iLink 接入的 AI Bot 查看健康任务、拍照提交资料；验证后为对应修仙者结算灵石，年轻人在游戏中抽卡。方案与待开发范围见 [微信信息入口](docs/WECHAT_ILINK_ENTRY.md) 及 [设计文档 v2](家族修真录-设计文档-v2.md)。

C 的本地后端已实现：账号密码登录、任务实例、绑定授权、事务账本、抽卡、D 接缝、通知重试及个人 WebSocket 同步。进入 `server/` 后执行 `npm ci`、`npm run dev` 启动；`npm run demo` 运行隔离模拟闭环。详见 [后端说明](server/README.md) 和 [团队合并指南](docs/BACKEND_INTEGRATION.md)。本轮没有部署远程服务器，真实微信与 AI、A/B/D 业务仍待合并。

## 开始玩

使用 Godot **4.7.2** 打开 `project.godot`，按 F5；Windows 可双击 `启动试玩.cmd`。启动器读取 `GODOT4` 环境变量，本机也支持 D 盘已安装的引擎路径。首次打开会导入素材。

选定男修或女修后，在仙村左侧点击 **五域山海 · 像素冒险**。原世界首领地点也通往新冒险。从照生乡的雷叔与听雷试灯开始，之后任选一域，依次完成两条支脉和一位主祟，收齐五枚归衡印前往常生台。旁篇与相痕海在任意一域归衡后开放。

| 地区 | 主线 |
| --- | --- |
| 照生乡 | 听雷教学，观察一次躲避或护盾并反击 |
| 苍梧林 · 木 | 朽梁 → 涩节 → 窃荣 |
| 丹霞岭 · 火 | 乱律 → 窄焰 → 赤棘 |
| 稷野 · 土 | 积璧 → 薄丹 → 失稷 |
| 白羽关 · 金 | 闭岚 → 灼羽 → 缄风 |
| 玄泽 · 水 | 沉砂 → 滞潮 → 壅川 |
| 旁篇 / 相痕海 | 漏夜、失简 / 晦鳞 |
| 常生台 · 终章 | 执衡，五印齐备后开放 |

## 操作与反馈

探索用 **WASD / 方向键**移动，Shift 奔跑，E 与近处角色交谈，M 打开地图，Tab 打开祟兽图鉴。人物与门签也可以直接点击。

战斗用 **J 近攻、1 术法、K 护盾、空格闪避、E 操作阵眼**；下方按钮支持鼠标。Esc 暂停，可免费退出或重试。先收拢散祟，再完成该场的破阵、路标或护送目标，最后对抗主祟。圆、环、扇形和冲锋等预兆使用实际命中几何；所有挑战均可选择故事或标准难度。

每次首通发放固定修为与营造材，同一场不重复结算，回响练习不刷主线奖励。区域主祟归衡后，NPC 会说出新的对白，两只散祟回到地图安居，也会到原仙村做客。营造材逐步换取门灯、药圃、听雨亭与观星台，实际显示在行旅营地。

失败、离开和暂停不扣已有修为、归衡印或营造。资料中的五行属于虚构世界观；健康模拟值不参与诊断，游戏胜利不表示现实康复。

## 原有仙村

原有形象、家人计划、服药确认、每日奖励、阶段恢复篇章、三回合天雷试炼保留。每日奖励仍由明确的家属模拟确认触发，游戏战斗不自动完成任何健康记录。旧实时妖龙组件保留用于旧玩法回归，新世界首领入口已改为五域故事。

## 素材与实现范围

新增 14 张生成图：5 张 Boss 图集（每张 4 只）、1 张十小怪图集、1 张六 NPC 图集、7 张地区底图。图集按格取样并使用最近邻过滤。主角复用原有四向行走；新 Boss 和 NPC 当前是静态像素精灵，通过位移、呼吸、受击闪白及技能特效表现动作，尚无各 Boss 完整逐帧攻击动画。

地图由固定背景画与独立 Godot 角色、交互门签、行走边界、营造道具组成；序章/旁篇共享一张底图，共域/终章共享一张底图。当前为离线单人 Godot 项目，未导出网页包或接入真实健康设备。

生成提示词和图集编号见 [assets/pixel_campaign/PROMPTS.md](assets/pixel_campaign/PROMPTS.md)。故事与二十祟对应表见 [docs/PIXEL_CAMPAIGN_STORY.md](docs/PIXEL_CAMPAIGN_STORY.md)，机制与数值见 [docs/PIXEL_CAMPAIGN_BALANCE.md](docs/PIXEL_CAMPAIGN_BALANCE.md)。

## 存档与检查

五域冒险使用独立 `pixel_five_realms_v1.json`。Windows 有 D 盘时默认保存到 `D:/Projects/Codex/user-data/xiuxian/pixel-campaign/`；可通过 `XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR` 指定其他目录。原仙村记录沿用其原有存档，两者只显式同步昵称与形象。

```powershell
# 默认执行导入、旧仙村回归、20 Boss 规则和战斗呈现检查
powershell -ExecutionPolicy Bypass -File .\tools\test_pixel_campaign.ps1
# 再跑真实渲染与键鼠输入：教学 + 木域三连战 + 营造 + 地图 + 返回
powershell -ExecutionPolicy Bypass -File .\tools\test_pixel_campaign.ps1 -Graphical
```

可使用 `-Godot 'D:\path\Godot.exe'` 指定引擎。自动验证使用隔离存档；`--preview` 不加载玩家进度。渲染结果写入 `outputs/pixel-campaign`，日志在 `work/pixel-campaign`。测试输入由脚本驱动，不等同于真人可用性测试。最后一轮离屏鼠标注入存在不稳定情况，完整验证状态见 [docs/PIXEL_CAMPAIGN_VALIDATION.md](docs/PIXEL_CAMPAIGN_VALIDATION.md)。

## 核心文件

- `scripts/pixel_campaign/village_ui.gd`：原仙村入口、角色资料和战后访客。
- `world.gd` / `story_ui.gd`：地区探索、地图、图鉴、人物故事、营造与结算。
- `battle.gd` / `encounter.gd`：像素战斗呈现和独立规则。
- `state.gd` / `catalogue.gd`：主线进度、一次性奖励与资料查询。
- `data/pixel_campaign_*.json`：20 位祟兽、10 种散祟与 6 位 NPC 完整资料。

仓库：<https://github.com/Oii6111/xiuxian>。本功能分支基于当前像素 `main`，没有将旧低多边形原型设为默认入口。
