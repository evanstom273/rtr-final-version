extends RefCounted
class_name MatchDifficultyDiagnostics

## Compact, opt-in JSONL diagnostics for difficulty investigations. The writer
## never prints per-action data to the editor console and is disabled in release
## builds even if a scene accidentally leaves the option enabled.

const OUTPUT_PATH := "user://difficulty_diagnostics.jsonl"

var enabled: bool = false
var _file: FileAccess
var _sequence: int = 0


func begin_match(requested: bool, metadata: Dictionary = {}) -> void:
	close()
	enabled = requested and OS.is_debug_build()
	if not enabled:
		return
	_file = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if _file == null:
		enabled = false
		return
	_sequence = 0
	record(&"match_started", metadata)


func record(event_type: StringName, values: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	_sequence += 1
	var payload: Dictionary = _json_safe(values)
	payload["sequence"] = _sequence
	payload["event"] = String(event_type)
	payload["recorded_unix_msec"] = Time.get_unix_time_from_system() * 1000.0
	_file.store_line(JSON.stringify(payload))
	_file.flush()


func close(final_values: Dictionary = {}) -> void:
	if _file != null:
		if enabled and not final_values.is_empty():
			record(&"match_finished", final_values)
		_file.close()
	_file = null
	enabled = false


func output_path() -> String:
	return OUTPUT_PATH


func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[String(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_json_safe(item))
		return result
	if value is PackedStringArray:
		return Array(value)
	if value is StringName:
		return String(value)
	if value is Resource:
		var resource := value as Resource
		return resource.resource_path if not resource.resource_path.is_empty() else str(resource)
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Color:
		return value.to_html(true)
	return value
