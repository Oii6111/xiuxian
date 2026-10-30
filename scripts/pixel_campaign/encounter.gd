extends RefCounted
const Catalogue = preload("res://scripts/pixel_campaign/catalogue.gd")
## Deterministic X/Z-plane combat. Health presets are snapshotted at entry.
var entry: Dictionary
var snapshot: Dictionary
var difficulty: String = "story"
var hp: float = 360.0
var hp_max: float = 360.0
var stamina: float = 100.0
var stamina_max: float = 100.0
var energy: float = 100.0
var boss_hp: float = 800.0
var boss_max: float = 800.0
var boss_position = Vector2(3.0, -0.8)
var arena = Rect2(-9.0, -6.0, 18.0, 12.0)
var nodes: Array = []
var hazards: Array = []
var minions: Array = []
var feedback: Array = []
var elapsed: float = 0.0
var until_attack: float = 2.4
var attack_cd: float = 0.0
var skill_cd: float = 0.0
var guard_cd: float = 0.0
var dash_cd: float = 0.0
var guard_time: float = 0.0
var dodge_time: float = 0.0
var weak_time: float = 0.0
var flash: float = 0.0
var damage_done: float = 0.0
var hits_taken: int = 0
var perfect_blocks: int = 0
var interactions: int = 0
var avoided_attacks: int = 0
var hurt_immunity: float = 0.0
var cycle: int = 0
var hazard_seq: int = 0
var finished: bool = false
var won: bool = false
var paused: bool = false
var hint: String = ""
var last_hit: String = ""
var selected_skill: String = "雷诀"
var escort = Vector2(-6.5, 3.5)
var escort_done: bool = false
var health_phase: int = 0

func _init(row: Dictionary, state_snapshot: Dictionary = {}, mode: String = "story", skill: String = "雷诀") -> void:
	entry = row.duplicate(true)
	snapshot = state_snapshot.duplicate(true)
	difficulty = mode
	selected_skill = skill
	hp_max = 420.0 if mode == "story" else 300.0
	hp = hp_max
	stamina_max = 100.0 * float(snapshot.get("stamina", 1.0))
	stamina = stamina_max
	boss_max = 800.0 + float(entry.get("tier", 1)) * 200.0
	if entry.id == "b00":
		boss_max = 320.0
	elif entry.id == "b19":
		boss_max = 3200.0
	boss_hp = boss_max
	hint = entry.objective_hint
	_make_nodes()
	_make_minions()

func _make_nodes() -> void:
	nodes.clear()
	if entry.id == "b00":
		return
	var count = 4 if entry.id in ["b09", "b18"] else (5 if entry.id == "b19" else (2 if entry.id == "b14" else 3))
	var points = [Vector2(-5.0,-2.5),Vector2(-4.0,3.4),Vector2(1.0,4.1),Vector2(5.5,3.2),Vector2(6.0,-3.7)]
	for i in range(count):
		var text = ["左阵","近阵","远阵","后阵","中阵"][i]
		var labels = {"b01":"支架","b02":"榫卯","b03":"根瘤","b04":"回声鼓","b05":"灯台","b06":"赤晶","b07":"渠壁","b08":"路灯","b09":"灵渠","b10":"风闸","b11":"散雾口","b12":"玉环","b13":"泉眼","b14":"水轮","b15":"量水碑","b16":"余灯","b18":"残痕","b19":"归衡印"}
		text = str(labels.get(entry.id,"阵眼")) + str(i+1)
		if entry.id == "b17":
			text = ["茶杯","归家","渡口"][i]
		nodes.append({"position":points[i],"done":false,"label":text,"hp":2})

func clamp_position(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, arena.position.x + 0.6, arena.end.x - 0.6), clampf(point.y, arena.position.y + 0.6, arena.end.y - 0.6))

func remaining_nodes() -> int:
	var count = 0
	for node in nodes:
		if not node.done:
			count += 1
	return count

func nearest_node(position: Vector2, radius: float = 1.9) -> int:
	var nearest = -1
	var distance = radius
	for i in range(nodes.size()):
		if nodes[i].done:
			continue
		var d = position.distance_to(nodes[i].position)
		if d < distance:
			distance = d
			nearest = i
	return nearest

func interact(position: Vector2) -> bool:
	if finished or paused:
		return false
	if entry.id == "b11" and not escort_done:
		hint = "先靠近金色羽灯伴行，送到对侧安全庭；这段护送不能用阵眼操作代替。"
		return false
	var index = nearest_node(position)
	if index < 0:
		hint = "靠近发光阵眼按 E · " + entry.objective_hint
		return false
	if entry.id == "b17":
		var order = [2,0,1]
		if index != order[interactions]:
			hint = "路标顺序一直可查：渡口 → 茶杯 → 归家。此处暂不需要操作。"
			return false
	_activate_node(index)
	return true

