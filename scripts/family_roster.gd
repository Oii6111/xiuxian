extends RefCounted
## Local child account, at most two elders. Every member owns a separate GameState.
const State = preload("res://scripts/game_state.gd")
const Privacy = preload("res://scripts/game_save_privacy.gd")
const LegacySaves = preload("res://scripts/legacy_saves.gd")
const MAX_MEMBERS = 2
const Companions = preload("res://scripts/companion_catalogue.gd")
var companion: Dictionary = Companions.clean({})
var members: Array = []
var active_id = "self"
var owner_state: RefCounted
var account_bound = false
var cache_root_override = ""
var legacy_source_override = ""
var legacy_candidates_override = PackedStringArray()
var legacy_record: Dictionary = {}
var legacy_choice_made = false
var account = {"id": "local-child", "name": "我的守护账号"}
var persist_enabled = true
var save_file_override = ""
var last_error = ""
var load_blocked = false

func _init() -> void:
	reset_owner()

func reset_owner(identity: Dictionary = {}) -> void:
	if owner_state != null:
		owner_state.family_save = Callable()
	owner_state = State.new()
	owner_state.cultivation = 0
	owner_state.seals = 0
	owner_state.days = 0
	owner_state.medication_required = false
	owner_state.choose_avatar(str(identity.get("avatar", "male")), str(identity.get("display_name", "我的角色")))
	bind_owner(owner_state, {"name": str(identity.get("display_name", "我")), "relation": "本人", "age": 0, "sex": "", "title": owner_state.player_name, "avatar": owner_state.avatar_id, "mode": "self", "consent": false})

func bind_owner(state, identity: Dictionary = {}) -> void:
	if owner_state != null and owner_state != state:
		owner_state.family_save = Callable()
	owner_state = state
	owner_state.family_member_id = "self"
	owner_state.family_identity = identity.duplicate(true)
	owner_state.family_identity.relation = "本人"
	owner_state.family_identity.mode = "self"
	owner_state.family_identity.title = state.player_name
	owner_state.family_identity.avatar = state.avatar_id
	owner_state.persist_enabled = persist_enabled
	owner_state.family_save = save_game

func cache_root() -> String:
	if not cache_root_override.is_empty():
		return cache_root_override
	return "res://output/accounts" if OS.has_feature("editor") else "user://accounts"

func legacy_candidates() -> PackedStringArray:
	if not legacy_source_override.is_empty():
		return PackedStringArray([legacy_source_override])
	if not legacy_candidates_override.is_empty():
		return legacy_candidates_override
	return LegacySaves.candidates(OS.has_feature("editor"))

func legacy_path() -> String:
	return str(legacy_record.path) if not legacy_record.is_empty() else LegacySaves.resolve(legacy_candidates())

func discover_legacy() -> Dictionary:
	legacy_record.clear()
	var path = LegacySaves.resolve(legacy_candidates())
	if path.is_empty():
		return {"ok": true, "found": false}
	var document = Privacy.read(path, persist_enabled, true)
	if not document.ok:
		last_error = document.message
		return {"ok": false, "message": last_error}
	var digest = FileAccess.get_file_as_string(path).sha256_text()
	if digest != document.disk_digest:
		last_error = "旧存档在检查期间发生变化，请重新登录后确认。"
		return {"ok": false, "message": last_error}
	var fingerprint = str(document.data.get("legacy_import_fingerprint", digest))
	var pattern = RegEx.new()
	pattern.compile("^[a-f0-9]{64}$")
	if pattern.search(fingerprint) == null:
		fingerprint = digest
	legacy_record = {"path": path, "digest": digest, "fingerprint": fingerprint}
	return {"ok": true, "found": true}

func legacy_snapshot() -> Dictionary:
	if legacy_record.is_empty():
		var found = discover_legacy()
		if not found.ok:
			return found
	if legacy_record.is_empty() or not FileAccess.file_exists(legacy_record.path):
		return {"ok": false, "message": "旧存档已不存在，请重新登录后检查。"}
	if FileAccess.get_file_as_string(legacy_record.path).sha256_text() != legacy_record.digest:
		return {"ok": false, "message": "旧存档已发生变化，请重新登录后确认导入。"}
	return {"ok": true, "path": legacy_record.path, "fingerprint": legacy_record.fingerprint}

