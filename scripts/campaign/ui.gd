extends CanvasLayer
const Catalogue = preload("res://scripts/campaign/catalogue.gd")
var game: Node3D
var hud: Control
var panel: Control
var title_label: Label
var status_label: Label
var hint_label: Label
var objective_label: Label
var toast_label: Label
var hp_bar: ProgressBar
var boss_bar: ProgressBar
var fight_hud: Control
var toast_time: float = 0.0
var modal_open: bool = false
var selected: String = "b00"
var action_buttons: Array = []
const INK = Color("20394c")
const GOLD = Color("f4c668")
const PAPER = Color("eef8fa")
const DARK = Color("183647")

func _ready() -> void:
	hud = Control.new()
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar = card(hud,Rect2(22,18,1396,76),DARK)
	var row = HBoxContainer.new()
	bar.add_child(row)
	title_label = label(row,"照生五域",30,Color("fff1bc"))
	title_label.custom_minimum_size.x = 210
	status_label = label(row,"",18,Color("d4f4ff"))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(row,"山海图鉴",func(): open_atlas())
	button(row,"散祟志",open_minions)
	button(row,"家族洞府",open_home)
	hint_label = label(hud,"",19,Color("e9fcff"))
	hint_label.position = Vector2(26,820)
	hint_label.size = Vector2(1380,35)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_outline_color",Color("183647"))
	hint_label.add_theme_constant_override("outline_size",7)
	toast_label = label(hud,"",19,Color("fff1bd"))
	toast_label.position = Vector2(340,106)
	toast_label.size = Vector2(760,45)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.hide()
	_build_fight_hud()
	refresh()

func frame(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.border_color = Color("8ccec9")
	style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.04,0.12,0.17,0.22)
	style.shadow_size = 7
	return style

func card(parent: Node, rect: Rect2, color: Color = PAPER) -> VBoxContainer:
	var box = PanelContainer.new()
	box.position = rect.position
	box.size = rect.size
	box.custom_minimum_size = rect.size
	box.add_theme_stylebox_override("panel",frame(color))
	parent.add_child(box)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation",10)
	box.add_child(content)
	return content

func label(parent: Node,text: String,size: int = 18,color: Color = INK) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_override("font",game.font)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	parent.add_child(node)
	return node

func paragraph(parent: Node,text: String,size: int = 18) -> Label:
	var node = label(parent,text,size)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func button(parent: Node,text: String,action: Callable,primary: bool = false) -> Button:
	var node = Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(120,44)
	node.add_theme_font_override("font",game.font)
	node.add_theme_font_size_override("font_size",17)
	node.add_theme_stylebox_override("normal",frame(Color("287f95") if primary else Color("dceef0")))
	node.add_theme_stylebox_override("hover",frame(Color("399cb2") if primary else Color("f7e8b7")))
	node.add_theme_stylebox_override("pressed",frame(Color("28657b")))
	node.add_theme_stylebox_override("disabled",frame(Color("d6dfe1")))
	node.add_theme_color_override("font_color",Color.WHITE if primary else INK)
	node.add_theme_color_override("font_hover_color",Color.WHITE if primary else INK)
	node.add_theme_color_override("font_pressed_color",Color.WHITE)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _build_fight_hud() -> void:
	fight_hud = Control.new()
	hud.add_child(fight_hud)
	fight_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fight_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top = card(fight_hud,Rect2(380,115,680,80),DARK)
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	_style_bar(boss_bar,Color("e4ac64"))
	boss_bar.custom_minimum_size.y = 24
	top.add_child(boss_bar)
	objective_label = label(top,"",16,Color("f9efcb"))
	var lower = card(fight_hud,Rect2(30,672,345,124),DARK)
	label(lower,"借影：青松真人 · 模拟状态",16,Color("c4e9ed"))
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 18
	_style_bar(hp_bar,Color("6ed3b1"))
	lower.add_child(hp_bar)
	var controls = HBoxContainer.new()
	controls.position = Vector2(405,727)
	controls.add_theme_constant_override("separation",10)
	fight_hud.add_child(controls)
	for i in range(5):
		var action = i
		var b = button(controls,["攻击 J","功法 1","护盾 K","闪避 空格","阵眼 E"][i],func(): game.combat_action(action),i==1)
		b.custom_minimum_size = Vector2(158,58)
		action_buttons.append(b)
	fight_hud.hide()

