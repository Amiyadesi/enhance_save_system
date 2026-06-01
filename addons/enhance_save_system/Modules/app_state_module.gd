class_name AppStateModule
extends ISaveModule

static var instance: AppStateModule

const KEY_HAS_PLAYED_BEFORE := "has_played_before"
const KEY_OPEN_COUNT := "open_count"
const KEY_PENDING_MENU_EVENT := "pending_menu_event"
const DEFAULT_VALUES := {
	"crash_return_count": 0,
}

var has_played_before: bool = false
var open_count: int = 0
var pending_menu_event: String = ""
var values: Dictionary = DEFAULT_VALUES.duplicate(true)


# Registers the latest app-state module instance and resets default values.
func _init() -> void:
	instance = self
	values = DEFAULT_VALUES.duplicate(true)


# Returns the stable global-save key for app-level state.
func get_module_key() -> String:
	return "app_state"


# Stores app state in the global save because it is not slot-specific.
func is_global() -> bool:
	return true


# Captures app-level flags, counters, and custom values for serialization.
func collect_data() -> Dictionary:
	return {
		"has_played_before": has_played_before,
		"open_count": open_count,
		"pending_menu_event": pending_menu_event,
		"values": values.duplicate(true),
	}


# Applies persisted app state while preserving default-backed custom values.
func apply_data(data: Dictionary) -> void:
	has_played_before = _is_truthy(data.get("has_played_before", false))
	open_count = maxi(int(data.get("open_count", 0)), 0)
	pending_menu_event = str(data.get("pending_menu_event", ""))
	values = DEFAULT_VALUES.duplicate(true)
	var loaded_values := (data.get("values", {}) as Dictionary)
	for key in loaded_values:
		values[key] = loaded_values[key]


# Provides the first-run payload for global app state.
func get_default_data() -> Dictionary:
	return {
		"has_played_before": false,
		"open_count": 0,
		"pending_menu_event": "",
		"values": DEFAULT_VALUES.duplicate(true),
	}


# Reads one app-state value by public key.
func get_value(key: String, fallback: Variant = null) -> Variant:
	match key:
		"has_played_before":
			return has_played_before
		"open_count":
			return open_count
		"pending_menu_event":
			return pending_menu_event
		_:
			return values.get(key, DEFAULT_VALUES.get(key, fallback))


# Writes one app-state value by public key.
func set_value(key: String, value: Variant) -> bool:
	match key:
		"has_played_before":
			has_played_before = _is_truthy(value)
			return true
		"open_count":
			open_count = maxi(int(value), 0)
			return true
		"pending_menu_event":
			pending_menu_event = str(value)
			return true
		_:
			values[key] = value
			return true


# Resets one app-state value to its built-in default or removes custom data.
func clear_value(key: String) -> bool:
	match key:
		"pending_menu_event":
			pending_menu_event = ""
			return true
		"has_played_before":
			has_played_before = false
			return true
		"open_count":
			open_count = 0
			return true
		_:
			if DEFAULT_VALUES.has(key):
				values[key] = DEFAULT_VALUES[key]
			else:
				values.erase(key)
			return true


# Adds to a numeric app-state value and preserves integer-looking results.
func increment_value(key: String, amount: float = 1.0) -> Variant:
	var current_value = float(get_value(key, 0.0))
	var next_value = current_value + amount
	if round(next_value) == next_value:
		set_value(key, int(next_value))
	else:
		set_value(key, next_value)
	return get_value(key)


# Coerces common scalar values to bool for loaded flags.
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