func pristine_account() -> bool:
	var state = owner_state
	return members.is_empty() and state.health_profile_id.is_empty() and state.health_baseline.is_empty() and state.cultivation == 0 and state.seals == 0 and state.days == 0 and state.contribution == 0 and state.boss_attempts == 0 and state.cleared_bosses.is_empty() and state.cleared_stages.is_empty() and state.rewarded_days.is_empty() and state.daily_tasks.is_empty() and state.equipment.qi == 0 and state.equipment.inventory.is_empty() and state.equipment.receipts.is_empty()

func open_account(identity: Dictionary) -> Dictionary:
	legacy_record.clear()
	var pattern = RegEx.new()
	# 旧本机账号为 32 位十六进制；C 统一账号为 account_<uuid>。
	pattern.compile("^([a-f0-9]{32}|account_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$")
	if pattern.search(str(identity.get("id", ""))) == null:
		return {"ok": false, "message": "账号标识无效。"}
	dispose()
	members.clear()
	load_blocked = false
	last_error = ""
	legacy_choice_made = false
	account = identity.duplicate(true)
	account.name = str(identity.get("display_name", identity.get("username", "我的账号")))
	account_bound = true
	companion = Companions.clean({})
	reset_owner(identity)
	active_id = "self"
	if FileAccess.file_exists(save_path()):
		var cached = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
		if not cached is Dictionary or not cached.get("account") is Dictionary or cached.account.get("id", "") != account.id:
			load_blocked = true
			return {"ok": false, "message": "账号存档归属不一致，原文件已保留。"}
		var authenticated = account.duplicate(true)
		load_game(owner_state)
		account = authenticated
		if load_blocked:
			return {"ok": false, "message": last_error}
		if not legacy_choice_made and pristine_account():
			var recoverable = discover_legacy()
			if not recoverable.ok:
				return recoverable
			if recoverable.found:
				return {"ok": true, "needs_import": true, "existing": true}
		return {"ok": true, "needs_import": false, "existing": true}
	var legacy = discover_legacy()
	if not legacy.ok:
		return legacy
	return {"ok": true, "needs_import": legacy.found, "existing": false}

func import_legacy() -> bool:
	var source = legacy_snapshot()
	if not source.ok:
		last_error = source.message
		return false
	var authenticated = account.duplicate(true)
	var old_override = save_file_override
	save_file_override = source.path
	account_bound = false
	load_game(owner_state, legacy_record.digest)
	save_file_override = old_override
	account_bound = true
	account = authenticated
	if load_blocked:
		return false
	legacy_choice_made = true
	return save_game()

func save_path() -> String:
	if not save_file_override.is_empty():
		return save_file_override
	if account_bound:
		return cache_root().path_join(str(account.id) + ".json")
	return LegacySaves.primary(OS.has_feature("editor"))

func state_for(id: String):
	if id == "self":
		return owner_state
	for member in members:
		if member.id == id:
			return member.state
	return null

func active_state():
	return state_for(active_id)

func identity_for(id: String) -> Dictionary:
	var state = state_for(id)
	return state.family_identity if state != null else {}

func validate_identity(payload: Dictionary) -> Dictionary:
	var name = str(payload.get("name", "")).strip_edges()
	var relation = str(payload.get("relation", "")).strip_edges()
	var raw_age = str(payload.get("age", "")).strip_edges()
	var sex = str(payload.get("sex", ""))
	var mode = str(payload.get("mode", "family"))
	if name.is_empty() or name.length() > 10:
		return {"ok": false, "message": "请填写家人姓名，最多 10 个字。"}
	if relation in ["本人", "自己", "我", "self"]:
		return {"ok": false, "message": "本人角色在账号区域，两个家人位置专门用于老人。"}
	if relation.is_empty() or relation.length() > 30:
		return {"ok": false, "message": "请填写与我的关系，例如父亲、母亲。"}
	if not raw_age.is_valid_int() or int(raw_age) < 1 or int(raw_age) > 120:
		return {"ok": false, "message": "年龄请填写 1—120 之间的整数。"}
	if sex not in ["男", "女"]:
		return {"ok": false, "message": "请选择家人性别。"}
	if mode not in ["family", "self"] or payload.get("consent", false) != true:
		return {"ok": false, "message": "请确认本人同意，或已获得家人同意后代填。"}
	var title = str(payload.get("title", "")).strip_edges().left(10)
	if title.is_empty():
		title = name + "的化身"
	return {"ok": true, "identity": {"name": name, "relation": relation, "age": int(raw_age), "sex": sex, "title": title.left(10), "avatar": "female" if payload.get("avatar", "male") == "female" else "male", "mode": mode, "consent": true}}

