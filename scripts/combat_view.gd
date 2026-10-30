extends Control

const Assets = preload("res://scripts/pixel_assets.gd")
const TrialRules = preload("res://scripts/tribulation_rules.gd")
const BossRules = preload("res://scripts/boss_rules.gd")
const Effects = preload("res://scripts/combat_effects.gd")
var game: Node2D
var ui: Control
var mode: String = "tribulation"
var support: int = 0
var rules: RefCounted
var hero: Sprite2D
var elder: Sprite2D
var dragon: Sprite2D
var dragon_frames: Array[Texture2D] = []
var clock: float = 0
var busy: bool = false
var cast_visual: float = 0
var shield_visual: float = 0
var lightning_visual: float = 0
var hurt_visual: float = 0
var impact_text: Label
var result_shown: bool = false
var skill_nodes: Array[Button] = []
var top_label: Label
var meter: ProgressBar
var player_status: Label
var message: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules = TrialRules.new(game.state) if mode == "tribulation" else BossRules.new(game.state, support)
	var background = TextureRect.new()
	background.texture = Assets.texture("res://assets/gameplay/" + ("tribulation-stage.png" if mode == "tribulation" else "boss-stage.png"))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode == "tribulation":
		hero = actor(game.walk_textures[8], Vector2(300, 655), 156)
		elder = actor(Assets.texture("res://assets/gameplay/elder-meditating.png"), Vector2(895, 550), 176)
	else:
		hero = actor(game.walk_textures[8], Vector2(345, 630), 148)
		dragon_frames = Assets.frames("res://assets/gameplay/dragon-states.png", 2, 2)
		dragon = actor(dragon_frames[0], Vector2(1130, 510), 410)
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

func _build_hud() -> void:
	var title = ui.card(Rect2(20, 18, 405, 71), self, Color("342922"))
	var name_label = ui.label_into(title, "天雷渡劫 · 守护青松" if mode == "tribulation" else "云海妖龙 · 首领挑战", 28, Color("f3d19a"))
	name_label.add_theme_font_override("font", game.title_font)
	var bar = ui.card(Rect2(491, 18, 704, 90), self, Color("342922"))
	top_label = ui.label_into(bar, "", 18, Color("f8e5c2"))
	meter = ProgressBar.new()
	meter.custom_minimum_size.y = 18
	meter.show_percentage = false
	var track = StyleBoxFlat.new()
	track.bg_color = Color("392a38")
	track.set_border_width_all(1)
	track.border_color = Color("c79c58")
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color("bb8149") if mode == "tribulation" else Color("a44b87")
	meter.add_theme_stylebox_override("background", track)
	meter.add_theme_stylebox_override("fill", fill)
	bar.add_child(meter)
	var leave = ui.button(self, "返回仙村 ×", ui.close_modal)
	leave.position = Vector2(1231, 20)
	leave.size.x = 185
	var status = ui.card(Rect2(20, 112, 315, 136), self, Color("342922"))
	player_status = ui.label_into(status, "", 19, Color("ffe9bd"))
	message = ui.label_into(self, "", 22, Color("fff0c6"))
	message.position = Vector2(350, 692)
	message.size = Vector2(850, 38)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_outline_color", Color("2b2830"))
	message.add_theme_constant_override("outline_size", 6)
	impact_text = ui.label_into(self, "", 36, Color("ffe298"))
	impact_text.add_theme_color_override("font_outline_color", Color("3a2b2b"))
	impact_text.add_theme_constant_override("outline_size", 7)
	impact_text.hide()
	var row = HBoxContainer.new()
	row.position = Vector2(365, 755)
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	var names = ["雷诀  [1]\n5 灵气 · 破劫 90", "镇心诀  [2]\n3 灵气 · 蓄盾", "守护符  [3]\n1 张 · 抵挡天雷"] if mode == "tribulation" else ["攻击  [J]\n挥剑 · 灵刃", "护盾  [K]\n抵挡吐息", "闪避  [空格]\n短暂避开攻击"]
	for i in range(3):
		var choice = i
		var b = ui.button(row, names[i], func(): use_skill(choice), i == 0)
		b.custom_minimum_size = Vector2(214, 85)
		skill_nodes.append(b)
	var tips = ui.label_into(self, "", 16, Color("fff0c6"))
	tips.position = Vector2(20, 856)
	tips.text = "选择功法后观看施法与落雷。游戏通关不代表现实康复；中途离开保留已消耗资源。" if mode == "tribulation" else "WASD 移动 · J 攻击 · K 护盾 · 空格闪避 · 红色区域锁定后可移开躲避（本地模拟）"
	tips.add_theme_color_override("font_outline_color", Color("29242e"))
	tips.add_theme_constant_override("outline_size", 5)
	message.text = "老者已入定。选择第一招，守住这一轮天雷。" if mode == "tribulation" else "妖龙即将吐息，留意红色预警区域。"

