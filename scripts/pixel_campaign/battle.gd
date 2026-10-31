extends Control
## Pixel battle presentation. Encounter owns the rules; this view owns input and drawing.
const Encounter = preload("res://scripts/pixel_campaign/encounter.gd")
const Art = preload("res://scripts/pixel_campaign/pixel_art.gd")
signal completed(won: bool, metrics: Dictionary)
signal leave_requested
signal retry_requested
signal minion_collected(id: String)

var host: Node2D
var entry: Dictionary = {}
var snapshot: Dictionary = {}
var difficulty: String = "story"
var selected_skill: String = "雷诀"
var avatar: String = "male"
var rules: RefCounted
var player_position := Vector2(-5.8, 3.4)
var last_direction := Vector2.RIGHT
var completion_sent := false
var last_effect_target := Vector2.ZERO
var collected_minions: Array = []

var canvas: ArenaCanvas
var actors: Node2D
var hero: Sprite2D
var boss: Sprite2D
var mob_sprites: Array = []
var mob_labels: Array = []
var node_labels: Array = []
var frames: Array = []
var font: SystemFont
var clock := 0.0
var moving := false
var finish_delay := 0.0
var health: ProgressBar
var energy: ProgressBar
var stamina: ProgressBar
var boss_health: ProgressBar
var boss_caption: Label
var objective: Label
var hint: Label
var status: Label
var buttons: Array = []
var pause_overlay: Control
var effects: Array = []
var popups: Array = []
const INK := Color("422e24")
const DARK := Color("30251f")
const GOLD := Color("d6ad65")
const PAPER := Color("efdbb5")
const ORIGIN := Vector2(720,450)
const PROJECTION := Vector2(55,35)

class ArenaCanvas extends Node2D:
	var battle
	func _draw() -> void:
		if is_instance_valid(battle):
			battle.draw_arena(self)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	# 网页没有系统中文字体，回退到随包的 Noto Sans SC（OFL）。
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC-Regular.otf")]
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","KaiTi"])
	_setup_input()
	rules = Encounter.new(entry,snapshot,difficulty,selected_skill)
	frames = Art.hero_frames(avatar)
	_build_scene()
	_build_hud()
	_update_actors()
	_refresh()
	set_process_input(true)

func _setup_input() -> void:
	for spec in [["realm_left",KEY_A,KEY_LEFT],["realm_right",KEY_D,KEY_RIGHT],["realm_up",KEY_W,KEY_UP],["realm_down",KEY_S,KEY_DOWN]]:
		if not InputMap.has_action(spec[0]):
			InputMap.add_action(spec[0])
		for code in [spec[1],spec[2]]:
			var event = InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(spec[0],event):
				InputMap.action_add_event(spec[0],event)

func world_to_screen(point: Vector2) -> Vector2:
	return ORIGIN + point * PROJECTION

func screen_to_world(point: Vector2) -> Vector2:
	return (point-ORIGIN) / PROJECTION

func hazard_geometry(h: Dictionary) -> Dictionary:
	# The same world parameters used by Encounter.contains are projected without a second hitbox.
	var result = {"shape":str(h.shape),"center":world_to_screen(h.position)}
	match str(h.shape):
		"circle":
			result["radii"] = Vector2.ONE * float(h.radius) * PROJECTION
		"ring":
			result["outer_radii"] = Vector2.ONE * (float(h.radius)+float(h.width)) * PROJECTION
			result["inner_radii"] = Vector2.ONE * maxf(0,float(h.radius)-float(h.width)) * PROJECTION
		"line","charge":
			result["start"] = world_to_screen(h.position)
			result["end"] = world_to_screen(h.end)
			result["world_width"] = float(h.width)
		"cone":
			result["radius"] = float(h.radius)
			result["angle"] = float(h.angle)
			result["half_angle"] = float(h.half_angle)
	return result

