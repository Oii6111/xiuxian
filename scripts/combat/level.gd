extends Control
## 单人关卡最小可玩场景：走位、近攻、闪避、敌人预兆出手。数值全部来自 combat_fight.gd 的纯规则。
## 本场景不增加任何资源；带 session_id 时只向内核上报一次战果，奖励由服务端结算。
## 快照默认是演示数据；正式接入后由 combat.start 返回的属性快照覆盖。
signal finished(result: Dictionary)
signal left
const HERO_ART = preload("res://assets/pixel/cultivator-walk.png")
const BOSS_ART = preload("res://assets/pixel_campaign/boss_sheet_e.png")
const MINION_ART = preload("res://assets/pixel_campaign/minion_sheet.png")
const ARENA_ART = preload("res://assets/pixel_campaign/map_final.png")
const Fight = preload("res://scripts/systems/combat/combat_fight.gd")
const BossFight = preload("res://scripts/systems/combat/boss_fight.gd")
const PartyAi = preload("res://scripts/systems/combat/party_ai.gd")
const ELEMENT_NAMES: Dictionary = {"wood": "木", "fire": "火", "earth": "土", "metal": "金", "water": "水"}
const ARENA := Rect2(60, 140, 1320, 660)
const STRIKE_RANGE: float = 150.0
const ENEMY_REACH: float = 190.0
var session_id: String = ""
var kernel: Node = null
var reporting: bool = false
var report_ok: bool = false
var paused: bool = false
var _leaving: bool = false
var _emitted: bool = false
var player_snapshot: Dictionary = {"hp": 120, "attack": 22, "defense": 5, "crit_rate": 0.15, "element": "wood"}
var enemy_snapshot: Dictionary = {"hp": 160, "attack": 14, "defense": 4, "crit_rate": 0.0, "element": "earth"}
## Boss 模式默认关闭；开启后敌人按三阶段切换五行属性、加快出招并加重威力，同时召唤小怪。
var boss_mode: bool = false
var boss_elements: Array = ["fire", "metal", "wood"]
## 队友默认关闭；开启后 Boss 模式下会有一位水灵根 AI 队友自动出手。
var allies_enabled: bool = false
var party: RefCounted = null
var boss: RefCounted
var shown_phase: int = 0
var fight: RefCounted
var player_pos := Vector2(300, 470)
var enemy_pos := Vector2(1080, 470)
var telegraph: float = -1.0
var wait: float = 2.0
var ended: bool = false
var reported: bool = false
var message: String = "J 攻击 · 空格 闪避 · WASD 移动 · Esc 离开"
var _font: SystemFont

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "KaiTi"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if boss_mode:
		if allies_enabled:
			party = PartyAi.new()
			party.add_ally("water", 12)
		boss = BossFight.new(player_snapshot, enemy_snapshot, rng, boss_elements, [], party)
		fight = boss.fight if boss.valid else null
	else:
		fight = Fight.new(player_snapshot, enemy_snapshot, rng)
	if fight == null or not fight.valid:
		ended = true
		message = "属性快照无效，无法开始战斗"

func _process(delta: float) -> void:
	if ended:
		queue_redraw()
		return
	if paused:
		return
	fight.step(delta)
	fight.companion_step(delta)
	if boss_mode and party != null:
		party.step(delta)
		for strike in boss.ally_strikes():
			message = "队友出手 %d 点伤害（打%s）" % [int(strike.damage), "小怪" if strike.target == "minion" else "Boss"]
	_check_end()
	if ended:
		return
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	player_pos += direction.normalized() * 260.0 * delta
	player_pos = Vector2(clampf(player_pos.x, ARENA.position.x, ARENA.end.x), clampf(player_pos.y, ARENA.position.y, ARENA.end.y))
	var gap: float = enemy_pos.distance_to(player_pos)
	if telegraph < 0.0:
		if gap > 120.0:
			enemy_pos += enemy_pos.direction_to(player_pos) * 70.0 * delta
		wait -= delta
		if wait <= 0.0:
			telegraph = 0.8
	else:
		telegraph -= delta
		if telegraph <= 0.0:
			telegraph = -1.0
			wait = boss.attack_interval() if boss_mode else 2.0
			if gap <= ENEMY_REACH:
				var hit: Dictionary = boss.enemy_attack() if boss_mode else fight.enemy_attack()
				message = "已闪避" if hit.get("evaded", false) else "受到 %d 点伤害" % int(hit.get("damage", 0))
			else:
				message = "敌人挥空"
	_check_end()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		attack()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_J:
			attack()
		KEY_SPACE:
			dodge()
		KEY_Q:
			skill(false)
		KEY_R:
			if ended:
				retry_report()
			else:
				skill(true)
		KEY_P:
			paused = not paused
			message = "暂停 · P 继续" if paused else "继续战斗"
		KEY_ESCAPE:
			request_leave()

func attack() -> void:
	if ended or paused:
		return
	if enemy_pos.distance_to(player_pos) > STRIKE_RANGE:
		message = "距离太远"
		return
	var swing: Dictionary = boss.player_attack() if boss_mode else fight.player_attack()
	if swing.ok:
		if boss_mode and swing.get("target", "boss") == "minion":
			message = "击中小怪 %d 点伤害%s · 剩余 %d 只" % [int(swing.damage), "（会心）" if swing.crit else "", boss.minions.alive()]
		else:
			message = "造成 %d 点伤害%s" % [int(swing.damage), "（会心）" if swing.crit else ""]
		if boss_mode and boss.phase != shown_phase:
			shown_phase = boss.phase
			message += " · 第%d阶段 · 属性转为%s" % [shown_phase + 1, ELEMENT_NAMES[boss.elements[shown_phase]]]
			if boss.minions.alive() > 0:
				message += " · 召唤了 %d 只小怪" % boss.minions.alive()
	else:
		message = "冷却中"
	_check_end()