func _activate_node(index: int) -> void:
	if nodes[index].done:
		return
	nodes[index].done = true
	interactions += 1
	stamina = minf(stamina_max, stamina + 12.0)
	energy = minf(100.0, energy + 12.0)
	weak_time = 4.5
	if remaining_nodes() == 0:
		weak_time = 9.0
		hint = "阵眼已复位！护障解除，抓住反击窗口。"
		feedback.append({"kind":"objective","text":"护障解除","position":boss_position})
	else:
		hint = "已处理 %d / %d · 继续观察，或趁现在进攻。" % [interactions, nodes.size()]
	feedback.append({"kind":"interact","text":"阵眼归位","position":nodes[index].position})

func attack(position: Vector2) -> Dictionary:
	if finished or paused or attack_cd > 0.0:
		return {"ok":false}
	attack_cd = 0.42
	var mob = nearest_minion(position,3.3)
	if mob >= 0:
		return _damage_minion(mob,58.0 * float(snapshot.get("attack",1.0)))
	var node = nearest_node(position, 2.2)
	if node >= 0 and entry.id == "b11" and not escort_done:
		hint = "护灯途中无需击破阵眼。靠近羽灯伴行，送到安全庭。"
		return {"ok":true,"damage":0.0,"blocked_by_objective":true,"position":nodes[node].position}
	if node >= 0 and entry.id != "b17":
		nodes[node].hp -= 1
		if nodes[node].hp <= 0:
			_activate_node(node)
		return {"ok":true,"damage":0,"node":true,"position":nodes[node].position}
	if position.distance_to(boss_position) > 3.6:
		hint = "离劫核太远，靠近出手；也可用 1 施放远程功法。"
		return {"ok":true,"damage":0,"miss":true,"position":position}
	return _damage_boss(58.0 * float(snapshot.get("attack",1.0)))

func cast(position: Vector2) -> Dictionary:
	if finished or paused or skill_cd > 0.0 or energy < 24.0:
		return {"ok":false}
	if position.distance_to(boss_position) > 10.5:
		hint = "功法距离不足，向场中靠近。"
		return {"ok":false}
	skill_cd = 6.0 if selected_skill == "分流" else 3.4
	energy -= 24.0
	var power = 126.0
	if selected_skill == "分流":
		hp = minf(hp_max, hp + 25.0)
		weak_time = maxf(weak_time, 2.0)
		power = 72.0
	elif selected_skill == "镇心":
		guard_time = maxf(guard_time, 2.0)
		power = 85.0
	var amount = power * float(snapshot.get("attack",1.0))
	var mob = nearest_minion(position,8.0)
	if mob >= 0:
		return _damage_minion(mob,amount)
	return _damage_boss(amount)

func _damage_boss(amount: float) -> Dictionary:
	if living_minions() > 0:
		hint = "先收拢散祟，再破主阵。主祟护障仍在。"
		return {"ok":true,"damage":0.0,"blocked_by_prelude":true,"position":boss_position}
	if entry.id != "b00" and ((entry.id == "b11" and not escort_done) or remaining_nodes() > 0):
		hint = "先把金色羽灯送到对侧安全庭，再破主祟护障。" if entry.id == "b11" else ("先按路标顺序完成：渡口 → 茶杯 → 归家，再反击主祟。" if entry.id == "b17" else "先完成%s（还剩%d处），再打破主祟护障。" % [entry.objective_title,remaining_nodes()])
		return {"ok":true,"damage":0.0,"blocked_by_objective":true,"position":boss_position}
	var actual = minf(boss_hp, amount * (1.2 if weak_time > 0 else 1.0))
	boss_hp -= actual
	damage_done += actual
	flash = 0.18
	feedback.append({"kind":"damage","text":"-%d" % roundi(actual),"position":boss_position})
	if boss_hp <= 0 and entry.id == "b00" and perfect_blocks + avoided_attacks == 0:
		boss_hp = 1
		hint = "试灯最后一步：移开一次落雷，或在命中前按 K 护盾，再反击。"
	elif boss_hp <= 0:
		finished = true
		won = true
		hazards.clear()
	return {"ok":true,"damage":actual,"position":boss_position}

func guard() -> bool:
	if finished or paused or guard_cd > 0.0:
		return false
	guard_time = 1.35
	guard_cd = 3.8
	return true

func dash() -> bool:
	if finished or paused or dash_cd > 0.0 or stamina < 24.0:
		return false
	dash_cd = 1.1
	dodge_time = 0.38
	stamina -= 24.0
	return true