func refresh() -> void:
	if mode == "tribulation":
		top_label.text = "第 %d / 3 回合     天雷余势 %d / 240" % [rules.round, rules.thunder]
		meter.max_value = 240
		meter.value = rules.thunder
		player_status.text = "守元  %d / 260\n护盾  %d\n灵气  %d    守护符  %d" % [rules.hp, rules.shield, game.state.qi, game.state.charms]
		for i in range(skill_nodes.size()):
			skill_nodes[i].disabled = busy or rules.finished or (game.state.qi < (5 if i == 0 else 3) if i < 2 else game.state.charms < 1)
	else:
		top_label.text = "云海妖龙   %d / 1440     本局贡献 %d" % [rules.boss_hp, rules.damage_total]
		meter.max_value = 1440
		meter.value = rules.boss_hp
		player_status.text = "%s\n护元  %d / 300\n本次出战  %d / 3" % [game.state.player_name, rules.hp, game.state.boss_attempts]
		for i in range(skill_nodes.size()):
			var cooldown = [rules.attack_cd, rules.shield_cd, rules.dodge_cd][i]
			skill_nodes[i].disabled = rules.finished or cooldown > 0
			skill_nodes[i].text = ["攻击  [J]\n挥剑 · 灵刃", "护盾  [K]\n抵挡吐息", "闪避  [空格]\n短暂避开攻击"][i] if cooldown <= 0 else ["攻击", "护盾", "闪避"][i] + "\n冷却 %.1f 秒" % cooldown

func use_skill(choice: int) -> void:
	if rules.finished:
		return
	if mode == "tribulation":
		if not busy:
			_trial_turn(choice)
	else:
		if choice == 0:
			var result = rules.attack()
			if result.ok:
				cast_visual = 0.38
				hurt_visual = 0.32
				floating("-%d" % result.damage, Vector2(1060, 260))
				game.state.save_game()
		elif choice == 1:
			if rules.defend():
				message.text = "护盾已展开 · 把握吐息时机"
		elif choice == 2:
			if rules.dodge():
				var direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
				if direction == Vector2.ZERO:
					direction = Vector2.UP if hero.position.y > 570 else Vector2.DOWN
				hero.position += direction * 105
				_clamp_hero()
		refresh()

func _trial_turn(choice: int) -> void:
	var result = rules.choose(choice)
	if not result.ok:
		message.text = result.message
		return
	busy = true
	game.state.save_game()
	cast_visual = 1.0
	shield_visual = 2.4 if choice in [1, 2] else 0
	message.text = ["雷诀引动灵光，消解雷劫余势。", "镇心诀结阵，护盾正在凝聚。", "家人的守护符展开金色屏障。 "][choice]
	refresh()
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree():
		return
	lightning_visual = 0.75
	floating("天雷 -%d" % result.damage, Vector2(850, 278))
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree():
		return
	busy = false
	message.text = "天雷被守护挡下。" if result.protected else "本轮受到 %d 点游戏伤害。" % result.hurt
	refresh()
	ui.refresh()
	if rules.finished:
		await get_tree().create_timer(0.5).timeout
		if is_inside_tree():
			show_result()

