extends "res://scripts/kernel/system_module.gd"
## 战斗：接收属性与装备快照，管理会话并上报战果；即时战斗实体放 scripts/combat/。
## 只允许修行状态出战；战果不能改变渡劫结果，奖励由服务端结算。

func _init() -> void:
	super("combat")
