# A 分工：PR #4 战斗与生命周期适配

当前基线：PR #4「新增聚宝阁抽卡装备与账号家族管理」，提交 f2c284ba5161bc9aa7a324de79092325455b4f45。开发分支 feat/a-combat-lifecycle。

本轮将 A 的阶段、预兆、护法、生命周期与 AI 辅助迁到 PR #4 的实际仙村、账号家族和四技能体系。产品运行 scenes/main.tscn，沿用聚宝阁及二十 Boss 长廊。旧五行职业、Q/R 大招和独立三关开发演示保留作规则/接口测试，不进入本版主流程。

## 试玩

F5 或项目根目录双击「启动A分工试玩.cmd」。默认进入 PR #4 的账号登录及主仙村。已有账号、聚宝阁和两个老人位置沿用原流程。

~~~powershell
# 正常账号入口
powershell -NoProfile -ExecutionPolicy Bypass -File tools/play_combat_lifecycle.ps1

# 隔离的预览角色，不写入真实家族存档
powershell -NoProfile -ExecutionPolicy Bypass -File tools/play_combat_lifecycle.ps1 -Preview
~~~

可传 -Godot 指定 Godot 4.7.2 可执行文件。缓存/过程文件放 work/play-a，导出放 outputs/combat-lifecycle。

- 仙村左侧「渡劫台 / 修行状态」打开当前本人或家人的生命周期。
- 「四式说明 / 技能练习」使用听风剑诀、踏云步、云罡护体、饕餮归元；保留原消耗、冷却和首通解锁规则。
- 新增「AI 护法陪练」，只在不结算的练习中辅助攻击。它读取冻结后的攻击值，不花玩家灵力、不增加首通、贡献或灵气。
- 「属性闯关」继续进入 PR #4 的二十 Boss 长廊。P 暂停，Esc 或返回按钮退出。

## 战斗迁移

当前进一步加入固定二十关梯度、Boss 连段、精准闪避反击、破势、地面余势和独立版本战绩，详细规则与对照结果见 [战斗挑战版](CHALLENGE_COMBAT.md)。

1. 开局直接复制当前 GameState.battle_stats()，包括聚宝阁装备加成。每场绑定 entered_state，不从后来切换的角色读取结果。新装备/新评估仅影响下一场。
2. 本版保持五项数值与四技能，不将健康属性解释为五行职业，也不把旧 Q/R 大招覆盖到主玩法。
3. 二十个具名 Boss 使用独立配置，共六十招；每只包含两招基础技和第二阶段开放的标志技。追击、侧移、拉远距离根据位置决策，冲锋和扑击会改变实际判定位置。三阶段仍按剩余生命 2/3、1/3 进入。
4. 界面已隐藏 Boss 攻击红区、范围线、方向箭头和落点圈，玩家依靠实际动作、特效与声音闪避；基础生命统一 100，装备生命继续叠加，Boss 基础攻击比上一版提高 25%。蓄力时固定方向、落点、几何和时长，换阶段不会改变正在显示的预兆。斩击、冲锋、扑击、弹幕、环震、地面连爆、吐息线、十字阵八种机制的命中几何统一由规则层维护，界面不绘制其边界。弹幕在实际接触时命中，冲锋采用连续扫掠；单次冲锋不重复伤害。
5. 连段最后一击保留至少 1.05 秒收招，额外每段增加 .22 秒；段间用明确提示和完整预警继续进攻。每个 Boss 的召唤数量分别配置，最多四只散祟，散祟会追击、分散、固定落点蓄力 .72 秒后扑咬，再收招 1.45 秒。不再隐形提高 Boss 伤害。受击后 .5 秒保护避免同时受到重叠攻击。
6. 具名 Boss 固定生命、基础攻击和破势上限按关卡严格递增，不随玩家装备提高。调整前早期 Boss 会被 PR4 基础输出在约 2.4 秒内击败；现在自动对战可展示多轮出招。练习原数值不改，装备提高仍直接缩短具名战斗。
7. 二十个 Boss 和男女角色均使用本轮生成的 16 帧动作资产，真实绘制交替迈腿、抬爪、挥剑、吐息、受击和倒地。八类栅格特效每类四帧，总计 384 帧。普攻 / 剑诀分别在 .12 / .16 秒后命中，翻滚在 .18 秒内连续位移。固定比例与显式脚底锚点避免整图平移冒充动作；命中有停顿、浮字和轻震动。资产和精确提示词位于 assets/combat_animations。
8. 练习仍单阶段、无首通/贡献；具名挑战的首通、归元解锁、最佳记录沿用 PR #4。战斗不改变医疗生命周期，A 不写抽卡资源。完整招式表和数值见 [Boss 战斗打磨](BOSS_COMBAT_DESIGN.md)。