func bind_state(id: String, identity: Dictionary, state) -> void:
	state.family_member_id = id
	state.family_identity = identity.duplicate(true)
	state.family_identity.name = str(identity.get("name", "家人")).left(10)
	state.family_identity.relation = str(identity.get("relation", "")).left(30)
	state.family_identity.age = clampi(int(identity.get("age", 0)), 0, 120)
	state.family_identity.title = state.player_name
	state.family_identity.avatar = state.avatar_id
	state.persist_enabled = persist_enabled
	state.family_save = save_game
	members.append({"id": id, "state": state})

func add_member(payload: Dictionary) -> Dictionary:
	if members.size() >= MAX_MEMBERS:
		return {"ok": false, "message": "当前最多照顾两位老人。"}
	var checked = validate_identity(payload)
	if not checked.ok:
		return checked
	var identity = checked.identity
	for member in members:
		var other = member.state.family_identity
		if other.get("name", "") == identity.name and other.get("age", 0) == identity.age and other.get("sex", "") == identity.sex:
			return {"ok": false, "message": "这位家人已有档案，请直接选择原来的角色。"}
	var state = State.new()
	state.cultivation = 0
	state.seals = 0
	state.days = 0
	state.medication_required = false
	state.choose_avatar(identity.avatar, identity.title)
	var id = "elder_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var before_id = active_id
	bind_state(id, identity, state)
	active_id = id
	if not save_game():
		members.pop_back()
		active_id = before_id
		state.family_save = Callable()
		return {"ok": false, "message": "家人档案保存失败，尚未占用位置，请重试。"}
	return {"ok": true, "id": id, "message": "家人已添加，可以开始代填健康资料。"}

func update_member(id: String, payload: Dictionary) -> Dictionary:
	var state = state_for(id)
	if state == null:
		return {"ok": false, "message": "没有找到这位家人。"}
	var checked = validate_identity(payload)
	if not checked.ok:
		return checked
	for member in members:
		var other = member.state.family_identity
		if member.id != id and other.get("name", "") == checked.identity.name and other.get("age", 0) == checked.identity.age and other.get("sex", "") == checked.identity.sex:
			return {"ok": false, "message": "另一位家人已有相同基本资料，请检查当前编辑对象。"}
	var before = state.family_identity.duplicate(true)
	var old_created = state.profile_created
	var old_avatar = state.avatar_id
	var old_name = state.player_name
	state.family_identity = checked.identity
	state.choose_avatar(checked.identity.avatar, checked.identity.title)
	if not save_game():
		state.family_identity = before
		state.avatar_id = old_avatar
		state.player_name = old_name
		state.profile_created = old_created
		return {"ok": false, "message": "保存失败，原有家人资料已保留。"}
	return {"ok": true, "id": id, "message": "基本资料已保存，健康属性和成长进度保持原样。"}

func select_member(id: String) -> Dictionary:
	if state_for(id) == null:
		return {"ok": false, "message": "没有找到这位家人。"}
	var before = active_id
	active_id = id
	if not save_game():
		active_id = before
		return {"ok": false, "message": "切换保存失败，仍保留当前家人。"}
	return {"ok": true, "id": id}

func is_remote() -> bool:
	return not owner_state.cultivator_id.is_empty()

func id_for_cultivator(cultivator_id: String) -> String:
	if owner_state.cultivator_id == cultivator_id:
		return "self"
	for member in members:
		if member.state.cultivator_id == cultivator_id:
			return str(member.id)
	return ""

