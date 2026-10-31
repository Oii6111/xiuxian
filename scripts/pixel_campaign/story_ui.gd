extends CanvasLayer
## Shared parchment UI. Modal windows suspend only campaign movement.
const Catalogue = preload("res://scripts/pixel_campaign/catalogue.gd")
const Art = preload("res://scripts/pixel_campaign/pixel_art.gd")
const REGIONS = ["序章", "木", "火", "土", "金", "水", "旁篇", "共域", "终章"]
const INK = Color("493b30")
const MUTED = Color("7c6c54")
const GOLD = Color("c5a56d")
var world
var root: Control
var hud: Control
var actor_controls: Control
var modal: Control
var modal_open: bool = false
var status_label: Label
var region_label: Label
var quest_label: Label
var hint_label: Label
var restoration_label: Label
var _toast: Control

func _ready() -> void:
	layer = 31
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font = SystemFont.new()
	# 网页没有系统中文字体，回退到随包的 Noto Sans SC（OFL）。
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC-Regular.otf")]
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color("2e493d"))
	theme.set_color("font_disabled_color", "Button", Color("9c9380"))
	theme.set_stylebox("normal", "Button", _style(Color("e8dbba"), Color("a99772")))
	theme.set_stylebox("hover", "Button", _style(Color("f7ebc7"), Color("b69859")))
	theme.set_stylebox("pressed", "Button", _style(Color("c6b68f"), Color("85734f")))
	theme.set_stylebox("disabled", "Button", _style(Color("d1c7ae"), Color("aaa08b")))
	root.theme = theme
	add_child(root)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	actor_controls = Control.new()
	actor_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actor_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(actor_controls)
	_build_hud()

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _panel(parent: Node, color: Color = Color("e9dec1")) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, GOLD))
	parent.add_child(panel)
	return panel

func _label(text: String, size: int = 18, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable, minimum: Vector2 = Vector2(110, 39)) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	return button

func _portrait(texture: Texture2D, size: Vector2) -> TextureRect:
	var picture = TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = size
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture

func _build_hud() -> void:
	var top = _panel(hud, Color("3e3c32"))
	top.position = Vector2(24, 18)
	top.size = Vector2(1392, 86)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	top.add_child(row)
	var description = VBoxContainer.new()
	description.custom_minimum_size = Vector2(680, 65)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	region_label = _label("五域归衡", 25, Color("f4e8c7"))
	description.add_child(region_label)
	status_label = _label("", 16, Color("d6c49f"))
	description.add_child(status_label)
	row.add_child(_button("五域图 M", world.open_map))
	row.add_child(_button("祟兽图鉴", world.open_atlas.bind("")))
	row.add_child(_button("人物志", show_people))
	row.add_child(_button("洞府", show_home, Vector2(88, 39)))
	row.add_child(_button("归仙村", show_exit))
	var quest = _panel(hud, Color(0.91, 0.86, 0.73, 0.94))
	quest.position = Vector2(24, 122)
	quest.size = Vector2(580, 74)
	quest_label = _label("", 17)
	quest.add_child(quest_label)
	restoration_label = _label("", 20, Color("fff1c9"))
	restoration_label.position = Vector2(865, 133)
	restoration_label.size = Vector2(530, 62)
	restoration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	restoration_label.add_theme_color_override("font_outline_color", Color("344b3b"))
	restoration_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(restoration_label)
	var bottom = _panel(hud, Color(0.24, 0.23, 0.19, 0.95))
	bottom.position = Vector2(24, 826)
	bottom.size = Vector2(1392, 52)
	hint_label = _label("WASD 移动 · E 交谈 · M 五域图 · Tab 图鉴", 18, Color("f0e2bd"))
	bottom.add_child(hint_label)

func refresh_hud() -> void:
	if status_label == null:
		return
	var data = world.state.data
	region_label.text = "五域归衡  /  " + world.stage_name
	status_label.text = "%s · %s    修为 %d    营造材 %d    归衡印 %d / 5    祟兽 %d / 20" % [data.name, world.state.realm(), data.xp, data.materials, data.seals.size(), data.clears.size()]
	quest_label.text = "当前线索  ·  " + world.state.next_goal()
	if world.current_region == "序章" and "b00" not in data.clears:
		quest_label.text = "初来照生乡  ·  向雷叔问路，再靠近右侧听雷。\n按 E 交谈，或点击人物与祟门下方的签牌。"
	restoration_label.text = ""
	for core in Catalogue.cores():
		if core in data.clears and Catalogue.entry(core).region == world.current_region:
			restoration_label.text = "此域已归衡  ·  两只散祟已安居\n故人有了新的话，去听一听。"

