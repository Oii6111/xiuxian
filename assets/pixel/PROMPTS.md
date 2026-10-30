# 像素版美术素材

生成方式：内置 image_gen。输入参考为用户选中的像素风概念图。

- village-background.png：无 HUD、无人物的固定斜俯视场景底图。
- cultivator-walk.png：透明四方向 × 四步角色图集；运行时使用 AtlasTexture 提取帧。
- village-npcs.png：三位透明 NPC 立绘。

地图碰撞、角色动画、寻路、文字、数值、界面、传送阵、水面和灯笼特效由 Godot 实时运行。

## pixel-village-background

Use case: stylized-concept. Asset type: actual playable 2D Godot game environment background, full bleed landscape 16:10, ideally 1600x1000. Input image 1 is the style and composition reference.
Create a clean game environment based very closely on the attached pixel-art Chinese cultivation village. Preserve the extremely rich hand-placed pixel-art aesthetic, crisp pixel clusters, warm golden light, detailed blue-grey tiled timber homes on the LEFT half, lanterns, little crop garden lower left, lush green trees, bright turquoise stream and arched stone bridge lower middle, towering misty mountains and waterfalls at distance, glowing gold circular tribulation platform upper middle-right, a dark violet demonic portal arch upper far right and a carved stone achievement stele lower right. Fixed isometric/three-quarter view.
CRITICAL: This is the clean background layer for a real game. REMOVE ALL the reference HUD, title, character card, top resource bar, quest scroll, keyboard controls, every label, sign text, ALL CHARACTERS/people/animals, speech bubbles. Reconstruct uninterrupted scenery behind them. Empty timber signs are fine. No Chinese characters, no text, no letters, no numbers. No interface at all. No playable character.
Maintain a WIDE CLEAR WALKABLE light tan cobblestone plaza across the center from roughly x=24% to x=80%, y=42% to y=76%. Open paved paths link the house front at x=28%,y=52%, the staircase to the golden platform x=57%,y=30%, the violet portal approach x=81%,y=47%, and the stele x=77%,y=69%. Keep those spaces clear for separate animated sprites. Foreground stream runs near y=83%, the stone bridge crosses at x=63%, with a clear paved bridge path from the plaza. The empty central spawn is at x=49%,y=65%.
No camera perspective distortion, no depth of field, no smooth vector lines, no blurry painterly rendering. Polished 32-bit RPG environment, coherent pixel scale, not Minecraft, not voxel. Match reference strongly rather than inventing a different scene.

## pixel-cultivator-walk

Use case: stylized-concept. Asset type: production sprite animation sheet for a Godot 2D pixel-art Chinese cultivation RPG.
Make one perfectly regular FOUR COLUMNS by FOUR ROWS (4x4 = 16 cells) sprite sheet on a TRUE TRANSPARENT background. Square overall canvas. Equal cells, no borders, no labels, no text, no shadows on the ground, no scenery. Each cell contains exactly ONE full-body tiny chibi young male swordsman character, centered horizontally with feet at exactly the same baseline. Nothing touches a cell edge. Keep generous uniform transparent padding. Character occupies 70% of each cell height.
Character identity: dark brown hair tied in high bun/ponytail with navy ribbon, white/ivory flowing Chinese robe with blue trim, navy trousers, small brown shoes, narrow brown belt, a sheathed sword on his back. Friendly pixel-art RPG hero with a large expressive head, about 3 heads tall. Visible crisp square pixels, 32-bit game sprite aesthetics matching a richly detailed warm pixel-art Chinese village. Restrained ivory, ink blue, chestnut, warm skin tones. Entire sheet must have consistent scale and identical character identity.
ROW 1: walking DOWN facing camera, four consecutive steps: left foot forward, passing neutral, right foot forward, passing neutral.
ROW 2: walking LEFT, four consecutive steps.
ROW 3: walking RIGHT, four consecutive steps.
ROW 4: walking UP away from camera, four consecutive steps.
All 16 sprites have their feet aligned to a uniform baseline within every equal square cell. No extra items, duplicate faces, design variants, diagonal views, captions, gridlines or checkerboard. Genuine alpha transparency.

## pixel-village-npcs

undefined

