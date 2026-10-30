extends "res://scripts/gameplay_interface.gd"
## Bridge the existing village to the independent pixel Five Realms campaign.
const Saga = preload("res://scripts/pixel_campaign/state.gd")
const World = preload("res://scripts/pixel_campaign/world.gd")
const Art = preload("res://scripts/pixel_campaign/pixel_art.gd")
var saga = Saga.new()
var campaign: Node2D
var campaign_hidden: Array[Control] = []
var restored_visitors: Node2D
var campaign_button: Button
var campaign_hint: Label

func _ready() -> void:
	super._ready()
	if "--preview" in OS.get_cmdline_user_args():
		saga.persist_enabled = false
	else:
		saga.load_game()
	campaign_button = button(self, "五域山海 · 像素冒险", open_campaign, true)
	campaign_button.position = Vector2(16, 385)
	campaign_button.size = Vector2(216, 54)
	campaign_button.focus_mode = Control.FOCUS_NONE
	campaign_hint = label_into(self, "20 祟兽 · 五域地图 · 故事归衡", 13, Color("f5dda8"))
	campaign_hint.position = Vector2(20, 443)
	campaign_hint.add_theme_color_override("font_shadow_color", Color("30251f"))
	campaign_hint.add_theme_constant_override("shadow_outline_size", 3)
	_refresh_restoration.call_deferred()

func close_modal() -> void:
	if is_instance_valid(campaign):
		return
	super.close_modal()

func open_campaign(region: String = "序章") -> void:
	if is_instance_valid(start_screen) or is_instance_valid(campaign):
		return
	close_modal()
	saga.adopt_profile(game.state.player_name, game.state.avatar_id)
	campaign_hidden.clear()
	for child in get_children():
		if child is Control and child.visible and not child.is_queued_for_deletion():
			campaign_hidden.append(child)
			child.hide()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	campaign = World.new()
	campaign.state = saga
	campaign.origin_village = game
	campaign.initial_region = region
	campaign.exit_to_village.connect(_return_from_campaign)
	game.add_child(campaign)

func _return_from_campaign() -> void:
	if is_instance_valid(campaign):
		campaign.queue_free()
	campaign = null
	for item in campaign_hidden:
		if is_instance_valid(item):
			item.show()
	campaign_hidden.clear()
	modal_open = false
	game.player.blocked = false
	_refresh_restoration()
	refresh()
	toast("归乡了。" + saga.next_goal())

func open_boss() -> void:
	open_campaign("序章" if "b00" not in saga.data.clears else "木")

func _refresh_restoration() -> void:
	if is_instance_valid(restored_visitors):
		restored_visitors.queue_free()
	restored_visitors = Node2D.new()
	restored_visitors.name = "RestoredFiveRealmVisitors"
	restored_visitors.z_index = 6
	game.add_child(restored_visitors)
	var visitor_ids = {"木":"m01", "火":"m03", "土":"m06", "金":"m08", "水":"m10"}
	for i in range(saga.data.seals.size()):
		var region = str(saga.data.seals[i])
		var texture = Art.minion_texture(visitor_ids.get(region, "m01"))
		if texture == null:
			continue
		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.position = Vector2(553 + i * 49, 594 + (i % 2) * 13)
		sprite.offset.y = -texture.get_height() * 0.5
		sprite.scale = Vector2.ONE * 45.0 / texture.get_height()
		restored_visitors.add_child(sprite)
		var tag = Label.new()
		tag.text = region + "域来客"
		tag.position = sprite.position + Vector2(-25, 4)
		tag.add_theme_font_override("font", game.font)
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color("fff0b9"))
		tag.add_theme_color_override("font_outline_color", Color("32271e"))
		tag.add_theme_constant_override("outline_size", 4)
		restored_visitors.add_child(tag)
	if is_instance_valid(campaign_hint):
		campaign_hint.text = "20 祟兽 · 五印 %d/5 · 像素故事" % saga.data.seals.size()
