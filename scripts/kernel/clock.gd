extends RefCounted
## 单一时间来源。时区明确使用固定 UTC 偏移；不依赖开发机器时区。
## 测试可注入返回 Unix 秒的 Callable；服务端权威时间接入也使用同一接口。
var _source: Callable
var _offset_seconds: int

func _init(source: Callable = Callable(), utc_offset_minutes: int = 480) -> void:
	_source = source
	_offset_seconds = utc_offset_minutes * 60

func now_unix() -> int:
	return int(_source.call()) if _source.is_valid() else int(Time.get_unix_time_from_system())

func day_key(at_unix: int = -1) -> String:
	var instant: int = now_unix() if at_unix < 0 else at_unix
	return Time.get_date_string_from_unix_time(instant + _offset_seconds)

func week_key(at_unix: int = -1) -> String:
	var instant: int = now_unix() if at_unix < 0 else at_unix
	var local_seconds: int = instant + _offset_seconds
	var weekday: int = Time.get_datetime_dict_from_unix_time(local_seconds).weekday
	var monday_offset: int = (weekday + 6) % 7
	return Time.get_date_string_from_unix_time(local_seconds - monday_offset * 86400)
