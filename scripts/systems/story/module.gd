extends "res://scripts/kernel/system_module.gd"
## 剧情：章节、对话与天道进度的投影；全服进度以服务端广播为准。
## 与生命周期分离：剧情解锁不能自动宣告康复或飞升。

func _init() -> void:
	super("story")