### 关键文件

| 文件 | 职责 |
|---|---|
| scripts/boss_rules.gd | PR #4 四技能、属性快照、阶段、散祟、出战限制 |
| scripts/combat_view.gd | 当前角色绑定、阶段显示、散祟、暂停、AI 陪练 |
| scripts/combat_effects.gd | 与规则共用的预兆及技能表现 |
| scripts/systems/combat/pr4_patterns.gd | 共同命中/绘制几何纯规则 |
| scripts/systems/combat/pr4_boss_brain.gd | 二十 Boss 移动、选招、弹体和攻击时序 |
| data/combat/pr4_boss_moves.json | 六十招、走位、伤害倍率、召唤与生命预算 |
| scripts/systems/combat/pr4_companion.gd | 不结算的 AI 陪练纯规则 |

## 生命周期与家人存档

- 修行 → 渡劫；渡劫 → 修行/闭关/飞升；闭关 → 修行/飞升；飞升不可再出战。
- 状态按钮先弹确认框。点击确认后才调用生命周期命令，取消不改变状态。飞升必须两个独立确认；取消后撤销本次待确认凭证，重新发起需再确认两次。
- 渡劫、闭关、飞升中的当前角色均不能进入技能练习或 Boss。可以关闭面板并切换另一位修行中的家人继续玩。
- 打开确认框或保存期间不能切换家人。适配器再次核对账号、成员 ID 和角色实例，旧窗口/旧账号的迟到操作无法写入新角色。
- 三种阶段模板在开始前选定并保留。每次手动更新阶段保存游戏时间线；阶段可回退。到出院阶段不会自动结算。
- 护法灯保存到当前家人，只影响画面。闭关显示安静场景和陪伴说明，健康任务页改为陪伴提示；飞升保留角色、装备及记录。庆典只展示，A 不发灵气、不修改装备或境界。
- 庆典可保存 960×540 PNG，只含游戏庆典文案，不带阶段、模板或健康资料。
- 界面常驻「当前账号本机演示确认」。这是 PR #4 本地原型的家属操作流程，未冒充远程权威服务。

### 存档兼容

家族外层 schema 8 保持不变，角色原有 schema 6 增加可选 lifecycle_v2 命名空间：

~~~json
{
  "schema": 1,
  "state": "tribulation",
  "version": 3,
  "template_id": "cardio",
  "stage_index": 1,
  "lamps": 2,
  "history": [],
  "last_event_id": "example_event"
}
~~~

template_id 在 stage_index=-1 时可表示尚未入院的模板偏好；活动阶段从 admission 开始。该偏好不会被当作医疗状态变化。

旧档没有此命名空间时，已由家属确认的 recovery_status=active 对应渡劫，其余对应修行。旧 begin_recovery/confirm_recovery 演示接口同步更新投影，避免两套状态不一致。

每次更改通过 GameState.commit_lifecycle 验证字段、版本并调用原家族原子保存，失败回滚角色状态。当前灵气、装备、健康属性、另一位家人和账号都不改。非法生命周期数据阻止出战和覆盖保存，保留原档供恢复。时间线仅保存固定游戏字段，最多 64 项；令牌与确认进度仅在面板内存中。

### 关键文件

| 文件 | 职责 |
|---|---|
| scripts/systems/lifecycle/lifecycle_rules.gd | 共享 FSM 和阶段模板 |
| scripts/systems/lifecycle/family_record.gd | PR #4 角色投影白名单与时间线 |
| scripts/tribulation/family_gateway.gd | 账号/角色绑定、本机确认、持久化适配 |
| scripts/tribulation/platform.gd | 确认/取消、渡劫、闭关、飞升、庆典、卡片 |
| scripts/game_state.gd | 角色命名空间、出战判定、失败回滚、旧档兼容 |
| scripts/family_roster.gd | 直接家族保存同样检查坏档保护 |
| scripts/gameplay_interface.gd | 实际仙村入口、家人切换、角色状态与任务提示 |

