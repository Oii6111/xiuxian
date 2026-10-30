extends SceneTree
## Presentation integration: inject actual InputEvents into a live Battle.
## Combat fixtures select an encounter/position; they do not claim a human playthrough.
const Battle = preload("res://scripts/pixel_campaign/battle.gd")
const Catalogue = preload("res://scripts/pixel_campaign/catalogue.gd")
const Art = preload("res://scripts/pixel_campaign/pixel_art.gd")
var assertions := 0
var failures: Array[String] = []
var active: Control
var completions: Array = []

class FakeHost extends Node2D:
	var settlement_calls := 0
	func settle(_won: bool, _metrics: Dictionary) -> void:
		settlement_calls += 1

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: ",description)

func _run() -> void:
	root.size=Vector2i(1440,900)
	if OS.get_cmdline_user_args().has("--capture"):
		await capture_review()
		return
	await _spawn("b03")
	projection_contract()
	prelude_contract()
	await input_contract()
	await _spawn("b03")
	await target_contract()
	await objective_contract()
	await _spawn("b03")
	await objective_gate_contract()
	await _spawn("b11")
	await escort_gate_contract()
	await _spawn("b00")
	await healer_contract()
	await _spawn("b00")
	await completion_contract()
	asset_contract()
	if is_instance_valid(active):
		active.queue_free()
	await process_frame
	print("PIXEL_BATTLE ",assertions," assertions; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _spawn(id: String) -> void:
	if is_instance_valid(active):
		active.queue_free()
		await process_frame
	active=Battle.new()
	active.entry=Catalogue.entry(id)
	active.snapshot={"status":"unknown","attack":1.0,"stamina":1.0}
	root.add_child(active)
	await process_frame
	active.set_process(false)
	expect(active.rules!=null,id+" creates its encounter")
	expect(active.hero.texture!=null,id+" uses a real pixel player texture")
	expect(active.boss.texture!=null,id+" uses a real boss texture")
	expect(active.buttons.size()==5,"five mouse action buttons exist")
	expect(active.hint.text.begins_with("WASD / 方向键移动"),"movement controls remain visible beside current story hint")
	expect(is_zero_approx(active.hero.get_rect().end.y),"player texture is anchored at its bottom edge")
	expect(is_zero_approx(active.boss.get_rect().end.y),"boss texture is anchored at its bottom edge")
	expect(active.rules.arena.end.y*35+450<728,"entire walkable arena stays above bottom HUD")
	for button in active.buttons:
		expect(button.focus_mode==Control.FOCUS_NONE,"action buttons cannot consume Space through keyboard focus")

func projection_contract() -> void:
	for point in [Vector2.ZERO,Vector2(-7,-4),Vector2(6.5,3.2)]:
		expect(active.screen_to_world(active.world_to_screen(point)).is_equal_approx(point),"screen projection round trips "+str(point))
	expect(active.world_to_screen(Vector2(2,3))==Vector2(830,555),"battle uses world X/Z projection 55 by 35")
	var h: Dictionary=active.rules._spawn("circle",Vector2(1,-1),2.4,1.5)
	var geometry: Dictionary=active.hazard_geometry(h)
	expect(geometry.radii.is_equal_approx(Vector2(132,84)),"circular world tell becomes correct screen ellipse")
	var edge: Vector2=active.screen_to_world(geometry.center+Vector2(geometry.radii.x,0))
	expect(active.rules.contains(h,edge),"projected ellipse boundary is inside the shared combat tell")
	expect(not active.rules.contains(h,edge+Vector2(.4,0)),"a point beyond player contact tolerance is outside")
	h=active.rules._spawn("ring",Vector2.ZERO,3.0,1.2,.7)
	geometry=active.hazard_geometry(h)
	expect(geometry.outer_radii.is_equal_approx(Vector2(203.5,129.5)),"ring outer ellipse derives radius plus width")
	expect(geometry.inner_radii.is_equal_approx(Vector2(126.5,80.5)),"ring inner ellipse preserves a visible safe center")
	expect(not active.rules.contains(h,Vector2.ZERO),"ring center is safe in shared rules")
	for shape in ["line","charge"]:
		h=active.rules._spawn(shape,Vector2(-3,-1),0,1.0,.6)
		h.end=Vector2(4,2)
		geometry=active.hazard_geometry(h)
		expect(geometry.start==active.world_to_screen(h.position) and geometry.end==active.world_to_screen(h.end),shape+" endpoints share exact world coordinates")
		expect(is_equal_approx(float(geometry.world_width),float(h.width)),shape+" visual capsule uses combat width")
	h=active.rules._spawn("cone",Vector2(1,2),4,1.1)
	h.angle=.8
	h.half_angle=.4
	geometry=active.hazard_geometry(h)
	expect(geometry.radius==h.radius and geometry.angle==h.angle and geometry.half_angle==h.half_angle,"fan tell preserves radius, angle and aperture")
	# Exercise all five rendering paths in the live canvas, including the ring.
	active.canvas.queue_redraw()

func prelude_contract() -> void:
	expect(active.rules.living_minions()==2,"b03 starts with its two related minions")
	var hp: float=active.rules.boss_hp
	active.player_position=active.rules.boss_position+Vector2(1,0)
	active.perform_action(0)
	expect(active.rules.boss_hp==hp,"b03 cannot melee the boss while its minions are alive")
	active.rules.hazards.clear()
	for i in range(60):
		active.rules.step(.1,Vector2(-7,4))
	expect(active.rules.boss_hp==hp,"prelude does not grant hidden boss damage")
	expect(active.rules.hazards.all(func(h):return not str(h.get("source","")).is_empty()),"only minions can spawn prelude attacks")
	active.rules.hazards.clear()
	active.rules.attack_cd=0
	active.rules.skill_cd=0
	active.rules.dash_cd=0
	active.rules.guard_cd=0
	active.rules.stamina=active.rules.stamina_max

func _key(code: Key,pressed: bool) -> void:
	var event=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)

