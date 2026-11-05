extends RefCounted
## 基础演示战斗状态：只提供与正式 BossRules 相同的最小状态接口。
## 演示账号不读取真实健康数据，也不允许以 0 HP 启动战斗。

const BASE_STATS: Dictionary = {
    "max_hp": 100,
    "attack": 50,
    "damage_multiplier": 100.0 / 140.0,
    "max_mp": 48,
    "max_stamina": 50,
    "shield": 135,
}
const ATTRIBUTE_KEYS: Array = ["life", "attack", "defense", "spirit", "stamina"]
const ATTRIBUTE_LABELS: Dictionary = {
    "life": "生命",
    "attack": "攻击",
    "defense": "防御",
    "spirit": "灵力",
    "stamina": "体力",
}

var player_name: String = "游客样例"
var avatar_id: String = "male"
var selected_tier: int = 10
var selected_track: String = "attack"
var contribution: int = 0
var cleared_bosses: Array = []
var boss_records: Dictionary = {}

func battle_stats() -> Dictionary:
    return BASE_STATS.duplicate(true)

func allows_battle() -> bool:
    return true

func heal_unlocked() -> bool:
    # 保持和正式账号的进度规则一致：演示首通两个 Boss 后才开放归元。
    return cleared_bosses.size() >= 2

func complete_boss(id: String, record: Dictionary = {}) -> void:
    if id.is_empty():
        return
    if id not in cleared_bosses:
        cleared_bosses.append(id)
    boss_records[id] = record.duplicate(true)

func complete_stage(_track: String, _tier: int, _record: Dictionary = {}) -> void:
    pass

func save_game() -> bool:
    return true

func realm() -> String:
    return "演示基准"

func is_remote() -> bool:
    return false
