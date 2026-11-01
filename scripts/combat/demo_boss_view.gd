extends "res://scripts/combat_view.gd"
## 演示入口复用正式账号的 BossRules / PR4 BossBrain。
## 这些标记保留给旧演示入口和测试，用来区分普通关卡与 Boss 关卡。
signal left
var boss_mode: bool = true
var allies_enabled: bool = false