static func remote_identity(character: Dictionary) -> Dictionary:
	var profile = character.get("profile", {})
	return {"name": str(character.get("name", "家人")).left(10), "relation": str(profile.get("relation", "")), "age": int(profile.get("age", 0)), "sex": str(profile.get("sex", "")), "title": str(profile.get("title", character.get("name", ""))).left(10), "avatar": "female" if profile.get("avatar", "male") == "female" else "male", "mode": str(profile.get("mode", "family")), "consent": profile.get("consent", false) == true}

static func remote_profile(identity: Dictionary) -> Dictionary:
	return {"title": identity.title, "avatar": identity.avatar, "relation": identity.relation, "age": int(identity.age), "sex": identity.sex, "mode": identity.mode, "consent": true}

## C 是家族角色的权威来源：本人与两位老人按 cultivator_id 对应。只在本机存在的老人补建到 C，再用服务端快照刷新钱包、装备与初始投影。
func apply_remote(cultivators: Array, core: Node) -> Dictionary:
	var remote = {}
	for character in cultivators:
		if character is Dictionary and character.get("role") in ["self", "elder"]:
			remote[str(character.cultivator_id)] = character
	for character in remote.values():
		if character.role == "self":
			owner_state.cultivator_id = str(character.cultivator_id)
	for member in members.duplicate():
		if member.state.cultivator_id.is_empty() and core != null:
			var identity = member.state.family_identity
			var created = await core.dispatch("growth.create_member", {"role": "elder", "name": str(identity.get("name", "")), "profile": remote_profile(identity), "request_id": "member-" + str(account.id) + "-" + str(member.id)})
			if not created.ok and created.get("code") != "MEMBER_EXISTS":
				return created
			if created.ok:
				member.state.cultivator_id = str(created.data.cultivator_id)
				remote[member.state.cultivator_id] = created.data
	for character in remote.values():
		if character.role == "elder" and id_for_cultivator(str(character.cultivator_id)).is_empty() and members.size() < MAX_MEMBERS:
			var state = State.new()
			state.cultivation = 0
			state.seals = 0
			state.days = 0
			state.medication_required = false
			var identity = remote_identity(character)
			state.choose_avatar(identity.avatar, identity.title)
			state.cultivator_id = str(character.cultivator_id)
			bind_state(str(character.cultivator_id), identity, state)
	for member in members.duplicate():
		if not remote.has(member.state.cultivator_id):
			# 服务端不再承认的角色不能继续持有本地奖励缓存。
			member.state.family_save = Callable()
			members.erase(member)
	if state_for(active_id) == null:
		active_id = "self"
	owner_state.apply_remote(remote.get(owner_state.cultivator_id, {}))
	for member in members:
		member.state.apply_remote(remote[member.state.cultivator_id])
	if not save_game():
		return {"ok": false, "message": last_error}
	return {"ok": true}

func remote_add_member(payload: Dictionary, core: Node) -> Dictionary:
	if members.size() >= MAX_MEMBERS:
		return {"ok": false, "message": "当前最多照顾两位老人。"}
	var checked = validate_identity(payload)
	if not checked.ok:
		return checked
	var created = await core.dispatch("growth.create_member", {"role": "elder", "name": checked.identity.name, "profile": remote_profile(checked.identity), "request_id": "member-" + str(account.id) + "-" + checked.identity.name + "-" + str(checked.identity.age) + checked.identity.sex})
	if not created.ok:
		return {"ok": false, "message": str(created.message)}
	var state = State.new()
	state.cultivation = 0
	state.seals = 0
	state.days = 0
	state.medication_required = false
	state.choose_avatar(checked.identity.avatar, checked.identity.title)
	state.cultivator_id = str(created.data.cultivator_id)
	bind_state(state.cultivator_id, checked.identity, state)
	state.apply_remote(created.data)
	active_id = state.cultivator_id
	if not save_game():
		return {"ok": false, "message": "家人已在服务端建立，本机缓存保存失败，重新登录后会恢复。"}
	return {"ok": true, "id": state.cultivator_id, "message": "家人已添加，可以开始代填健康资料。"}

