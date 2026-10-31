extends "res://scripts/combat/level.gd"
## 表现层读取规则，输入转换为本局意图；最终沿用 level 的幂等战果上报。
const Simulation = preload("res://scripts/systems/combat/encounter_sim.gd")
var encounter: Dictionary = {}
var simulation: RefCounted
var weapon: String = "sword"
var _background: Texture2D
var _hero: Texture2D = preload("res://assets/pixel/cultivator-walk.png")
var _minion: Texture2D = preload("res://assets/pixel_campaign/minion_sheet.png")
var _boss_art: Texture2D
var _companion: Texture2D = preload("res://assets/pixel_campaign/npc_sheet.png")
var _audio: AudioStreamPlayer
var _attack_flash: float = 0.0
var _exit_button: Button
var _elapsed_frame: float = 0.0

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	simulation = Simulation.new(player_snapshot, encounter)
	fight = simulation.fight
	if fight == null:
		ended = true
		message = "关卡配置无效"
		return
	_background = load(encounter.map)
	_boss_art = load(encounter.boss_sheet)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -14
	add_child(_audio)
	message = simulation.message
	for item in [["普攻 J", 0], ["灵根技能 Q", 1], ["法宝 R", 2]]:
		var button := Button.new()
		button.text = item[0]
		button.position = Vector2(620 + int(item[1]) * 155, 815)
		button.size = Vector2(145, 48)
		var mode: int = item[1]
		button.pressed.connect(func() -> void: _strike(mode))
		add_child(button)
	var dodge_button := Button.new()
	dodge_button.text = "闪避 Space"
	dodge_button.position = Vector2(1085, 815)
	dodge_button.size = Vector2(155, 48)
	dodge_button.pressed.connect(dodge)
	add_child(dodge_button)
	_exit_button = Button.new()
	_exit_button.text = "结束本局并返回"
	_exit_button.position = Vector2(1200, 32)
	_exit_button.pressed.connect(request_leave)
	add_child(_exit_button)

func _process(delta: float) -> void:
	if ended or fight == null:
		queue_redraw()
		return
	if paused:
		return
	_elapsed_frame += delta
	_attack_flash = maxf(0, _attack_flash - delta)
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D): direction.x += 1
	if Input.is_physical_key_pressed(KEY_W): direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S): direction.y += 1
	simulation.player_pos = (simulation.player_pos + direction.normalized() * 260 * minf(delta, 0.05)).clamp(Vector2(100, 205), Vector2(1320, 715))
	# 小步推进，避免低帧率时跨过预兆、弹道命中或闪避窗口。
	var remaining: float = minf(delta, 0.25)
	while remaining > 0:
		var dt: float = minf(remaining, 1.0 / 60.0)
		simulation.step(dt)
		remaining -= dt
	player_pos = simulation.player_pos
	message = simulation.message
	if simulation.finished:
		ended = true
		await _report()
	queue_redraw()

func attack() -> void:
	_strike(0)

func skill(ultimate: bool = false) -> void:
	_strike(2 if ultimate else 1)

func _strike(mode: int) -> void:
	if simulation == null or ended or paused:
		return
	var aim: Vector2 = get_local_mouse_position()
	if not Rect2(60, 170, 1320, 590).has_point(aim):
		aim = simulation.player_pos
	var result: Dictionary = simulation.attack(aim, mode, weapon)
	if result.get("ok", false):
		_attack_flash = 0.24
		_audio.stream = load("res://assets/combat/strike.wav" if mode == 0 else "res://assets/combat/spell.wav")
		_audio.play()
	message = simulation.message
	if simulation.finished:
		ended = true
		_report()
	queue_redraw()

func request_leave() -> void:
	if simulation != null:
		simulation.finished = true
	await super.request_leave()

