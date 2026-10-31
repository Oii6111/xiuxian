extends SceneTree
const Assets = preload("res://scripts/pixel_assets.gd")
const MALE = "res://assets/pixel/cultivator-walk.png"
const FEMALE = "res://assets/gameplay/female-walk-v2.png"
var font: SystemFont
var title_font: SystemFont
var errors = 0

func _initialize() -> void:
	_run.call_deferred()

func _validate_atlas(path: String) -> void:
	var image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		push_error("Missing avatar image: " + path)
		errors += 1
		return
	if image.get_pixel(0, 0).a > 0.05:
		push_error("Avatar background is not transparent: " + path)
		errors += 1
	# Existing source atlases include up to three residual padding pixels.
	# Check visible alpha bounds, not invisible generator residue at alpha < 0.2.
	var cell = Vector2i(image.get_width() / 4, image.get_height() / 4)
	for row in range(4):
		for column in range(4):
			var frame_image = image.get_region(Rect2i(Vector2i(column, row) * cell, cell))
			var minimum = cell
			var maximum = Vector2i(-1, -1)
			var visible_pixels = 0
			for y in range(cell.y):
				for x in range(cell.x):
					if frame_image.get_pixel(x, y).a > 0.2:
						minimum = minimum.min(Vector2i(x, y))
						maximum = maximum.max(Vector2i(x, y))
						visible_pixels += 1
			print("VISIBLE CELL ", path.get_file(), " ", Vector2i(column, row), " bounds=", minimum, "..", maximum, " visible_pixels=", visible_pixels)
			if visible_pixels < 1000 or minimum.x <= 0 or minimum.y <= 0 or maximum.x >= cell.x - 1 or maximum.y >= cell.y - 1:
				push_error("Empty or visibly clipped avatar cell: " + path + " " + str(Vector2i(column, row)))
				errors += 1
	print("AVATAR ATLAS ", path, " ", image.get_size(), " / 16 frames / alpha ", image.detect_alpha())

func _label(parent: Node, text: String, position: Vector2, size_value: Vector2, font_size: int, color: Color, heading: bool = false) -> Label:
	var label = Label.new()
	label.text = text
	label.position = position
	label.size = size_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", title_font if heading else font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _sprite(parent: Node, texture: Texture2D, foot: Vector2, height: float) -> void:
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = foot
	sprite.offset.y = -texture.get_height() * 0.5
	sprite.scale = Vector2.ONE * height / texture.get_height()
	parent.add_child(sprite)

func _card(parent: Node, rect: Rect2, female: bool) -> void:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style = StyleBoxFlat.new()
	style.bg_color = Color("f5f0e3")
	style.border_color = Color("a5b4b0") if not female else Color("b9a6bd")
	style.set_border_width_all(3)
	style.shadow_color = Color(0.19, 0.17, 0.13, 0.14)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var frames = Assets.frames(FEMALE if female else MALE, 4, 4, 0.2)
	var accent = Color("65517b") if female else Color("3e596d")
	_label(panel, "女修 · 清岚" if female else "男修 · 松风", Vector2(0, 20), Vector2(rect.size.x, 48), 38, accent, true)
	_label(panel, "双髻长发 / 淡紫裙装 / 青色披帛" if female else "高束发 / 白蓝短袍 / 深蓝束带", Vector2(0, 77), Vector2(rect.size.x, 30), 19, Color("7c756d"))
	_sprite(panel, frames[0], Vector2(rect.size.x * 0.5, 464), 330)
	_label(panel, "正面形象", Vector2(0, 480), Vector2(rect.size.x, 30), 18, accent)
	var separator = ColorRect.new()
	separator.position = Vector2(32, 530)
	separator.size = Vector2(rect.size.x - 64, 1)
	separator.color = Color("d8cebc")
	panel.add_child(separator)
	for i in range(3):
		var x = rect.size.x * (0.21 + i * 0.29)
		_sprite(panel, frames[[4, 8, 12][i]], Vector2(x, 667), 112)
		_label(panel, ["左侧", "右侧", "背面"][i], Vector2(x - 65, 681), Vector2(130, 28), 17, Color("7c756d"))

func _run() -> void:
	_validate_atlas(MALE)
	_validate_atlas(FEMALE)
	if errors > 0 or "--validate-only" in OS.get_cmdline_user_args():
		quit(errors)
		return
	root.content_scale_size = Vector2i(1440, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(1440, 960)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "SimSun"])
	var canvas = Control.new()
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(canvas)
	var background = ColorRect.new()
	background.color = Color("e8e0cf")
	background.size = Vector2(1440, 960)
	canvas.add_child(background)
	_label(canvas, "松风与清岚", Vector2(0, 27), Vector2(1440, 70), 53, Color("493d32"), true)
	_label(canvas, "像素角色形象 · 正面 / 侧面 / 背面", Vector2(0, 100), Vector2(1440, 34), 22, Color("807260"))
	_card(canvas, Rect2(45, 159, 657, 741), false)
	_card(canvas, Rect2(738, 159, 657, 741), true)
	_label(canvas, "与游戏中的角色选择、仙村行走及战斗形象保持一致", Vector2(0, 919), Vector2(1440, 28), 17, Color("807260"))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result = root.get_texture().get_image().save_png("res://output/16-avatar-comparison.png")
	print("AVATAR COMPARISON CAPTURE: ", result)
	quit(result)