func _build_scene() -> void:
	var background = TextureRect.new()
	background.name = "PixelRealmBackground"
	background.texture = Art.background(str(entry.get("region","序章")))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -100
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0.07,0.04,0.03,0.12)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = -90
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = ArenaCanvas.new()
	canvas.battle = self
	canvas.name = "SharedParameterTelegraphs"
	canvas.z_index = -10
	add_child(canvas)
	actors = Node2D.new()
	actors.name = "PixelActors"
	add_child(actors)
	boss = _sprite(Art.boss_texture(str(entry.id)),255 if str(entry.id)!="b00" else 185)
	boss.name = "Boss_"+str(entry.id)
	hero = _sprite(frames[8] if frames.size()>8 else (frames[0] if not frames.is_empty() else null),112)
	hero.name = "Player"
	for mob in rules.minions:
		var sprite = _sprite(Art.minion_texture(str(mob.id)),84)
		sprite.name = "Minion_"+str(mob.id)
		mob_sprites.append(sprite)
		var caption = _label(actors,str(mob.name),15,Color("fff0c5"))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(160,24)
		caption.z_index = 900
		caption.add_theme_color_override("font_outline_color",DARK)
		caption.add_theme_constant_override("outline_size",4)
		mob_labels.append(caption)
	for node in rules.nodes:
		var caption = _label(actors,"",16,Color("fff0c5"))
		caption.size = Vector2(180,28)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = world_to_screen(node.position)+Vector2(-90,27)
		caption.add_theme_color_override("font_outline_color",DARK)
		caption.add_theme_constant_override("outline_size",4)
		caption.z_index = 850
		node_labels.append(caption)

func _sprite(texture: Texture2D,height: float) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.set_meta("height",height)
	if texture != null:
		sprite.scale = Vector2.ONE * height / texture.get_height()
		sprite.offset.y = -texture.get_height()*.5
	actors.add_child(sprite)
	return sprite

func _style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=12
	style.content_margin_bottom=12
	style.shadow_color=Color(0.08,0.04,0.02,.40)
	style.shadow_size=5
	style.shadow_offset=Vector2(3,3)
	return style

func _card(rect: Rect2,parent: Node=self,color: Color=PAPER) -> VBoxContainer:
	var panel=PanelContainer.new()
	panel.position=rect.position
	panel.custom_minimum_size=rect.size
	panel.size=rect.size
	panel.add_theme_stylebox_override("panel",_style(color))
	panel.z_index=1100
	parent.add_child(panel)
	var box=VBoxContainer.new()
	box.add_theme_constant_override("separation",7)
	panel.add_child(box)
	return box

func _label(parent: Node,text: String,size: int=18,color: Color=INK) -> Label:
	var item=Label.new()
	item.text=text
	item.add_theme_font_override("font",font)
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",color)
	item.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func _button(parent: Node,text: String,callback: Callable,primary: bool=false) -> Button:
	var button=Button.new()
	button.text=text
	button.focus_mode=Control.FOCUS_NONE
	button.custom_minimum_size=Vector2(174,48)
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",18)
	button.add_theme_stylebox_override("normal",_style(Color("765036") if primary else Color("e7cda2")))
	button.add_theme_stylebox_override("hover",_style(Color("91683f") if primary else Color("f5dfb5")))
	button.add_theme_stylebox_override("pressed",_style(Color("4f3727")))
	button.add_theme_stylebox_override("disabled",_style(Color("baac91")))
	button.add_theme_color_override("font_color",Color("fff0cd") if primary else INK)
	button.add_theme_color_override("font_hover_color",Color("fff0cd") if primary else INK)
	button.add_theme_color_override("font_disabled_color",Color("766655"))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _bar(parent: Node,color: Color,height: float=15) -> ProgressBar:
	var bar=ProgressBar.new()
	bar.show_percentage=false
	bar.custom_minimum_size.y=height
	var bg=StyleBoxFlat.new()
	bg.bg_color=Color("342928")
	var fill=StyleBoxFlat.new()
	fill.bg_color=color
	bar.add_theme_stylebox_override("background",bg)
	bar.add_theme_stylebox_override("fill",fill)
	parent.add_child(bar)
	return bar