func set_hint(text: String) -> void:
	if hint_label != null:
		hint_label.text = text

func actor_button(text: String, position: Vector2, size: Vector2, callback: Callable) -> void:
	var button = _button(text, callback, size)
	button.position = position
	button.size = size
	button.add_theme_font_size_override("font_size", 16)
	button.modulate.a = 0.96
	actor_controls.add_child(button)

func clear_actor_buttons() -> void:
	for child in actor_controls.get_children():
		actor_controls.remove_child(child)
		child.queue_free()

func close_modal() -> void:
	modal_open = false
	if is_instance_valid(modal):
		root.remove_child(modal)
		modal.queue_free()
	modal = null

func _window(title: String, subtitle: String = "") -> VBoxContainer:
	close_modal()
	modal_open = true
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(modal)
	var shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.08, 0.1, 0.09, 0.72)
	modal.add_child(shade)
	var panel = _panel(modal)
	panel.position = Vector2(86, 82)
	panel.size = Vector2(1268, 730)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header = HBoxContainer.new()
	column.add_child(header)
	var heading = _label(title, 27)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(_button("返回区域 · Esc", close_modal, Vector2(160, 38)))
	if subtitle != "":
		column.add_child(_label(subtitle, 16, MUTED))
	var separator = HSeparator.new()
	column.add_child(separator)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	return content

func _scroll(parent: Node) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	return column

func show_map() -> void:
	var content = _window("五域舆图", "一乡起灯，五域归衡。可以先看风景、听故事；祟门按线索次序开放。")
	var box = _scroll(content)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for region in REGIONS:
		var rows = Catalogue.all().filter(func(row): return row.region == region)
		var count = rows.filter(func(row): return row.id in world.state.data.clears).size()
		var button = _button("", world.change_region.bind(region), Vector2(395, 145))
		var status = "%d / %d 祟兽已归衡" % [count, rows.size()]
		if region == "终章":
			status = "五枚归衡印开启终局  ·  %d / 5" % world.state.data.seals.size()
		elif region == "共域" and world.state.data.seals.is_empty():
			status = "任意一域归衡后，晦鳞显现"
		elif count == rows.size():
			status += "  ·  故人新语"
		button.text = Catalogue.region_name(region) + " · " + (region + "域" if region in ["木", "火", "土", "金", "水"] else region) + ("  ◆" if region == world.current_region else "") + "\n\n" + status
		grid.add_child(button)
	box.add_child(_label("五域的散祟原本是守土小灵。破除主祟后，它们会回到地图，人物志也会留下新的归处。", 18))

func show_atlas(region: String = "") -> void:
	var content = _window("山海祟录  ·  二十祟", "祟兽有来历，也有归处。察看可阅读前情、招式预兆与破解目标。")
	var filters = HBoxContainer.new()
	filters.add_theme_constant_override("separation", 5)
	content.add_child(filters)
	filters.add_child(_button("全部", show_atlas.bind(""), Vector2(88, 34)))
	for value in REGIONS:
		filters.add_child(_button(value, show_atlas.bind(value), Vector2(113, 34)))
	var box = _scroll(content)
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for row in Catalogue.all():
		if region != "" and row.region != region:
			continue
		var panel = _panel(grid, Color("ddd3b5"))
		panel.custom_minimum_size = Vector2(294, 190)
		var card = VBoxContainer.new()
		card.add_theme_constant_override("separation", 5)
		panel.add_child(card)
		card.add_child(_portrait(Art.boss_texture(str(row.id)), Vector2(265, 105)))
		var status = "已归衡" if row.id in world.state.data.clears else ("线索已至" if world.state.availability(str(row.id)) == "" else "待解封")
		card.add_child(_button(str(row.name) + " · " + status, world.open_boss.bind(str(row.id)), Vector2(265, 36)))
		card.add_child(_label(Catalogue.region_name(str(row.region)) + "  /  " + str(row.role), 15, MUTED))

