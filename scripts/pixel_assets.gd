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

static func frames(path: String, columns: int, rows: int, alpha_threshold: float = 0.0, dominant_component: bool = false) -> Array[Texture2D]:
	var key = path + str(columns) + "x" + str(rows) + ":" + str(alpha_threshold) + ":" + str(dominant_component)
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
			var cell_image = image.get_region(Rect2i(offset, cell))
			var used = visible_rect(cell_image, alpha_threshold) if alpha_threshold > 0 else cell_image.get_used_rect()
			if dominant_component:
				used = dominant_rect(cell_image, alpha_threshold)
			if used.size == Vector2i.ZERO:
				used = Rect2i(Vector2i.ZERO, cell)
			var frame = AtlasTexture.new()
			frame.atlas = source
			frame.region = Rect2(offset + used.position, used.size)
			frame.filter_clip = true
			result.append(frame)
	atlases[key] = result
	return result

static func visible_rect(image: Image, alpha_threshold: float) -> Rect2i:
	# Ignore near-invisible generator residue when framing character animations.
	# Only texture regions change; the original generated PNG alpha is preserved.
	var minimum = image.get_size()
	var maximum = Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > alpha_threshold:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	if maximum.x < 0:
		return Rect2i()
	minimum = (minimum - Vector2i.ONE).max(Vector2i.ZERO)
	maximum = (maximum + Vector2i.ONE).min(image.get_size() - Vector2i.ONE)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

static func dominant_rect(image: Image, threshold: float) -> Rect2i:
	# Select the main connected creature when neighboring atlas cells leave stray pixels.
	# This changes only the sampled texture rectangle, never the downloaded artwork.
	var mask = BitMap.new()
	mask.create_from_image_alpha(image, threshold)
	var polygons = mask.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 1.0)
	var best_area: float = 0
	var best_rect = Rect2i()
	for polygon in polygons:
		if polygon.size() < 3:
			continue
		var area: float = 0
		var bounds = Rect2(polygon[0], Vector2.ZERO)
		for i in range(polygon.size()):
			area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
			bounds = bounds.expand(polygon[i])
		area = absf(area)
		if area > best_area:
			best_area = area
			best_rect = Rect2i(bounds.grow(2).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size()))))
	return best_rect if best_area > 0 else visible_rect(image, threshold)

static func portrait(frame: Texture2D) -> Texture2D:
	if frame is AtlasTexture:
		var result = AtlasTexture.new()
		result.atlas = frame.atlas
		result.region = Rect2(frame.region.position, frame.region.size * Vector2(1, 0.62))
		result.filter_clip = true
		return result
	return frame
