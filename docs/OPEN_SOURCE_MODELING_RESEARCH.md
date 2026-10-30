# 可复用建模项目核查（2026-10-30）

目标：改善本项目中式异兽对概念图的还原，以及亭阁、灯台、机关的制作效率。审阅依据为官方仓库、源码、许可和项目自己的测试记录；本轮未安装执行这些第三方项目，也未调用云端生成或支付接口。下面的适配判断属于针对本项目的工程分析，未实测的效果不能视为已验证。

## 采用顺序

1. 优先验证 cc-blender-skill 的参考图约束、多视图拟合和叠图校验模块，用于减少窃荣“合理但不像原图”的问题。
2. 优先复用 threejs-architecture-effects 的古建几何与材质构造，给灯台、亭阁、山门提供更完整的结构；Godot接入需另做静态GLB与材质转换。
3. 异兽底模另做图生3D试验：TRELLIS.2为主候选，Hunyuan3D-2.1为条件备选。图生输出再进入Blender修形、重拓扑/减面、材质处理、四足绑定和Godot验收。
4. 器物与机关需要参数精度时采用text-to-cad。暂不更换现有mcp-for-blender连接，也不因工具数量多就替换制作管线。

## 六个用户指定项目

| 项目 | 核查结果 | 本游戏用途与采用判断 |
|---|---|---|
| [RobLe3/cc-blender-skill](https://github.com/RobLe3/cc-blender-skill) | MIT。当前README为v1.4.0、30个技能；旧About仍显示10个。项目报告Blender5.1.1与Codex的有限实机验证，4.x仍待验证。旧v0.3脚手架状态已经过时。 | **优先试点。** 参考图分析、正交配准、多视图拟合、叠图和外观校准最贴合当前问题。它提供可执行校验脚本与工作流，并不自带一个训练好的异兽图生模型。 |
| [SekaiNoOwari77/mcp-3d-modeling-agent](https://github.com/SekaiNoOwari77/mcp-3d-modeling-agent) | AGPL-3.0-or-later。源码确有218个唯一Tool注册，来自RFingAdam/mcp-blender体系；原创增量是LangGraph编排。Observer以统计查询为主，默认不渲染，LLM消息不带图像。 | **流程参考，暂不整套替换。** 其闭环不能等同视觉相似度评审。默认9876端口及插件协议与现有连接有集成冲突；另需OpenAI兼容模型或本地LLM。 |
| [lhlGitHub/threejs-architecture-effects](https://github.com/lhlGitHub/threejs-architecture-effects) | MIT。真实Three.js古建程序几何、Canvas材质和建造效果；运行不需生成API Key。现成产物为Vite/React/Three.js网页，需Node22.13+与WebGL2。 | **优先用于场景建筑。** 复用飞檐、瓦片、斗拱和梁柱方法。没有现成GLB交付承诺；自定义建造着色器不能直接当通用GLB动画，需要转换或重做。 |
| [nirholas/three.ws](https://github.com/nirholas/three.ws) | 主仓Apache-2.0，相关Skill元数据标MIT。forge_free是托管文本生成入口，平台承担服务端供应商Key和资源；另有资助的托管路线、BYOK和付费路线。 | **远程生成候选，需试件。** 免费forge_free不接受参考图片，图生要选择另一条路线并核实实际可用性。create-3d-avatar面向人形，不能直接套用到鹿。不能把“用户免Key”解释为本地无依赖运行。 |
| [mfranzon/render](https://github.com/mfranzon/render) | 确有build123d建模、浏览器查看、局部编辑队列及GLB/STEP导出；setup.sh采用Bash与类Unix路径。当前树和README未找到明确项目许可证，GitHub元数据license为null。 | **借鉴交互，暂不直接并入代码。** 适合零件、器物和机关，不是异兽雕刻能力。先明确许可；Windows接入还需改启动/路径。 |
| [earthtojake/text-to-cad](https://github.com/earthtojake/text-to-cad) | MIT，持续维护；Python/build123d/OpenCASCADE建模、cadgen运行时、CAD Viewer与STEP/GLB等输出，支持Codex。运行时非纯Markdown，首次需下载。 | **参数化器物首选。** 适合铜镜、机关轮、阵盘、台座与结构件。对鹿脸、叶鬃、有机表面的帮助有限。项目发布分支latest与开发main分开，不宜盲装开发头。 |

“AGPL”不表示所有商业使用均收费；集成方式和修改分发义务需要按仓库LICENSE及COMMERCIAL.md处理。本轮没有把该代码并入游戏。mfranzon/render公开可读也不能直接认定为具有明确开源授权。

### 最值得直接审查的具体文件

- cc-blender-skill：
  - [reference-to-3d](https://github.com/RobLe3/cc-blender-skill/blob/a2634b588e80265e796aa53f8ab178d75105c2af/plugin/skills/reference-to-3d/SKILL.md)
  - [multiview-fit-loop](https://github.com/RobLe3/cc-blender-skill/blob/a2634b588e80265e796aa53f8ab178d75105c2af/plugin/skills/multiview-fit-loop/SKILL.md)
  - [实际叠图校验脚本](https://github.com/RobLe3/cc-blender-skill/blob/a2634b588e80265e796aa53f8ab178d75105c2af/plugin/skills/reference-analysis-validator/scripts/render_overlay_validator.py)
  - [版本与测试范围](https://github.com/RobLe3/cc-blender-skill/blob/a2634b588e80265e796aa53f8ab178d75105c2af/README.md)
- 218工具Agent：[Observer](https://github.com/SekaiNoOwari77/mcp-3d-modeling-agent/blob/3f22ad43ffff9dcb8bac09694fcfed97ff3387a3/agent/nodes/observer.py)、[LLM消息](https://github.com/SekaiNoOwari77/mcp-3d-modeling-agent/blob/3f22ad43ffff9dcb8bac09694fcfed97ff3387a3/agent/llm.py)、[配置](https://github.com/SekaiNoOwari77/mcp-3d-modeling-agent/blob/3f22ad43ffff9dcb8bac09694fcfed97ff3387a3/agent/config.py)。
- 古建：[architecture.ts](https://github.com/lhlGitHub/threejs-architecture-effects/blob/693ca2ec1193e7355054f14d7deb1427439a24d0/assets/starter/src/heritage/architecture.ts)、[materials.ts](https://github.com/lhlGitHub/threejs-architecture-effects/blob/693ca2ec1193e7355054f14d7deb1427439a24d0/assets/starter/src/heritage/materials.ts)、[建造着色器](https://github.com/lhlGitHub/threejs-architecture-effects/blob/693ca2ec1193e7355054f14d7deb1427439a24d0/assets/starter/src/heritage/builder.ts)。
- three.ws：[生成Skill](https://github.com/nirholas/three.ws/blob/0bdf443a8dae39d3eb09cf7617cc85a53a1579cc/.agents/skills/generate-3d-model/SKILL.md)、[路线区别](https://github.com/nirholas/three.ws/blob/0bdf443a8dae39d3eb09cf7617cc85a53a1579cc/.agents/skills/generate-3d-model/reference.md)、[人形限制](https://github.com/nirholas/three.ws/blob/0bdf443a8dae39d3eb09cf7617cc85a53a1579cc/.agents/skills/create-3d-avatar/SKILL.md)、[托管客户端](https://github.com/nirholas/three.ws/blob/0bdf443a8dae39d3eb09cf7617cc85a53a1579cc/api/_mcp-studio/forge-client.js)。
- render：[导出实现](https://github.com/mfranzon/render/blob/4fa2b88b2f501b46b410da2b4e991c62f076b2ab/viewer/render.py)、[安装脚本](https://github.com/mfranzon/render/blob/4fa2b88b2f501b46b410da2b4e991c62f076b2ab/setup.sh)。
- text-to-cad：[运行原理及安装范围](https://github.com/earthtojake/text-to-cad/blob/e4e6e8375d0e8fe7180c275082a9f260e436543e/README.md)。

## 补充：直接处理参考图的3D生成模型

| 模型 | 能力与约束 | 本项目判断 |
|---|---|---|
| [Microsoft TRELLIS.2](https://github.com/microsoft/TRELLIS.2) | 图片生成带PBR的网格并可导出GLB，代码与模型标MIT，部分依赖另有条款。官方仅验证Linux，需要NVIDIA至少24GB显存；其速度数据来自H100。 | **优先A/B试验的异兽底模候选。** 输入一张干净、完整的单主体三分之四图，再用其他角度验收；不能把四格视图当普通单图直接保证重建。尚未实测窃荣效果。 |
| [Tencent Hunyuan3D-2.1](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1) | 图生形体与PBR纹理。官方给出形体10GB、纹理21GB、合并29GB显存配置。采用专用Community License，有地域及使用条件，并非MIT/Apache。 | **条件备选。** 需先核实部署和发行适用条件。[许可原文](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/blob/82920d643c0dc2f7bfd7255f45f62d386edfe60c/LICENSE)。 |

本机枚举到AMD Radeon780M，没有发现NVIDIA显卡。TRELLIS.2官方CUDA环境不适合按默认方案直接装在这台机器上；图生试验应使用另有的兼容显卡、远程工作站或条件明确的托管服务。开源代码与权重不等于计算资源和托管服务免费。

## 建议的落地试点

- **先补可测量的美术反馈。** 在现有Blender4.5.14/MCP上隔离验证参考图清单、正交配准、剪影及关键点对照。cc-blender-skill中的Blender5.x配方另作兼容测试，不直接覆盖当前环境。
- **一个异兽样本。** 用相同参考制作图生底模，与当前窃荣对照。检查正侧背轮廓、脸部神态、鹿角/四肢完整性、叶鬃分层与可编辑性；不能只选一个漂亮角度。图生底模的骨骼和游戏可用拓扑仍需后处理。
- **一个建筑样本。** 以照生灯台试用古建几何，验证曲面飞檐、瓦片封口、梁柱比例、UV/材质和GLB进入Godot后的效果。
- **验收后再扩展。** 保留现有玩法、存档、模型回退与测试。源文件、贴图、生成参数、许可出处和真实游戏画面一起交付。

相似度指标只评价其定义的掩膜或图像条件，不能冒充完整美术质量评分。AI生成的多视图若互相矛盾，应先确认主视图与比例，再拟合模型。

## 固定审阅版本

| 仓库 | 提交 | 该提交时间UTC |
|---|---|---|
| cc-blender-skill | a2634b588e80265e796aa53f8ab178d75105c2af | 2026-10-12 |
| mcp-3d-modeling-agent | 3f22ad43ffff9dcb8bac09694fcfed97ff3387a3 | 2026-08-19 |
| threejs-architecture-effects | 693ca2ec1193e7355054f14d7deb1427439a24d0 | 2026-09-22 |
| three.ws | 0bdf443a8dae39d3eb09cf7617cc85a53a1579cc | 2026-10-30 |
| mfranzon/render | 4fa2b88b2f501b46b410da2b4e991c62f076b2ab | 2026-08-04 |
| text-to-cad | e4e6e8375d0e8fe7180c275082a9f260e436543e | 2026-10-30 |
| TRELLIS.2 | 75fbf0183001ed9876c8dbb35de6b68552ee08bd | 2026-06-05 |
| Hunyuan3D-2.1 | 82920d643c0dc2f7bfd7255f45f62d386edfe60c | 2025-10-17 |