func remote_update_member(id: String, payload: Dictionary, core: Node) -> Dictionary:
	var state = state_for(id)
	if state == null or id == "self":
		return {"ok": false, "message": "没有找到这位家人。"}
	var checked = validate_identity(payload)
	if not checked.ok:
		return checked
	var updated = await core.dispatch("growth.update_member", {"cultivator_id": state.cultivator_id, "name": checked.identity.name, "profile": remote_profile(checked.identity), "request_id": "update-" + state.cultivator_id + "-" + JSON.stringify(checked.identity, "", true).sha256_text()})
	if not updated.ok:
		return {"ok": false, "message": str(updated.message)}
	state.family_identity = checked.identity
	state.choose_avatar(checked.identity.avatar, checked.identity.title)
	save_game()
	return {"ok": true, "id": id, "message": "基本资料已保存，健康属性和成长进度保持原样。"}

func choose_companion(id: String, nickname: String) -> Dictionary:
	if not Companions.valid(id):
		return {"ok": false, "message": "请选择一位同行灵宠。"}
	var before = companion.duplicate(true)
	companion = Companions.clean({"id": id, "nickname": nickname})
	if not save_game():
		companion = before
		return {"ok": false, "message": "灵宠选择保存失败，已保留原来的伙伴，请重试。"}
	return {"ok": true, "message": "你的同行灵宠已经准备好啦。"}

func to_data() -> Dictionary:
	var records = []
	for member in members:
		records.append({"id": member.id, "identity": member.state.family_identity.duplicate(true), "progress": member.state.to_data()})
	return Privacy.clean({"schema": 8, "companion": Companions.clean(companion), "legacy_choice_made": legacy_choice_made, "account": account.duplicate(true), "owner": {"identity": owner_state.family_identity.duplicate(true), "progress": owner_state.to_data()}, "active_member_id": active_id, "members": records})

func save_game() -> bool:
	for state in [owner_state] + members.map(func(member): return member.state):
		if state != null and not state.lifecycle_load_error.is_empty():
			last_error = state.lifecycle_load_error
			return false
	if load_blocked:
		return false
	last_error = ""
	if not persist_enabled:
		return true
	var path = save_path()
	if account_bound and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		last_error = "无法创建当前账号的存档目录。"
		return false
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入家人存档。"
		return false
	file.store_string(JSON.stringify(to_data()))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
		last_error = "家人存档保存失败。"
		return false
	return true

func adopt_legacy(state) -> void:
	var name = str(state.health_baseline.get("display_name", state.player_name))
	bind_owner(state, {"name": name, "relation": "本人", "age": 0, "sex": "", "title": state.player_name, "avatar": state.avatar_id, "mode": "self", "consent": false})
	active_id = "self"

func load_game(fallback_state, expected_digest: String = "") -> void:
	# Validate into a detached roster; never append to or partly overwrite live state.
	var staged = get_script().new()
	staged.persist_enabled = persist_enabled
	staged.save_file_override = save_file_override
	staged.cache_root_override = cache_root_override
	staged.legacy_source_override = legacy_source_override
	staged.legacy_candidates_override = legacy_candidates_override
	staged.account_bound = account_bound
	staged.account = account.duplicate(true)
	var fallback = State.new()
	fallback.load_data(fallback_state.to_data())
	staged.load_staged(fallback, expected_digest)
	if staged.load_blocked:
		load_blocked = true
		last_error = staged.last_error
		staged.dispose()
		return
	dispose()
	members = staged.members
	owner_state = staged.owner_state
	active_id = staged.active_id
	account = staged.account
	companion = staged.companion
	legacy_choice_made = staged.legacy_choice_made
	load_blocked = false
	last_error = ""
	owner_state.family_save = save_game
	for member in members:
		member.state.family_save = save_game
	staged.members = []
	staged.owner_state = null

