extends SceneTree
const Roster = preload("res://scripts/family_roster.gd")
const State = preload("res://scripts/game_state.gd")
const Catalogue = preload("res://scripts/companion_catalogue.gd")
const Context = preload("res://scripts/companion_context.gd")
const Client = preload("res://scripts/companion_client.gd")
var passed = 0
var failed = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var family = Roster.new()
	family.persist_enabled = false
	check(family.companion.id.is_empty(), "Existing accounts without pet data start with a free choice")
	var original = family.owner_state.to_data().duplicate(true)
	for id in Catalogue.IDS:
		check(family.choose_companion(id, "").ok and family.companion.nickname == Catalogue.PETS[id].nickname, "All four pets can be selected with a default nickname: " + id)
		var texture = Catalogue.texture(id)
		check(texture != null and texture.get_width() > 0 and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "Each pet uses a real transparent asset: " + id)
	check(family.members.is_empty() and family.owner_state.to_data() == original, "Changing pets consumes no elder slot, currency or character progress")
	var old_pet = family.companion.duplicate(true)
	check(not family.choose_companion("unknown", "bad").ok and family.companion == old_pet, "Unknown pet IDs cannot replace the selected companion")
	family.choose_companion("cloud_fox", "  云\n绒  ")
	check(family.companion.nickname == "云 绒", "Nicknames are normalized before saving")
	var fixture = "res://output/companion-save-%d.json" % OS.get_process_id()
	family.save_file_override = fixture
	family.persist_enabled = true
	check(family.choose_companion("gourd_dragon", "小团子").ok, "Companion choice is committed to the account file")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	check(saved.schema == 8 and saved.companion.nickname == "小团子" and not saved.has("history"), "Compatible saves contain the pet but no conversations")
	var restored = Roster.new()
	restored.save_file_override = fixture
	restored.load_game(State.new())
	check(restored.companion == family.companion and restored.owner_state.to_data() == family.owner_state.to_data(), "Restart restores the pet while retaining all character data")
	restored.save_file_override = "res://output/absent-companion-test-dir/save.json"
	check(not restored.choose_companion("lotus_bird", "啾").ok and restored.companion == family.companion, "Failed saving rolls back the entire choice")
	saved.erase("companion")
	var file = FileAccess.open(fixture, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var legacy = Roster.new()
	legacy.save_file_override = fixture
	legacy.load_game(State.new())
	check(not legacy.load_blocked and legacy.companion.id.is_empty(), "Old schema 8 saves remain readable without migration or automatic selection")
	var fresh = Roster.new()
	fresh.persist_enabled = false
	check(fresh.companion.id.is_empty(), "A different account receives an independent pet selection")
	var valid = {"request_id": "r", "conversation_id": "c", "reply": "你好", "animation": "execute_code", "reward": 99999, "actions": [{"id": "record", "label": "查看记录"}, {"id": "give_qi", "label": "发奖"}]}
	var cleaned = Client.clean_response(valid, "r", "c")
	check(cleaned.actions.size() == 1 and cleaned.actions[0].id == "record" and not cleaned.has("reward") and cleaned.animation == "talk", "HTTP replies can only show plain text, preset animations and navigation")
	check(Client.clean_response(valid, "wrong", "c").is_empty() and Client.clean_response(valid, "r", "wrong").is_empty(), "Stale request and conversation IDs are rejected")
	check(Client.clean_response({"reply": ["bad"]}, "r", "c").is_empty(), "Malformed API data cannot enter the transcript")
	check(Client.clean_response({"request_id": "r", "conversation_id": "c", "reply": "你好"}, "r", "c").actions.is_empty(), "A valid text-only API response needs no optional action fields")
	check(Client.endpoint_allowed("https://example.com/api/chat") and Client.endpoint_allowed("http://127.0.0.1:8031/api/chat"), "HTTPS and local development endpoints are supported")
	check(not Client.endpoint_allowed("http://example.com/api/chat") and not Client.endpoint_allowed("http://localhost.evil/api/chat") and not Client.endpoint_allowed("https://token@example.com/api/chat"), "Remote plain HTTP and credential-bearing URLs are rejected")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.family.persist_enabled = false
	var dad = game.family.add_member({"name": "隐私姓名", "relation": "父亲", "age": 68, "sex": "男", "consent": true})
	var dad_state = game.family.state_for(dad.id)
	dad_state.record_task("planned_record", true)
	game.family.select_member("self")
	var context = Context.snapshot(game)
	check(context.characters.size() == 2 and context.characters[0].member_id == "self", "Companion context separates self and elder task records")
	check(context.characters[0].tasks[0].status == "not_applicable" and context.characters[1].tasks[1].status == "confirmed", "Task projection distinguishes no plan, recorded and unrecorded")
	var text = JSON.stringify(context)
	check(not "隐私姓名" in text and not "health_baseline" in text and not "health_attributes" in text and not "age" in text and not "token" in text, "API context excludes real names, clinical values and credentials")
	check("暂未收到记录" in Context.task_summary(context, true) and "已确认" in Context.task_summary(context, true), "Family summaries report only known record status")
	check("暂未收到记录" in Context.local_reply("我今天的任务完成了吗？", context, {}).reply, "Questions about completion read task status instead of becoming completion claims")
	var before = game.family.to_data().duplicate(true)
	Context.local_reply("我已经吃过药，任务完成了", context, {})
	check(game.family.to_data() == before, "Saying a task was done never writes completion or grants rewards")
	check(Context.next_step(context).actions[0].id == "health", "The first next-step hint opens the current character profile")
	game.ui.open_companion(true)
	await process_frame
	await process_frame
	var panel = game.ui.companion_panel
	check(panel.choice_buttons.size() == 4 and game.player.blocked, "The real selector shows four pets and stops map movement")
	for id in Catalogue.IDS:
		panel.select_pet(id)
		check(panel.selected_id == id and panel.choice_buttons[id].get_global_rect().end.x < 1291, "Every selection card is visible and selectable: " + id)
	panel.select_pet("gourd_dragon")
	panel.nickname_input.text = "小团子"
	panel.confirm_choice()
	await process_frame
	await process_frame
	check(game.family.companion.id == "gourd_dragon" and game.family.companion.nickname == "小团子" and not panel.choose_mode, "Confirming a pet opens its actual chat panel")
	check(game.companion_actor.visible and game.companion_actor.current_id == "gourd_dragon", "The selected pet is instantiated in the village")
	panel.send_message("家人今天的记录怎么样？")
	await process_frame
	await process_frame
	check(not game.companion_api.busy and game.companion_api.history[-1].source == "local_guide" and "已确认" in game.companion_api.history[-1].text, "Local chat answers with the current family records")
	check(game.family.state_for(dad.id).equipment.qi == 100 and game.family.owner_state.equipment.qi == 0, "Chatting preserves independent reward wallets")
	panel.open_action("record")
	await process_frame
	check(game.ui.companion_panel == null and game.ui.modal_open, "A chat navigation button opens the existing confirmation page")
	game.ui.close_modal()
	await process_frame
	check(not game.player.blocked, "Closing the conversation or destination resumes movement")
	var selected = game.family.companion.duplicate(true)
	game.ui.activate_family(dad.id)
	game.ui.close_modal()
	check(game.family.companion == selected, "Switching elders preserves the account companion")
	game.ui.open_companion()
	await process_frame
	check(game.ui.companion_panel != null and game.family.active_id == dad.id, "Chat uses the newly selected elder without changing ownership")
	game.ui.close_modal()
	game.ui.start_battle()
	game.ui.open_companion()
	check(game.ui.companion_panel == null and is_instance_valid(game.ui.combat), "Companion entry cannot interrupt an active battle")
	game.ui.close_modal()
	game.companion_api.reset_session()
	check(game.companion_api.history.is_empty() and not game.companion_api.busy, "Account session reset clears conversations and outstanding requests")
	game.queue_free()
	await process_frame
	family.dispose()
	restored.dispose()
	legacy.dispose()
	fresh.dispose()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	print("COMPANION CHECKS: ", passed, " passed, ", failed, " failed")
	quit(1 if failed else 0)
