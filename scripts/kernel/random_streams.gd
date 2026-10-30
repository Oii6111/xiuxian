extends RefCounted
## 按用途隔离随机流：UI 多取一次随机数不会改变战斗回放。
## 只供客户端表现和战斗模拟使用；正式抽卡必须由服务端决定。
var _seed: int
var _streams: Dictionary = {}

func _init(seed_value: int = 1) -> void:
	_seed = seed_value

func stream(stream_id: String) -> RandomNumberGenerator:
	if not _streams.has(stream_id):
		var generator := RandomNumberGenerator.new()
		generator.seed = _seed ^ int(stream_id.hash())
		_streams[stream_id] = generator
	return _streams[stream_id]
