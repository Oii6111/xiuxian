extends SceneTree
const Guard = preload("res://tests/helpers/pr4_render_guard.gd")
var checks: int = 0
var failures: Array = []
var folder = "res://outputs/combat-lifecycle/animated-combat"
func _init() -> void: call_deferred("_run")
func expect(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("FAIL: ",title)
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	expect(image!=null and image.save_png(folder.path_join(name+".png"))==OK,"render "+name)
func click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await process_frame
func key(code: Key) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func _hidden_geometry(view: Control) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,900)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var ground = preload("res://scripts/combat_effects.gd").new()
	ground.view = view
	ground.ground_only = true
	viewport.add_child(ground)
	await process_frame
	await RenderingServer.frame_post_draw
	var before: PackedByteArray = viewport.get_texture().get_image().get_data()
	var brain: RefCounted = view.rules.brain
	var phase: String = brain.phase
	var profiles: Array = brain.profiles.duplicate(true)
	for kind in ["cone","capsule","circle","ring","line","cross"]:
		brain.phase = "windup"
		brain.profiles = [{"kind":kind,"origin":Vector2(900,590),"target":Vector2(650,590),"radius":Vector2(220,130),"direction":Vector2.LEFT,"width":35.0}]
		ground.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		expect(viewport.get_texture().get_image().get_data()==before,"offscreen actual ground rendering hides "+kind+" attack geometry")
	brain.phase = phase
	brain.profiles = profiles
	viewport.queue_free()
	await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.family.persist_enabled = false
	var member: Dictionary = scene.family.add_member({"name":"青岚","relation":"父亲","age":65,"sex":"男","title":"松风真人","avatar":"male","mode":"family","consent":true})
	var actor = scene.family.state_for(member.id)
	actor.apply_health_profile(actor.HealthProfile.mock(40,1))
	scene.ui.activate_family(member.id)
	var wallet: int = actor.equipment.qi
	scene.ui.open_boss()
	await process_frame
	expect(scene.ui.corridor.portal_buttons.size()==20,"fixed progression presents twenty portals")
	await capture("fixed-progression")
	scene.ui.corridor.focus_boss(6)
	await process_frame
	await click(scene.ui.corridor.portal_buttons[6])
	var view: Control = scene.ui.combat
	view.set_process(false)
	expect(view.rules.brain.definition.rank==7 and view.dragon_frames.size()==16 and view.hero_bank.frames.size()==16,"actual portal loads fixed rank and both redrawn action atlases")
	await _hidden_geometry(view)
	expect(view.rules.hp==100 and view.vital_labels[0].text.contains("100 / 100"),"actual combat HUD starts at 100 full HP")
	await capture("100hp-no-range")
	view.hero.position = Vector2(650,610)
	var clock: float = view.clock
	await key(KEY_P)
	view._process(.5)
	expect(view.paused and view.clock==clock,"pause freezes frame animation and gameplay")
	await key(KEY_P)
	var dodged = false
	for frame in range(600):
		view._process(1.0/60)
		if view.rules.phase=="attack" and view.rules.brain.move.kind=="charge" :
			var heading: Vector2 = view.rules.brain.facing
			view.hero.position = view.rules.boss_position+heading*160
			view.facing = -heading
			await key(KEY_SPACE)
			for tick in range(8): view._process(1.0/60)
			dodged = view.rules.perfect_dodges==1
			break
	expect(dodged and view.rules.counter_time>0,"actual space input and moving charge collision produce precision")
	await capture("perfect-dodge")
	for tick in range(8): view._process(1.0/60)
	view.hero.position = view.rules.boss_position-Vector2(100,0)
	var hp_before: int = view.rules.boss_hp
	await key(KEY_J)
	expect(view.rules.boss_hp==hp_before and not view.rules.pending_action.is_empty() and view.cast_visual>0,"J begins windup without early damage")
	for tick in range(10): view._process(1.0/60)
	expect(view.rules.counter_time==0 and hp_before-view.rules.boss_hp>int(view.rules.stats.attack),"real J spends counter on a stronger landed strike")
	await capture("precision-counter")
	for tick in range(45): view._process(1.0/60)
	view.hero.position = view.rules.boss_position-Vector2(100,0)
	view.rules.poise = view.rules.max_poise-1
	await key(KEY_J)
	for frame in range(240):
		view._process(1.0/60)
		if view.rules.phase=="stagger": break
	expect(view.rules.phase=="stagger" and view.poise_bar.value==0,"landed input completes poise and visible stagger window")
	await capture("poise-break")
	scene.ui.combat.leave_battle()
	await process_frame
	expect(scene.ui.corridor.portal_buttons.size()==20,"return restores fixed progression corridor")
	for sample in [["b18","three-hit-chain"],["b03","ground-residue"]]:
		scene.ui.start_corridor_boss(sample[0])
		await process_frame
		view = scene.ui.combat
		view.set_process(false)
		view.hero.position = Vector2(650,610)
		view.rules._deal(roundi(view.rules.boss_max_hp*.70))
		var found = false
		for frame in range(1000):
			Guard.step(view)
			view._process(1.0/60)
			var brain: RefCounted = view.rules.brain
			if (sample[0]=="b18" and brain.phase=="windup" and brain.combo_index==2 and brain.progress()>.5) or (sample[0]=="b03" and not brain.hazards.is_empty()):
				found = true
				await capture(sample[1])
				break
			if frame%20==0: await process_frame
		expect(found,"actual scene shows "+sample[1])
		scene.ui.close_modal()
		await process_frame
	# Nine seconds of real rendering, with three-stage pressure and the existing movement inputs.
	scene.ui.start_corridor_boss("b18")
	await process_frame
	view = scene.ui.combat
	view.set_process(false)
	view.hero.position = Vector2(650,610)
	view.rules._deal(roundi(view.rules.boss_max_hp*.70))
	var frames = "res://work/action-assets/frames/chain"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames))
	var boss_poses: Dictionary = {}
	var hero_poses: Dictionary = {}
	for frame in range(270):
		if frame==40:
			view.hero.position = view.rules.boss_position-Vector2(100,0)
			await key(KEY_J)
		if frame==65: await key(KEY_SPACE)
		if frame==110: view.use_skill(0)
		Guard.step(view)
		view._process(1.0/30)
		boss_poses[view.boss_frame_index] = true
		hero_poses[view.hero_frame_index] = true
		if frame%3==0:
			await process_frame
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			image.resize(720,450,Image.INTERPOLATE_LANCZOS)
			image.save_png(frames.path_join("%03d.png" % (frame/3)))
	expect(boss_poses.size()>=6 and hero_poses.size()>=6,"rendered clip changes articulated boss and hero poses")
	expect(actor.equipment.qi==wallet and actor.lifecycle_record().state=="cultivating","challenge visuals and actions grant no wallet or lifecycle transitions")
	scene.ui.close_modal()
	await process_frame
	var female: Dictionary = scene.family.add_member({"name":"素月","relation":"母亲","age":63,"sex":"女","title":"素月真人","avatar":"female","mode":"family","consent":true})
	var female_actor = scene.family.state_for(female.id)
	female_actor.apply_health_profile(female_actor.HealthProfile.mock(40,1))
	scene.ui.activate_family(female.id)
	scene.ui.start_corridor_boss("b01")
	await process_frame
	view = scene.ui.combat
	view.set_process(false)
	expect(view.hero_bank.id=="hero_female" and view.hero_frame_index==15,"actual female family member uses generated idle frame")
	Input.action_press("move_right")
	for tick in range(12): view._process(1.0/60)
	Input.action_release("move_right")
	expect(view.hero_frame_index in [0,1,2,3],"actual movement plays female limb cycle")
	await capture("female-walk")
	view.hero.position = view.rules.boss_position-Vector2(100,0)
	await key(KEY_J)
	for tick in range(4): view._process(1.0/60)
	expect(view.hero_frame_index==5 and not view.rules.pending_action.is_empty(),"female sword arm draws back before impact")
	await capture("female-windup")
	for tick in range(5): view._process(1.0/60)
	expect(view.hero_frame_index==6 and view.rules.pending_action.is_empty(),"female extended sword frame matches actual hit")
	await capture("female-strike")
	for tick in range(35): view._process(1.0/60)
	await key(KEY_1)
	for tick in range(11): view._process(1.0/60)
	expect(view.hero_frame_index==10,"female sword spell has its own extended thrust frame")
	await capture("female-sword-skill")
	var roll_start: Vector2 = view.hero.position
	await key(KEY_SPACE)
	expect(view.hero.position==roll_start and view.roll_remaining==145,"actual dodge key reserves travel without teleporting")
	for tick in range(10): view._process(1.0/60)
	expect(view.hero_frame_index==13 and view.roll_remaining>0,"female dodge uses a folded-limb pose during continuous movement")
	await capture("female-roll")
	expect(female_actor.equipment.qi==0 and actor.equipment.qi==wallet,"animation actions keep both elders wallets isolated")
	scene.ui.close_modal()
	await process_frame
	scene.queue_free()
	await process_frame
	await create_timer(.3).timeout
	print("PR4_CHALLENGE_RENDER_TEST: %d assertions; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
