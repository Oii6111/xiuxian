# Blender 制作管线与免费资源筛选

2026-10-30 已完成本机安装、原生 MCP 实测和首批三件资产接入。保留 Godot 4.7.2 游戏逻辑，Blender 负责可编辑模型、骨骼动画、材质和 GLB 导出。

## 已验证连接

- Blender 4.5.14 LTS 便携版：D:/Projects/Codex/tools/blender/blender-4.5.14-windows-x64/blender.exe。
- 官方 ZIP SHA256：b9533d2397ac1984db4466fb23a7a4649391cca93f6e84209f9bcc60d071c8b9，已与 Blender 官方校验文件匹配。
- uv 0.13.6 和隔离 MCP 环境均在 D:/Projects/Codex/tools/uv；缓存位于 D:/Projects/Codex/tools/cache/uv。
- mcp-for-blender 固定 2.2.6；addon.py 固定官方仓库提交 992233bb258975a05eec8b5691465c50c2831e34。
- Codex 原配置只追加 blender 服务，既有配置保留，并在原配置目录留备份。连接为 127.0.0.1:9876，遥测关闭。
- 原生 MCP 的 get_addon_status 返回 Blender 4.5.14 LTS、协议15、插件匹配、telemetry_consent=false；execute_blender_code 实际生成 Sapling 树，再执行本项目制作脚本成功导出资产。
- 付费生成器和需要 API key 的素材库未启用。MCP 安装本身不包含免费的“图片自动变精修模型”服务。
- Blender 专用配置和插件位于 D:/Projects/Codex/tools/blender/profile。运行 tools/blender/launch_windows.ps1 可启动相同配置。

