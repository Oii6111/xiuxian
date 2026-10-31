extends Node2D
const Actions = preload("res://scripts/systems/combat/action_atlas.gd")
## Pixel-snapped 2D ink, cloud and jade effects; no 3D resources.
var view: Control
var ground_only: bool = false

func _process(_delta: float) -> void:
	queue_redraw()

func ellipse(center: Vector2, radius: Vector2, color: Color, width: float = 2) -> void:
	var points = PackedVector2Array()
	for i in range(49):
		var angle = i * TAU / 48
		points.append((center + Vector2(cos(angle), sin(angle)) * radius).snapped(Vector2(3, 3)))
	draw_polyline(points, color, width)

func cloud(center: Vector2, scale_value: float, alpha: float) -> void:
	for i in range(3):
		var points = PackedVector2Array()
		for j in range(20):
			var angle = j * TAU / 19
			var radius = 4 + j * 0.75
			points.append((center + Vector2((i - 1) * 20 + cos(angle) * radius, sin(angle) * radius * 0.6) * scale_value).snapped(Vector2(3, 3)))
		draw_polyline(points, Color(0.72, 0.94, 0.9, alpha), 3)

func bolt(from: Vector2, to: Vector2, time: float) -> void:
	var points = PackedVector2Array()
	for i in range(13):
		var point = from.lerp(to, i / 12.0)
		if i > 0 and i < 12:
			point.x += sin(i * 31.3 + floor(time * 20)) * 28
		points.append(point.snapped(Vector2(3, 3)))
	draw_polyline(points, Color(0.7, 0.38, 0.9, 0.2), 18)
	draw_polyline(points, Color(view.encounter.color).lightened(0.25) if not view.encounter.is_empty() else Color("d69df0"), 4)

func _draw() -> void:
	if not is_instance_valid(view) or not is_instance_valid(view.hero):
		return
	var rules = view.rules
	var time: float = view.clock
	if view.companion_flash > 0 and is_instance_valid(view.companion_sprite):
		draw_line(view.companion_sprite.position + Vector2(0, -55), view.boss_anchor + Vector2(0, -80), Color(0.8, 0.95, 0.7, view.companion_flash * 2), 3)

	var hero: Vector2 = view.hero.position
	if ground_only:
		_ground()
		return
	if rules.brain != null and not rules.finished:
		_boss_effects()
	elif rules.brain == null and rules.phase == "breath" and not rules.finished:
		bolt(view.boss_anchor+Vector2(-60,-view.boss_height*.55),rules.target_position,time)
	_challenge_effects()
	if rules.shield_time > 0 and rules.shield_hp > 0:
		var center = hero + Vector2(0, -74)
		ellipse(center, Vector2(63, 83), Color("b4e5e3"), 4)
		ellipse(center, Vector2(68, 88), Color(0.65, 0.9, 0.9, 0.2), 7)
		for i in range(3):
			var angle = time * 1.9 + i * TAU / 3
			cloud(center + Vector2(cos(angle) * 58, sin(angle) * 73), 0.55, 0.9)
		if view.shield_impact > 0:
			ellipse(center, Vector2(74, 94) * (1.0 + (0.6 - view.shield_impact) * 0.3), Color(0.12, 0.3, 0.28, view.shield_impact), 5)
	if view.shield_break_visual > 0:
		var spread = (0.55 - view.shield_break_visual) * 95
		for i in range(6):
			var angle = i * TAU / 6
			cloud(hero + Vector2(0, -70) + Vector2(cos(angle), sin(angle)) * (45 + spread), 0.45, view.shield_break_visual)
	if view.dodge_visual > 0:
		for i in range(4):
			var point: Vector2 = view.dodge_origin.lerp(hero, i / 4.0)
			cloud(point + Vector2(0, -16), 1.0 - i * 0.12, view.dodge_visual * (1.6 - i * 0.2))
		cloud(hero + Vector2(0, 2), 1.2, view.dodge_visual * 1.8)
	if view.cast_visual > 0 and view.cast_duration-view.cast_visual>=(.16 if view.sword_visual else .12):
		var impact: float = .16 if view.sword_visual else .12
		var travel = clampf((view.cast_duration-view.cast_visual-impact)/(view.cast_duration-impact),0,1)
		var length = 820.0 if view.sword_visual else 120.0
		var center: Vector2 = view.cast_origin + view.cast_direction * length * travel
		var angle: float = view.cast_direction.angle()
		var arc = PackedVector2Array()
		for i in range(25):
			var a = angle - 1.15 + i * 2.3 / 24
			if not view.sword_visual and view.slash_combo == 2:
				a = angle+1.15-i*2.3/24
			arc.append((center + Vector2(cos(a), sin(a)) * (68 if view.sword_visual else 47)).snapped(Vector2(3, 3)))
		_draw_action_fx("blade",center,travel,Vector2(170,170) if view.sword_visual else Vector2(115,115),.85)
		draw_polyline(arc, Color(0.18, 0.35, 0.3, 0.5), 15 if view.sword_visual else 8)
		draw_polyline(arc, Color("ffe7aa") if view.counter_visual>0 else Color("8fd0b4"), 8 if view.counter_visual>0 else (7 if view.sword_visual else 3))
		if not view.sword_visual and view.slash_combo == 3:
			draw_arc(center,64,angle-1.45,angle+1.45,28,Color(1,.87,.55,.75),5)
		if view.sword_visual:
			draw_polyline(arc, Color("d0efd0"), 2)
			for i in range(8):
				var leaf = center + Vector2(sin(i * 2.2 + time * 8) * 60 - i * 12, (i - 4) * 13)
				leaf = leaf.snapped(Vector2(3, 3))
				draw_colored_polygon(PackedVector2Array([leaf, leaf + Vector2(12, -3), leaf + Vector2(21, 3), leaf + Vector2(9, 6)]), Color("6f9d79"))
	if rules.heal_cast>0 or view.heal_visual>0:
		var jade: Vector2 = hero+Vector2(10,-64)
		var alpha = 0.85 if rules.heal_cast > 0 else view.heal_visual
		for i in range(14):
			var angle = i * TAU / 14 + time * 1.7
			var radius = 20 + fmod(i * 11.0 + time * 55, 110)
			var point = jade + Vector2(cos(angle) * radius, sin(angle) * radius * 0.7)
			draw_rect(Rect2(point.snapped(Vector2(3, 3)), Vector2(4, 4)), Color(0.58, 0.91, 0.72, alpha))
		cloud(hero + Vector2(0, -17), 1.4, alpha)
		ellipse(jade, Vector2(20, 24), Color(1, 0.86, 0.58, alpha), 4)
		if view.heal_visual > 0:
			ellipse(hero + Vector2(0, -70), Vector2(55, 78), Color(0.72, 1, 0.75, view.heal_visual), 5)


