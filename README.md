# 家族修真录 · 像素仙村

四格示意图中的开始界面、男女形象、每日健康管理、老者打坐天雷试炼、妖龙实时战斗，已接入本机 Godot 项目。

## 启动

双击 `启动试玩.cmd`，或用 Godot 打开 `project.godot` 后按 F5。

开始界面选择男修或女修、填写昵称，再点击“开始修行”。已有形象可点击“继续上次修行”，或在仙村左侧“形象 / 开始界面”随时更换；更换形象不清空存档。

## 团队协作

仓库：<https://github.com/Oii6111/xiuxian>。

仓库所有者在 GitHub 的 **Settings → Collaborators** 中邀请队友，队友接受邀请后即可推送代码。每个人先克隆到自己的电脑，用 Godot 4.7.2 打开 `project.godot`；首次导入时会自动生成 `.godot/` 缓存。启动脚本中的引擎路径为本机路径，其他电脑可直接从 Godot 编辑器启动。

```bash
git clone https://github.com/Oii6111/xiuxian.git
cd xiuxian
git switch -c feature/your-task
```

开始新任务前，先回到 `main` 并拉取最新代码，再创建自己的功能分支：

```bash
git switch main
git pull --ff-only
git switch -c feature/your-next-task
```

完成修改并在 Godot 中验证后，提交并推送自己的分支，然后在 GitHub 发起 Pull Request，合并到 `main`：

```bash
git add .
git commit -m "Describe your change"
git push -u origin HEAD
```

Git 支持多人分别修改、提交和合并；需要实时一起编辑时，要另用实时协作工具。分工时尽量由一人负责一个 `.tscn` 场景或 `.tres` 资源，减少同时修改同一文件产生的冲突。脚本 `.gd`、对应 `.uid`、场景、素材和 `.import` 导入配置应一并提交；`.godot/`、本地存档、日志和更新备份已由 `.gitignore` 排除。

## 操作

| 场景 | 操作 |
| --- | --- |
| 仙村 | WASD / 方向键移动，Shift 奔跑，E 交互；底部地点可自动前往 |
| 村民 | 点击对话，进入计划、洞府或修行簿 |
| 打坐天雷试炼 | 1 雷诀、2 镇心诀、3 守护符，也可点击技能按钮 |
| 妖龙战 | WASD 移动、J 攻击、K 护盾、空格闪避，也可点击技能按钮 |
| 面板与战斗 | Esc 或“返回仙村”退出 |
| 截图 | F12 保存到 `output/pixel-screenshot.png` |

## 三分钟体验

1. 选择男女形象进入仙村。HUD 的年轻守护者与父亲“青松真人”是不同角色。
2. 右上角“记下一次坚持”查看长期管理。勾选家属确认，确认一次服药记录或个人计划记录。
3. 每项任务每天记录一次，两项共用每天一份主行为奖励。后确认的任务照常保存，不重复奖励。没有用药计划时，在“管理个人计划”关闭服药任务。
4. 打开“阶段恢复篇章”，由家属确认开启模拟篇章。长期管理可同时继续。
5. 前往渡劫台，进入三回合动画试炼。试试“雷诀 → 守护符 → 雷诀”，能看到施法、金色屏障、天雷和伤害反馈。旧存档灵气不足时，可在试炼准备界面领取演示补给。
6. 试炼完成后，恢复篇章仍保持进行中。只有家属另行确认已获得可靠来源的恢复确认，才结束篇章。
7. 进入世界首领，选择普通出战。妖龙会蓄力，红色椭圆锁定位置，随后吐息。可移动出红区，或在命中前使用护盾、闪避。

## 战斗规则

渡劫保持三回合策略：雷诀消耗 5 灵气、消解 90 雷劫余势；镇心诀消耗 3 灵气、消解 60 余势并获得 100 护盾；守护符消耗 1 张、消解 70 余势并挡下本轮。中途离开保留已消耗资源，历史修为不扣除。