来源：[MCP 官方项目](https://github.com/ahujasid/mcp-for-blender)、[Blender LTS](https://www.blender.org/releases/4-5/)、[官方下载和校验](https://download.blender.org/release/Blender4.5/)、[uv](https://github.com/astral-sh/uv)。

## 免费工具及资产研究结果

| 工具或套件 | 来源与许可 | 适合本游戏的用途 | 本次实际状态 |
|---|---|---|---|
| Sapling Tree Gen | [Blender 插件官方源码镜像](https://github.com/blender/blender-addons/tree/b42d68627734cb18af0e6f41537063984313a284/add_curve_sapling)，GPL 插件代码 | 林木和枝干快速生成，窃荣枝冠可先取结构参考再定制造型 | 已安装、启用，实际生成 sapling_tree 并进入主城；窃荣枝冠为本项目定制网格 |
| A.N.T. Landscape | [同一官方镜像](https://github.com/blender/blender-addons/tree/b42d68627734cb18af0e6f41537063984313a284/ant_landscape)，GPL 插件代码 | 山体与浮岛地貌草模 | 已安装、启用；本轮没有把新地形接入战斗地图 |
| Rigify | [官方镜像](https://github.com/blender/blender-addons/tree/b42d68627734cb18af0e6f41537063984313a284/rigify)、[官方说明](https://docs.blender.org/manual/en/latest/addons/rigify/index.html)，GPL 插件代码 | 人形角色控制架、动作制作 | 已安装、启用；窃荣采用定制7骨骼绑定，尚未采用 Rigify 人形控制架 |
| Kenney Nature Kit | [官网](https://kenney.nl/assets/nature-kit)，CC0，330件 | 草木、岩石与自然物件底库 | 许可已核实；官方 ZIP 下载返回403，未纳入游戏，也未使用来源不明的转载 |
| Quaternius Universal Base Characters | [官网](https://quaternius.com/packs/universalbasecharacters.html)，CC0，区分 Free/Source 层级 | 人形底模、发型与动作重定向 | 研究候选，未下载；免费包与付费 Source 内容有区别，不能把完整 .blend 源文件当成免费承诺 |
| Poly Haven | [素材许可](https://polyhaven.com/license)、[官方 API](https://github.com/Poly-Haven/Public-API)，素材CC0 | HDRI、石材木材参考和 PBR | 研究候选，未下载；API 使用条件与素材许可分开，使用 API 时按其要求展示信用信息 |

插件使用固定源码提交，已在 Blender 4.5.14 中实际启用；没有将整个插件库、安装包、机器配置或下载缓存提交游戏仓库。没有 GPL 插件源码复制进游戏脚本。表格中的“候选”不能算已经落地的游戏资产。

## 首批资产及真实交付

| 资源 | 三角面 | 材质槽 | GLB大小 | 游戏用途 |
|---|---:|---:|---:|---|
| b03 窃荣 V2 | 86,914 | 15 | 6,671,720 bytes | 替换该 Boss 的运行模型，7骨骼，Idle/Walk/Attack |
| sapling_tree | 15,964 | 2 | 665,160 bytes | 主城后方7株树共享同一资源 |
| zhaosheng_pagoda | 12,328 | 7 | 310,232 bytes | 主城照生灯台，曲面屋顶、瓦脊、铜饰、悬灯 |

各资产同时交付 assets/blender 下的 .blend、.glb 和 .metrics.json。灯台 .blend 保留分件结构，导出时合并静态网格以减少批次。Godot 直接加载 GLB，不依赖玩家安装 Blender；项目关闭 .blend 自动导入，避免本机路径成为运行依赖。参见 [Godot 官方格式说明](https://docs.godotengine.org/en/4.3/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)。

角色和底面材质统一到线性颜色空间，修复旧材质与 GLB 混用发白。原来的36个程序化角色场景已重新生成，作为其他角色和缺失新资源时的回退。模型不承担碰撞和命中判定，玩法继续使用已有的共享预兆参数。

## 参考图、实际模型和复现

1. assets/references/qierong-turnaround.png 是生成的四视图概念参考；同目录提示词保留目标及一致性要求。
2. tools/blender/build_assets.py 是总制作入口，deer() 已转到 tools/blender/refine_qierong.py 的新版制作。在专用 Blender 空场景通过 MCP 执行文件后，依次调用 sapling()、pagoda()、deer() 即可重建三件资源。脚本会清空当前场景，因此应在专用空文件运行。
3. 窃荣胸灯、枝冠、叶鬃、铜饰和木纹采用实际网格；新版木纹另有1024像素颜色和切线法线PNG，嵌入GLB并在Godot验证。图案由制作脚本生成，未以未导出的Blender专用节点代替游戏细节。
4. 保存源文件后导出 GLB。三段动作经 NLA 导出；Godot 运行时循环 Idle，主祟预兆触发 Attack，结束回到 Idle。Walk 已导出并验证，当前窃荣没有新增追逐移动 AI。
5. docs/screenshots/blender 保留第一版实际模型渲染；docs/screenshots/qierong-v2 包含当前新版四视角、Godot近景与战斗画面。两者均是实际模型渲染，不是概念图。
6. docs/screenshots/town-blender.png、boss-blender.png 是实际 Godot 画面；town-front/left/back/right.png 为同一主城的四个观察方向。可用 --preview --restored-town --capture-view=front --capture-clean --campaign-capture=D:/...png 复现，不写玩家进度。

## 美术范围

这是可复现的首批三件资产和已跑通的工具链。其余19只 Boss、10种小怪与 NPC 仍以先前的程序化模型为主体。概念参考比当前网格更精细；本轮没有完成20只 Boss 的商业级雕刻、重拓扑、烘焙贴图、肌肉形变、LOD 和完整动作库，不将此阶段称为“已完成3A”。

后续以窃荣样板的方法逐个推进赤棘、失稷、缄风、壅川，再扩展其他怪物：先定四视图与正交比例，优先复用已验证生成器，定制核心轮廓，再完成模型、绑定、贴图和游戏镜头验收。Unity/Unreal/Three.js 可以使用同一 GLB 资产作为后续移植起点，仍需分别验证材质、动画和渲染预算。

当前窃荣模型的造型对比、352项验证与剩余差距见[视觉精修记录](QIERONG_VISUAL_REFINEMENT.md)。
