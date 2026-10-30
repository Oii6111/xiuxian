# 松风仙境 · 首版美术记录

- 目标：休闲修仙、青绿水墨、云纹、饕餮纹、飘逸且亲切的长辈修士。
- 表现：Godot 原生 3D 网格、固定俯视镜头、低高光材质、细描边人物、动态双面披帛。角色为概念图的游戏化三维简化造型。
- `songfeng-concept.png`：本聊天已确认的主角原始概念图。
- `world-concept.png`：本聊天已确认的一座主岛与五座试炼浮岛的原始概念图。
- `cloud-sea.png`：内置 image_gen 生成的水墨远景位图，用作三维场景后方的背景。
- 人物、场景网格及云纹由本项目构建源文件生成，没有用概念图替代可行走场景。

## 背景生成提示词

生成方式：内置 image_gen；非 CLI。最终提示词如下：

> Use case: stylized-concept. Asset type: background texture behind a playable 3D game diorama.
> Create a wide 3:2 landscape background painting, no text, for a tranquil Chinese ink-and-watercolor cultivation game. An endless pale ivory cloud sea with soft sage-green and blue-gray ink mountains far in the distance, subtle warm rice-paper fibers. Atmospheric washed-out silhouettes of elegant tall Chinese karst peaks along the UPPER FIFTH and far left and right edges only. The center and lower center are mostly very pale warm off-white fog and empty soft mist, to leave space for the game's separately rendered floating islands. A few beautiful large delicate Chinese scroll-cloud shapes emerge as watercolor washes at the edges, dissolving into the paper. Very low contrast, restrained, luminous overcast daylight, sophisticated hand-painted animation background, poetic and airy, quiet jade-and-ivory palette, organic dry-brush mountain ridges and wet-ink diffusion. Broad flowing mist layers, no hard outlines around clouds. Entire surface is an actual finished background texture, edge to edge. No islands, no land or ground in foreground, no buildings, no characters, no diagram, no labels, no sun disc, no UI, no border, no watermark, no dark sky, no photorealism, no 3D rendering.