func _build_hud() -> void:
	var top=_card(Rect2(18,16,1404,112),self,DARK)
	var row=HBoxContainer.new()
	row.add_theme_constant_override("separation",22)
	top.add_child(row)
	var intro=VBoxContainer.new()
	intro.custom_minimum_size.x=355
	row.add_child(intro)
	_label(intro,str(entry.name)+" · "+str(entry.get("role","山海篇章")),26,Color("f6d69a"))
	_label(intro,str(entry.get("arena","五域幻境")),16,Color("dbc9ac"))
	var middle=VBoxContainer.new()
	middle.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(middle)
	boss_caption=_label(middle,"",16,Color("ffedc8"))
	boss_health=_bar(middle,Color("a45374"),18)
	objective=_label(middle,"",15,Color("e5d5b9"))
	_button(row,"暂歇  [Esc]",func():set_paused(true))
	_button(row,"返回地图",func():set_paused(true))
	var lower=_card(Rect2(18,728,316,155),self,DARK)
	status=_label(lower,"",15,Color("ffebc5"))
	health=_bar(lower,Color("8ac69b"),17)
	energy=_bar(lower,Color("80bcd2"),12)
	stamina=_bar(lower,Color("dfbc68"),12)
	var action_row=HBoxContainer.new()
	action_row.position=Vector2(356,752)
	action_row.add_theme_constant_override("separation",10)
	action_row.z_index=1100
	add_child(action_row)
	for i in range(5):
		var action=i
		var button=_button(action_row,"",func():perform_action(action),i==1)
		button.custom_minimum_size=Vector2(202,68)
		buttons.append(button)
	hint=_label(self,"",18,Color("fff0cd"))
	hint.position=Vector2(354,838)
	hint.size=Vector2(1064,42)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_outline_color",DARK)
	hint.add_theme_constant_override("outline_size",5)
	hint.z_index=1200

func _refresh() -> void:
	if rules == null or health == null:return
	health.max_value=rules.hp_max
	health.value=rules.hp
	energy.max_value=100
	energy.value=rules.energy
	stamina.max_value=rules.stamina_max
	stamina.value=rules.stamina
	status.text="护元 %d/%d   真气 %d   体力 %d" % [ceili(rules.hp),ceili(rules.hp_max),roundi(rules.energy),roundi(rules.stamina)]
	boss_health.max_value=rules.boss_max
	boss_health.value=rules.boss_hp
	boss_caption.text="%s  %d / %d%s" % [entry.name,ceili(rules.boss_hp),ceili(rules.boss_max)," · 散祟护阵" if rules.living_minions()>0 else (" · 护障尚存" if rules.remaining_nodes()>0 else " · 护障已解")]
	objective.text=rules.objective_text()
	hint.text="WASD / 方向键移动 · "+rules.hint
	var cds=[rules.attack_cd,rules.skill_cd,rules.guard_cd,rules.dash_cd,0.0]
	var captions=["近身攻击 [J]",selected_skill+" [1]","定时护盾 [K]","闪避 [空格]","操作阵眼 [E]"]
	for i in range(buttons.size()):
		buttons[i].disabled=rules.finished or rules.paused or float(cds[i])>0
		buttons[i].text=captions[i]+("\n冷却 %.1f 秒" % float(cds[i]) if float(cds[i])>0 else "\n"+["挥剑","消耗24真气","把握命中时机","消耗24体力","靠近发光印记"][i])
	if rules.energy<24:buttons[1].disabled=true
	if rules.stamina<24:buttons[3].disabled=true
	for i in range(node_labels.size()):
		node_labels[i].text=("✓ "+str(rules.nodes[i].label)) if rules.nodes[i].done else str(rules.nodes[i].label)+" · E"

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or rules == null:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if not rules.finished:set_paused(not rules.paused)
			get_viewport().set_input_as_handled()
			return
		var actions={KEY_J:0,KEY_1:1,KEY_K:2,KEY_SPACE:3,KEY_E:4}
		if actions.has(event.keycode):
			perform_action(actions[event.keycode])
			get_viewport().set_input_as_handled()

