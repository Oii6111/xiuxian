extends "res://scripts/kernel/system_module.gd"
## 赛季：同步当前赛季，提示体检刷新；具体切季规则由服务端负责。
## 灵根、装备、境界等永久状态保留。未体检沿用旧属性，不能清空角色。

func _init() -> void:
	super("season")
