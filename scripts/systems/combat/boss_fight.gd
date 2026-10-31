extends RefCounted
## Boss 战：包装 combat_fight.gd，在 Boss 血量跨过阈值时切换阶段与五行属性。
## 阶段只前进不回退；一次重击跨越多个阶段时直接进入最终阶段。战果仍只是一局游戏的胜负。
const Fight = preload("res://scripts/systems/combat/combat_fight.gd")
const Phases = preload("res://scripts/systems/combat/boss_phases.gd")
const Minions = preload("res://scripts/systems/combat/boss_minions.gd")
var fight: RefCounted
var minions: RefCounted = Minions.new()
var allies: RefCounted = null
var elements: Array = []
var phase: int = 0
var phase_changes: Array = []
var valid: bool = false

## party 为可选的 AI 队友（party_ai.gd）；队伍灵根交给底层计算相生加成，party_elements 参数在有队友时被忽略。
func _init(player_snapshot: Dictionary, boss_snapshot: Dictionary, rng: RandomNumberGenerator, phase_elements: Array, party_elements: Array = [], party: RefCounted = null) -> void:
	elements = phase_elements.duplicate()
	if not Phases.valid_config(elements):
		return
	allies = party
	var team: Array = party_elements
	if allies != null:
		team = allies.party_elements(str(player_snapshot.get("element", "")))
	var boss: Dictionary = boss_snapshot.duplicate(true)
	boss["element"] = elements[0]
	fight = Fight.new(player_snapshot, boss, rng, team)
	valid = fight.valid

func player_attack() -> Dictionary:
	if not valid:
		return {"ok": false, "reason": "INVALID"}
	# 有存活小怪时近攻先打小怪：Boss 不掉血，冷却与暴击随机仍由底层统一处理。
	var on_minion: bool = minions.alive() > 0
	var swing: Dictionary = fight.player_attack(not on_minion)
	if swing.ok:
		if on_minion:
			var struck: Dictionary = minions.hit_first(int(swing.damage))
			swing["target"] = "minion"
			swing["minion_defeated"] = struck.get("defeated", false)
		else:
			swing["target"] = "boss"
			_sync_phase()
	swing["phase"] = phase
	return swing

func player_dodge() -> Dictionary:
	return fight.player_dodge() if valid else {"ok": false, "reason": "INVALID"}

## 出招威力随阶段提高；闪避无敌窗口仍由底层战斗处理。
func enemy_attack() -> Dictionary:
	if not valid:
		return {"ok": false, "reason": "INVALID"}
	var hit: Dictionary = fight.enemy_attack(Phases.power(phase), minions.chip_damage())
	hit["phase"] = phase
	return hit

func step(delta: float) -> void:
	if valid:
		fight.step(delta)
		if allies != null and not fight.finished:
			allies.step(delta)

## 取出已就绪的队友出手并结算：有存活小怪时先打小怪，否则扣 Boss 血量并同步阶段。
## 每项返回 {"index", "damage", "target"}；战斗结束后不再出手。
func ally_strikes() -> Array:
	var done: Array = []
	if not valid or allies == null or fight.finished:
		return done
	var on_minion: bool = minions.alive() > 0
	var target_element: String = minions.minions[_first_alive()].element if on_minion else str(fight.enemy.element)
	var defense: float = 0.0 if on_minion else float(fight.enemy.defense)
	for strike in allies.ready_attacks(target_element, defense):
		if fight.finished:
			break
		var current_minion: bool = minions.alive() > 0
		var victim_element: String = str(minions.minions[_first_alive()].element) if current_minion else str(fight.enemy.element)
		var victim_defense: float = 0.0 if current_minion else float(fight.enemy.defense)
		var rules = preload("res://scripts/systems/combat/combat_rules.gd")
		var team_bonus: float = rules.generation_bonus(allies.party_elements(str(fight.player.element)))
		strike["damage"] = rules.damage(float(allies.allies[int(strike.index)].attack) * (1.0 + team_bonus), victim_defense, rules.element_multiplier(str(allies.allies[int(strike.index)].element), victim_element), false)
		if minions.alive() > 0:
			minions.hit_first(int(strike.damage))
			strike["target"] = "minion"
		else:
			fight.apply_ally_damage(int(strike.damage))
			strike["target"] = "boss"
			_sync_phase()
		done.append(strike)
	return done

func _first_alive() -> int:
	for index in range(minions.minions.size()):
		if minions.minions[index].hp > 0:
			return index
	return 0

## 当前阶段的出招间隔与召唤数，供关卡场景驱动。
func attack_interval() -> float:
	return Phases.attack_interval(phase)

func summon_count() -> int:
	return Phases.summon_count(phase)

func finished() -> bool:
	return valid and fight.finished

func result() -> Dictionary:
	return fight.result() if valid else {}

func _sync_phase() -> void:
	var target: int = Phases.phase_index(fight.enemy_hp, int(fight.enemy.hp))
	if target > phase:
		phase = target
		fight.enemy["element"] = elements[phase]
		phase_changes.append(phase)
		minions.summon(Phases.summon_count(phase), elements[phase])
