# 灵宠美术

由内置 imagegen 工具基于聊天中选定的四张原创概念板生成；本次安装四张透明 PNG，未覆盖既有角色美术。

- cloud_fox.png：奶白云尾小狐、桃色耳朵、青玉围巾。
- gourd_dragon.png：圆润薄荷色幼龙、金色小角、随身葫芦。
- lotus_bird.png：奶黄团雀、莲叶帽、桃色花苞。
- herb_deer.png：蜜棕小鹿、草叶鹿角、草药香囊。

生成提示词共用部分：

> Edit the reference concept board into a usable isolated game character asset. Keep the identity of the large hero pet exactly: same colors, accessories, proportions and charming face. Output only one full-body pet, centered, in a relaxed neutral friendly three-quarter idle pose facing slightly to the viewer's right. Every body part completely inside the frame with generous transparent margins. Genuine transparent alpha background. Remove the reference layout, frames, lettering, smaller pose examples, floor, scenery and decorations. No ground shadow or extra effects. Simplify details into deliberate crisp pixel clusters with warm-brown stepped outlines, a restrained palette and clear silhouette readable at 48–64 pixels in a Godot xianxia village. Cute original 2D pixel art. No text, photorealism or 3D lighting.

四次生成分别用上方四只宠物的概念图及对应颜色/配饰作为参考。原图保持不动，游戏资源保存于本目录。运行时读取 alpha 包围框生成 AtlasTexture；跟随、呼吸、说话与庆祝由本地位置、缩放和跳跃表现驱动，当前不是逐帧行走图集。