func refresh() -> void:
	if not is_instance_valid(status_label):
		return
	var state = game.state
	status_label.text = "%s · %s    修为 %d    材料 %d    五印 %d/5" % [state.data.name,state.realm(),state.data.xp,state.data.materials,state.data.seals.size()]
	title_label.text = "照生五域" if game.rules == null else game.rules.entry.name + " · 幻境"
	fight_hud.visible = game.rules != null
	if game.rules != null:
		var r = game.rules
		hp_bar.max_value = r.hp_max
		hp_bar.value = r.hp
		hp_bar.tooltip_text = "游戏护元 %d/%d" % [int(r.hp),int(r.hp_max)]
		boss_bar.max_value = r.boss_max
		boss_bar.value = r.boss_hp
		objective_label.text = r.objective_text()
		hint_label.text = r.hint
		var cds = [r.attack_cd,r.skill_cd,r.guard_cd,r.dash_cd,0.0]
		var names = ["攻击 J","功法 1","护盾 K","闪避 空格","阵眼 E"]
		for i in range(action_buttons.size()):
			action_buttons[i].disabled = r.finished or modal_open or cds[i] > 0.0
			action_buttons[i].text = names[i] + (" %.1fs" % cds[i] if cds[i]>0 else "")
		# Resource feedback stays close to the player's health display.
		lower_resource_text(r)

func lower_resource_text(r: RefCounted) -> void:
	var name = "ResourceReadout"
	var found = fight_hud.find_child(name,true,false)
	if found == null:
		found = label(fight_hud,"",15,Color("dcf4ff"))
		found.name = name
		found.position = Vector2(53,771)
	found.text = "护元 %d   真气 %d   体力 %d" % [int(r.hp),int(r.energy),int(r.stamina)]

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.show()
	toast_time = 3.0

func _process(delta: float) -> void:
	toast_time -= delta
	if toast_time <= 0 and is_instance_valid(toast_label):
		toast_label.hide()

func close_panel() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null
	modal_open = false
	if game.rules != null:
		game.rules.paused = false
	refresh()

func dialog(title: String, on_close: Callable = Callable()) -> VBoxContainer:
	close_panel()
	modal_open = true
	if game.rules != null:
		game.rules.paused = true
	panel = ColorRect.new()
	panel.color = Color(0.035,0.10,0.16,0.68)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content = card(panel,Rect2(130,115,1180,665))
	var heading = HBoxContainer.new()
	content.add_child(heading)
	var name_label = label(heading,title,28)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading,"返回 ×",on_close if on_close.is_valid() else close_panel)
	return content

func open_start() -> void:
	var content = dialog("家族修真录 · 照生五域")
	paragraph(content,"长夜未尽，灯火尚在。\n化身守灯者，与家族命影一同走过五域，找回万物各自的节奏。",26)
	paragraph(content,"全新 Q 版立体卡通 · 斜俯视探索 · 20 个可挑战篇章",18)
	var input = LineEdit.new()
	input.text = game.state.data.name
	input.max_length = 12
	input.placeholder_text = "守灯者昵称"
	content.add_child(input)
	var choices = HBoxContainer.new()
	content.add_child(choices)
	button(choices,"云行 · 青蓝衣",func(): game.change_avatar("male"))
	button(choices,"清岚 · 紫霞衣",func(): game.change_avatar("female"))
	paragraph(content,"WASD / 方向键移动，Shift 加速，E 交互。战斗 J 攻击、1 功法、K 护盾、空格闪避。",19)
	button(content,"接过照生灯 · 开始",func():
		if input.text.strip_edges() != "":
			game.state.data.name = input.text.strip_edges()
		game.state.save_game()
		close_panel()
		open_atlas("序章")
	,true)
	paragraph(content,"本版健康系数仅为明确标注的模拟演示；游戏胜负不改变真实疾病或康复记录。",15)

func open_atlas(region: String = "") -> void:
	if game.rules != null:
		show_toast("先结束本次挑战，或按 Esc 返回故乡。")
		return
	var content = dialog("山海图鉴 · 自选你的下一段旅程")
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation",24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300,420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",10)
	body.add_child(details)
	for row in Catalogue.all():
		if region != "" and row.region != region:
			continue
		var id: String = row.id
		var mark = "✓ " if id in game.state.data.clears else ""
		button(list,mark + row.name + " · " + Catalogue.region_name(row.region),func(): _show_details(details,id))
	selected = "b00" if region=="序章" else selected
	if region != "":
		for item in Catalogue.all():
			if item.region == region:
				selected = item.id
				break
	_show_details(details,selected)

