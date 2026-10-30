extends SceneTree
const Art = preload("res://scripts/campaign/creatures.gd")
const Catalogue = preload("res://scripts/campaign/catalogue.gd")
var passed := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for id in ["b03","sapling_tree","zhaosheng_pagoda"]:
		var asset = Art.blender_asset(id)
		check(asset != null, id + " imports as a game scene")
		if asset == null:
			continue
		root.add_child(asset)
		var meshes = asset.find_children("*","MeshInstance3D",true,false)
		check(meshes.size() > 0,id + " contains visible meshes")
		var bounds := AABB()
		var triangles := 0
		for mesh in meshes:
			var local_box: AABB = mesh.transform * mesh.get_aabb()
			bounds = bounds.merge(local_box)
			for surface in range(mesh.mesh.get_surface_count()):
				var material = mesh.get_active_material(surface)
				check(material != null,id + " retains material")
				if id == "b03" and material != null and material.resource_name.begins_with("Q2_bark"):
					check(material.albedo_texture != null,"Wood basecolor texture survives GLB")
					check(material.normal_enabled and material.normal_texture != null,"Wood tangent normal survives GLB")
					var arrays = mesh.mesh.surface_get_arrays(surface)
					check(arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() > 0,"Wood has usable UVs in game mesh")
				var indices = mesh.mesh.surface_get_array_index_len(surface)
				triangles += indices / 3 if indices > 0 else mesh.mesh.surface_get_array_len(surface) / 3
		check(triangles > 0 and triangles < 100000,id + " is under the scene mesh budget")
		if id == "b03":
			var skeletons = asset.find_children("*","Skeleton3D",true,false)
			check(skeletons.size() == 1,"Deer retains one skeleton")
			if not skeletons.is_empty():
				check(skeletons[0].get_bone_count() == 7,"All seven articulated bones survive import")
			var player = asset.find_child("AnimationPlayer",true,false) as AnimationPlayer
			check(player != null,"Deer retains animation player")
			if player != null:
				for clip in ["Idle","Walk","Attack"]:
					check(player.has_animation(clip),"Deer retains " + clip)
					if player.has_animation(clip):
						var animation = player.get_animation(clip)
						check(animation.length > 0,"Animation has real duration " + clip)
						check(animation.get_track_count() > 0,"Animation contains transform tracks " + clip)
						player.play(clip)
						player.seek(animation.length*0.4,true)
						if not skeletons.is_empty():
							var bone_id = skeletons[0].find_bone("frontL" if clip == "Walk" else "head")
							check(skeletons[0].get_bone_pose_rotation(bone_id).get_angle() > 0.0001,"Animation actually moves imported bone " + clip)
				check(player.autoplay == "Idle","Idle starts in actual encounter")
			if player != null:
				player.play("Idle")
			Art.play_attack(asset)
			if player != null:
				check(player.current_animation == "Attack","Combat attack starts imported clip")
				check("Idle" in player.get_queue(),"Attack queues Idle")
				player.advance(player.get_animation("Attack").length+0.2)
				check(player.current_animation == "Idle","Finished attack really returns to Idle")
		asset.free()
	var boss = Art.model(Catalogue.entry("b03"),"bosses")
	check(boss != null and boss.find_children("*","Skeleton3D",true,false).size() == 1,"Boss loader selects refined Blender asset")
	boss.free()
	check(Art.blender_asset("missing-asset") == null,"Missing resource preserves procedural fallback path")
	print("Blender assets: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