func floating(text: String, pos: Vector2) -> void:
	impact_text.text = text
	impact_text.position = pos
	impact_text.show()
	var tween = create_tween()
	tween.tween_property(impact_text, "position:y", pos.y - 30, 0.6)
	tween.tween_callback(impact_text.hide)

func _process(delta: float) -> void:
	clock += delta
	cast_visual = maxf(0, cast_visual - delta)
	shield_visual = maxf(0, shield_visual - delta)
	lightning_visual = maxf(0, lightning_visual - delta)
	hurt_visual = maxf(0, hurt_visual - delta)
	if mode == "tribulation":
		elder.position.y = 550 + sin(clock * 1.3) * 1.5
		hero.rotation = sin(clock * 1.5) * 0.01
	else:
		if not rules.finished:
			var direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			hero.position += direction * 255 * delta
			_clamp_hero()
			if direction.length() > 0:
				hero.texture = game.walk_textures[8 + int(clock * 9) % 4]
			else:
				hero.texture = game.walk_textures[8]
			hero.offset.y = -hero.texture.get_height() * 0.5
			hero.scale = Vector2.ONE * 148 / hero.texture.get_height()
			var result = rules.step(delta, hero.position)
			match result.get("event", ""):
				"windup": message.text = "妖龙蓄力！移开红区，或准备护盾 / 闪避。"
				"evaded": message.text = "避开吐息！继续进攻。"
				"blocked": message.text = "护盾抵挡了吐息！"
				"hurt":
					message.text = "受到吐息伤害 -80。下一次留意预警。"
					floating("-80", hero.position - Vector2(20, 160))
					hero.modulate = Color("ffaaa0")
					create_tween().tween_property(hero, "modulate", Color.WHITE, 0.4)
		var frame = 3 if rules.finished and rules.won else (1 if rules.phase in ["windup", "breath"] else (2 if hurt_visual > 0 else 0))
		dragon.texture = dragon_frames[frame]
		dragon.offset.y = -dragon.texture.get_height() * 0.5
		dragon.scale = Vector2.ONE * 410 / dragon.texture.get_height()
		dragon.position.y = 510 + sin(clock * 1.6) * 8
		dragon.position.x = 1130 - (20 if rules.phase == "breath" else 0)
		refresh()
		if rules.finished and not result_shown:
			show_result()

func _clamp_hero() -> void:
	hero.position.x = clampf(hero.position.x, 115, 735)
	hero.position.y = clampf(hero.position.y, 454, 697)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			ui.close_modal()
			return
		if rules.finished:
			return
		var keys = [KEY_1, KEY_2, KEY_3] if mode == "tribulation" else [KEY_J, KEY_K, KEY_SPACE]
		for i in range(3):
			if event.keycode == keys[i]:
				use_skill(i)
				get_viewport().set_input_as_handled()

func show_result() -> void:
	if result_shown:
		return
	result_shown = true
	game.state.save_game()
	ui.refresh()
	var content = ui.card(Rect2(421, 250, 600, 365), self)
	var heading = "雷劫平息 · 游戏试炼完成" if mode == "tribulation" else "妖龙退散 · 挑战完成"
	ui.label_into(content, heading if rules.won else "今日暂且休整", 28)
	ui.line(content)
	if mode == "tribulation":
		ui.paragraph(content, "这次游戏挑战已经结束。长期修为完整保留。\n恢复篇章需要家属另外确认，战斗结果不表示现实康复。", 20, Color("5c432e"))
		ui.button(content, "查看阶段恢复篇章", ui.open_recovery, true)
	else:
		ui.paragraph(content, "本局贡献  %d\n累计贡献  %d\n今日出战  %d / 3" % [rules.damage_total, game.state.contribution, game.state.boss_attempts], 21, Color("5c432e"))
	ui.button(content, "回到仙村", ui.close_modal, true)
