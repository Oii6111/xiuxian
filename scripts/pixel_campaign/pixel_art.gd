extends RefCounted
## Sprite sheet sampling only: generated source PNGs stay intact.
const Legacy = preload("res://scripts/pixel_assets.gd")
const DIR = "res://assets/pixel_campaign/"
static var cache: Dictionary = {}
static var sheets: Dictionary = {}
static func _texture(path: String) -> Texture2D:
	if not cache.has(path):
		var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if texture == null and FileAccess.file_exists(path):
			var raw = Image.load_from_file(path)
			if raw != null and not raw.is_empty():
				texture = ImageTexture.create_from_image(raw)
		cache[path] = texture
	return cache[path]
static func _cell(file: String,index: int,columns: int,rows: int) -> Texture2D:
	var key=file+":"+str(index)
	if sheets.has(key):return sheets[key]
	var atlas=_texture(DIR+file)
	if atlas==null:return null
	var image=atlas.get_image()
	var size=Vector2i(image.get_width()/columns,image.get_height()/rows)
	var start=Vector2i((index%columns)*size.x,(index/columns)*size.y)
	var used=image.get_region(Rect2i(start,size)).get_used_rect()
	if used.size.x<=0 or used.size.y<=0:return null
	var item=AtlasTexture.new()
	item.atlas=atlas
	item.region=Rect2(start+used.position,used.size)
	item.filter_clip=true
	sheets[key]=item
	return item
static func boss_texture(id: String) -> Texture2D:
	var number=int(id.trim_prefix("b"))
	if number<0 or number>19:return null
	var group=["a","b","c","d","e"][number/4]
	var image=_cell("boss_sheet_"+group+".png",number%4,2,2)
	if image!=null:return image
	return Legacy.frames("res://assets/gameplay/dragon-states.png",2,2)[0]
static func minion_texture(id: String) -> Texture2D:
	var n=int(id.trim_prefix("m"))-1
	return _cell("minion_sheet.png",clampi(n,0,9),5,2)
static func npc_texture(id: String) -> Texture2D:
	var n=["lei","tinglan","hesheng","suniang","taobo","ahe"].find(id)
	var image=_cell("npc_sheet.png",maxi(0,n),3,2)
	if image!=null:return image
	var old=Legacy.frames("res://assets/pixel/village-npcs.png",3,1)
	return old[maxi(0,n)%3]
static func hero_frames(avatar: String) -> Array[Texture2D]:
	return Legacy.frames("res://assets/gameplay/female-walk.png" if avatar=="female" else "res://assets/pixel/cultivator-walk.png",4,4)
static func background(region: String) -> Texture2D:
	var id={"木":"wood","火":"fire","土":"earth","金":"metal","水":"water","序章":"origin","旁篇":"origin","共域":"final","终章":"final"}.get(region,"origin")
	var texture=_texture(DIR+"map_"+str(id)+".png")
	if texture!=null:return texture
	return Legacy.texture("res://assets/gameplay/boss-stage.png")