妖龙为本地实时挑战，有 1440 点生命，玩家有 300 点护元。普通攻击造成 96 伤害，攻击、护盾、闪避均有冷却。吐息先预警，再按红色椭圆范围判定。每次进入消耗当日一次出战机会，每天最多 3 次，实际伤害实时计入本地贡献。可选守护符只为首击额外增加 20 伤害；普通出战不消耗健康资源。

## 存档

沿用 `output/local-save.json`，兼容之前仅含修为和资源的旧存档，升级和更换形象不清空进度。新增保存男女形象、昵称、每日任务、长期管理和恢复篇章。测试使用独立存档文件，不写入玩家存档；`--preview` 截图模式不写入用户存档。

“重置演示”会主动重置游戏资源及管理记录，保留已选择的形象。升级前的存档备份位于 `output/backups/before-gameplay-upgrade.json`（若升级前存在存档）。

## 数据和实现范围

所有健康记录均为本地模拟、由家属确认的演示数据，不识别真实服药，不提供药物、剂量或调整建议。游戏胜利不表示现实康复。尚未接入真实设备、相机上传、OCR、AI 服务、多人服务器或在线共享 Boss。

像素环境是固定视角底图；男女主角、三位村民、打坐老者、妖龙、技能、伤害、护盾、落雷、攻击预警与判定均为独立 Godot 对象或脚本。妖龙使用待机、攻击、受击和倒下四个姿态，配合实时移动和特效。主角为四方向行走动画，战斗挥剑用精灵动作与灵刃特效表现，尚未另做完整逐帧攻击图集。

素材由内置 image_gen 生成，保存在 `assets/gameplay/`，完整提示词见 `assets/gameplay/PROMPTS.md`。原始像素素材与风格概念图继续保留。系统字体使用 Microsoft YaHei / KaiTi。

## 文件

- `scripts/gameplay_interface.gd`：开始界面、形象选择、计划记录、恢复篇章和战斗入口。
- `scripts/game_state.gd`：奖励、任务、两条管理轨道、存档兼容和 Boss 次数。
- `scripts/combat_view.gd`：可视化战斗场景、角色状态、技能输入与结算。
- `scripts/tribulation_rules.gd`：三回合天雷规则。
- `scripts/boss_rules.gd`：实时妖龙攻击、冷却、危险区和防御判定。
- `scripts/combat_effects.gd`：实时雷电、护盾、符文、吐息、红区与灵刃。
- `scripts/pixel_assets.gd`：纹理缓存和透明图集切帧。
- `output/07-start.png`、`08-daily-plan.png`、`09-thunder-trial.png`、`10-dragon-battle.png`、`11-recovery-chapter.png`：实际 Godot 运行截图。

旧低多边形场景仍在 `scenes/lowpoly.tscn`，可用 `查看旧版低多边形.cmd` 对比。原有 Godot AI 插件文件未修改。本次提供本机 Godot 项目，尚未导出网页包。

## 检查

```powershell
& 'F:\Godot_v4.7.2-stable_win64.exe' --headless --path . --script res://tests/gameplay_test.gd --log-file ./output/gameplay-tests.log -- --preview --skip-intro
```

旧的 `tests/smoke_test.gd` 入口现在复用同一套流程。已通过 61 项检查，覆盖每日去重和奖励、跨日、两种管理并存、独立恢复确认、旧存档、男女切换、真实界面按钮、动画时序、Boss 伤害与防御、NPC 和四个完整自动行走路线。

在本机 Godot 4.7.2 Compatibility 下实际运行并渲染检查。当前沙箱可能出现系统证书库访问提示，不影响离线游戏。

引擎行为参考 Godot 官方 [Control](https://docs.godotengine.org/en/stable/classes/class_control.html)、[Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html) 和 [SceneTreeTimer](https://docs.godotengine.org/en/stable/classes/class_scenetreetimer.html) 文档。
