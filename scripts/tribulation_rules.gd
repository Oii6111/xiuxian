extends RefCounted
## Game-only trial. Winning never changes recovery_status.
var state: RefCounted
var round: int = 0
var thunder: int = 240
var hp: int = 260
var shield: int = 0
var finished: bool = false
var won: bool = false

func _init(data: RefCounted) -> void:
	state = data

func choose(choice: int) -> Dictionary:
	if finished or choice < 0 or choice > 2:
		return {"ok": false, "message": "本次试炼已结束。"}
	var cost = 5 if choice == 0 else 3
	if choice < 2 and state.qi < cost:
		return {"ok": false, "message": "灵气不足，可使用守护符或稍后再来。"}
	if choice == 2 and state.charms <= 0:
		return {"ok": false, "message": "暂无守护符，请选择其他功法。"}
	round += 1
	if choice == 2:
		state.charms -= 1
	else:
		state.qi -= cost
	if choice == 1:
		shield += 100
	var damage = [90, 60, 70][choice]
	thunder = maxi(0, thunder - damage)
	var incoming = 145 if round == 3 else 65
	if choice == 2 or thunder == 0:
		incoming = 0
	var absorbed = mini(shield, incoming)
	shield -= absorbed
	var hurt = incoming - absorbed
	hp = maxi(0, hp - hurt)
	finished = thunder == 0 or round >= 3 or hp == 0
	won = finished and thunder == 0 and hp > 0
	if won:
		state.trial_cleared = true
	return {"ok": true, "choice": choice, "damage": damage, "hurt": hurt, "absorbed": absorbed, "protected": choice == 2 or absorbed > 0, "finished": finished, "won": won}
