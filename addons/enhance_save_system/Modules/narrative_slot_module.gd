class_name NarrativeSlotModule
extends ISaveModule

static var instance: NarrativeSlotModule

const DEFAULT_STAGE_ID := "stage_0_menu"
const DEFAULT_PROGRESS_NOTE := "序章：菜单"
const DEFAULT_STAGE_STATE := {
	"flags": {},
	"values": {},
}

var chapter_progress: int = 1
var current_stage_id: String = DEFAULT_STAGE_ID
var progress_note: String = DEFAULT_PROGRESS_NOTE
var flags: Dictionary = {}
var values: Dictionary = {}
var choices: Dictionary = {}
var event_history: Dictionary = {}
var stage_states: Dictionary = {}


# Registers the latest slot narrative module instance.
func _init() -> void:
	instance = self


# Returns the stable slot-save key for narrative state.
func get_module_key() -> String:
	return "narrative_slot"


# Stores narrative state in slot saves because it belongs to one playthrough.
func is_global() -> bool:
	return false


# Captures slot narrative progress, values, choices, events, and stage state.
func collect_data() -> Dictionary:
	return {
		"chapter_progress": chapter_progress,
		"current_stage_id": current_stage_id,
		"progress_note": progress_note,
		"flags": flags.duplicate(true),
		"values": values.duplicate(true),
		"choices": choices.duplicate(true),
		"event_history": event_history.duplicate(true),
		"stage_states": stage_states.duplicate(true),
	}


# Applies persisted slot narrative data and restores required default stage state.
func apply_data(data: Dictionary) -> void:
	chapter_progress = maxi(int(data.get("chapter_progress", 1)), 1)
	current_stage_id = str(data.get("current_stage_id", DEFAULT_STAGE_ID))
	if current_stage_id.is_empty():
		current_stage_id = DEFAULT_STAGE_ID
	progress_note = str(data.get("progress_note", DEFAULT_PROGRESS_NOTE))
	if progress_note.is_empty():
		progress_note = DEFAULT_PROGRESS_NOTE
	flags = _safe_dict(data.get("flags", {}))
	values = _safe_dict(data.get("values", {}))
	choices = _safe_dict(data.get("choices", data.get("choices_made", {})))
	event_history = _safe_dict(data.get("event_history", {}))
	stage_states = _normalize_stage_states(data.get("stage_states", {}))
	ensure_stage_state(DEFAULT_STAGE_ID)
	ensure_stage_state(current_stage_id)


# Provides the first-run payload for a fresh save slot.
func get_default_data() -> Dictionary:
	return {
		"chapter_progress": 1,
		"current_stage_id": DEFAULT_STAGE_ID,
		"progress_note": DEFAULT_PROGRESS_NOTE,
		"flags": {},
		"values": {},
		"choices": {},
		"event_history": {},
		"stage_states": {
			DEFAULT_STAGE_ID: DEFAULT_STAGE_STATE.duplicate(true),
		},
	}


# Resets the slot narrative state to default data for a new game.
func on_new_game() -> void:
	apply_data(get_default_data())


# Repairs required progress fields and stage dictionaries after direct field edits.
func ensure_defaults() -> void:
	if chapter_progress <= 0:
		chapter_progress = 1
	if current_stage_id.is_empty():
		current_stage_id = DEFAULT_STAGE_ID
	if progress_note.is_empty():
		progress_note = DEFAULT_PROGRESS_NOTE
	ensure_stage_state(DEFAULT_STAGE_ID)
	ensure_stage_state(current_stage_id)


# Marks the menu stage as initialized for save-slot previews and flow checks.
func mark_menu_ready() -> void:
	ensure_defaults()
	set_stage_flag(DEFAULT_STAGE_ID, "menu_ready", true)


# Reads one slot narrative value by public key or namespace.
func get_value(key: String, fallback: Variant = null) -> Variant:
	match key:
		"chapter_progress":
			return chapter_progress
		"current_stage_id":
			return current_stage_id
		"progress_note":
			return progress_note
		_:
			if key.begins_with("flags."):
				return flags.get(key.trim_prefix("flags."), fallback)
			if key.begins_with("choices."):
				return choices.get(key.trim_prefix("choices."), fallback)
			if key.begins_with("events."):
				return event_history.get(key.trim_prefix("events."), fallback)
			if key.begins_with("stage_states."):
				return _resolve_stage_path(key.trim_prefix("stage_states."), fallback)
			return values.get(key, fallback)