func _show_details(parent: VBoxContainer,id: String) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	selected = id
	var row = Catalogue.entry(id)
	label(parent,row.name + "  ·  " + row.role,30)
	label(parent,row.arena,18)
	var record_key = id+"|"+str(game.state.data.difficulty)+"|"+str(game.state.data.simulated_health)+"|"+str(game.state.data.skill)
	if game.state.data.best_records.has(record_key):
		label(parent,"当前配置个人最佳：%.1f秒" % float(game.state.data.best_records[record_key].seconds),16)
	var scroller = ScrollContainer.new()
	scroller.custom_minimum_size.y = 245
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroller)
	var text = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(text)
	paragraph(text,row.backstory,18)
	paragraph(text,"破阵要诀：" + row.objective_hint,18)
	paragraph(text,"战后：" + row.world_change,17)
	paragraph(text,"固定首通：修为 +120、材料 +3（主祟 +6）及永久剧情记录；练习不限次。",15)
	var reason = game.state.availability(id)
	var begin = button(parent,"照亮线索并进入幻境" if id not in game.state.data.clears else "再次挑战 · 不消耗资源",func():
		game.state.investigate(id)
		game.start_encounter(id)
	,true)
	begin.disabled = reason != ""
	if reason != "":
		paragraph(parent,reason,16)
	button(parent,"查看创作主题与来源",func(): open_theme(id))
	var choices = HBoxContainer.new()
	parent.add_child(choices)
	var mode = OptionButton.new()
	mode.add_item("故事 · 更宽裕的预兆")
	mode.add_item("标准 · 更紧凑的应对")
	mode.selected = 0 if game.state.data.difficulty=="story" else 1
	mode.item_selected.connect(func(index):
		game.state.data.difficulty = "story" if index==0 else "standard"
		game.state.save_game())
	choices.add_child(mode)
	var skill = OptionButton.new()
	for name in Catalogue.skills():
		skill.add_item(name)
	skill.selected = ["雷诀","镇心","分流"].find(game.state.data.skill)
	skill.item_selected.connect(func(index):
		game.state.data.skill = ["雷诀","镇心","分流"][index]
		game.state.save_game())
	choices.add_child(skill)

func open_theme(id: String) -> void:
	var row = Catalogue.entry(id)
	var content = dialog(row.name + " · 创作说明")
	paragraph(content,"主题：" + str(row.disease_theme if row.disease_theme != null else "纯虚构幻境"),23)
	paragraph(content,row.clinical_inspiration,20)
	paragraph(content,"五行与招式是原创幻想机制，不是医学判断或治疗方法。公共篇章不会推断你或家人患有该病。",18)
	if row.source_id != null:
		var raw = JSON.parse_string(FileAccess.get_file_as_string(Catalogue.PATH))
		var source = raw.sources[row.source_id]
		button(content,"打开官方参考资料",func(): OS.shell_open(source.url))
	button(content,"返回山海图鉴",func(): open_atlas())

func open_home() -> void:
	if game.rules != null:
		show_toast("先回到故乡再布置洞府。")
		return
	var content = dialog("家族洞府 · 留一盏灯，慢慢走")
	paragraph(content,game.state.next_goal(),23)
	paragraph(content,"每件摆设消耗 3 份游戏材料。首通获得材料，重试不扣资源；家园不因离线或缺少健康记录损坏。",17)
	var row = HBoxContainer.new()
	content.add_child(row)
	for item in ["门灯","石景","谷亭","风铃"]:
		var name = item
		var placed = name in game.state.data.buildings
		var b = button(row,("✓ " if placed else "") + name + (" 已安放" if placed else " · 3材料"),func():
			if game.state.build(name):
				game.refresh_home()
				open_home()
				show_toast("洞府添了一处新景：" + name)
			else:
				show_toast("材料不足，或已经安放。"))
		b.disabled = placed or game.state.data.materials < 3
	paragraph(content,"命影状态演示（不读取真实医疗数据，下一场生效）",18)
	var health = OptionButton.new()
	for text in ["未知 · 使用默认值，不作健康判断","模拟稳定 · 攻击×1.10","模拟疲劳 · 攻击×0.95"]:
		health.add_item(text)
	health.selected = ["unknown","steady","tired"].find(game.state.data.simulated_health)
	health.item_selected.connect(func(index):
		game.state.data.simulated_health = ["unknown","steady","tired"][index]
		game.state.save_game()
		show_toast("模拟状态已保存，下一场挑战使用新快照。"))
	content.add_child(health)
	paragraph(content,"长期境界保留。模拟状态只改变本局命影属性，不强化 Boss，不改变首通奖励。",16)
	if game.state.load_warning != "":
		paragraph(content,game.state.load_warning,16)

