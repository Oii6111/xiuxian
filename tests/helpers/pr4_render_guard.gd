extends RefCounted
## Rendering choreography uses real shield/dodge inputs and visible poses, never extra HP.
const Brain = preload("res://scripts/systems/combat/pr4_boss_brain.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")

static func step(view: Control) -> void:
	if view.rules.finished or view.rules.brain==null: return
	var rules: RefCounted = view.rules
	var brain: RefCounted = rules.brain
	var kind: String = str(brain.move.get("kind",""))
	var signature: bool = brain.move.has("signature")
	var imminent: bool = not signature and brain.phase=="windup" and brain.progress()>.86 and kind!="leap"
	imminent = imminent or (not signature and brain.phase=="attack" and kind=="leap" and brain.progress()>.80)
	for shot in brain.projectiles:
		if not shot.spent and view.hero.position.distance_to(shot.position)<65: imminent=true
	for add in rules.adds:
		if add.hp>0 and add.phase=="windup" and add.clock>.57 and view.hero.position.distance_to(add.target)<85: imminent=true
	if brain.phase=="windup" and brain.progress()>.65 and rules.shield_cd<=0: view.use_skill(2)
	var signature_escape := _signature_escape(brain, view.hero.position) if signature else Vector2.ZERO
	imminent = imminent or not signature_escape.is_zero_approx()
	if imminent and rules.dodge_cd<=0:
		var escape: Vector2 = (view.hero.position-rules.boss_position).normalized()
		if kind in ["charge","beam"]: escape=Vector2(0,1 if view.hero.position.y<570 else -1)
		if not signature_escape.is_zero_approx(): escape=signature_escape
		if escape.is_zero_approx():escape=Vector2.LEFT
		view.facing=escape
		view.use_skill(1)

static func _signature_escape(brain: RefCounted, hero: Vector2) -> Vector2:
	var zones: Array = brain.signature_zones()
	if zones.is_empty():
		return Vector2.ZERO
	var until := float(zones[0].profile.at) - float(brain.phase_clock)
	if brain.phase == "windup":
		until += float(brain.phase_duration)
	if until > .20 or not zones.any(func(zone): return Patterns.hits(zone.profile, hero)):
		return Vector2.ZERO
	for i in range(8):
		var direction := Vector2.from_angle(i * TAU / 8.0)
		var landing := Brain.clamp_floor(hero + direction * 145.0)
		if not zones.any(func(zone): return Patterns.hits(zone.profile, landing)):
			return direction
	return (hero - Vector2(brain.position)).normalized()