func _ground() -> void:
	# Only real shadows and live effects; collision geometry is private to the rules.
	var rules: RefCounted = view.rules
	var shadow = Color(.08,.07,.13,.28)
	draw_circle(view.hero.position,33,shadow)
	if rules.brain == null: return
	var brain: RefCounted = rules.brain
	ellipse(rules.boss_position,Vector2(view.boss_height*.25,23),shadow,14)
	# A lingering attack still has its real flame/root effect, without an area outline.
	for hazard in brain.hazards:
		var profile: Dictionary = hazard.profile
		_draw_action_fx(str(hazard.style),profile.target,fposmod(view.clock*2.2,1),Vector2(profile.radius)*2,.7)
	for add in rules.adds:
		if add.hp > 0:
			ellipse(add.position,Vector2(21,10),shadow,8)
			var at: Vector2 = add.position+Vector2(-18,-80)
			draw_rect(Rect2(at,Vector2(36,4)),Color("362930"))
			draw_rect(Rect2(at,Vector2(36*float(add.hp)/(36+rules.tier/2),4)),Color("d7b66f"))

func _palette(style: String) -> Color:
	match style:
		"fire", "ember": return Color("ffb250")
		"wood", "leaf", "roots": return Color("a8db86")
		"water", "wind": return Color("a8edf1")
		"metal", "seal", "grain": return Color("ffe0a1")
		"stone", "sand": return Color("e6c494")
		"ink": return Color("b9c0e9")
		"crystal": return Color("f9a7a0")
		"moon": return Color("e4d8ff")
	return Color("d9b7ff")