func perform_action(action: int) -> void:
	if rules==null or rules.paused or rules.finished:return
	match action:
		0,1:
			var result: Dictionary=rules.attack(player_position) if action==0 else rules.cast(player_position)
			if result.get("ok",false):
				last_effect_target=result.get("position",player_position)
				effects.append({"kind":"slash" if action==0 else "spell","from":player_position,"to":last_effect_target,"life":.28,"max_life":.28})
		2:
			rules.guard()
		3:
			if rules.dash():
				var start=player_position
				player_position=rules.clamp_position(player_position+last_direction*2.1)
				effects.append({"kind":"dash","from":start,"to":player_position,"life":.25,"max_life":.25})
		4:
			rules.interact(player_position)
	_refresh()
	canvas.queue_redraw()

func set_paused(value: bool) -> void:
	if rules==null or rules.finished:return
	rules.paused=value
	if is_instance_valid(pause_overlay):
		pause_overlay.queue_free()
	pause_overlay=null
	if value:
		pause_overlay=ColorRect.new()
		pause_overlay.color=Color(.07,.04,.03,.72)
		pause_overlay.z_index=2500
		add_child(pause_overlay)
		pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var card=_card(Rect2(424,235,592,365),pause_overlay)
		_label(card,"暂歇片刻",30)
		var description=_label(card,"场内时间已暂停。\n可以继续挑战，或返回地图稍作休整。",20)
		description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_button(card,"继续挑战",func():set_paused(false),true)
		_button(card,"返回地图 · 可免费重试",func():leave_requested.emit())
	_refresh()

func _process(delta: float) -> void:
	if rules==null:return
	if rules.paused:
		_refresh()
		return
	var dt=minf(delta,.1)
	clock+=dt
	if rules.finished:
		finish_delay+=dt
		_update_actors()
		_advance_effects(dt)
		if finish_delay>=.45 and not completion_sent:
			_complete()
		return
	var direction=Input.get_vector("realm_left","realm_right","realm_up","realm_down")
	moving=direction.length_squared()>.01
	if moving:
		last_direction=direction.normalized()
		player_position=rules.clamp_position(player_position+direction*6.0*dt)
	rules.step(dt,player_position)
	for event in rules.feedback:
		_feedback(event)
	rules.feedback.clear()
	_update_actors()
	_advance_effects(dt)
	_refresh()
	canvas.queue_redraw()

func _update_actors() -> void:
	var hero_frame=0
	if absf(last_direction.x)>absf(last_direction.y):
		hero_frame=12 if last_direction.x>0 else 4
	else:
		hero_frame=0 if last_direction.y>0 else 8
	if moving:hero_frame+=int(clock*10)%4
	if frames.size()>hero_frame:
		hero.texture=frames[hero_frame]
	if hero.texture!=null:
		hero.scale=Vector2.ONE*112/hero.texture.get_height()
		hero.offset.y=-hero.texture.get_height()*.5
	hero.position=world_to_screen(player_position)+Vector2(0,-absf(sin(clock*12))*3 if moving else 0)
	hero.z_index=int(hero.position.y)
	hero.modulate=Color("ffc6a9") if rules.hurt_immunity>.35 else Color.WHITE
	boss.position=world_to_screen(rules.boss_position)+Vector2(0,-sin(clock*2.2)*2)
	boss.z_index=int(boss.position.y)
	if boss.texture!=null:
		var height=float(boss.get_meta("height"))
		boss.scale=Vector2.ONE*height/boss.texture.get_height()
		for h in rules.hazards:
			if h.get("source","")=="" and not h.active:
				boss.scale*=1.0+.035*(1.0-float(h.timer)/maxf(.01,float(h.warning)))
				break
	boss.modulate=Color("ffc5a6") if rules.flash>0 else (Color(1,1,1,.55) if rules.won else Color.WHITE)
	boss.rotation=-.08 if rules.won else 0.0
	for i in range(mob_sprites.size()):
		var mob=rules.minions[i]
		mob_sprites[i].visible=mob.hp>0
		mob_sprites[i].position=world_to_screen(mob.position)+Vector2(0,-sin(clock*3+i)*2)
		mob_sprites[i].z_index=int(mob_sprites[i].position.y)
		mob_labels[i].visible=mob.hp>0
		mob_labels[i].position=world_to_screen(mob.position)+Vector2(-80,9)
		mob_labels[i].text="%s  %d" % [mob.name,maxi(0,ceili(mob.hp))]

