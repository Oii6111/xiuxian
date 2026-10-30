# 家族修真录 · 仙岛初见

根据提供的项目设计文档制作的快速 Godot 3D 交互原型。先体验“家人的健康计划 → 家庭确认 → 游戏资源 → 年轻人的策略挑战”，再选择美术方向。

## 立刻试玩

- 双击本目录的 `启动试玩.cmd`，使用本机已有的 `F:\Godot_v4.7.2-stable_win64.exe` 启动。
- 或用 Godot 打开 `project.godot`，按 **F5** 运行。
- 按 **WASD / 方向键**移动，**Shift** 奔跑，走近建筑按 **E**。也可直接点击底部四个入口。
- **右键拖动**旋转视角，**滚轮**缩放，**Esc** 关闭弹窗。
- **F12** 保存当前截图到 `output/demo-screenshot.png`。

## 两分钟体验路线

1. 点击右侧“模拟健康记录”，查看预置解析草稿。
2. 勾选本次演示使用授权，再点击确认。获得修为 +10、灵气 +4、守护符 +1、灵印 +1。
3. 打开“渡劫试炼”，确认开启游戏挑战。试试 **雷诀 → 守护符 → 雷诀**，三回合破阵。
4. 查看“家族洞府”的修行积累和成就，再到“万象灵阵”贡献一次力量。
5. 点击“打开风格画册”，比较三张 AI 概念图。

每天主行为奖励只领取一次，事件编号去重。模拟世界 Boss 每日限三次。点击右下角“重置演示”可恢复初始资源，便于反复演示。试玩存档位于 `output/local-save.json`；导出构建会改用 Godot 的 `user://` 目录。

## 三种视觉方向

| 概念图 | 方向 | 适合的感觉 |
| --- | --- | --- |
| `concepts/01-pixel-village.png` | 像素仙村 | 亲切、怀旧、轻量养成 |
| `concepts/02-ink-cultivation.png` | 国风仙侠 | 山水、仙境、沉浸感 |
| `concepts/03-cozy-3d-island.png` | 温暖的低多边形仙岛 | 轻松、立体、便于先验证交互 |

三张图由内置 image_gen 生成，是视觉方向草图，不是已实现画面的截图。完整提示词见 `concepts/PROMPTS.md`。目前真实可玩 Demo 使用原生网格制作低多边形仙岛，画面比概念图简单。

## 本次范围

已实现：可移动的 3D 角色与碰撞、四个场景入口、三个装饰 NPC、可旋转缩放的正交视角、角色资源 HUD、模拟记录确认和授权、奖励上限与去重、三回合策略试炼、可选守护符、世界 Boss 本地贡献模拟、家族积累、风格画册、本地存档与重置。

未接入：真实拍照/上传、OCR、AI Agent、医疗设备、联网多人、后端、真实共享血条。榜单其他家族是固定示例。游戏胜利只代表试炼结果，不判定现实康复。此版没有实现纪念系统、恢复确认或完整康复庆典。

本次提供可直接在本机运行的 Godot 项目，尚未导出网页包。系统中文字体使用 Microsoft YaHei；场景与人物都能继续编辑，不依赖外部模型资产。

## 文件

- `scripts/main.gd`：程序化仙岛、建筑、角色外观、场景交互与截图。
- `scripts/player.gd`：摄像机方向移动、物理碰撞、步行动画。
- `scripts/interface.gd`：HUD、记录、洞府、试炼、Boss、画册。
- `scripts/game_state.gd`：模拟事件核验、资源和存档。
- `tests/smoke_test.gd`：奖励去重、授权、上限、战斗结算与真实物理输入检查。
- `output/01-island-demo.png`、`02-health-record.png`、`03-tribulation.png`：实际 Godot 运行截图。

保留了项目原有的 `addons/godot_ai` 插件，没有更改插件文件。

## 检查命令

```powershell
& 'F:\Godot_v4.7.2-stable_win64.exe' --headless --path . --script res://tests/smoke_test.gd --log-file ./output/tests.log -- --preview
```

已在本机 Godot 4.7.2 下运行。受当前沙箱影响，测试日志可能包含系统证书库和 shader 缓存目录的访问提示；这两个环境提示不影响本地离线场景和截图。

实现中参考了 Godot 官方 [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html) 与 [环境设置](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html) 文档。