func show_boss(id: String) -> void:
	var row = Catalogue.entry(id)
	if row.is_empty():
		return
	var content = _window(str(row.name) + "  ·  " + str(row.role), Catalogue.region_name(str(row.region)) + "  /  " + str(row.arena))
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 26)
	content.add_child(columns)
	var picture_column = VBoxContainer.new()
	picture_column.custom_minimum_size = Vector2(270, 350)
	columns.add_child(picture_column)
	picture_column.add_child(_portrait(Art.boss_texture(id), Vector2(270, 310)))
	var forms = {"cloud":"雷云灵禽", "deer":"苍木灵鹿", "hinge":"机关角兽", "cicada":"离火鸣蝉", "serpent":"窄焰螭蛇", "boar":"丹棘山彘", "pangolin":"积璧穿山", "moth":"薄翅灯蛾", "ox":"稷土玄牛", "rhino":"闭岚石犀", "heron":"灼羽长鹭", "crane":"缄风仙鹤", "clam":"沉砂灵蜃", "kui":"滞潮独夔", "tortoise":"玄泽负龟", "moon":"漏夜月灵", "fish":"失简游鱼", "dragon":"晦鳞长螭", "astrolabe":"执衡星仪"}
	picture_column.add_child(_label("形象志  ·  " + str(forms.get(row.get("creature", ""), "山海散祟")), 16, MUTED))
	var text_column = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(text_column)
	var lore = _scroll(text_column)
	lore.add_child(_label("前情", 21))
	lore.add_child(_label(str(row.backstory), 19))
	lore.add_child(_label("归衡之法  ·  " + str(row.objective_title), 21))
	lore.add_child(_label(str(row.objective_hint), 18))
	lore.add_child(_label("观察预兆  ·  " + str(row.attack_name), 20))
	lore.add_child(_label(str(row.tell), 18))
	lore.add_child(_label("归衡之后", 20))
	lore.add_child(_label(str(row.world_change), 18, Color("526849")))
	var first = id not in world.state.data.clears
	var xp = (80 if id == "b00" else 120) if first else 0
	var materials = (6 if id in Catalogue.cores() else 3) if first else 0
	content.add_child(_label("首通奖励  ·  修为 %d  /  营造材 %d%s" % [xp, materials, "  /  一枚归衡印" if first and id in Catalogue.cores() else ""] if first else "回响练习  ·  不重复发放主线奖励，练习不限次。", 17, MUTED))
	var settings = HBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	content.add_child(settings)
	var mode_label = _label("挑战：", 17)
	mode_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mode_label.custom_minimum_size = Vector2(65, 38)
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	settings.add_child(mode_label)
	var mode = OptionButton.new()
	mode.focus_mode = Control.FOCUS_NONE
	mode.custom_minimum_size = Vector2(240, 44)
	mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode.add_item("故事 · 宽容窗口")
	mode.add_item("标准 · 观察反击")
	mode.select(0 if world.state.data.difficulty == "story" else 1)
	mode.item_selected.connect(_set_mode)
	settings.add_child(mode)
	var skill_label = _label("携带术法：", 17)
	skill_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	skill_label.custom_minimum_size = Vector2(110, 38)
	skill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	settings.add_child(skill_label)
	var skill = OptionButton.new()
	skill.focus_mode = Control.FOCUS_NONE
	skill.custom_minimum_size = Vector2(150, 44)
	skill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var index = 0
	for value in Catalogue.skills():
		skill.add_item(value)
		if value == world.state.data.skill:
			skill.select(index)
		index += 1
	skill.item_selected.connect(_set_skill)
	settings.add_child(skill)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(spacer)
	var reason = world.state.availability(id)
	var begin = _button("进入祟门" if first else "再访回响", world.enter_boss.bind(id), Vector2(180, 44))
	begin.disabled = reason != ""
	begin.tooltip_text = reason
	settings.add_child(begin)
	if reason != "":
		content.add_child(_label("尚待线索：" + reason, 18, Color("995e48")))
	elif id == "b00":
		content.add_child(_label("移动躲开预兆，J 普攻，1 术法，K 护盾，Space 闪避；先解散祟，再归衡主祟。", 17, MUTED))

func _set_mode(index: int) -> void:
	world.state.data.difficulty = "story" if index == 0 else "standard"
	world.state.save_game()

func _set_skill(index: int) -> void:
	world.state.data.skill = Catalogue.skills().keys()[index]
	world.state.save_game()