func _feedback(event: Dictionary) -> void:
	var point: Vector2=event.get("position",Vector2.ZERO)
	if point==Vector2.ZERO:point=player_position
	popups.append({"point":point,"text":str(event.text),"life":.85,"max_life":.85,"kind":str(event.kind)})
	if event.kind=="minion_defeat":
		var id=str(event.id)
		if id not in collected_minions:
			collected_minions.append(id)
			minion_collected.emit(id)

func _advance_effects(dt: float) -> void:
	for effect in effects:effect.life-=dt
	effects=effects.filter(func(item):return item.life>0)
	for item in popups:item.life-=dt
	popups=popups.filter(func(item):return item.life>0)
	canvas.queue_redraw()

func _disk(point: Vector2,radius: float,count: int=48) -> PackedVector2Array:
	var points=PackedVector2Array()
	for i in range(count):
		var angle=i*TAU/count
		points.append(world_to_screen(point+Vector2(cos(angle),sin(angle))*radius))
	return points

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result=points.duplicate()
	if not points.is_empty():result.append(points[0])
	return result

func _capsule(start: Vector2,end: Vector2,width: float) -> PackedVector2Array:
	var points=PackedVector2Array()
	var angle=(end-start).angle()
	for i in range(17):
		var a=angle-PI*.5+float(i)/16*PI
		points.append(world_to_screen(end+Vector2(cos(a),sin(a))*width))
	for i in range(17):
		var a=angle+PI*.5+float(i)/16*PI
		points.append(world_to_screen(start+Vector2(cos(a),sin(a))*width))
	return points

