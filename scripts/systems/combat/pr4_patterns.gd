extends RefCounted
## PR4 四技能规则的预兆/命中共同几何；不涉及玩家灵根或健康属性映射。
const KINDS = ["circle", "line", "ring", "cross"]

static func build(index: int, stage: int, origin: Vector2, target: Vector2, radius: Vector2) -> Dictionary:
	return {"kind": KINDS[posmod(index + stage, 4)], "origin": origin, "target": target, "radius": radius, "width": 32.0}

static func hits(profile: Dictionary, point: Vector2) -> bool:
	for polygon in polygons(profile):
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

static func polygons(profile: Dictionary) -> Array:
	var areas: Array = _raw_polygons(profile)
	if not profile.has("clip"):
		return areas
	var rect: Rect2 = profile.clip
	var boundary := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var clipped: Array = []
	for area in areas:
		clipped.append_array(Geometry2D.intersect_polygons(area,boundary))
	return clipped

static func _raw_polygons(profile: Dictionary) -> Array:
	var center: Vector2 = profile.target
	var radius: Vector2 = profile.radius
	var width: float = profile.get("width", 32.0)
	match profile.kind:
		"cone":
			var cone := PackedVector2Array([center])
			var heading: Vector2 = profile.get("direction", Vector2.LEFT)
			var angle: float = profile.get("angle", 1.15)
			for i in range(33):
				var ray := heading.rotated(-angle + i * angle * 2 / 32)
				cone.append(center + ray * radius)
			return [cone]
		"capsule":
			var origin: Vector2 = profile.origin
			var axis := (center-origin).normalized()
			if axis.is_zero_approx():
				return polygons({"kind":"circle", "target":center, "radius":Vector2(width,width)})
			var capsule := PackedVector2Array()
			for i in range(17):
				capsule.append(center + axis.rotated(-PI/2 + i*PI/16) * width)
			for i in range(17):
				capsule.append(origin + axis.rotated(PI/2 + i*PI/16) * width)
			return [capsule]
		"line":
			var across: Vector2 = (center - Vector2(profile.origin)).normalized().orthogonal() * width
			if across.is_zero_approx():
				return [PackedVector2Array([center+Vector2(-width,-width),center+Vector2(width,-width),center+Vector2(width,width),center+Vector2(-width,width)])]
			return [PackedVector2Array([Vector2(profile.origin) + across, center + across, center - across, Vector2(profile.origin) - across])]
		"cross":
			return [PackedVector2Array([center+Vector2(-radius.x,-width),center+Vector2(radius.x,-width),center+Vector2(radius.x,width),center+Vector2(-radius.x,width)]), PackedVector2Array([center+Vector2(-width,-radius.y),center+Vector2(width,-radius.y),center+Vector2(width,radius.y),center+Vector2(-width,radius.y)])]
		"ring":
			var pieces: Array = []
			for i in range(48):
				var a := Vector2(cos(i * TAU / 48), sin(i * TAU / 48)) * radius
				var b := Vector2(cos((i+1) * TAU / 48), sin((i+1) * TAU / 48)) * radius
				pieces.append(PackedVector2Array([center+a,center+b,center+b*0.48,center+a*0.48]))
			return pieces
	var polygon := PackedVector2Array()
	for i in range(48):
		polygon.append(center + Vector2(cos(i * TAU / 48), sin(i * TAU / 48)) * radius)
	return [polygon]