func show_npc(id: String) -> void:
	var person = Catalogue.person(id)
	if person.is_empty():
		return
	var restored = str(person.flag) in world.state.data.clears
	var content = _window(str(person.name) + "  ·  " + Catalogue.region_name(str(person.region)), "故人的委托随区域变化；散祟安居之后，回来听听新的故事。")
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(_portrait(Art.npc_texture(id), Vector2(265, 380)))
	var column = _scroll(row)
	column.add_child(_label("归来之言" if restored else "灯下相逢", 23))
	column.add_child(_label(str(person.after if restored else person.before), 22))
	column.add_child(_label("托付", 21))
	column.add_child(_label(str(person.request), 20))
	if restored:
		column.add_child(_label("这片土地已留下你的足迹。地图中的两只散祟已安居，可以靠近交谈，或在人物志中查看归处。", 19, Color("526849")))
	var actions = HBoxContainer.new()
	content.add_child(actions)
	actions.add_child(_button("记下这份委托", _track.bind(str(person.region)), Vector2(200, 44)))
	var first = _next_region_boss(str(person.region))
	if first != "":
		actions.add_child(_button("察看下一条祟兽线索", world.open_boss.bind(first), Vector2(280, 44)))
	actions.add_child(_button("人物与散祟志", show_people, Vector2(200, 44)))

func _track(region: String) -> void:
	world.state.track(region)
	world.change_region(region)
	toast("已记下委托  ·  " + Catalogue.region_name(region))

func _next_region_boss(region: String) -> String:
	for row in Catalogue.all():
		if row.region == region and row.id not in world.state.data.clears and world.state.availability(str(row.id)) == "":
			return str(row.id)
	return ""

func show_people() -> void:
	var content = _window("灯下人物志  ·  散祟归处", "人和小灵都记得这片土地。每次收拢散祟都会记入故事，主祟归衡后，它们会回到区域。")
	var box = _scroll(content)
	box.add_child(_label("故人  ·  六位守望者", 22))
	var people_grid = GridContainer.new()
	people_grid.columns = 3
	people_grid.add_theme_constant_override("h_separation", 12)
	people_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(people_grid)
	for person in Catalogue.people():
		var button = _button("%s  /  %s\n%s" % [person.name, Catalogue.region_name(str(person.region)), "归来新语" if str(person.flag) in world.state.data.clears else "灯下委托"], show_npc.bind(str(person.id)), Vector2(395, 95))
		people_grid.add_child(button)
	box.add_child(_label("散祟  ·  十种旧日小灵", 22))
	var minion_grid = GridContainer.new()
	minion_grid.columns = 5
	minion_grid.add_theme_constant_override("h_separation", 12)
	minion_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(minion_grid)
	for mob in Catalogue.minions():
		var panel = _panel(minion_grid, Color("ddd3b5"))
		panel.custom_minimum_size = Vector2(232, 175)
		var card = VBoxContainer.new()
		panel.add_child(card)
		card.add_child(_portrait(Art.minion_texture(str(mob.id)), Vector2(200, 95)))
		var captured = mob.id in world.state.data.minion_lore
		card.add_child(_button(str(mob.name) + (" · 已结缘" if captured else " · 待相逢"), show_minion.bind(str(mob.id)), Vector2(205, 38)))

func show_minion(id: String) -> void:
	var mob = Catalogue.minion(id)
	if mob.is_empty():
		return
	var known = id in world.state.data.minion_lore
	var content = _window(str(mob.name) + "  ·  " + str(mob.kind), Catalogue.region_name(str(mob.element)) + ("  /  已结缘" if known else "  /  山海线索"))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(_portrait(Art.minion_texture(id), Vector2(270, 370)))
	var column = _scroll(row)
	column.add_child(_label("从前", 23))
	column.add_child(_label(str(mob.story), 21))
	column.add_child(_label("化解之法", 21))
	column.add_child(_label(str(mob.tell) + "\n" + str(mob.counter), 19))
	column.add_child(_label("安居之后", 21))
	column.add_child(_label(str(mob.home), 21, Color("526849")))
	if not known:
		column.add_child(_label("战斗中打散散祟会自动收拢并记入人物志；使这片区域的主祟归衡后，它们会在地图中安居。", 18, MUTED))
	content.add_child(_button("前往" + Catalogue.region_name(str(mob.element)), world.change_region.bind(str(mob.element)), Vector2(250, 44)))

