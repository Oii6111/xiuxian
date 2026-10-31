extends RefCounted
## Rendering choreography uses real shield/dodge inputs and visible poses, never extra HP.
static func step(view: Control) -> void:
	if view.rules.finished or view.rules.brain==null: return
	var rules: RefCounted = view.rules
	var brain: RefCounted = rules.brain
	var kind: String = str(brain.move.get("kind",""))
	var imminent: bool = brain.phase=="windup" and brain.progress()>.86 and kind!="leap"
	imminent = imminent or (brain.phase=="attack" and kind=="leap" and brain.progress()>.80)
	for shot in brain.projectiles:
		if not shot.spent and view.hero.position.distance_to(shot.position)<65: imminent=true
	for add in rules.adds:
		if add.hp>0 and add.phase=="windup" and add.clock>.57 and view.hero.position.distance_to(add.target)<85: imminent=true
	if brain.phase=="windup" and brain.progress()>.65 and rules.shield_cd<=0: view.use_skill(2)
	if imminent and rules.dodge_cd<=0:
		var escape: Vector2 = (view.hero.position-rules.boss_position).normalized()
		if kind in ["charge","beam"]: escape=Vector2(0,1 if view.hero.position.y<570 else -1)
		if escape.is_zero_approx():escape=Vector2.LEFT
		view.facing=escape
		view.use_skill(1)
