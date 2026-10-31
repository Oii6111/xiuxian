extends RefCounted
## Stable IDs are shared by saves, the selector and the future chat service.
const IDS = ["cloud_fox", "gourd_dragon", "lotus_bird", "herb_deer"]
const PETS = {
	"cloud_fox": {"name": "云团小狐", "nickname": "云绒", "trait": "温柔细腻 · 云尾轻摇", "intro": "别着急，我陪你把今天的小事一件件做好。", "color": "a3bcb0"},
	"gourd_dragon": {"name": "葫芦小龙", "nickname": "团团", "trait": "活泼热情 · 葫芦相伴", "intro": "今天也一起修行吧！想知道下一步，尽管问我。", "color": "9abd9b"},
	"lotus_bird": {"name": "莲叶团雀", "nickname": "啾啾", "trait": "俏皮轻快 · 莲叶摇摇", "intro": "啾！家人的近况和今天的安排，我帮你一起看看。", "color": "d8c47c"},
	"herb_deer": {"name": "药草小鹿", "nickname": "芽芽", "trait": "沉稳贴心 · 草木守护", "intro": "一步一步来，每一份坚持都值得被记住。", "color": "c9a37d"}
}
static var textures: Dictionary = {}

static func valid(id: String) -> bool:
	return id in IDS

static func clean(value: Variant) -> Dictionary:
	if not value is Dictionary or not valid(str(value.get("id", ""))):
		return {"id": "", "nickname": ""}
	var id = str(value.id)
	var nickname = str(value.get("nickname", "")).strip_edges().replace("\n", " ").replace("\r", " ").left(10)
	return {"id": id, "nickname": PETS[id].nickname if nickname.is_empty() else nickname}

static func nickname(value: Dictionary) -> String:
	var pet = clean(value)
	return str(pet.nickname) if valid(pet.id) else "灵宠"

static func texture(id: String) -> Texture2D:
	if not valid(id):
		return null
	if not textures.has(id):
		var atlas = load("res://assets/companions/" + id + ".png") as Texture2D
		if atlas == null:
			return null
		var region = AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(atlas.get_image().get_used_rect())
		region.filter_clip = true
		textures[id] = region
	return textures[id]