func load_staged(fallback_state, expected_digest: String = "") -> void:
	var path = save_path()
	if save_file_override.is_empty() and not account_bound:
		path = LegacySaves.resolve(legacy_candidates())
	if path.is_empty() or not FileAccess.file_exists(path):
		if not account_bound and (not fallback_state.health_profile_id.is_empty() or fallback_state.profile_created):
			adopt_legacy(fallback_state)
		return
	var document = Privacy.read(path, persist_enabled, not account_bound)
	if not document.ok:
		last_error = document.message
		load_blocked = true
		return
	if not expected_digest.is_empty() and document.disk_digest != expected_digest:
		last_error = "旧存档在导入期间发生变化，请重新登录后确认。"
		load_blocked = true
		return
	var original = document.text
	var data = document.data
	legacy_choice_made = data.get("legacy_choice_made", false) == true
	companion = Companions.clean(data.get("companion", {}))
	if int(data.get("schema", 1)) > 8:
		last_error = "存档版本较新，请使用对应版本的游戏。"
		load_blocked = true
		return
	if int(data.get("schema", 1)) in [7, 8]:
		if not data.get("members", []) is Array or data.get("members", []).size() > MAX_MEMBERS:
			last_error = "家人存档格式异常，原文件已保留。"
			load_blocked = true
			return
		var ids = {"self": true} if int(data.schema) == 8 else {}
		var moved_self_id = ""
		if int(data.schema) == 8:
			var own = data.get("owner", {})
			if not own is Dictionary or not own.get("progress") is Dictionary or not own.get("identity") is Dictionary:
				last_error = "本人角色存档不完整，原文件已保留。"
				load_blocked = true
				return
			var own_state = State.new()
			own_state.load_data(own.progress)
			bind_owner(own_state, own.identity)
		for record in data.get("members", []):
			if not record is Dictionary or not record.get("identity") is Dictionary or not record.get("progress") is Dictionary or str(record.get("id", "")).is_empty() or ids.has(str(record.get("id", ""))):
				last_error = "家人存档不完整，原文件已保留。"
				load_blocked = true
				dispose()
				members.clear()
				return
			var state = State.new()
			state.load_data(record.progress)
			var is_self = int(data.schema) == 7 and ((str(record.id) == "elder_legacy" and str(record.identity.get("relation", "")).is_empty()) or str(record.identity.get("relation", "")) in ["本人", "自己", "我", "self"])
			if (int(data.schema) == 8 and str(record.identity.get("relation", "")) in ["本人", "自己", "我", "self"]) or (is_self and not moved_self_id.is_empty()):
				last_error = "本人和家人存档归属冲突，原文件已保留。"
				load_blocked = true
				return
			if is_self and moved_self_id.is_empty():
				bind_owner(state, record.identity)
				moved_self_id = str(record.id)
			else:
				bind_state(str(record.id), record.identity, state)
			ids[str(record.id)] = true
		active_id = str(data.get("active_member_id", "self"))
		if active_id == moved_self_id or state_for(active_id) == null:
			active_id = "self"
		if int(data.schema) == 7 and persist_enabled and not backup_legacy(path, original):
			return
		if data.get("account") is Dictionary:
			account = {"id": str(data.account.get("id", "local-child")), "name": str(data.account.get("name", "我的守护账号")).left(20)}
		return
	if persist_enabled and not backup_legacy(path, original):
		return
	fallback_state.load_data(data)
	adopt_legacy(fallback_state)

func backup_legacy(path: String, original: String) -> bool:
	var backup_path = path.trim_suffix(".json") + "-before-accounts-v8.json"
	if FileAccess.file_exists(backup_path):
		var cleaned = Privacy.read(backup_path, true, true)
		if cleaned.ok:
			return true
		last_error = cleaned.message
		load_blocked = true
		return false
	var backup = FileAccess.open(backup_path, FileAccess.WRITE)
	if backup != null:
		backup.store_string(original)
		backup.flush()
		if backup.get_error() == OK:
			return true
	last_error = "旧存档备份失败，请检查存档目录权限。"
	load_blocked = true
	return false

func dispose() -> void:
	if owner_state != null:
		owner_state.family_save = Callable()
	# Clear callback references so the RefCounted roster and states can be released.
	for member in members:
		member.state.family_save = Callable()
