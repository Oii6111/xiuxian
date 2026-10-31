# 战斗动作资产

内置 imagegen 参考原 Boss 外观与男女角色，生成透明 4×4 逐帧图集。精确提示词在 PROMPTS.json，原始图 *_actions_v*.png 及修订保留，打包时选择各 ID 的最高版本；*_runtime_v1.png 为实际播放图，索引在 data/combat/action_atlases.json。

- b00..b19：0–3 四帧行走 / 游动 / 扇翼，4–7 肢体攻击，8–11 施法，12–13 受击，14 失衡，15 倒地。
- hero_male / hero_female：0–3 行走，4–7 挥剑，8–11 剑诀，12–13 翻滚，14 受击，15 待机。
- vfx_elements：每行四帧，分别为剑弧、雷电、火晶、水浪。
- vfx_nature：每行四帧，分别为藤木、岩砂、月光、金印。

共 24 图集 / 384 帧。角色与各 Boss 保持原外观，动作按其身体结构重新绘制。四关键帧适合当前像素动画节奏，尚未制作额外中间帧或三维骨架。

python tools/pack_action_atlases.py 使用 Pillow / NumPy / SciPy 作技术打包：按透明连通轮廓提取完整姿态，记录 source_boxes；固定统一比例、透明边距和脚底锚点，避免等格切图截断肢体或混入旁边姿态；保留主体与原图。每图所有姿态共用一个尺寸比例，不做逐姿态放大缩小。运行时代码 scripts/systems/combat/action_atlas.gd 按战斗阶段和真实命中窗口选帧。

python tools/build_action_previews.py 输出根位置不动的动作 GIF 和源帧预览；真实场景录像由 Godot 渲染测试输出，两者明确区分。未使用其他游戏的动画素材或采样。
