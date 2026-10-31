extends Control
const Rules = preload("res://scripts/equipment_rules.gd")
const Icon = preload("res://scripts/equipment_icon.gd")
const CREAM = Color("f5e8d0")
const MUTED_TEXT = Color("b7b0a8")
const GOLD_TEXT = Color("edd096")
const SURFACE = Color("232830")
var game: Node
var ui: Control
var tab = "wish"
var selected_id = ""
var selected_slot = "all"
var busy = false
var reveal_tween: Tween
var result_cards: Array[Control] = []
var single_button: Button
var ten_button: Button
var skip_button: Button
var result_grid: GridContainer
var status_label: Label

class WishSeal extends Control:
	var clock = 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()
	func _draw() -> void:
		var center = size / 2
		draw_circle(center, 83, Color(0.9, 0.65, 0.3, 0.05))
		draw_circle(center, 62, Color(0.9, 0.65, 0.3, 0.07))
		draw_arc(center, 78, clock * 0.15, TAU + clock * 0.15, 64, Color("94764d"), 1.0)
		draw_arc(center, 65, -clock * 0.2, TAU - clock * 0.2, 48, Color("d4b779"), 1.0)
		for i in range(8):
			var angle = i * TAU / 8 + clock * 0.15
			var point = center + Vector2(cos(angle), sin(angle)) * 78
			draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), Color("edce8b"))
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -40), center + Vector2(29, 0), center + Vector2(0, 40), center + Vector2(-29, 0)]), Color("9c8051"))
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -29), center + Vector2(19, 0), center + Vector2(0, 29), center + Vector2(-19, 0)]), Color("f0d79b"))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()

func box(color: Color = SURFACE, border: Color = Color("514837"), width: int = 1) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(width)
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 14
	result.content_margin_bottom = 14
	return result

func panel_at(rect: Rect2, color: Color = SURFACE) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", box(color))
	add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column

