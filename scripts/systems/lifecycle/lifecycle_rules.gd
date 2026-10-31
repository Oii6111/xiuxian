extends RefCounted
## 生命周期纯规则：合法迁移表与渡劫阶段模板。无节点、无文件、无网络，可单测。
## 只回答“这次迁移/阶段变更是否合法”；确认令牌的签发与消费、持久化由服务端权威完成。
## 掉线、计时器、战斗结果都不是触发源，所以这里不提供任何自动迁移入口。
const STATES: Array = ["cultivating", "tribulation", "seclusion", "ascended"]
## 迁移表依据设计文档 v2 第 14 节：修行→渡劫；渡劫→修行/闭关/飞升；闭关→修行/飞升；飞升不可再迁移。
const TRANSITIONS: Dictionary = {
	"cultivating": ["tribulation"],
	"tribulation": ["cultivating", "seclusion", "ascended"],
	"seclusion": ["cultivating", "ascended"],
	"ascended": []
}
## 飞升必须家属二次确认；其余迁移一次确认。
const DOUBLE_CONFIRM_TARGETS: Array = ["ascended"]
## 渡劫阶段模板（设计文档 v2 15.2）。阶段可回退（病情反复），回退不使用惩罚性表述。
const TEMPLATES: Dictionary = {
	"cardio": {"title": "心脑血管急症", "stages": ["admission", "emergency", "monitoring", "ward", "discharge"]},
	"fracture": {"title": "骨折与手术", "stages": ["admission", "preop", "surgery", "recovery", "discharge"]},
	"pneumonia": {"title": "重症肺炎/感染", "stages": ["admission", "acute", "stable", "improving", "discharge"]}
}

static func is_state(state: String) -> bool:
	return state in STATES

static func can_transition(from_state: String, to_state: String) -> bool:
	return TRANSITIONS.get(from_state, []).has(to_state)

static func confirmations_required(to_state: String) -> int:
	return 2 if to_state in DOUBLE_CONFIRM_TARGETS else 1

## 只有修行状态可以出战；渡劫中的修仙者在渡劫画面静守（设计文档 v2 11.6）。
static func allows_combat(state: String) -> bool:
	return state == "cultivating"

static func stage_id(template_id: String, stage_key: String) -> String:
	return template_id + "." + stage_key

## 阶段编号形如 cardio.emergency；未知模板或阶段返回空字典。
static func parse_stage(identifier: String) -> Dictionary:
	var parts: PackedStringArray = identifier.split(".")
	if parts.size() != 2 or not TEMPLATES.has(parts[0]):
		return {}
	var index: int = TEMPLATES[parts[0]].stages.find(parts[1])
	if index < 0:
		return {}
	return {"template_id": parts[0], "stage": parts[1], "index": index}

## 阶段可前进也可回退，但不能原地重复提交，也不能越界。
static func can_move_stage(template_id: String, from_index: int, to_index: int) -> bool:
	if not TEMPLATES.has(template_id):
		return false
	var count: int = TEMPLATES[template_id].stages.size()
	return from_index != to_index and from_index >= 0 and to_index >= 0 and from_index < count and to_index < count

## 到达最后一个阶段（出院）不会自动改变角色状态；渡劫结算必须另行经家属确认。
static func is_final_stage(template_id: String, index: int) -> bool:
	return TEMPLATES.has(template_id) and index == TEMPLATES[template_id].stages.size() - 1