func _tap(code: Key) -> void:
	_key(code,true)
	await process_frame
	_key(code,false)
	await process_frame

func input_contract() -> void:
	active.player_position=Vector2(-5,3)
	active.last_direction=Vector2.RIGHT
	var start: Vector2=active.player_position
	var before: float=active.rules.stamina
	await _tap(KEY_SPACE)
	expect(active.player_position.x>start.x+2,"real Space event moves the player through dash")
	expect(active.rules.dash_cd>0 and active.rules.dodge_time>0,"real Space starts cooldown and invulnerability")
	expect(active.rules.stamina<=before-24,"dash consumes stamina")
	await _tap(KEY_K)
	expect(active.rules.guard_time>0 and active.rules.guard_cd>0,"real K activates timed guard")
	await _tap(KEY_ESCAPE)
	expect(active.rules.paused and is_instance_valid(active.pause_overlay),"Escape opens pause overlay")
	var elapsed: float=active.rules.elapsed
	start=active.player_position
	var cd: float=active.rules.dash_cd
	_key(KEY_D,true)
	active._process(.1)
	active._process(.1)
	_key(KEY_D,false)
	active.perform_action(0)
	active.perform_action(1)
	expect(active.player_position==start and active.rules.elapsed==elapsed,"paused movement and combat time remain frozen")
	expect(active.rules.dash_cd==cd,"pause freezes cooldowns")
	await _tap(KEY_ESCAPE)
	expect(not active.rules.paused,"Escape resumes battle")
	start=active.player_position
	_key(KEY_D,true)
	await process_frame
	active._process(.1)
	_key(KEY_D,false)
	expect(active.player_position.x>start.x,"real D input moves the player when resumed")
	expect(active.rules.elapsed>elapsed,"resuming restarts combat time")

func target_contract() -> void:
	active.player_position=Vector2(-5.8,3.4)
	var mob: Dictionary=active.rules.minions[0]
	var hp: float=mob.hp
	var boss_hp: float=active.rules.boss_hp
	await _tap(KEY_1)
	expect(float(mob.hp)<hp,"real 1 key hits a nearby minion")
	expect(active.last_effect_target==mob.position,"spell effect ends at the actual returned minion target")
	expect(active.last_effect_target!=active.rules.boss_position,"minion-target spell is not drawn onto the boss")
	expect(active.rules.boss_hp==boss_hp,"minion spell does not also damage the boss")
	expect(active.rules.skill_cd>0 and active.rules.energy<100,"spell starts cooldown and spends energy")

func objective_contract() -> void:
	active.player_position=active.rules.nodes[0].position
	var count: int=active.rules.remaining_nodes()
	await _tap(KEY_E)
	expect(active.rules.remaining_nodes()==count-1,"real E key operates the nearby story objective")
	expect(active.node_labels[0].text.begins_with("✓"),"completed objective updates its visible caption")
	active.rules.attack_cd=0
	var living: Dictionary={}
	for mob in active.rules.minions:
		if mob.hp>0:
			living=mob
			break
	active.player_position=living.position
	var hp: float=living.hp
	await _tap(KEY_J)
	expect(living.hp<hp,"real J key performs melee")
	var clicked=[false]
	active.buttons[2].pressed.connect(func():clicked[0]=true)
	active.buttons[2].pressed.emit()
	expect(clicked[0],"mouse button dispatches its action signal")

