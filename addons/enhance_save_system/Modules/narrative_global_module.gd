class_name NarrativeGlobalModule
extends ISaveModule

static var instance: NarrativeGlobalModule

var world_flags: Dictionary = {}
var values: Dictionary = {}
var event_history: Dictionary = {}


# Registers the latest global narrative module instance.
func _init() -> void:
	instance = self


# Returns the stable global-save key for narrative state.
func get_module_key() -> String:
	return "narrative_global"


# Stores narrative state globally because these flags span save slots.
func is_global() -> bool:
	return true


# Captures global narrative flags, values, and event history for serialization.
func collect_data() -> Dictionary:
	return {
		"world_flags": world_flags.duplicate_deep(true),
		"values": values.duplicate_deep(true),
		"event_history": event_history.duplicate_deep(true),
	}


# Applies persisted narrative state after validating each dictionary section.
func apply_data(data: Dictionary) -> void:
	world_flags = _safe_dict(data.get("world_flags", {}))
	values = _safe_dict(data.get("values", {}))
	event_history = _safe_dict(data.get("event_history", {}))


# Provides an empty first-run payload for global narrative state.
func get_default_data() -> Dictionary:
	return {
		"world_flags": {},
		"values": {},
		"event_history": {},
	}


# Reads one narrative value from flags, events, or plain value namespaces.
func get_value(key: String, fallback: Variant = null) -> Variant:
	if key.begins_with("flags."):
		return world_flags.get(key.trim_prefix("flags."), fallback)
	if key.begins_with("events."):
		return event_history.get(key.trim_prefix("events."), fallback)
	return values.get(key, fallback)


# Writes one narrative value to flags, events, or plain value namespaces.
func set_value(key: String, value: Variant) -> bool:
	if key.begins_with("flags."):
		world_flags[key.trim_prefix("flags.")] = value
		return true
	if key.begins_with("events."):
		event_history[key.trim_prefix("events.")] = value
		return true
	values[key] = value
	return true


# Clears one narrative value from flags, events, or plain value namespaces.
func clear_value(key: String) -> bool:
	if key.begins_with("flags."):
		world_flags.erase(key.trim_prefix("flags."))
		return true
	if key.begins_with("events."):
		event_history.erase(key.trim_prefix("events."))
		return true
	values.erase(key)
	return true


# Checks whether a global narrative event marker has been written.
func is_event_fired(event_id: String) -> bool:
	return _is_truthy(event_history.get(event_id, false))


# Writes a global narrative event marker.
func mark_event_fired(event_id: String) -> void:
	if event_id.is_empty():
		return
	event_history[event_id] = true


# Returns a defensive dictionary copy or an empty dictionary for invalid data.
func _safe_dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


# Coerces common scalar values to bool for event markers.
func _is_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return not is_zero_approx(value)
	if value is String:
		var trimmed := String(value).strip_edges().to_lower()
		return trimmed in ["true", "1", "yes", "on"]
	return false
