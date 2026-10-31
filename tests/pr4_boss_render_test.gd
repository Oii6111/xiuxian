extends SceneTree
const Guard = preload("res://tests/helpers/pr4_render_guard.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
var checks: int = 0
var failures: Array = []
var folder = "res://outputs/combat-lifecycle/boss-polish"
func _init() -> void: call_deferred("_run")
func expect(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("FAIL: ",title)
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	expect(image!=null and image.save_png(folder.path_join(name+".png"))==OK,"render "+name)
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
	var kinds: Dictionary = {}
	var mechanic_shots: Dictionary = {}
	for row in Catalogue.all():
		scene.ui.start_corridor_boss(row.id)
		await process_frame
		var view: Control = scene.ui.combat
		view.set_process(false)
		expect(view.dragon_frames.size()==16 and view.boss_bank.id==row.id,"actual scene uses its own complete action atlas "+row.id)
		view.hero.position = Vector2(660,610)
		if row.id == "b01": view.hero.position = view.rules.boss_position-Vector2(190,0)
		view.rules._deal(roundi(view.rules.boss_max_hp*.70))
		var start: Vector2 = view.rules.boss_position
		var tell = false
		var attack = false
		var recovery = false
		for frame in range(330):
			Guard.step(view)
			view._process(1.0/30)
			var brain: RefCounted = view.rules.brain
			if brain.phase=="windup": kinds[brain.move.kind] = true
			if brain.phase=="attack" and brain.progress()>=.60 and not mechanic_shots.has(brain.move.kind):
				await capture("mechanic-"+str(brain.move.kind))
				mechanic_shots[brain.move.kind] = {"boss":row.name,"move":brain.move.name}
			if not tell and brain.phase == "windup" and brain.progress()>=.68:
				tell = true
				kinds[brain.move.kind] = true
				await capture(row.id+"-tell")
				# P freezes all gameplay clocks, including moving enemies.
				view.paused = true
				var frozen: Vector2 = view.rules.boss_position
				view._process(.4)
				expect(view.rules.boss_position==frozen,"pause freezes boss "+row.id)
				view.paused = false
			if tell and not attack and brain.phase == "attack" and brain.progress()>=.6:
				attack = true
				await capture(row.id+"-attack")
			if attack and brain.phase == "breath":
				recovery = true
				if str(brain.move.kind) in ["leap","nova","eruption"]:
					await capture(row.id+"-impact")
				break
			if frame%15 == 0: await process_frame
		expect(start.distance_to(view.rules.boss_position)>20,"actual scene boss moves "+row.id)
		expect(tell and attack and recovery,"visible tell, committed attack, recovery "+row.id)
		expect(view.dragon.position.distance_to(view.rules.boss_position)<170,"sprite follows authoritative combat foot "+row.id)
		expect(view.enemy_intent.text.contains("收招"),"recovery is explained by real HUD "+row.id)
		scene.ui.close_modal()
		await process_frame
	expect(kinds.size()==8 and mechanic_shots.size()==8,"actual main scenes display all eight attack mechanics")
	var metadata = FileAccess.open(folder.path_join("mechanics.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify(mechanic_shots,"  "))
	metadata.close()
	for id in ["b06","b16"]:
		scene.ui.start_corridor_boss(id)
		await process_frame
		var view: Control = scene.ui.combat
		view.set_process(false)
		view.hero.position = Vector2(640,610)
		var frames = "res://work/boss-polish/frames/"+id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames))
		for frame in range(180):
			Guard.step(view)
			view._process(1.0/30)
			if frame%3 == 0:
				await process_frame
				await RenderingServer.frame_post_draw
				var image: Image = root.get_texture().get_image()
				image.resize(720,450,Image.INTERPOLATE_LANCZOS)
				image.save_png(frames.path_join("%03d.png" % (frame/3)))
		scene.ui.close_modal()
		await process_frame
	scene.queue_free()
	await process_frame
	await create_timer(.3).timeout
	print("PR4_BOSS_RENDER_TEST: %d assertions; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