func _burst(center: Vector2, radius: Vector2, style: String, alpha: float, age: float) -> void:
	var color = _palette(style)
	for i in range(12):
		var angle = i*TAU/12 + (0.3 if style == "ink" else 0)
		var offset = Vector2(cos(angle),sin(angle))*radius*(.2+age*1.1)
		var point = (center+offset).snapped(Vector2(3,3))
		var lift = (sin(age*PI)*45 + i%3*9)
		match style:
			"roots", "wood", "crystal", "stone", "grain":
				var height = (22+i%4*12)*sin(minf(1,age*2)*PI/2)
				draw_colored_polygon(PackedVector2Array([point+Vector2(-8,0),point+Vector2(i%3*6-6,-height),point+Vector2(9,-4)]),Color(color,alpha))
			"thunder":
				var points = PackedVector2Array([point+Vector2(0,-58),point+Vector2(-9,-34),point+Vector2(8,-28),point])
				draw_polyline(points,Color(color,alpha),3)
			"water", "wind", "sound":
				draw_arc(point+Vector2(0,-lift*.25),12+age*9,-PI,0,12,Color(color,alpha),3)
			"seal", "moon":
				draw_rect(Rect2(point+Vector2(-5,-lift),Vector2(10,10)),Color(color,alpha),false,2)
			_:
				draw_rect(Rect2(point+Vector2(-3,-lift),Vector2(6,9)),Color(color,alpha))

func _boss_effects() -> void:
	var brain: RefCounted = view.rules.brain
	var move: Dictionary = brain.move
	if move.is_empty():
		return
	var color = _palette(str(move.style))
	var boss: Vector2 = view.rules.boss_position
	var hand = boss+Vector2(brain.facing.x*view.boss_height*.20,-view.boss_height*.45)
	if brain.phase == "windup":
		var progress: float = brain.progress()
		for i in range(8):
			var angle = i*TAU/8+view.clock*2
			var radius = 18+(1-progress)*45
			var point = hand+Vector2(cos(angle)*radius,sin(angle)*radius*.65)
			draw_rect(Rect2(point.snapped(Vector2(3,3)),Vector2(4,4)),Color(color,.35+progress*.6))
		ellipse(hand,Vector2(14,14)*(1+progress*.5),Color(color,.7),3)
		# A compact overhead tell remains visible above a large sprite.
		var mark = boss+Vector2(0,-view.boss_height-20)
		draw_line(mark+Vector2(0,-8),mark+Vector2(0,4),Color("ffe6a6"),4)
		draw_rect(Rect2(mark+Vector2(-2,9),Vector2(4,4)),Color("ffe6a6"))
	if brain.phase == "attack":
		match str(move.kind):
			"charge":
				for i in range(0,brain.trail.size(),3):
					var item: Dictionary = brain.trail[i]
					var alpha: float = float(item.life)/.24*.16
					var texture: Texture2D = view.dragon.texture
					var scale: float = view.dragon.scale.y
					var size = texture.get_size()*scale
					draw_texture_rect(texture,Rect2(Vector2(item.position)+(view.dragon.offset-texture.get_size()*.5)*scale,size),false,Color(color,alpha))
					cloud(item.position,.7,alpha*3)
				for i in range(3):
					var point: Vector2 = boss + Vector2(0,-35-i*22)
					draw_line(point-brain.facing*60,point-brain.facing*15,Color(color,.5-i*.1),3)
			"slash":
				var angle: float = brain.facing.angle()
				var progress: float = brain.progress()
				var arc = PackedVector2Array()
				for i in range(25):
					var a = angle-1.25+progress*1.1+i*.09
					arc.append(boss+Vector2(cos(a)*145,sin(a)*85-30))
				draw_polyline(arc,Color(color,.25),18)
				draw_polyline(arc,color,5)
				draw_polyline(arc,Color("fff4d7"),2)
				_draw_action_fx(str(move.style),boss+brain.facing*135+Vector2(0,-35),progress,Vector2(165,130),.9)
			"beam":
				var target: Vector2 = brain.profiles[0].target
				var origin: Vector2 = brain.profiles[0].origin
				var muzzle: Vector2 = hand
				var destination: Vector2 = target+Vector2(0,-25)
				draw_line(muzzle,destination,Color(color,.30),float(move.width)*1.4)
				for i in range(3):
					var offset = Vector2(0,-i*6)
					draw_line(muzzle+offset,destination+offset,Color(color,.8-i*.2),4-i)
				var segments := clampi(ceili(origin.distance_to(target)/85),2,12)
				for i in range(segments+1):
					var point: Vector2 = muzzle.lerp(destination,float(i)/segments)
					_draw_action_fx(str(move.style),point+Vector2(0,20),fposmod(brain.phase_clock*2.4-i*.13,1.0),Vector2(110,maxf(80,float(move.width)*2.6)),.72)
	for projectile in brain.projectiles:
		if projectile.spent:
			continue
		var point: Vector2 = projectile.position
		var direction: Vector2 = Vector2(projectile.velocity).normalized()
		# Render the moving spell itself; no collision-radius guide.
		var travel: float = clampf(float(projectile.get("distance",220))/220,0,1)
		var lift: float = lerpf(view.boss_height*.45,25,travel)
		var core = point+Vector2(brain.facing.x*view.boss_height*.20*(1-travel),-lift)
		draw_line(core-direction*33,core,Color(color,.24),float(projectile.radius)*1.3)
		_draw_action_fx(str(move.style),core+Vector2(0,12),fposmod(view.clock*2.2,1.0),Vector2.ONE*(float(projectile.radius)*4+20),.85)
		if move.style in ["leaf","ink","seal"]:
			var across = direction.orthogonal()*8
			draw_colored_polygon(PackedVector2Array([core+direction*16,core+across,core-direction*12,core-across]),color)
		else:
			draw_circle(core,float(projectile.radius)*.72+3,Color(.13,.09,.17,.8))
			draw_circle(core,float(projectile.radius)*.72,Color(color,.95))
			draw_circle(core,4,Color("fff6db"))
	for impact in brain.impacts:
		var age = 1-float(impact.life)/.48
		var profile: Dictionary = impact.profile
		if profile.kind in ["circle","ring","cross"]:
			_draw_action_fx(str(impact.style),profile.target,age,Vector2.ONE*clampf(Vector2(profile.radius).x*1.5,150,370),1-age*.45)
			_burst(profile.target,profile.radius,str(impact.style),1-age,age)


