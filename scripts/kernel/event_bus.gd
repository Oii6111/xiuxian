extends RefCounted
## 进程内事实通知，不充当网络消息总线，不记录健康原始数据。
## 每个监听者拿到独立副本；订阅返回令牌，系统关闭时统一退订。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
var _topics: Dictionary = {}
var _listeners: Dictionary = {}
var _next_token: int = 0

func define_topic(topic: String, fields: Dictionary) -> Dictionary:
	if not Contracts.valid_fields(fields):
		return Result.failure("INVALID_CONFIG", "事件字段类型未定义")
	if topic.is_empty() or _topics.has(topic):
		return Result.failure("DUPLICATE_TOPIC", "事件名称为空或重复：" + topic)
	_topics[topic] = fields.duplicate(true)
	return Result.success()

func subscribe(topic: String, callback: Callable) -> int:
	if not _topics.has(topic) or not callback.is_valid():
		return -1
	_next_token += 1
	_listeners[_next_token] = {"topic": topic, "callback": callback}
	return _next_token

func unsubscribe(token: int) -> void:
	_listeners.erase(token)

func publish(topic: String, payload: Dictionary) -> Dictionary:
	if not _topics.has(topic):
		return Result.failure("UNKNOWN_TOPIC", "未声明的事件：" + topic)
	var checked: Dictionary = Contracts.validate(payload, _topics[topic])
	if not checked.ok:
		return checked
	# 遍历令牌快照，允许监听者在回调中退订；新订阅从下一次发布开始生效。
	for token in _listeners.keys():
		if not _listeners.has(token):
			continue
		var listener: Dictionary = _listeners[token]
		if listener.topic == topic and listener.callback.is_valid():
			listener.callback.call(payload.duplicate(true))
	return Result.success()

func clear() -> void:
	_listeners.clear()