## B/C/D 接口

### B：家族、聚宝阁和导航

GameState.battle_stats() 仍为最终装备快照的唯一入口。PR #4 的 qi 钱包、四槽装备、背包、抽卡概率/保底、角色创建、登录与家族 schema 均保留原职责。主战斗引用捕获的 entered_state。生命周期 UI 由 open_recovery 打开。

读取 GameState.lifecycle_record() 获取只读副本，allows_battle() 获取出战资格。闭关/飞升时主任务页展示陪伴/回忆，不由 A 生成健康任务或额外功德。

### C：权威服务和联机

family_gateway 是本机演示装配；其 dispatch/snapshot 与现有内核门面一致，内部复用 v2 lifecycle 模块。actor_id 是本地账号/成员/实例的隔离键，不是后端鉴权证明。

既有 scripts/combat/service_binding.gd 保留正式 game_api.invoke 接缝，数据样例见 data/combat/integration_examples.json。正式接入时：
- 后端建立稳定的 cultivator_id 与账号/家人映射，客户端不自行推断授权。
- 确认令牌绑定角色、目标、版本、时效与独立确认步骤，并提供取消/重放语义。
- 权威状态更新 GameState 的游戏投影和出战资格；本地缓存不能覆盖服务端事实。
- 奖励、抽卡、真实联机、全服庆典广播与重连恢复继续由 C 的服务负责。不能用本机 family_gateway 或战斗胜负代替现实结果。
- 当前 AI 陪练只用于练习；不是已经完成的网络队伍服务。

### D：内容

PR #4 data/trial_bosses.json 仍提供二十 Boss 的 ID、图集、地点及阶级。data/combat/pr4_boss_moves.json 按稳定 Boss ID 提供招式、走位和游戏数值；pr4_patterns 提供共用几何，未引入疾病对应伤害。阶段模板来自 lifecycle_rules；真实健康凭证核验、微信消息、授权和原图留在 D 的健康入口。

## 测试与输出

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_pr4_integration.ps1 -Graphical
~~~

统一入口包含：
- tests/pr4_challenge_rules_test.gd、pr4_challenge_duel_test.gd、pr4_challenge_render_test.gd：固定梯度、动作帧、延迟命中、攻守机制、独立战绩、操作对照与实际输入；
- 原 A/内核规则和接口回归；
- tests/pr4_a_migration_test.gd：真实仙村/两位家人/装备快照/出战限制/确认取消/旧接口兼容/保存失败/存档恢复/AI 陪练；
- 聚宝阁、家族、四技能、二十 Boss 长廊、仙村与旧剧情规则/战斗回归；
- tests/pr4_boss_design_test.gd：二十 Boss 三阶段真实时序、边界、六十招、锁定预兆、伤害与收招、扫掠和帧分割；
- tests/pr4_boss_duel_test.gd：使用实际移速和四技能消耗打完整二十关，核对多轮出招、阶段和存档边界；
- tests/pr4_boss_render_test.gd：实际二十场景的移动、八种攻击机制、暂停、预警/攻击/落地截图和动态帧；
- tests/pr4_a_render_test.gd：实际主场景的鼠标入口、嵌入弹窗确认点击、键盘暂停、聚宝阁、Boss 阶段、AI 及卡片导出。

过程日志放 work/pr4-integration，主流程截图放 outputs/combat-lifecycle/pr4-adapted，Boss 截图和动态预览放 outputs/combat-lifecycle/boss-polish，源码包和机器可读验证记录放 outputs/combat-lifecycle。图形验证使用真实 OpenGL，不等同于真人试玩；测试使用模拟人物、隔离存档和内存内核。未验证 Web 导出、移动性能或真实多人后端。

## 开发台保留内容

scripts/systems/combat 下原 combat_fight、encounter_sim、boss_fight、party_ai 以及 scenes/combat/demo_hub 保留早期 v2 规则与接口样例，供回归/团队联调。它们的五行、三关、Q/R 设定不进入本版主仙村；主玩法以本文件的 PR #4 适配为准。