func _challenge_effects() -> void:
	if view.rules.brain == null:
		return
	var hero: Vector2 = view.hero.position
	var boss: Vector2 = view.rules.boss_position
	var brain: RefCounted = view.rules.brain
	for burst in view.hit_bursts:
		_draw_action_fx("blade",burst.position,1-float(burst.life)/.42,Vector2(155,155) if burst.counter else Vector2(110,110),.9)
	if view.perfect_visual>0:
		var t: float = 1-view.perfect_visual/.7
		ellipse(hero+Vector2(0,-65),Vector2(48,70)*(1+t*.5),Color(1,.88,.57,(1-t)*.8),3)
		for i in range(8):
			var angle = i*TAU/8
			var point = hero+Vector2(0,-70)+Vector2(cos(angle),sin(angle))*(35+t*65)
			draw_line(point,point+Vector2(cos(angle),sin(angle))*10,Color(1,.96,.78,1-t),3)
	if view.rules.counter_time>0:
		for i in range(5):
			var angle = view.clock*4+i*TAU/5
			var point = hero+Vector2(cos(angle)*40,-75+sin(angle)*55)
			draw_rect(Rect2(point.snapped(Vector2(2,2)),Vector2(4,7)),Color("ffe3a0"))
	if brain.phase == "stagger":
		var center = boss+Vector2(0,-view.boss_height-12)
		for i in range(3):
			var angle = view.clock*5+i*TAU/3
			var point = center+Vector2(cos(angle)*38,sin(angle)*12)
			draw_line(point-Vector2(6,0),point+Vector2(6,0),Color("ffe9a4"),3)
			draw_line(point-Vector2(0,6),point+Vector2(0,6),Color("ffe9a4"),3)
	if view.phase_flash>0:
		var t: float = 1-view.phase_flash/.75
		ellipse(boss,Vector2(70,35)*(1+t*4),Color(1,.82,.48,view.phase_flash*.65),4)
	if brain.phase == "attack" and brain.move.kind == "volley" and fmod(brain.phase_clock,.34)<.12:
		var center = boss+Vector2(brain.facing.x*view.boss_height*.2,-view.boss_height*.45)
		var color = _palette(brain.move.style)
		for i in range(6):
			var angle = i*TAU/6+view.clock*3
			draw_line(center,center+Vector2(cos(angle),sin(angle))*28,color,3)


func _draw_action_fx(style: String, at: Vector2, progress: float, size: Vector2, alpha: float = 1.0) -> void:
	var frame: Dictionary = Actions.effect_frame(style,progress)
	if not frame.is_empty():
		draw_texture_rect(frame.texture,Rect2(at-size*frame.pivot,size),false,Color(1,1,1,alpha))