func completion_contract() -> void:
	var fake=FakeHost.new()
	root.add_child(fake)
	active.host=fake
	active.completed.connect(func(won,metrics):completions.append({"won":won,"metrics":metrics}))
	active.rules.finished=true
	active.rules.won=false
	for i in range(9):
		active._process(.1)
	expect(completions.size()==1,"completion is emitted exactly once")
	expect(not completions[0].won,"loss is preserved in completion payload")
	expect(completions[0].metrics.has("seconds") and completions[0].metrics.has("collected_minions"),"result carries encounter metrics and collected lore ids")
	expect(not completions[0].metrics.has("xp") and fake.settlement_calls==0,"battle reports an outcome and never settles campaign rewards")
	fake.queue_free()

func asset_contract() -> void:
	for row in Catalogue.all():
		expect(Art.boss_texture(str(row.id))!=null,str(row.id)+" has a usable sprite without editor import dependencies")
	for mob in Catalogue.minions():
		expect(Art.minion_texture(str(mob.id))!=null,str(mob.id)+" has a usable minion sprite")

func capture_review() -> void:
	# Deterministic rendering fixtures, not screenshots from a completed playthrough.
	var directory=ProjectSettings.globalize_path("res://outputs/pixel_battle_review")
	DirAccess.make_dir_recursive_absolute(directory)
	for id in ["b03","b19"]:
		await _spawn(id)
		active.rules.hazards.clear()
		var h: Dictionary=active.rules._spawn("circle",Vector2(.1,.5),1.65,1.7)
		h.timer=.9
		h=active.rules._spawn("line",Vector2(-6,-3),0,1.7,.6)
		h.end=Vector2(2,2.3)
		h.timer=1.2
		h=active.rules._spawn("ring",Vector2(5,2.6),1.75,1.7,.45)
		h.timer=.5
		active._update_actors()
		active._refresh()
		active.canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var path=directory+"/"+id+"_render_fixture.png"
		var error=root.get_texture().get_image().save_png(path)
		expect(error==OK,"render fixture saved "+id)
		print("BATTLE_RENDER_FIXTURE ",path)
	if is_instance_valid(active):active.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func objective_gate_contract() -> void:
	# A legal combat fixture after prelude; objectives must still gate the core.
	for mob in active.rules.minions:mob.hp=0
	active.player_position=active.rules.boss_position+Vector2(1,0)
	var hp: float=active.rules.boss_hp
	await _tap(KEY_J)
	expect(active.rules.boss_hp==hp,"real J cannot bypass unfinished objective after prelude")
	expect(active.hint.text.contains("先完成"),"HUD explains the objective gate after a blocked attack")
	for node in active.rules.nodes:
		active.player_position=node.position
		await _tap(KEY_E)
	expect(active.rules.remaining_nodes()==0,"real E inputs complete every b03 root node")
	for i in range(5):active._process(.1)
	active.player_position=active.rules.boss_position+Vector2(1,0)
	await _tap(KEY_J)
	expect(active.rules.boss_hp<hp,"real J damages the boss after legitimate objectives are complete")
	expect(active.boss_health.value==active.rules.boss_hp,"boss bar displays the updated stronger rules health")

func escort_gate_contract() -> void:
	for mob in active.rules.minions:mob.hp=0
	active.player_position=active.rules.nodes[0].position
	var count: int=active.rules.remaining_nodes()
	var node_hp: int=active.rules.nodes[0].hp
	await _tap(KEY_E)
	expect(active.rules.remaining_nodes()==count,"real E cannot replace b11 escort")
	await _tap(KEY_J)
	expect(active.rules.nodes[0].hp==node_hp,"real J cannot break an escort objective early")
	expect(active.hint.text.contains("羽灯"),"HUD explains that the player must escort the feather lamp")

func healer_contract() -> void:
	active.selected_skill="分流"
	active.rules.selected_skill="分流"
	active.player_position=active.rules.boss_position+Vector2(-2,0)
	active.rules.hp=active.rules.hp_max-80
	var hp: float=active.rules.hp
	await _tap(KEY_1)
	expect(is_equal_approx(active.rules.hp,hp+25),"real 1 restores the updated 25 health for 分流")
	expect(is_equal_approx(active.rules.skill_cd,6),"分流 uses the updated 6 second cooldown")
	expect(active.buttons[1].text.contains("分流") and active.buttons[1].text.contains("6.0"),"skill button displays name and cooldown from active rules")
	active._process(.1)
	expect(active.buttons[1].text.contains("5.9"),"skill HUD follows the running rules cooldown")

