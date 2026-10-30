extends "res://scripts/kernel/system_module.gd"
## 社交：名片、洞府、好友、护法、庆典与道统碑的展示和请求。
## 公共视图使用显式字段白名单；不透传健康域对象，不因护法改变渡劫结果。

func _init() -> void:
	super("social")
