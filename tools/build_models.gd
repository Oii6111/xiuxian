extends SceneTree
const Catalogue = preload("res://scripts/campaign/catalogue.gd")
const Art = preload("res://scripts/campaign/creatures.gd")
var failures: int = 0
var manifest: Array = []

func _initialize() -> void:
	build.call_deferred()

func own_children(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		own_children(child,root_node)

func save_model(root_node: Node3D, folder: String, id: String, label: String) -> void:
	root_node.name = id
	own_children(root_node,root_node)
	var directory = "res://assets/generated/" + folder
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path = directory + "/" + id + ".tscn"
	var packed = PackedScene.new()
	var error = packed.pack(root_node)
	if error == OK:
		error = ResourceSaver.save(packed,path)
	if error != OK:
		failures += 1
		push_error("Model export failed: "+path)
	else:
		manifest.append({"id":id,"name":label,"kind":folder,"path":path,"origin":"original_procedural_q3d","editable":true})
	root_node.free()

func build() -> void:
	for row in Catalogue.all():
		save_model(Art.beast(row),"bosses",row.id,row.name)
	for row in Catalogue.minions():
		save_model(Art.minion(row),"minions",row.id,row.name)
	for row in Catalogue.people():
		save_model(Art.npc(row),"npcs",row.id,row.name)
	var file = FileAccess.open("res://assets/generated/model_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":1,"models":manifest}, "\t"))
	file.close()
	print("MODEL EXPORT: ",manifest.size()," scenes, ",failures," failures")
	quit(failures)