# Writes one slot narrative value by public key or namespace.
func set_value(key: String, value: Variant) -> bool:
	match key:
		"chapter_progress":
			chapter_progress = maxi(int(value), 1)
			return true
		"current_stage_id":
			current_stage_id = str(value)
			ensure_stage_state(current_stage_id)
			return true
		"progress_note":
			progress_note = str(value)
			return true
		_:
			if key.begins_with("flags."):
				flags[key.trim_prefix("flags.")] = value
				return true
			if key.begins_with("choices."):
				choices[key.trim_prefix("choices.")] = value
				return true
			if key.begins_with("events."):
				event_history[key.trim_prefix("events.")] = value
				return true
			if key.begins_with("stage_states."):
				return _write_stage_path(key.trim_prefix("stage_states."), value)
			values[key] = value
			return true


# Clears one slot narrative value by public key or namespace.
func clear_value(key: String) -> bool:
	match key:
		"chapter_progress":
			chapter_progress = 1
			return true
		"current_stage_id":
			current_stage_id = DEFAULT_STAGE_ID
			return true
		"progress_note":
			progress_note = DEFAULT_PROGRESS_NOTE
			return true
		_:
			if key.begins_with("flags."):
				flags.erase(key.trim_prefix("flags."))
				return true
			if key.begins_with("choices."):
				choices.erase(key.trim_prefix("choices."))
				return true
			if key.begins_with("events."):
				event_history.erase(key.trim_prefix("events."))
				return true
			if key.begins_with("stage_states."):
				return _clear_stage_path(key.trim_prefix("stage_states."))
			values.erase(key)
			return true


# Stores one named player choice in the slot narrative history.
func set_choice(choice_key: String, value: Variant) -> void:
	if choice_key.is_empty():
		return
	choices[choice_key] = value


# Stores one slot-scoped narrative flag.
func set_flag(flag_key: String, value: Variant = true) -> void:
	if flag_key.is_empty():
		return
	flags[flag_key] = value


# Checks whether a slot-scoped narrative flag is truthy.
func has_flag(flag_key: String) -> bool:
	return _is_truthy(flags.get(flag_key, false))


# Clears one slot-scoped narrative flag.
func clear_flag(flag_key: String) -> void:
	if flag_key.is_empty():
		return
	flags.erase(flag_key)


# Checks whether a slot-scoped event marker has been written.
func is_event_fired(event_id: String) -> bool:
	return _is_truthy(event_history.get(event_id, false))


# Writes a slot-scoped event marker.
func mark_event_fired(event_id: String) -> void:
	if event_id.is_empty():
		return
	event_history[event_id] = true


# Creates or repairs a normalized stage-state dictionary for one stage id.
func ensure_stage_state(stage_id: String) -> Dictionary:
	var normalized_stage_id := _normalize_stage_id(stage_id)
	var stage_state := stage_states.get(normalized_stage_id, {})
	if not (stage_state is Dictionary):
		stage_state = {}
	stage_state = _normalize_stage_state(stage_state)
	stage_states[normalized_stage_id] = stage_state
	return stage_state


# Returns a defensive copy of one stage-state dictionary.
func get_stage_state(stage_id: String) -> Dictionary:
	return ensure_stage_state(stage_id).duplicate(true)


# Reads one value from a stage-state value dictionary.
func get_stage_value(stage_id: String, key: String, fallback: Variant = null) -> Variant:
	var stage_state := ensure_stage_state(stage_id)
	var values_dict: Dictionary = stage_state.get("values", {})
	return values_dict.get(key, fallback)


# Writes one value into a normalized stage-state value dictionary.
func set_stage_value(stage_id: String, key: String, value: Variant) -> void:
	if key.is_empty():
		return
	var normalized_stage_id := _normalize_stage_id(stage_id)
	var stage_state := ensure_stage_state(stage_id)
	var values_dict: Dictionary = stage_state.get("values", {})
	values_dict[key] = value
	stage_state["values"] = values_dict
	stage_states[normalized_stage_id] = stage_state


