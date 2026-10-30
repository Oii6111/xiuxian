extends "res://scripts/kernel/system_module.gd"
## 生命周期：修行/渡劫/闭关/飞升，以及渡劫阶段、庆典与纪念流程。
## 必须经家属确认；飞升需要二次确认。掉线、计时器和战斗结果都不是触发源。
## 这里只预留请求接口，确认令牌的签发与消费由未来服务端实现。

func _init() -> void:
	super("lifecycle")
