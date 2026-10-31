extends Control

const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Atmosphere = preload("res://scripts/arena_atmosphere.gd")
const Assets = preload("res://scripts/pixel_assets.gd")
const BossRules = preload("res://scripts/boss_rules.gd")
const Effects = preload("res://scripts/combat_effects.gd")
const SKILL_NAMES = ["听风剑诀", "踏云步", "云罡护体", "饕餮归元"]
@export var boss_id: String = ""
var encounter: Dictionary = {}
var boss_anchor = Vector2(1130, 510)
var boss_height: float = 410
var game: Node2D
var ui: Control
var mode: String = "boss"
var support: int = 0
var rules: RefCounted
var hero: Sprite2D
var dragon: Sprite2D
var dragon_frames: Array[Texture2D] = []
var clock: float = 0
var cast_visual: float = 0
var cast_duration: float = 0.5
var sword_visual: bool = false
var cast_origin = Vector2.ZERO
var cast_direction = Vector2.RIGHT
var dodge_origin = Vector2.ZERO
var dodge_visual: float = 0
var hurt_visual: float = 0
var heal_visual: float = 0
var shield_impact: float = 0
var shield_break_visual: float = 0
var result_shown: bool = false
var heal_was_unlocked: bool = false
var facing = Vector2.RIGHT
var skill_nodes: Array[Button] = []
var basic_button: Button
var top_label: Label
var meter: ProgressBar
var player_status: Label
var vital_labels: Array[Label] = []
var vital_bars: Array[ProgressBar] = []
var impact_text: Label
var message: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	encounter = Catalogue.entry(boss_id) if boss_id != "" else {}
	rules = BossRules.new(game.state, 0, game.state.selected_tier, game.state.selected_track, mode == "practice", encounter)
	heal_was_unlocked = game.state.heal_unlocked()
	var background = TextureRect.new()
	background.texture = Assets.texture(encounter.get("background", "res://assets/gameplay/boss-stage.png"))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not encounter.is_empty():
		var atmosphere = Node2D.new()
		atmosphere.set_script(Atmosphere)
		atmosphere.view = self
		add_child(atmosphere)
	var spawn = Vector2(625, 630) if encounter.is_empty() else Vector2(encounter.hero_spawn[0], encounter.hero_spawn[1])
	hero = actor(game.walk_textures[8], spawn, 148)
	if encounter.is_empty():
		dragon_frames = Assets.frames("res://assets/gameplay/dragon-states.png", 2, 2)
	else:
		dragon_frames = [Catalogue.boss_texture(boss_id)]
		boss_anchor = rules.boss_position
		boss_height = float(encounter.boss_height)
	dragon = actor(dragon_frames[0], boss_anchor, boss_height)
	var effects = Node2D.new()
	effects.set_script(Effects)
	effects.view = self
	add_child(effects)
	_build_hud()
	refresh()

func actor(texture: Texture2D, foot: Vector2, height: float) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.position = foot
	sprite.scale = Vector2.ONE * height / texture.get_height()
	sprite.offset.y = -texture.get_height() * 0.5
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return sprite

