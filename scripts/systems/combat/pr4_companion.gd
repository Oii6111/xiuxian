extends RefCounted
## PR4 本机 AI 陪练：读取冻结后的游戏攻击值，不使用五行、不改玩家冷却/灵力或资源。
var attack: int
var cooldown: float = 1.8
func _init(stats: Dictionary) -> void:
	attack = maxi(1, int(float(stats.attack) * 0.25))
func step(delta: float) -> void:
	if is_finite(delta) and delta > 0:
		cooldown = maxf(0, cooldown - delta)
func strike(origin: Vector2, target: Vector2) -> int:
	if cooldown > 0 or origin.distance_to(target) > 820:
		return 0
	cooldown = 1.8
	return attack
