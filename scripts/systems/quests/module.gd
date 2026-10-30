extends "res://scripts/kernel/system_module.gd"
## 任务：任务列表与进度的投影、领奖请求。任务模板由内容表提供。
## 客户端不能确认设备真实性、计算验证倍率或突破每日上限；这些属于服务端规则。

func _init() -> void:
	super("quests")