func _bar(parent: Node, color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size.y = 13
	bar.show_percentage = false
	var track = StyleBoxFlat.new()
	track.bg_color = Color("272b2d")
	track.set_border_width_all(1)
	track.border_color = Color("94794e")
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func _build_hud() -> void:
	var title = ui.card(Rect2(20, 18, 410, 90), self, Color("342922"))
	title.add_theme_constant_override("separation", 4)
	var name_label = ui.label_into(title, "松风四式 · " + ("演武练习" if mode == "practice" else "属性试炼"), 27, Color("f3d19a"))
	name_label.add_theme_font_override("font", game.title_font)
	ui.label_into(title, encounter.arena if not encounter.is_empty() else "%s线 / %d 档 / %s" % [game.state.ATTRIBUTE_LABELS[rules.track], rules.tier, game.state.realm()], 16, Color("e2c89e"))
	var boss_card = ui.card(Rect2(452, 18, 738, 90), self, Color("342922"))
	boss_card.add_theme_constant_override("separation", 8)
	top_label = ui.label_into(boss_card, "", 19, Color("f8e5c2"))
	meter = _bar(boss_card, Color("b76075"))
	var leave = ui.button(self, "返回长廊 ×" if not encounter.is_empty() else "返回仙村 ×", leave_battle)
	leave.position = Vector2(1231, 20)
	leave.size.x = 185
	var status = ui.card(Rect2(20, 125, 292, 274), self, Color("342922"))
	status.add_theme_constant_override("separation", 7)
	ui.label_into(status, game.state.player_name, 23, Color("f5ddb4"))
	for i in range(3):
		vital_labels.append(ui.label_into(status, "", 16, Color("f6e3c3")))
		vital_bars.append(_bar(status, [Color("bd6a63"), Color("63aebd"), Color("a4bc6c")][i]))
	player_status = ui.label_into(status, "", 15, Color("dfcda9"))
	message = ui.label_into(self, "靠近目标普攻回灵；剑诀、护盾与归元共用灵力。", 21, Color("fff0c6"))
	message.position = Vector2(330, 690)
	message.size = Vector2(1070, 38)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_outline_color", Color("2b2830"))
	message.add_theme_constant_override("outline_size", 6)
	impact_text = ui.label_into(self, "", 34, Color("c8f3d6"))
	impact_text.add_theme_color_override("font_outline_color", Color("3a2b2b"))
	impact_text.add_theme_constant_override("outline_size", 7)
	impact_text.hide()
	var row = HBoxContainer.new()
	row.position = Vector2(25, 754)
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	basic_button = ui.button(row, "普攻 [J]\n近身命中 · 灵力 +5", basic_attack)
	basic_button.custom_minimum_size = Vector2(250, 86)
	basic_button.add_theme_font_size_override("font_size", 17)
	for i in range(4):
		var choice = i
		var button = ui.button(row, "", func(): use_skill(choice), i == 0)
		button.custom_minimum_size = Vector2(270, 86)
		button.add_theme_font_size_override("font_size", 17)
		skill_nodes.append(button)
	var tips = ui.label_into(self, "WASD 移动  ·  J 普攻  ·  1 剑诀  ·  2 / 空格 踏云  ·  3 / K 护盾  ·  4 / R 归元  ·  体力自动恢复", 16, Color("fff0c6"))
	tips.position = Vector2(25, 858)
	tips.add_theme_color_override("font_outline_color", Color("29242e"))
	tips.add_theme_constant_override("outline_size", 5)

func refresh() -> void:
	top_label.text = "%s  %d / %d    用时 %.1f 秒" % [rules.boss_name, rules.boss_hp, rules.boss_max_hp, rules.elapsed]
	meter.max_value = rules.boss_max_hp
	meter.value = rules.boss_hp
	var current = [rules.hp, rules.mp, rules.stamina]
	var maximum = [rules.max_hp, rules.max_mp, rules.max_stamina]
	for i in range(3):
		vital_labels[i].text = "%s  %d / %d" % [["生命", "灵力", "体力"][i], current[i], maximum[i]]
		vital_bars[i].max_value = maximum[i]
		vital_bars[i].value = current[i]
	player_status.text = "云罡护盾 %d\n%s" % [rules.shield_hp, "吐纳 %.1f 秒 · 移动减速" % rules.heal_cast if rules.heal_cast > 0 else "本局资源 · 不扣健康属性"]
	basic_button.disabled = rules.finished or rules.attack_cd > 0 or rules.heal_cast > 0
	var cooldowns = [rules.sword_cd, rules.dodge_cd, rules.shield_cd, rules.heal_cd]
	var descriptions = ["18 灵力 · 路径剑气", "24 体力 · 位移 / 闪避", "24 灵力 · 短时护盾", "45 灵力 · 吐纳恢复"]
	for i in range(4):
		var unlocked = i != 3 or game.state.heal_unlocked()
		var enough = rules.stamina >= BossRules.DODGE_COST if i == 1 else rules.mp >= [BossRules.SWORD_COST, 0, BossRules.SHIELD_COST, BossRules.HEAL_COST][i]
		var detail = descriptions[i]
		if not unlocked:
			detail = "首通两个不同关卡解锁"
		elif cooldowns[i] > 0:
			detail = "冷却 %.1f 秒" % cooldowns[i]
		elif not enough:
			detail = "体力不足 · 等待恢复" if i == 1 else "灵力不足 · 普攻回灵"
		if i == 3 and rules.heal_cast > 0:
			detail = "吐纳 %.1f 秒" % rules.heal_cast
		skill_nodes[i].text = SKILL_NAMES[i] + " [%d]\n" % (i + 1) + detail
		skill_nodes[i].disabled = not unlocked or rules.finished or rules.heal_cast > 0 or cooldowns[i] > 0 or not enough or (i == 3 and rules.hp == rules.max_hp)

func _slash(is_sword: bool, damage: int) -> void:
	sword_visual = is_sword
	cast_duration = 0.5 if is_sword else 0.25
	cast_visual = cast_duration
	cast_origin = hero.position + Vector2(22, -75)
	cast_direction = (rules.boss_position - hero.position).normalized()
	if damage > 0:
		hurt_visual = 0.32
		floating("-%d" % damage, boss_anchor - Vector2(30, boss_height + 10))

func basic_attack() -> void:
	var result = rules.attack(hero.position)
	if result.ok:
		_slash(false, result.damage)
	message.text = result.message
	refresh()
	if rules.finished:
		show_result()

func use_skill(choice: int) -> void:
	if rules.finished or choice < 0 or choice > 3:
		return
	match choice:
		0:
			var result = rules.sword(hero.position, rules.boss_position - hero.position)
			message.text = result.message
			if result.ok:
				_slash(true, result.damage)
		1:
			if rules.dodge():
				dodge_origin = hero.position
				dodge_visual = 0.45
				var direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
				if direction.is_zero_approx():
					direction = facing
				hero.position += direction.normalized() * 145
				_clamp_hero()
			message.text = rules.last_message
		2:
			rules.defend()
			message.text = rules.last_message
		3:
			rules.heal()
			message.text = rules.last_message
	refresh()
	if rules.finished:
		show_result()

func floating(text: String, position: Vector2) -> void:
	impact_text.text = text
	impact_text.position = position
	impact_text.show()
	var tween = create_tween()
	tween.tween_property(impact_text, "position:y", position.y - 30, 0.6)
	tween.tween_callback(impact_text.hide)

func _process(delta: float) -> void:
	clock += delta
	cast_visual = maxf(0, cast_visual - delta)
	dodge_visual = maxf(0, dodge_visual - delta)
	hurt_visual = maxf(0, hurt_visual - delta)
	heal_visual = maxf(0, heal_visual - delta)
	shield_impact = maxf(0, shield_impact - delta)
	shield_break_visual = maxf(0, shield_break_visual - delta)
	if not rules.finished:
		var direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if not direction.is_zero_approx():
			facing = direction.normalized()
		hero.position += direction * 255 * delta * (0.3 if rules.heal_cast > 0 else 1.0)
		_clamp_hero()
		hero.texture = game.walk_textures[8 + int(clock * 9) % 4] if direction.length() > 0 else game.walk_textures[8]
		hero.offset.y = -hero.texture.get_height() * 0.5
		hero.scale = Vector2.ONE * 148 / hero.texture.get_height()
		var shield_before: int = rules.shield_hp
		var result = rules.step(delta, hero.position)
		if shield_before > 0 and rules.shield_hp == 0:
			shield_break_visual = 0.55
		if int(result.get("healed", 0)) > 0:
			heal_visual = 0.8
			floating("+%d" % result.healed, hero.position - Vector2(20, 160))
			message.text = "饕餮归元 · 暖光回流，生命恢复。"
		match result.get("event", ""):
			"windup": message.text = rules.boss_name + "正在蓄力！移开红区，或选择踏云 / 云罡。"
			"evaded": message.text = "避开吐息，寻找出剑机会！"
			"blocked":
				shield_impact = 0.6
				message.text = "云罡抵挡 %d 点伤害。" % result.absorbed
			"hurt":
				shield_impact = 0.6 if result.absorbed > 0 else 0
				message.text = "受到 %d 点伤害。" % result.damage + ("归元被中断。" if result.interrupted else "")
				floating("-%d" % result.damage, hero.position - Vector2(20, 160))
				hero.modulate = Color("ffaaa0")
				create_tween().tween_property(hero, "modulate", Color.WHITE, 0.4)
	var frame = 3 if rules.finished and rules.won else (1 if rules.phase in ["windup", "breath"] else (2 if hurt_visual > 0 else 0))
	dragon.texture = dragon_frames[mini(frame, dragon_frames.size() - 1)]
	dragon.offset.y = -dragon.texture.get_height() * 0.5
	dragon.scale = Vector2.ONE * boss_height / dragon.texture.get_height()
	dragon.position = boss_anchor + Vector2(-12 if rules.phase == "breath" else 0, sin(clock * 1.6) * 4)
	if not encounter.is_empty():
		dragon.modulate = Color(1.5, 1.25, 1.05) if hurt_visual > 0 else Color.WHITE
		if rules.finished and rules.won:
			dragon.modulate = Color(0.55, 0.55, 0.55, 0.5)
	refresh()
	if rules.finished and not result_shown:
		show_result()

func _clamp_hero() -> void:
	hero.position.x = clampf(hero.position.x, 115, 1060)
	hero.position.y = clampf(hero.position.y, 454, 680)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE: leave_battle()
		KEY_J: basic_attack()
		KEY_1, KEY_Q: use_skill(0)
		KEY_2, KEY_SPACE: use_skill(1)
		KEY_3, KEY_K: use_skill(2)
		KEY_4, KEY_R: use_skill(3)
		_: return
	get_viewport().set_input_as_handled()

func leave_battle() -> void:
	if not encounter.is_empty():
		ui.open_boss()
	else:
		ui.close_modal()

func show_result() -> void:
	if result_shown:
		return
	result_shown = true
	game.state.save_game()
	ui.refresh()
	var content = ui.card(Rect2(410, 225, 640, 450), self)
	content.add_theme_constant_override("separation", 10)
	ui.label_into(content, "试炼通过 · " + rules.boss_name + "退散" if rules.won else "本次挑战结束", 28)
	ui.line(content)
	var stage_name = encounter.arena + " · " + encounter.name if not encounter.is_empty() else game.state.ATTRIBUTE_LABELS[rules.track] + "试炼"
	ui.paragraph(content, "%s · %d 档%s\n用时 %.1f 秒    造成伤害 %d\n受到伤害 %d    受击 %d 次" % [stage_name, rules.tier, " · 练习" if mode == "practice" else "", rules.elapsed, rules.damage_total, rules.damage_taken, rules.hit_count], 20, Color("5c432e"))
	if mode == "practice":
		ui.paragraph(content, "技能练习不结算首通，健康属性和关卡进度保持原样。", 17)
	elif rules.won:
		ui.paragraph(content, "首通进度已保存 · 当前境界 " + game.state.realm(), 18)
		if not heal_was_unlocked and game.state.heal_unlocked():
			ui.label_into(content, "新技能解锁：饕餮归元 [4]", 21, Color("3a6b59"))
	else:
		ui.paragraph(content, "健康属性与已通关记录保留。可再次练习，也可更新健康档案后再挑战。", 17)
	var actions = HBoxContainer.new()
	content.add_child(actions)
	if mode == "practice":
		ui.button(actions, "再次练习", ui.start_battle, true)
	else:
		if not encounter.is_empty():
			ui.button(actions, "再次挑战", func(): ui.start_corridor_boss(boss_id), true)
		else:
			ui.button(actions, "再次挑战", func(): ui.start_boss(false, rules.tier, rules.track), true)
	ui.button(actions, "返回长廊", ui.open_boss)
	ui.button(actions, "回到仙村", ui.close_modal)