func dodge() -> void:
	if ended:
		return
	message = "闪避" if fight.player_dodge().ok else "闪避冷却中"

func _check_end() -> void:
	if ended or fight == null or not fight.finished:
		return
	ended = true
	message = "胜利 · Esc 返回" if fight.won else "战败 · Esc 返回（不扣任何资源）"
	_report()

## 同一局只上报一次；重复上报也会被模块按 session_id 幂等处理。
func _report() -> void:
	if fight == null:
		return
	var outcome: Dictionary = fight.result()
	if outcome.is_empty():
		return
	if not _emitted:
		_emitted = true
		finished.emit(outcome)
	if session_id.is_empty():
		report_ok = true
		return
	if reporting or report_ok:
		return
	reporting = true
	reported = true
	var transport: Node = kernel if kernel != null else get_node_or_null("/root/GameKernel")
	var response: Dictionary = {"ok": false, "code": "BACKEND_UNAVAILABLE"}
	if transport != null:
		response = await transport.dispatch("combat.finish", {"session_id": session_id, "won": outcome.won, "duration_seconds": outcome.duration_seconds})
	if not is_inside_tree():
		return
	reporting = false
	report_ok = bool(response.get("ok", false))
	if not report_ok:
		message = "战果上报失败：" + str(response.code) + " · R 重试 / Esc 返回"
	queue_redraw()

func retry_report() -> void:
	await _report()

func request_leave() -> void:
	if _leaving:
		return
	_leaving = true
	if fight != null and fight.valid and not ended:
		ended = true
		fight.finished = true
		fight.won = false
	await _report()
	_leaving = false
	if not session_id.is_empty() and not report_ok:
		message = "本局战果尚未同步 · R 重试，成功后可返回"
		return
	left.emit()

func skill(ultimate: bool = false) -> void:
	if ended or paused:
		return
	if not ultimate and enemy_pos.distance_to(player_pos) > 420.0:
		message = "目标超出术法范围"
		return
	var on_minion: bool = boss_mode and boss.minions.alive() > 0
	var cast: Dictionary = fight.cast_skill(ultimate, not on_minion)
	if cast.ok:
		if on_minion:
			boss.minions.hit_first(int(cast.damage))
		if boss_mode:
			boss._sync_phase()
		message = ("法宝" if ultimate else "灵根术法") + " · %d 点伤害" % cast.damage
	else:
		message = "法宝能量未满" if cast.reason == "ENERGY" else "术法冷却中"
	_check_end()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.16, 0.14))
	draw_texture_rect(ARENA_ART, ARENA, false, Color(0.55, 0.55, 0.55))
	draw_rect(ARENA, Color(0.8, 0.7, 0.45), false, 3.0)
	if fight == null:
		return
	if telegraph >= 0.0:
		var progress: float = 1.0 - telegraph / 0.8
		draw_arc(enemy_pos, ENEMY_REACH, 0.0, TAU, 48, Color(1.0, 0.3, 0.2, 0.35 + 0.5 * progress), 4.0)
	_draw_sprite(BOSS_ART, 3, 2, 2, enemy_pos + Vector2(0, 50), 150)
	if boss_mode:
		var index: int = 0
		var alive: int = maxi(1, boss.minions.alive())
		for minion in boss.minions.minions:
			if minion.hp > 0:
				var behind: float = (enemy_pos - player_pos).angle()
				var spread: float = deg_to_rad(140.0)
				var angle: float = behind if alive == 1 else behind - spread / 2.0 + spread * index / float(alive - 1)
				var spot: Vector2 = enemy_pos + Vector2(cos(angle), sin(angle)) * 120.0
				_draw_sprite(MINION_ART, index % 10, 5, 2, spot + Vector2(0, 20), 65)
				index += 1
	_draw_sprite(HERO_ART, 0, 4, 4, player_pos + Vector2(0, 35), 110)
	if boss_mode and party != null:
		_draw_sprite(HERO_ART, 4, 4, 4, player_pos + Vector2(-60, 70), 80)
	_bar(Vector2(80, 60), float(fight.player_hp) / float(fight.player.hp), Color(0.4, 0.85, 0.5), "修仙者 %d" % fight.player_hp)
	_bar(Vector2(820, 60), float(fight.enemy_hp) / float(fight.enemy.hp), Color(0.9, 0.45, 0.3), ("Boss 第%d阶段 · %s · %d" % [boss.phase + 1, ELEMENT_NAMES[fight.enemy.element], fight.enemy_hp]) if boss_mode else ("敌人 %d" % fight.enemy_hp))
	draw_string(_font, Vector2(80, 860), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.9, 0.75))

func _bar(origin: Vector2, ratio: float, color: Color, label: String) -> void:
	draw_rect(Rect2(origin, Vector2(520, 26)), Color(0.05, 0.05, 0.05))
	draw_rect(Rect2(origin, Vector2(520.0 * clampf(ratio, 0.0, 1.0), 26)), color)
	draw_string(_font, origin + Vector2(8, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.9, 0.75))

func _draw_sprite(texture: Texture2D, cell: int, columns: int, rows: int, location: Vector2, height: float) -> void:
	var tile := Vector2(texture.get_width() / float(columns), texture.get_height() / float(rows))
	draw_texture_rect_region(texture, Rect2(location - Vector2(height * tile.x / tile.y * 0.5, height), Vector2(height * tile.x / tile.y, height)), Rect2(Vector2(cell % columns, cell / columns) * tile, tile))