func _sprite(texture: Texture2D, cell: int, columns: int, rows: int, position: Vector2, height: float) -> void:
	var tile := Vector2(texture.get_width() / float(columns), texture.get_height() / float(rows))
	draw_texture_rect_region(texture, Rect2(position - Vector2(height * tile.x / tile.y * 0.5, height), Vector2(height * tile.x / tile.y, height)), Rect2(Vector2(cell % columns, cell / columns) * tile, tile))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#101c25"))
	if _background != null:
		draw_texture_rect(_background, Rect2(60, 170, 1320, 590), false, Color(0.68, 0.68, 0.68))
	if simulation == null or fight == null:
		return
	for enemy in simulation.enemies:
		if enemy.hp <= 0: continue
		var pos: Vector2 = enemy.pos
		if enemy.warning >= 0:
			if enemy.behavior in ["rush", "boss"] and int(enemy.phase) == 0:
				draw_line(pos, enemy.target, Color(1, 0.35, 0.22, 0.7), 55, true)
			else:
				var center: Vector2 = pos if enemy.behavior == "bomber" else enemy.target
				draw_circle(center, 150, Color(1, 0.3, 0.16, 0.22))
				draw_arc(center, 150, 0, TAU, 48, Color("#ffc07a"), 3)
		if enemy.behavior == "boss":
			_sprite(_boss_art, int(encounter.boss_cell), 2, 2, pos + Vector2(0, 45), 145)
		else:
			var cell: int = {"rush": 0, "shooter": 1, "bomber": 2, "summoner": 6}[enemy.behavior]
			_sprite(_minion, cell, 5, 2, pos + Vector2(0, 25), 83)
		draw_rect(Rect2(pos + Vector2(-35, -62), Vector2(70, 6)), Color("#272626"))
		draw_rect(Rect2(pos + Vector2(-35, -62), Vector2(70.0 * enemy.hp / enemy.max_hp, 6)), Color("#f5ac70"))
		var names: Dictionary = {"rush": "冲撞", "shooter": "远射", "bomber": "自爆", "summoner": "召唤", "boss": "守关主祟"}
		draw_string(_font, pos + Vector2(-35, -75), names[enemy.behavior], HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	for shot in simulation.projectiles:
		draw_circle(shot.pos, 9, Color("#ffa96e"))
	var frame: int = int(_elapsed_frame * 7) % 4
	_sprite(_hero, frame, 4, 4, simulation.player_pos + Vector2(0, 25), 100)
	_sprite(_companion, 0, 3, 2, simulation.player_pos + Vector2(-54, 40), 55)
	if _attack_flash > 0:
		draw_arc(simulation.player_pos, 85, -PI * 0.8, PI * 0.8, 22, Color(1, 0.88, 0.5, _attack_flash * 4), 5)
	if fight.shield > 0:
		draw_arc(simulation.player_pos, 44, 0, TAU, 40, Color("#b0def4"), 3)
	draw_string(_font, Vector2(60, 45), str(encounter.get("title", "主题试炼")), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#f1dca5"))
	_bar(Vector2(60, 93), float(fight.player_hp) / float(fight.player.hp), Color("#87bda3"), "气血 %d · 护盾 %d" % [fight.player_hp, fight.shield])
	draw_string(_font, Vector2(650, 85), "第 %d / 3 波 · 法宝 %d / 100" % [mini(simulation.wave + 1, 3), fight.energy], HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(_font, Vector2(650, 123), "WASD 移动 · 鼠标瞄准 / 左键普攻 · P 暂停", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#b0c3c2"))
	draw_string(_font, Vector2(60, 803), message, HORIZONTAL_ALIGNMENT_LEFT, 1280, 23, Color("#f2ddb0"))
	var skill_names: Dictionary = {"wood": "木 · 回春藤", "fire": "火 · 赤焰", "earth": "土 · 厚土盾", "metal": "金 · 穿云", "water": "水 · 凝霜"}
	draw_string(_font, Vector2(60, 855), "%s · Q 冷却 %.1fs" % [skill_names[fight.player.element], fight.skill_cd], HORIZONTAL_ALIGNMENT_LEFT, -1, 23)
	if paused:
		draw_rect(Rect2(430, 330, 580, 150), Color(0.05, 0.1, 0.14, 0.95))
		draw_string(_font, Vector2(535, 415), "已暂停 · P 继续 / Esc 返回", HORIZONTAL_ALIGNMENT_LEFT, -1, 27)
