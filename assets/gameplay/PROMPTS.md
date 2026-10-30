# 四格示意图接入游戏：美术素材

生成工具：内置 image_gen。所有最终素材均已复制到当前目录，游戏不引用 generated_images 缓存路径。

参考：`concepts/next-features-overview.png`。场景仅保留环境，角色、数值、护盾、落雷、吐息、危险区和技能为 Godot 的独立节点及实时逻辑。

## female-walk.png

透明背景：是

Use case: stylized-concept. Actual Godot RPG sprite sheet, matching the FEMALE player in the top left of reference 1. Exactly 4 columns by 4 rows =16 equally sized cells, one character per cell, perfectly even square overall canvas with genuine alpha TRANSPARENCY. No words, borders, scenery or floor shadows. Friendly three-head-tall chibi young woman cultivator, dark chestnut long high ponytail, navy blue ribbon trailing, ivory white Chinese robe with navy blue collar and jade/turquoise hem accents, brown belt with small gold clasp, blue trousers, brown shoes, sheathed sword strapped diagonally on back. Crisp visible square-pixel 32-bit RPG sprite style consistent with reference. Each full body centered, equal size, uniform padding and feet at same baseline inside each square cell. Row 1 faces DOWN front walking four steps. Row 2 faces LEFT walking four steps. Row 3 faces RIGHT walking four steps. Row 4 faces UP back walking four steps. Feet cycle left-forward, neutral passing, right-forward, neutral passing. Keep identity and robe consistent in all sixteen images. No extra sprites or labels.

## elder-meditating.png

透明背景：是

Use case: stylized-concept. Actual transparent Godot game sprite of the elderly family-member cultivator meditating, same person and pixel style as bottom left in reference. ONE full-body kindly elderly Chinese male, white eyebrows, white tied hair topknot and long white beard, warm ivory and muted tan traditional robe, brown sash. Sitting cross-legged in lotus meditation pose, BOTH hands calmly resting together before the abdomen, eyes peacefully closed. Front-facing slight elevated 3/4 view matching an isometric RPG ground. Crisp readable 32-bit pixel art, carefully placed square pixels, chibi about 3 heads tall when standing, gentle kindly expression. Entire seated body included, no crop, centered with transparent margin. Genuine alpha transparency. Absolutely NO platform, lightning, runes, shield, scene, ground shadow, text or UI baked into sprite; these will be separate real-time game effects. Not a smooth anime painting.

## dragon-states.png

透明背景：是

Use case: stylized-concept. Production transparent boss animation sprite atlas for Godot, based on the purple dragon in bottom right of reference. EXACT 2 columns x 2 rows, four equal square cells, ONE complete dragon in each, uniform scale and center, generous transparent padding so no part touches cell borders. A magnificent horned PURPLE SHADOW DRAGON, bright violet eyes, dark indigo-purple overlapping scales with magenta highlights, open clawed front limbs, long curled serpentine body and curling tail. Faces LEFT toward the player, side / three-quarter isometric RPG view. Rich but clearly pixelated 32-bit game art, bold readable silhouette, stylized friendly fantasy menace. Four states of SAME creature: top left idle mouth slightly open; top right attack jaws OPEN WIDE preparing breath; bottom left flinching hurt head lowered and claws recoiling; bottom right defeated curled on ground with closed eyes. NO energy beams, particles, floor, portal, shadows or scenery, no UI, text or gridlines. Genuine alpha transparency. Keep full dragon entirely within each equal cell. Not four dragon designs, all identical anatomy, horns, scales and palette.

## tribulation-stage.png

透明背景：否

Use case: stylized-concept. Actual full-screen 16:10 Godot pixel RPG background, based closely on bottom left of reference. A spacious ancient circular stone meditation terrace suspended above a sea of mist and tall Chinese mountain spires, waterfalls, pines, distant tiled pavilions. Deep blue storm clouds overhead, warm lanterns around terrace, ornate golden circular rune patterns carved into the central stone dais. Camera fixed elevated three-quarter game view. Ground fills lower 60 percent. Central dais located at 62% width, 60% height with ample clear space to put separate meditating elder sprite; clear left foreground at 23% width,73% height for player casting. Contrast luminous warm stone and distant misty blue mountains. CRITICAL clean background layer: remove all characters, elder, player, shield, lightning bolts, effects, interface, buttons, health bars, titles and ALL text from the scene. Only environment, lamps and faint static gold engravings. Real lightning and shield will be rendered by engine separately. Rich crisp square pixel art matching reference exactly. No smooth painting, no people, no screens or watermarks.

## boss-stage.png

透明背景：否

Use case: stylized-concept. Actual full-screen 16:10 Godot pixel RPG battle background, closely matching bottom right of reference. Vast ruined Chinese fantasy stone battleground above clouds, cool dark twilight, misty blue mountains and distant floating tiled pavilions. Stone paving fills the lower two thirds and gives clearly open walkable space. Huge dark indigo jagged carved STONE PORTAL on the RIGHT third, restrained faint purple glow within its EMPTY opening. Torch braziers, chains and dark red banners at edges. Left foreground at 22% width,72% height clear for player, right center at 77% width,50% height clear for separate dragon sprite. Keep open space across center to render attacks. CRITICAL clean environment layer ONLY: no dragon, no monsters, no player, no people, no red attack warning, no sword slash, no energy beam, no health bar, no skill buttons, no UI, no labels or text. These will all be separate game objects and effects. Rich visible square pixel clusters, 32-bit Chinese RPG art, coherent same pixel size as reference, not glossy 3D or smooth anime painting.