func step(delta: float, position: Vector2) -> void:
	if finished or paused:
		return
	var dt = clampf(delta, 0, 0.1)
	elapsed += dt
	for field in ["attack_cd","skill_cd","guard_cd","dash_cd","guard_time","dodge_time","weak_time","flash","hurt_immunity"]:
		set(field, maxf(0.0, float(get(field)) - dt))
	stamina = minf(stamina_max, stamina + dt * 17.0)
	energy = minf(100.0, energy + dt * 8.0)
	if entry.id == "b11" and not escort_done and position.distance_to(escort) < 3.5:
		escort.x = minf(6.0, escort.x + dt * 1.4)
		if escort.x >= 6.0:
			escort_done = true
			for i in range(nodes.size()):
				_activate_node(i)
			hint = "羽灯已到安全庭！护障解除。"
	if entry.id == "b19":
		var phase = mini(4, int((1.0 - boss_hp / boss_max) * 5.0))
		if phase != health_phase:
			health_phase = phase
			hint = ["木行接枝","火行蓄势","土行分流","金行开合","水行伏澜"][phase] + " · 留意接下来的预兆。"
	var survivors: Array = []
	for hazard in hazards:
		hazard.timer -= dt
		if hazard.timer <= 0.0 and not hazard.active:
			hazard.active = true
			hazard.life = 0.42
			if hazard.shape == "charge":
				boss_position = clamp_position(hazard.end)
		if hazard.active:
			hazard.life -= dt
			if not hazard.hit and contains(hazard, position):
				hazard.hit = true
				_take_hit(hazard)
		if hazard.active and hazard.life <= 0.0 and not hazard.hit:
			avoided_attacks += 1
			feedback.append({"kind":"evade","text":"避开了 · 可以反击","position":Vector2.ZERO})
		if not hazard.active or hazard.life > 0.0:
			survivors.append(hazard)
	hazards = survivors
	_step_minions(dt,position)
	if living_minions() > 0:
		until_attack = maxf(until_attack,1.4)
	else:
		until_attack -= dt
	if until_attack <= 0.0:
		_prepare_attack(position)

func _take_hit(hazard: Dictionary) -> void:
	if hurt_immunity > 0.0:
		return
	if dodge_time > 0.0:
		feedback.append({"kind":"evade","text":"闪避成功","position":Vector2.ZERO})
		energy = minf(100.0, energy + 8.0)
		return
	if guard_time > 0.0:
		perfect_blocks += 1
		weak_time = maxf(weak_time, 2.2)
		feedback.append({"kind":"block","text":"守住！反击窗口","position":Vector2.ZERO})
		return
	var damage = 27.0 if difficulty == "story" else 45.0
	if hazard.get("minion",false):
		damage *= 0.45
	if entry.id == "b00":
		damage *= 0.45
	hp = maxf(0.0, hp - damage)
	hurt_immunity = 0.6
	hits_taken += 1
	last_hit = hazard.label
	hint = "受到「%s」伤害。%s" % [last_hit, entry.tell]
	feedback.append({"kind":"hurt","text":"-%d" % int(damage),"position":Vector2.ZERO})
	if hp <= 0:
		finished = true
		won = false

func _prepare_attack(target: Vector2) -> void:
	cycle += 1
	var patterns: Array = entry.patterns
	var kind: String = patterns[(cycle - 1) % patterns.size()]
	if entry.id == "b19":
		kind = patterns[health_phase]
	var warn = 1.65 if difficulty == "story" else 1.15
	if entry.id == "b04":
		warn += [0.35,0.0,0.55][cycle % 3]
	until_attack = warn + (2.1 if remaining_nodes() == 0 else 1.6)
	hint = entry.attack_name + " · " + entry.tell
	match kind:
		"circle":
			_spawn("circle", target, 1.75, warn)
		"line":
			_line(boss_position, target, 1.15, warn)
		"charge":
			_line(boss_position, target, 1.4, warn, true)
		"cross":
			_line(Vector2(-8.0,target.y),Vector2(8.0,target.y),0.9,warn)
			_line(Vector2(target.x,-5.0),Vector2(target.x,5.0),0.9,warn)
		"ring":
			var radius = 3.5 + float(cycle % 2)
			_spawn("ring", boss_position, radius, warn, 0.8)
		"cone":
			var h = _spawn("cone",boss_position,8.0,warn)
			h.angle = (target - boss_position).angle()
			h.half_angle = 0.50
		"corridor":
			# Two flanks leave a safe corridor down the middle.
			_line(Vector2(-7,-3.4),Vector2(7,-3.4),1.35,warn)
			_line(Vector2(-7,3.4),Vector2(7,3.4),1.35,warn)
		"roots":
			_spawn("circle",target,1.65,warn)
			for node in nodes:
				if not node.done:
					_line(boss_position,node.position,0.55,warn + 0.2)
					break
		"pulse":
			_spawn("ring",boss_position,2.5,warn,0.65)
			_spawn("ring",boss_position,5.2,warn + 0.7,0.65)