func pause_menu() -> void:
	var content = dialog("暂歇片刻")
	paragraph(content,"场内已暂停。你可以继续，也可以不损失修为地回村。",23)
	button(content,"继续挑战",close_panel,true)
	button(content,"回到照生乡",game.return_town)

func show_result(result: Dictionary) -> void:
	var r = game.rules
	var content = dialog(r.entry.name + (" · 幻境已解" if r.won else " · 暂且休整"),game.return_town)
	paragraph(content,result.get("message",""),23)
	if r.won:
		paragraph(content,r.entry.world_change,21)
		paragraph(content,"修为 +%d    材料 +%d    完美抵挡 %d次" % [result.get("xp",0),result.get("materials",0),r.perfect_blocks],20)
		if result.get("new_best",false):
			paragraph(content,"刷新个人最佳：%.1f秒（相同难度、功法与模拟状态分别记录）" % float(result.get("seconds",0)),17)
		if r.entry.id == "b19":
			paragraph(content,"长夜退去，五域各得其生。\n青松：我还有我的路，你也有你的路。灯留一盏，我们慢慢走。",21)
	else:
		paragraph(content,"上次命中：" + (r.last_hit if r.last_hit!="" else "本次未完成") + "\n应对：" + r.entry.tell,20)
	var id: String = r.entry.id
	var row = HBoxContainer.new()
	content.add_child(row)
	button(row,"回到故乡 · 看看新变化",game.return_town,true)
	button(row,"再试一次",func(): game.start_encounter(id))
	paragraph(content,"这是游戏结果，不宣告现实疾病治愈或恶化。所有挑战均可免费重试。",15)

func open_minions() -> void:
	if game.rules != null:
		show_toast("先回村，再翻看散祟故事。")
		return
	var content = dialog("散祟志 · 草木器物各有来处")
	paragraph(content,"断脉行炁附着于枝芽、余炭、陶土、纸信与水痕，化为散祟。它们没有对应的现实病名。收拢散祟，学会地区机制，再与乡人一同修复主阵。",17)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 430
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",14)
	scroll.add_child(list)
	for mob in Catalogue.minions():
		label(list,mob.name+" · "+Catalogue.region_name(mob.element)+(" 〔已收拢〕" if mob.id in game.state.data.minion_lore else ""),23)
		paragraph(list,mob.story,17)
		paragraph(list,"出手："+mob.attack+"。"+mob.tell+"\n应对："+mob.counter,16)
		paragraph(list,"复归："+mob.home,16)
		button(list,"去"+Catalogue.region_name(mob.element),func(): open_atlas(mob.element))

func open_npc(id: String) -> void:
	var person = Catalogue.person(id)
	if person.is_empty():
		return
	var content = dialog(person.name+" · 灯下小叙")
	var restored = person.flag in game.state.data.clears
	paragraph(content,person.after if restored else person.before,24)
	paragraph(content,person.request,18)
	if person.element != "无":
		for mob in Catalogue.minions_for(person.element):
			paragraph(content,mob.name+"："+(mob.home if restored else mob.story),17)
	var region: String = person.region
	button(content,"再访此地" if restored else "记下委托 · 前往此地",func():
		game.state.track(region)
		open_atlas(region)
	,true)
	button(content,"翻看散祟志",open_minions)

func _style_bar(bar: ProgressBar,color: Color) -> void:
	var track = StyleBoxFlat.new()
	track.bg_color = Color("102937")
	track.set_corner_radius_all(6)
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background",track)
	bar.add_theme_stylebox_override("fill",fill)