func text(parent: Node, value: String, font_size: int = 18, color: Color = CREAM) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func paragraph_text(parent: Node, value: String, font_size: int = 16, color: Color = MUTED_TEXT) -> Label:
	var label = text(parent, value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func action(parent: Node, value: String, callback: Callable, primary: bool = false) -> Button:
	var button = Button.new()
	button.text = value
	button.custom_minimum_size.y = 44
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color = Color("735735") if primary else Color("303640")
		if state == "hover":
			color = color.lightened(0.12)
		if state == "pressed":
			color = color.darkened(0.12)
		if state == "disabled":
			color = Color("303036")
		button.add_theme_stylebox_override(state, box(color, Color("a38350") if primary else Color("54565d")))
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", CREAM)
	button.add_theme_color_override("font_disabled_color", Color("797b81"))
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	result_cards.clear()
	var shade = ColorRect.new()
	shade.color = Color(0.035, 0.04, 0.06, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var backdrop = Panel.new()
	backdrop.position = Vector2(70, 35)
	backdrop.size = Vector2(1300, 830)
	backdrop.add_theme_stylebox_override("panel", box(Color("191d25"), Color("a18351"), 2))
	add_child(backdrop)
	var header = panel_at(Rect2(90, 52, 1260, 68), Color("191d25"))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	header.add_child(row)
	text(row, "聚 宝 阁", 30, GOLD_TEXT)
	var subtitle = text(row, game.state.member_label() + " · " + game.state.player_name, 17, MUTED_TEXT)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action(row, "祈愿装备", func(): switch_tab("wish"), tab == "wish")
	action(row, "我的行囊 · %d" % game.state.equipment.inventory.size(), func(): switch_tab("bag"), tab == "bag")
	action(row, "返回仙村 ×", ui.close_modal)
	var left = panel_at(Rect2(90, 138, 320, 696))
	text(left, "灵气", 17, MUTED_TEXT)
	text(left, str(game.state.equipment.qi), 44, GOLD_TEXT)
	var progress = ProgressBar.new()
	progress.custom_minimum_size.y = 9
	progress.max_value = Rules.TEN_COST
	progress.value = mini(int(game.state.equipment.qi), Rules.TEN_COST)
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", box(Color("35383f")))
	progress.add_theme_stylebox_override("fill", box(Color("c6a162")))
	left.add_child(progress)
	var remaining = maxi(0, Rules.TEN_COST - int(game.state.equipment.qi))
	text(left, "十连已备齐" if remaining == 0 else "距十连还差 %d 灵气" % remaining, 16, MUTED_TEXT)
	paragraph_text(left, "每日有效习惯记录 +100\n单抽 70 · 十连 700\n积攒七天，即可十连。漏记不清零。", 16)
	action(left, "查看今日习惯", ui.open_record)
	var separator = HSeparator.new()
	left.add_child(separator)
	text(left, "本角色基础概率", 18, GOLD_TEXT)
	# Keep long probability explanations inside the left column at the base viewport size.
	left.add_theme_constant_override("separation", 8)
	var locked = float(game.state.equipment.initial_score) >= 0
	if locked:
		var odds = Rules.probabilities(float(game.state.equipment.initial_score))
		for i in range(5):
			var odds_row = HBoxContainer.new()
			left.add_child(odds_row)
			var name_label = text(odds_row, "◆ " + Rules.RARITIES[i], 16, Rules.COLORS[i])
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text(odds_row, "%.2f%%" % odds[i], 16)
		paragraph_text(left, "初始基础属性参与成长扶持。概率已固定，后续属性改善不会降低待遇。", 14)
	else:
		paragraph_text(left, "确认基础档案后显示概率。初始基础属性越低，优质装备的基础概率越高。", 16)
		action(left, "建立基础档案", ui.open_home, true)
	paragraph_text(left, "十连至少一件史诗或以上。\n以上为保底前概率；保底只提升品质。", 14, GOLD_TEXT)
	text(left, "累计祈愿  %d 次" % game.state.equipment.draw_count, 15, MUTED_TEXT)
	if tab == "wish":
		build_wish()
	else:
		build_bag()

func switch_tab(next_tab: String) -> void:
	finish_reveal()
	tab = next_tab
	build()

func last_receipt() -> Dictionary:
	return game.state.equipment.receipts.get(game.state.equipment.last_request, {})

func build_wish() -> void:
	var right = panel_at(Rect2(428, 138, 922, 696))
	var title = HBoxContainer.new()
	right.add_child(title)
	var title_label = text(title, "灵器祈愿", 27, GOLD_TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text(title, "四类装备 · 五种品质", 17, MUTED_TEXT)
	var receipt = last_receipt()
	if receipt.is_empty():
		var seal = WishSeal.new()
		seal.custom_minimum_size.y = 148
		right.add_child(seal)
		var introduction = text(right, "每一份坚持，都有回响", 26, GOLD_TEXT)
		introduction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		right.add_child(row)
		for template_id in [0, 1, 3, 4]:
			var showcase = {"id": "showcase", "template": template_id, "rarity": 4}
			var info = Rules.detail(showcase)
			var column = VBoxContainer.new()
			column.custom_minimum_size.x = 178
			row.add_child(column)
			var icon = Icon.new()
			icon.setup(showcase)
			icon.custom_minimum_size = Vector2(150, 132)
			column.add_child(icon)
			var label = text(column, info.name, 18, info.color)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var kind = text(column, "神话 · " + Rules.SLOT_NAMES[info.slot], 14, MUTED_TEXT)
			kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var preview_note = text(right, "神话灵器外观预览 · 实际获得品质以祈愿结果为准", 14, MUTED_TEXT)
		preview_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var guidance = paragraph_text(right, "装备收入行囊后可查看与穿戴。加成独立于健康基础属性，下一场战斗生效。", 17)
		guidance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		text(right, "最近一次祈愿 · %d 抽 · 消耗 %d 灵气" % [receipt.count, receipt.cost], 17, MUTED_TEXT)
		result_grid = GridContainer.new()
		result_grid.columns = 5
		result_grid.add_theme_constant_override("h_separation", 10)
		result_grid.add_theme_constant_override("v_separation", 10)
		right.add_child(result_grid)
		for item in receipt.items:
			result_cards.append(item_card(result_grid, item, Vector2(165, 190)))
		if receipt.guaranteed:
			text(right, "十连保底已生效 · 至少一件史诗", 16, Rules.COLORS[2])
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	status_label = paragraph_text(right, "十连至少一件史诗或以上 · 所有结果均已存入行囊", 16)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	right.add_child(actions)
	single_button = action(actions, "祈愿一次 · 70", func(): summon(1))
	ten_button = action(actions, "十连祈愿 · 700", func(): summon(10), true)
	single_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ten_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	single_button.disabled = busy or int(game.state.equipment.qi) < Rules.SINGLE_COST or float(game.state.equipment.initial_score) < 0
	ten_button.disabled = busy or int(game.state.equipment.qi) < Rules.TEN_COST or float(game.state.equipment.initial_score) < 0
	skip_button = action(actions, "跳过动画", finish_reveal)
	skip_button.visible = busy

func item_card(parent: Node, item: Dictionary, dimensions: Vector2) -> Button:
	var info = Rules.detail(item)
	var card = Button.new()
	card.custom_minimum_size = dimensions
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s · %s\n%s\n点击查看与穿戴" % [info.quality, info.name, Rules.bonus_text(item)]
	var background = box(Color("262a35").lerp(info.color.darkened(0.7), 0.25), info.color, 2)
	background.shadow_color = Color(info.color, 0.12)
	background.shadow_size = 5
	card.add_theme_stylebox_override("normal", background)
	card.add_theme_stylebox_override("hover", box(info.color.darkened(0.72), info.color, 3))
	card.add_theme_stylebox_override("pressed", box(info.color.darkened(0.8), info.color, 3))
	card.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, info.color, 2))
	parent.add_child(card)
	var column = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_right = -10
	column.offset_top = 12
	column.offset_bottom = -10
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)
	var quality = text(column, info.quality, 15, info.color)
	quality.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var icon = Icon.new()
	icon.setup(item)
	icon.custom_minimum_size.y = 68
	column.add_child(icon)
	var name_label = text(column, info.name, 17)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bonus = text(column, Rules.bonus_text(item), 15, GOLD_TEXT)
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var equipped = game.state.equipment.equipped.get(info.slot, "") == info.id
	var foot = text(column, "已穿戴" if equipped else Rules.SLOT_NAMES[info.slot], 13, Color("9cceb4") if equipped else MUTED_TEXT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for child in column.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.pressed.connect(func():
		finish_reveal()
		selected_id = info.id
		tab = "bag"
		build()
	)
	return card

func summon(count: int) -> void:
	if busy:
		return
	busy = true
	# A receipt is committed before presentation. Reopening always shows that same result.
	var request_id = "wish_%d_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), game.state.equipment.next_id]
	var receipt = await remote_draw(count, request_id) if game.state.is_remote() else game.state.draw_equipment(count, request_id)
	if not receipt.ok:
		busy = false
		status_label.text = receipt.message
		return
	ui.refresh()
	build()
	for card in result_cards:
		card.modulate.a = 0
	reveal_tween = create_tween().set_parallel(true)
	for i in range(result_cards.size()):
		reveal_tween.tween_property(result_cards[i], "modulate:a", 1.0, 0.3).set_delay(i * 0.08)
	reveal_tween.chain().tween_callback(finish_reveal)

## 由 C 扣费并生成装备；成功后刷新本角色读模型，并按原卡片样式展示同一回执。
func remote_draw(count: int, request_id: String) -> Dictionary:
	var state = game.state
	var core = get_tree().root.get_node("GameKernel")
	var result = await core.dispatch("growth.draw", {"cultivator_id": state.cultivator_id, "count": count, "request_id": request_id})
	if not result.ok:
		return {"ok": false, "message": str(result.message)}
	state.apply_remote(result.data.character)
	var items = []
	for item in result.data.items:
		items.append({"id": str(item.equipment_id), "template": int(item.template), "rarity": int(item.rarity_index)})
	var receipt = {"ok": true, "request_id": request_id, "count": count, "cost": int(result.data.cost), "items": items, "guaranteed": result.data.guaranteed == true}
	state.equipment.receipts[request_id] = receipt
	state.equipment.last_request = request_id
	state.save_game()
	return receipt

func remote_wear(info: Dictionary, equipped: bool) -> Dictionary:
	var state = game.state
	var core = get_tree().root.get_node("GameKernel")
	var result: Dictionary
	if equipped:
		result = await core.dispatch("growth.unequip", {"cultivator_id": state.cultivator_id, "slot": info.slot, "request_id": "off-%s-%d" % [info.id, Time.get_ticks_usec()]})
	else:
		result = await core.dispatch("growth.equip", {"cultivator_id": state.cultivator_id, "equipment_id": info.id, "slot": info.slot})
	if not result.ok:
		return {"ok": false, "message": str(result.message)}
	state.apply_remote(result.data)
	state.save_game()
	return {"ok": true, "message": ("已卸下装备" if equipped else "已穿戴「%s」" % info.name) + "，下一场战斗生效。"}

func finish_reveal() -> void:
	if is_instance_valid(reveal_tween) and reveal_tween.is_running():
		reveal_tween.kill()
	busy = false
	for card in result_cards:
		if is_instance_valid(card):
			card.modulate.a = 1
	if is_instance_valid(skip_button):
		skip_button.hide()
	if is_instance_valid(single_button):
		single_button.disabled = int(game.state.equipment.qi) < Rules.SINGLE_COST or float(game.state.equipment.initial_score) < 0
	if is_instance_valid(ten_button):
		ten_button.disabled = int(game.state.equipment.qi) < Rules.TEN_COST or float(game.state.equipment.initial_score) < 0

func build_bag() -> void:
	var right = panel_at(Rect2(428, 138, 922, 696))
	text(right, "我的行囊", 27, GOLD_TEXT)
	var slots = HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	right.add_child(slots)
	for slot in Rules.SLOTS:
		var name_text = "未穿戴"
		var color = MUTED_TEXT
		for item in game.state.equipment.inventory:
			var info = Rules.detail(item)
			if game.state.equipment.equipped.get(slot, "") == info.id:
				name_text = info.name
				color = info.color
		var current_slot = slot
		var slot_button = action(slots, Rules.SLOT_NAMES[slot] + "\n" + name_text, func(): select_equipped(current_slot))
		slot_button.custom_minimum_size.y = 65
		slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_button.add_theme_stylebox_override("normal", box(Color("2b2e36"), color, 2))
	var totals = Rules.bonuses(game.state.equipment)
	text(right, "总加成  生命 +%d  攻击 +%d  防御 +%d  灵力 +%d  体力 +%d" % [totals.life, totals.attack, totals.defense, totals.spirit, totals.stamina], 16, GOLD_TEXT)
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	right.add_child(filter_row)
	for slot in ["all"] + Rules.SLOTS:
		var current = slot
		action(filter_row, "全部" if slot == "all" else Rules.SLOT_NAMES[slot], func(): selected_slot = current; build(), selected_slot == slot)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 258
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var items = game.state.equipment.inventory.duplicate()
	items.reverse()
	items.sort_custom(func(a, b): return int(a.rarity) > int(b.rarity))
	for item in items:
		if selected_slot == "all" or Rules.detail(item).slot == selected_slot:
			item_card(grid, item, Vector2(160, 190))
	if grid.get_child_count() == 0:
		paragraph_text(grid, "这里还没有装备。\n完成每日习惯、积攒灵气后，前往祈愿。", 18)
	build_detail(right)

func select_equipped(slot: String) -> void:
	selected_slot = slot
	selected_id = str(game.state.equipment.equipped.get(slot, ""))
	build()

func build_detail(parent: Node) -> void:
	var selected = {}
	for item in game.state.equipment.inventory:
		if item.id == selected_id:
			selected = item
	if selected.is_empty():
		paragraph_text(parent, "点击装备查看详情与穿戴。相同装备会分别保留，每个槽位只能穿戴一件。", 16)
		return
	var info = Rules.detail(selected)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var preview = Icon.new()
	preview.name = "EquipmentDetailPreview"
	preview.setup(selected)
	preview.custom_minimum_size = Vector2(112, 112)
	row.add_child(preview)
	var description = VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	text(description, "%s · %s" % [info.name, info.quality], 21, info.color)
	text(description, Rules.bonus_text(selected) + " · " + Rules.SLOT_NAMES[info.slot], 17)
	var currently = {}
	for item in game.state.equipment.inventory:
		if game.state.equipment.equipped.get(info.slot, "") == item.id:
			currently = item
	var comparison = "此槽位尚未穿戴"
	if not currently.is_empty():
		var other = Rules.detail(currently)
		comparison = "当前：%s（%s）" % [other.name, Rules.bonus_text(currently)]
	text(description, comparison, 15, MUTED_TEXT)
	var equipped = game.state.equipment.equipped.get(info.slot, "") == info.id
	action(row, "卸下装备" if equipped else "穿戴装备", func():
		var result = await remote_wear(info, equipped) if game.state.is_remote() else (game.state.unequip_item(info.slot) if equipped else game.state.equip_item(info.id))
		ui.toast(result.message)
		ui.refresh()
		build()
	, true)
