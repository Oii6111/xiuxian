extends RefCounted
## Reuse imported textures in exports; raw images remain supported during CLI development.
static var textures: Dictionary = {}
static var atlases: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path]
	var result: Texture2D
	if FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path):
		result = load(path)
	else:
		var image = Image.load_from_file(path)
		if image:
			result = ImageTexture.create_from_image(image)
	textures[path] = result
	return result

static func frames(path: String, columns: int, rows: int) -> Array[Texture2D]:
	var key = path + str(columns) + "x" + str(rows)
	if atlases.has(key):
		return atlases[key]
	var source = texture(path)
	var result: Array[Texture2D] = []
	if source == null:
		return result
	var image = source.get_image()
	var cell = Vector2i(image.get_width() / columns, image.get_height() / rows)
	for row in range(rows):
		for column in range(columns):
			var offset = Vector2i(column, row) * cell
			var used = image.get_region(Rect2i(offset, cell)).get_used_rect()
			if used.size == Vector2i.ZERO:
				used = Rect2i(Vector2i.ZERO, cell)
			var frame = AtlasTexture.new()
			frame.atlas = source
			frame.region = Rect2(offset + used.position, used.size)
			frame.filter_clip = true
			result.append(frame)
	atlases[key] = result
	return result

static func portrait(frame: Texture2D) -> Texture2D:
	if frame is AtlasTexture:
		var result = AtlasTexture.new()
		result.atlas = frame.atlas
		result.region = Rect2(frame.region.position, frame.region.size * Vector2(1, 0.62))
		result.filter_clip = true
		return result
	return frame
