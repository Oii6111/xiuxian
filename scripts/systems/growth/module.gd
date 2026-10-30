extends "res://scripts/kernel/system_module.gd"
## 角色养成：童子/修仙者关系、灵根、装备、境界、资源与抽卡结果的客户端投影。
## 每位修仙者独立持有灵石/经验/材料/装备/保底；功德属于童子。
## 接入后端后在 execute 中申请操作，成功后 commit；严禁本地抽卡或发奖。

func _init() -> void:
	super("growth")