func _spawn(shape: String, position: Vector2, radius: float, warn: float, width: float = 0.8) -> Dictionary:
	hazard_seq += 1
	var h = {"id":hazard_seq,"shape":shape,"position":position,"end":position,"radius":radius,"width":width,"timer":warn,"warning":warn,"active":false,"life":0.42,"hit":false,"label":entry.attack_name,"angle":0.0,"half_angle":0.5}
	hazards.append(h)
	return h

func _line(start: Vector2, target: Vector2, width: float, warn: float, charge: bool = false) -> void:
	var end = target
	if start.distance_to(target) < 0.1:
		end = target + Vector2.LEFT * 5.0
	var h = _spawn("charge" if charge else "line", start, 0.0, warn, width)
	h.end = end

func contains(hazard: Dictionary, position: Vector2) -> bool:
	var distance = position.distance_to(hazard.position)
	match hazard.shape:
		"circle":
			return distance <= hazard.radius + 0.25
		"ring":
			return absf(distance - hazard.radius) <= hazard.width + 0.2
		"line", "charge":
			var point = Geometry2D.get_closest_point_to_segment(position, hazard.position, hazard.end)
			return position.distance_to(point) <= hazard.width + 0.25
		"cone":
			if distance < 0.5:
				return true
			var angle = (position - hazard.position).angle()
			return distance <= hazard.radius and absf(wrapf(angle - hazard.angle, -PI, PI)) <= hazard.half_angle
	return false

func objective_text() -> String:
	if living_minions() > 0:
		return "清障：散祟 %d只 · J近身 / 1远程 · 看预兆躲开" % living_minions()
	if entry.id == "b00":
		return "观察预兆 → 移开 / 护盾 → 反击"
	if entry.id == "b17":
		return "路标：渡口 → 茶杯 → 归家（随时可查）  %d/3" % interactions
	if entry.id == "b11" and not escort_done:
		return "靠近金色羽灯伴行，送到场地另一侧"
	return "%s  %d/%d · E 操作，J 也可击破一般节点" % [entry.objective_title,interactions,nodes.size()]

func _make_minions() -> void:
	var rows = Catalogue.minions_for(str(entry.region))
	if rows.is_empty():
		return
	for i in range(rows.size()):
		var row = rows[i]
		minions.append({"id":row.id,"name":row.name,"hp":float(row.hp),"max_hp":float(row.hp),"position":Vector2(-3.7+float(i)*3.2,1.0+float(i)*2.0),"cooldown":2.2+float(i)*1.3,"pattern":row.pattern,"attack":row.attack})
	if not minions.is_empty():
		hint = "先收拢散祟，再破主阵。小怪退散会恢复少量真气与体力。"

func living_minions() -> int:
	var count = 0
	for mob in minions:
		if mob.hp > 0:
			count += 1
	return count

func nearest_minion(position: Vector2,radius: float) -> int:
	var closest = radius
	var index = -1
	for i in range(minions.size()):
		if minions[i].hp <= 0:
			continue
		var d = position.distance_to(minions[i].position)
		if d < closest:
			closest = d
			index = i
	return index

func _damage_minion(index: int,amount: float) -> Dictionary:
	var mob = minions[index]
	var actual = minf(mob.hp,amount)
	mob.hp -= actual
	feedback.append({"kind":"damage","text":"-%d" % roundi(actual),"position":mob.position})
	if mob.hp <= 0:
		hazards = hazards.filter(func(h): return h.get("source","") != mob.id)
		energy = minf(100.0,energy+12.0)
		stamina = minf(stamina_max,stamina+10.0)
		feedback.append({"kind":"minion_defeat","text":mob.name+" · 收拢","position":mob.position,"id":mob.id})
		if living_minions()==0:
			until_attack = 2.2
			hint = "散祟已收拢，接下来观察主祟。" + entry.objective_hint
	return {"ok":true,"damage":actual,"minion":true,"position":mob.position}

func _step_minions(dt: float,position: Vector2) -> void:
	for mob in minions:
		if mob.hp <= 0:
			continue
		# Readable stationary tells: one attack at a time, no invisible rush.
		mob.cooldown -= dt
		if mob.cooldown > 0:
			continue
		mob.cooldown = 4.8
		var warning = 1.5 if difficulty=="story" else 1.1
		var h: Dictionary
		match str(mob.pattern):
			"line":
				var before = hazards.size()
				_line(mob.position,position,0.55,warning)
				h = hazards[before]
			"ring":
				h = _spawn("ring",mob.position,2.1,warning,0.40)
			"cone":
				h = _spawn("cone",mob.position,4.5,warning)
				h.angle = (position-mob.position).angle()
				h.half_angle = 0.45
			_:
				h = _spawn("circle",position,1.0,warning)
		h.label = mob.name+" · "+mob.attack
		h["minion"] = true
		h["source"] = mob.id