func show_home() -> void:
	var content = _window("洞府营造  ·  把远行带回家", "远行带回材料，归衡解锁新的营造。建成后立即出现在区域左下的行旅营地，离开再来依然保留。")
	content.add_child(_label("现有营造材 %d  /  已营造 %d 处" % [world.state.data.materials, world.state.data.buildings.size()], 22))
	var box = _scroll(content)
	var descriptions = {"门灯":"夜归的人先看见一盏灯。照亮行旅营地，也给远行留下归处。", "药圃":"把稷野带回的种子种在小畦里。小灵可以歇脚，草木各守一方。", "听雨亭":"留下一片能停步的檐。忙过一场之后，坐下来听风穿过水面。", "观星台":"把五域的星图刻上石台。归衡的经历有了可以回望的位置。"}
	var requirements = {"门灯":"完成听雷试炼", "药圃":"获得任意一枚归衡印", "听雨亭":"获得三枚归衡印", "观星台":"完成常生台终章"}
	var specs = world.state.building_specs()
	for item in specs:
		var spec = specs[item]
		var cost = int(spec.cost)
		var reason = world.state.building_availability(item)
		var panel = _panel(box, Color("ddd3b5"))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 25)
		panel.add_child(row)
		var column = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		column.add_child(_label(item + "  ·  " + str(cost) + " 营造材\n" + str(descriptions.get(item, spec.get("description", ""))), 19))
		var built = item in world.state.data.buildings
		var condition = "已经建成，归处长留。" if built else ("营造条件：" + requirements.get(item, "") if reason == "" else "尚待线索：" + reason)
		if not built and reason == "" and int(world.state.data.materials) < cost:
			condition += "  /  还需 %d 营造材" % (cost - int(world.state.data.materials))
		column.add_child(_label(condition, 16, MUTED))
		var build_button = _button("已经建成" if built else "营造" + item + " · " + str(cost) + " 材", _build.bind(item), Vector2(225, 62))
		build_button.disabled = built or reason != "" or int(world.state.data.materials) < cost
		build_button.tooltip_text = reason
		row.add_child(build_button)
	box.add_child(_label("修为只记录这段冒险的成长。失败可以立刻重试，已经获得的营造与归衡印都会保留。", 18, MUTED))

func _build(item: String) -> void:
	if world.state.build(item):
		world.refresh_home_decor()
		show_home()
		toast(item + "已经建成。回到区域，看看左下角的营地。")

func show_result(id: String, won: bool, result: Dictionary) -> void:
	var row = Catalogue.entry(id)
	var content = _window(("祟息归衡  ·  " if won else "暂歇整装  ·  ") + str(row.name), "每一步都会留下痕迹。" if won else "没有损失修为、营造材或已收集的归衡印。")
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	columns.add_child(_portrait(Art.boss_texture(id), Vector2(270, 350)))
	var text = _scroll(columns)
	text.add_child(_label("大地回声" if won else "下一次可以这样试", 24))
	text.add_child(_label(str(row.world_change) if won else str(row.objective_hint), 22))
	text.add_child(_label(str(result.get("message", "")), 19, MUTED))
	if won and result.get("ok", false):
		text.add_child(_label("获得修为  +%d\n获得营造材  +%d" % [int(result.get("xp", 0)), int(result.get("materials", 0))], 25, Color("526849")))
		if id in Catalogue.cores():
			text.add_child(_label("%s归衡印已归位  ·  五印 %d / 5\n故人有了新对白，两只散祟已经在区域安居。" % [str(row.region), world.state.data.seals.size()], 21, Color("526849")))
		if result.get("new_best", false):
			text.add_child(_label("留下新的回响纪录  ·  %.1f 秒" % float(result.get("seconds", 0)), 19))
	elif not won:
		text.add_child(_label("先观察地面的预兆，再用护盾或闪避留出安全位置。术法可以在进入祟门前重新选择。", 20))
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	actions.add_child(_button("回到区域看变化" if won else "回区域调整", close_modal, Vector2(240, 48)))
	actions.add_child(_button("回响练习" if won else "立即再试 · 免费", world.enter_boss.bind(id), Vector2(240, 48)))
	if won:
		actions.add_child(_button("下一条线索" if world.next_boss(id) != "" else "前往其他区域", world.follow_next.bind(id), Vector2(240, 48)))
		actions.add_child(_button("回洞府营造", show_home, Vector2(200, 48)))

func show_exit() -> void:
	var content = _window("灯火在归处", "冒险进度已经保存，随时可以从仙村重新出发。")
	content.add_child(_label("这段远行走过 %d / 20 位祟兽，带回 %d / 5 枚归衡印。\n\n地图、图鉴与人物志都可以慢慢看。下一步由你决定。" % [world.state.data.clears.size(), world.state.data.seals.size()], 25))
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	content.add_child(_button("继续探索", close_modal, Vector2(300, 52)))
	content.add_child(_button("返回像素仙村", world.request_exit, Vector2(300, 52)))

func toast(message: String) -> void:
	if is_instance_valid(_toast):
		_toast.queue_free()
	var panel = _panel(root, Color("3e493d"))
	panel.position = Vector2(365, 742)
	panel.size = Vector2(710, 65)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text = _label(message, 18, Color("f5e9c6"))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(text)
	_toast = panel
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(panel):
			panel.queue_free()
	)