func draw_arena(target: Node2D) -> void:
	if rules==null:return
	for node in rules.nodes:
		var color=Color("7ba987") if node.done else Color("eac46f")
		target.draw_colored_polygon(_disk(node.position,.64),Color(color,.23))
		target.draw_polyline(_closed(_disk(node.position,.68)),color,3,true)
		target.draw_polyline(_closed(_disk(node.position,.43)),color,1.5,true)
		if not node.done:
			var center=world_to_screen(node.position)
			target.draw_line(center+Vector2(-10,0),center+Vector2(10,0),color,2)
			target.draw_line(center+Vector2(0,-7),center+Vector2(0,7),color,2)
	if rules.remaining_nodes()>0 or rules.living_minions()>0:
		target.draw_polyline(_closed(_disk(rules.boss_position,1.45)),Color("e5c477"),2,true)
	for h in rules.hazards:
		var edge=Color("ff775c") if h.active else Color("ffc96c")
		var color=Color(edge,.50 if h.active else .25)
		match str(h.shape):
			"circle":
				var points=_disk(h.position,h.radius)
				target.draw_colored_polygon(points,color)
				target.draw_polyline(_closed(points),Color(.12,.08,.06,.8),6,true)
				target.draw_polyline(_closed(points),edge,3,true)
			"ring":
				var outer=_disk(h.position,h.radius+h.width)
				var inner=_disk(h.position,maxf(.01,h.radius-h.width))
				for i in range(outer.size()):
					var next=(i+1)%outer.size()
					target.draw_colored_polygon(PackedVector2Array([outer[i],outer[next],inner[next],inner[i]]),color)
				target.draw_polyline(_closed(outer),Color(.12,.08,.06,.8),5,true)
				target.draw_polyline(_closed(inner),Color(.12,.08,.06,.8),5,true)
				target.draw_polyline(_closed(outer),edge,2,true)
				target.draw_polyline(_closed(inner),edge,2,true)
			"line","charge":
				var points=_capsule(h.position,h.end,h.width)
				target.draw_colored_polygon(points,color)
				target.draw_polyline(_closed(points),Color(.12,.08,.06,.8),6,true)
				target.draw_polyline(_closed(points),edge,3,true)
			"cone":
				var points=PackedVector2Array([world_to_screen(h.position)])
				for i in range(33):
					var angle=h.angle-h.half_angle+float(i)/32*h.half_angle*2
					points.append(world_to_screen(h.position+Vector2(cos(angle),sin(angle))*h.radius))
				target.draw_colored_polygon(points,color)
				target.draw_polyline(_closed(points),Color(.12,.08,.06,.8),6,true)
				target.draw_polyline(_closed(points),edge,3,true)
		var p=world_to_screen(h.position)
		if not h.active:
			var progress=1.0-clampf(h.timer/maxf(.01,h.warning),0,1)
			target.draw_arc(p,13,-PI*.5,-PI*.5+TAU*progress,24,edge,3,true)
	# Foot shadows are also the player's visual contact radius.
	for p in [player_position,rules.boss_position]:
		target.draw_colored_polygon(_disk(p,.3 if p==player_position else .95),Color(0.06,.035,.02,.33))
	for mob in rules.minions:
		if mob.hp>0:target.draw_colored_polygon(_disk(mob.position,.45),Color(0.06,.035,.02,.29))
	if rules.guard_time>0 or rules.dodge_time>0:
		var color=Color("e9d792") if rules.guard_time>0 else Color("b0e8ed")
		target.draw_polyline(_closed(_disk(player_position,.85)),color,5,true)
	if str(entry.id)=="b11" and not rules.escort_done:
		var escort_point=world_to_screen(rules.escort)
		target.draw_circle(escort_point+Vector2(0,-24),17,Color("ffdb88"))
		target.draw_circle(escort_point+Vector2(0,-24),25,Color(1,.9,.6,.25))
	for effect in effects:
		var alpha=clampf(effect.life/effect.max_life,0,1)
		var start=world_to_screen(effect.from)+Vector2(0,-45)
		var end=world_to_screen(effect.to)+Vector2(0,-45)
		if effect.kind=="spell":
			target.draw_line(start,end,Color(.6,.9,1,alpha*.4),15,true)
			target.draw_line(start,end,Color(.9,.97,1,alpha),4,true)
			target.draw_circle(end,14,Color(.95,.96,1,alpha*.7))
		elif effect.kind=="dash":
			target.draw_line(start+Vector2(0,42),end+Vector2(0,42),Color(.7,.9,1,alpha*.5),8,true)
		else:
			var origin=world_to_screen(effect.from)+Vector2(0,-38)
			target.draw_arc(origin,42,-2.5+.6*(1-alpha),.9+.6*(1-alpha),18,Color(1,.94,.73,alpha),6,true)
			if effect.to!=effect.from:
				target.draw_arc(end,14,0,TAU,16,Color(1,.9,.55,alpha),3,true)
	for item in popups:
		var alpha=clampf(item.life/item.max_life,0,1)
		var pos=world_to_screen(item.point)+Vector2(-45,-104-(1-alpha)*35)
		var color=Color("ffdb94") if item.kind=="damage" else Color("e3f6cd")
		target.draw_string(font,pos+Vector2(2,2),item.text,HORIZONTAL_ALIGNMENT_CENTER,180,21,Color(0.10,.07,.04,alpha))
		target.draw_string(font,pos,item.text,HORIZONTAL_ALIGNMENT_CENTER,180,21,Color(color,alpha))

func metrics() -> Dictionary:
	return {"seconds":rules.elapsed,"hits":rules.hits_taken,"blocks":rules.perfect_blocks,"preset":snapshot.get("status","unknown"),"skill":selected_skill,"collected_minions":collected_minions.duplicate()}

func _complete() -> void:
	completion_sent=true
	if host==null:
		var result=_card(Rect2(432,247,576,367),self)
		_label(result,str(entry.name)+(" · 幻境已解" if rules.won else " · 暂且休整"),28)
		var text=_label(result,str(entry.get("world_change","灯火仍在，稍作休整再来。")) if rules.won else "这次没有失去修为。\n观察预兆，下一次可以做得更从容。",19)
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_button(result,"返回地图",func():leave_requested.emit(),true)
		_button(result,"再试一次",func():retry_requested.emit())
	completed.emit(bool(rules.won),metrics())

