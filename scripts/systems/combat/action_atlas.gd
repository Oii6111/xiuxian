extends RefCounted
## Fixed-size cells and explicit pivots preserve limb motion without per-pose rescaling.
const Assets = preload("res://scripts/pixel_assets.gd")
const PATH = "res://data/combat/action_atlases.json"
static var _manifest: Dictionary = {}
static var _banks: Dictionary = {}
static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _manifest = parsed
	return _manifest
static func bank(id: String) -> Dictionary:
	if _banks.has(id): return _banks[id]
	var data: Dictionary = manifest().get("assets",{}).get(id,{})
	if data.is_empty(): return {}
	var texture: Texture2D = Assets.texture(data.path)
	if texture==null: return {}
	var frames: Array[Texture2D] = []
	for i in range(16):
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2((i%4)*int(data.cell),(i/4)*int(data.cell),data.cell,data.cell)
		frame.filter_clip = true
		frames.append(frame)
	var result := {"frames":frames,"cell":int(data.cell),"pivots":data.pivots,"reference_height":float(data.reference_height),"id":id}
	_banks[id] = result
	return result
static func apply(sprite: Sprite2D, data: Dictionary, frame: int, height: float) -> void:
	var index := clampi(frame,0,15)
	sprite.texture = data.frames[index]
	var pivot := Vector2(data.pivots[index][0],data.pivots[index][1])
	sprite.offset = Vector2.ONE*float(data.cell)*.5-pivot
	sprite.scale = Vector2.ONE*height/float(data.reference_height)
static func boss_frame(rules: RefCounted, clock: float, hurt: float = 0) -> int:
	if rules.finished and rules.won: return 15
	var brain: RefCounted = rules.brain
	if brain==null: return 0
	var t: float = brain.progress()
	var melee: bool = str(brain.move.get("kind","")) in ["slash","charge","leap"]
	var start := 4 if melee else 8
	match brain.phase:
		"waiting", "link":
			if hurt>.05: return 12 if hurt>.12 else 13
			return int(clock*8)%4 if brain.velocity.length()>3 else 0
		"windup": return start if t<.5 else start+1
		"attack":
			if brain.move.kind=="charge": return int(clock*15)%4
			if brain.move.kind=="leap": return 5 if t<.72 else 6
			if brain.move.kind=="volley": return 10 if fmod(brain.phase_clock,.34)<.22 else 9
			return start+2
		"breath":
			if hurt>.05: return 12 if hurt>.12 else 13
			return start+3 if t<.7 else 0
		"stagger": return 14
	return 0
static func effect_frame(style: String, progress: float) -> Dictionary:
	var id := "vfx_elements"
	var row := 0
	match style:
		"thunder": row=1
		"fire","ember","crystal": row=2
		"water","wind","sound": row=3
		"wood","leaf","roots": id="vfx_nature"; row=0
		"stone","sand","grain": id="vfx_nature"; row=1
		"moon","ink": id="vfx_nature"; row=2
		"seal","metal": id="vfx_nature"; row=3
	var data := bank(id)
	if data.is_empty(): return {}
	var index := row*4+clampi(int(progress*4),0,3)
	return {"texture":data.frames[index],"pivot":Vector2(data.pivots[index][0],data.pivots[index][1])/float(data.cell)}
static func effect(style: String, progress: float) -> Texture2D:
	return effect_frame(style,progress).get("texture")