# Clears one value from a normalized stage-state value dictionary.
func clear_stage_value(stage_id: String, key: String) -> void:
	if key.is_empty():
		return
	var normalized_stage_id := _normalize_stage_id(stage_id)
	var stage_state := ensure_stage_state(stage_id)
	var values_dict: Dictionary = stage_state.get("values", {})
	values_dict.erase(key)
	stage_state["values"] = values_dict
	stage_states[normalized_stage_id] = stage_state


# Writes one flag into a normalized stage-state flag dictionary.
func set_stage_flag(stage_id: String, flag_key: String, value: Variant = true) -> void:
	if flag_key.is_empty():
		return
	var normalized_stage_id := _normalize_stage_id(stage_id)
	var stage_state := ensure_stage_state(stage_id)
	var flags_dict: Dictionary = stage_state.get("flags", {})
	flags_dict[flag_key] = value
	stage_state["flags"] = flags_dict
	stage_states[normalized_stage_id] = stage_state


# Checks whether one stage-state flag is truthy.
func has_stage_flag(stage_id: String, flag_key: String) -> bool:
	var stage_state := ensure_stage_state(stage_id)
	var flags_dict: Dictionary = stage_state.get("flags", {})
	return _is_truthy(flags_dict.get(flag_key, false))


# Clears one flag from a normalized stage-state flag dictionary.
func clear_stage_flag(stage_id: String, flag_key: String) -> void:
	if flag_key.is_empty():
		return
	var normalized_stage_id := _normalize_stage_id(stage_id)
	var stage_state := ensure_stage_state(stage_id)
	var flags_dict: Dictionary = stage_state.get("flags", {})
	flags_dict.erase(flag_key)
	stage_state["flags"] = flags_dict
	stage_states[normalized_stage_id] = stage_state


# Resolves a dotted stage_states path into a stage value or flag.
func _resolve_stage_path(path: String, fallback: Variant) -> Variant:
	var parts := path.split(".", false)
	if parts.size() < 2:
		return fallback
	var stage_id := parts[0]
	var subkey := ".".join(parts.slice(1))
	if subkey.begins_with("flags."):
		return has_stage_flag(stage_id, subkey.trim_prefix("flags."))
	return get_stage_value(stage_id, subkey, fallback)


# Writes a dotted stage_states path into a stage value or flag.
func _write_stage_path(path: String, value: Variant) -> bool:
	var parts := path.split(".", false)
	if parts.size() < 2:
		return false
	var stage_id := parts[0]
	var subkey := ".".join(parts.slice(1))
	if subkey.begins_with("flags."):
		set_stage_flag(stage_id, subkey.trim_prefix("flags."), value)
		return true
	set_stage_value(stage_id, subkey, value)
	return true


# Clears a dotted stage_states path from a stage value or flag.
func _clear_stage_path(path: String) -> bool:
	var parts := path.split(".", false)
	if parts.size() < 2:
		return false
	var stage_id := parts[0]
	var subkey := ".".join(parts.slice(1))
	if subkey.begins_with("flags."):
		clear_stage_flag(stage_id, subkey.trim_prefix("flags."))
		return true
	clear_stage_value(stage_id, subkey)
	return true


# Normalizes every persisted stage-state entry and drops empty stage ids.
func _normalize_stage_states(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		for stage_id_variant in value.keys():
			var stage_id := str(stage_id_variant).strip_edges()
			if stage_id.is_empty():
				continue
			result[stage_id] = _normalize_stage_state(value[stage_id_variant])
	return result


# Normalizes one stage-state entry to the required flags/values shape.
func _normalize_stage_state(value: Variant) -> Dictionary:
	var incoming := value as Dictionary if value is Dictionary else {}
	var stage_state: Dictionary = DEFAULT_STAGE_STATE.duplicate(true)
	stage_state["flags"] = _safe_dict(incoming.get("flags", stage_state["flags"]))
	stage_state["values"] = _safe_dict(incoming.get("values", stage_state["values"]))
	return stage_state


# Converts incoming stage ids to the canonical non-empty id used in stage_states.
func _normalize_stage_id(stage_id: String) -> String:
	var normalized_stage_id := stage_id.strip_edges()
	return DEFAULT_STAGE_ID if normalized_stage_id.is_empty() else normalized_stage_id


# Returns a defensive dictionary copy or an empty dictionary for invalid data.
func _safe_dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


# Coerces common scalar values to bool for flags and event markers.
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
