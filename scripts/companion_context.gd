extends RefCounted
## Read-only projection. Never includes reports, health values or authentication data.
const Catalogue = preload("res://scripts/companion_catalogue.gd")
const TASK_NAMES = {"medication": "既有用药计划记录", "planned_record": "个人计划坚持记录"}
const ACTIONS = ["record", "family", "health", "treasure", "equipment", "boss"]

static func character(state, id: String, own: bool) -> Dictionary:
	var alias = "我" if own else str(state.family_identity.get("relation", "家人"))
	if alias.is_empty():
		alias = "家人"
	var tasks: Array = []
	for key in ["medication", "planned_record"]:
		var applicable = key != "medication" or (state.longterm_enabled and state.medication_required)
		tasks.append({"id": key, "title": TASK_NAMES[key], "status": "not_applicable" if not applicable else ("confirmed" if state.task_done(key) else "unrecorded")})
	return {"member_id": id, "label": alias, "kind": "self" if own else "elder", "has_profile": not state.health_profile_id.is_empty(), "tasks": tasks, "reward_recorded": state.today() in state.rewarded_days, "qi": int(state.equipment.qi), "equipment_count": state.equipment.inventory.size(), "boss_cleared_count": state.cleared_bosses.size()}

static func snapshot(game) -> Dictionary:
	var characters = [character(game.family.owner_state, "self", true)]
	for member in game.family.members:
		if member.state.family_identity.get("consent", false) == true:
			characters.append(character(member.state, str(member.id), false))
	var context = {"source": "local_game", "as_of_date": game.state.today(), "active_member_id": game.family.active_id, "characters": characters}
	if is_instance_valid(game.companion_tasks):
		game.companion_tasks.overlay(context)
	return context

static func active(context: Dictionary) -> Dictionary:
	for person in context.characters:
		if person.member_id == context.active_member_id:
			return person
	return context.characters[0]

static func response(reply: String, actions: Array = [], animation: String = "talk") -> Dictionary:
	return {"reply": reply, "actions": actions, "animation": animation, "source": "local_guide"}

static func action(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label}

static func task_summary(context: Dictionary, everybody: bool) -> String:
	var lines: Array[String] = ["按今天（%s）的游戏记录：" % context.as_of_date]
	for person in context.characters:
		if not everybody and person.member_id != context.active_member_id:
			continue
		lines.append("%s：" % person.label)
		if person.get("task_source", "") == "wechat":
			lines.append("  · " + person.sync_status)
			if person.tasks.is_empty():
				lines.append("  · 尚未确认适用的安排，暂未开启任务。" if person.sync_ready else "  · 等待同步后查看当前安排。")
		for task in person.tasks:
			var status = {"confirmed": "已确认", "unrecorded": "暂未收到记录", "not_applicable": "未安排，无需记录"}.get(task.status, "待核对")
			if person.get("task_source", "") == "wechat":
				status = {"confirmed": "老人已在微信确认完成", "unrecorded": "等待老人微信反馈", "cancelled": "已取消，不再需要反馈"}.get(task.status, "等待核对")
			lines.append("  · %s：%s" % [task.title, status])
		if person.reward_recorded:
			lines.append("  · 今日有效记录奖励已记入。")
	lines.append("暂未收到记录，表示游戏里还没有确认信息。")
	return "\n".join(lines)

static func next_step(context: Dictionary) -> Dictionary:
	var person = active(context)
	if person.get("task_source", "") == "wechat":
		if not person.sync_ready:
			return response("微信记录暂时还没同步好，我会继续等候更新。", [action("record", "查看同步状态")])
		if person.tasks.is_empty():
			return response("目前还没有已确认、适用的安排。可以先在微信告诉聊天伙伴已有的生活安排，说清后再开启对应记录。", [action("record", "查看微信记录")])
		var active_count = 0
		for task in person.tasks:
			active_count += int(task.status != "cancelled")
		if active_count == 0:
			return response("当前安排已取消或不再适用，暂时没有需要反馈的任务。", [action("record", "查看微信记录")])
		for task in person.tasks:
			if task.status == "unrecorded":
				return response("还有「%s」等待反馈。请由老人按原有安排完成后，在微信告诉聊天伙伴，我会同步看到。" % task.title, [action("record", "查看微信记录")])
		return response("今天适用的安排已经收到完成反馈啦。可以看看其他家人的近况，也可以休息一会儿。", [action("family", "查看家人")], "celebrate")
	if not person.has_profile:
		return response("先为当前角色确认一份健康档案吧。完成后，我就能陪你查看计划、装备与试炼安排。", [action("health", "查看健康档案"), action("family", "选择家人")])
	for task in person.tasks:
		if task.status == "unrecorded":
			return response("当前角色还有「%s」暂未收到记录。实际完成后，可以去记录页面核对并确认。按原有安排慢慢来就好。" % task.title, [action("record", "查看今日记录"), action("family", "看看家人")])
	if int(person.qi) >= 700:
		return response("当前角色今天安排的记录都已确认，灵气也够一次十连了。可以去聚宝阁看看，或带上装备去试炼。", [action("treasure", "前往聚宝阁"), action("boss", "看看试炼")], "celebrate")
	return response("当前角色今天安排的记录都已确认，辛苦啦！接下来可以整理装备、探索试炼，也可以休息一会儿。", [action("equipment", "整理装备"), action("boss", "看看试炼")], "celebrate")

static func local_reply(message: String, context: Dictionary, pet: Dictionary) -> Dictionary:
	var name = Catalogue.nickname(pet)
	if "下一步" in message or "做什么" in message or "接下来" in message:
		return next_step(context)
	if "家人" in message or "爸爸" in message or "妈妈" in message or "父亲" in message or "母亲" in message:
		return response(task_summary(context, true), [action("family", "查看我的家人"), action("record", "查看当前角色记录")])
	var asking_status = "了吗" in message or "有没有" in message or "是否" in message or "怎么样" in message or "做没做" in message
	if not asking_status and ("完成了" in message or "做完了" in message or "吃过" in message or "吃了" in message or "打卡" in message):
		if active(context).get("task_source", "") == "wechat":
			return response("这项安排由老人微信反馈完成。可以在微信向聊天伙伴说明，我会自动同步状态。", [action("record", "查看微信记录")])
		return response("我听到了。可以打开记录页面，核对是哪位家人、今天的哪项计划，再由你确认。确认结果会出现在今日任务里。", [action("record", "去核对并确认")])
	if "任务" in message or "记录" in message or "完成" in message or "今天" in message:
		return response(task_summary(context, false), [action("record", "查看今日记录"), action("family", "看看家人")])
	if "抽" in message or "灵气" in message or "装备" in message or "聚宝" in message:
		var person = active(context)
		return response("当前角色有 %d 灵气、%d 件装备。聚宝阁单抽需要 70 灵气，十连需要 700 灵气。每日首次有效习惯记录可以积攒 100 灵气，按自己的节奏来。" % [person.qi, person.equipment_count], [action("treasure", "前往聚宝阁"), action("equipment", "整理装备")])
	if "累" in message or "难过" in message or "休息" in message:
		return response("那就先歇一会儿吧。今天已经做过的事，都值得被好好记住。我就在这里，想聊今天的安排时再来找我。")
	if "你好" in message or "名字" in message or "是谁" in message:
		return response("我是%s，你的同行灵宠。今日任务、家人近况、下一步安排，都可以问我。" % name)
	return response("%s在听呢。我现在可以帮你看看今日任务、家人近况、灵气装备，或者一起想想下一步做什么。" % name, [action("record", "今日任务"), action("family", "家人近况")])
