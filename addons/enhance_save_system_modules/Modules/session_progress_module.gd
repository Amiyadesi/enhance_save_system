class_name SessionProgressModule
extends ISaveModule

const MAX_RECENT_SUMMARIES := 16

static var instance: SessionProgressModule

var recent_session_summaries: Array = []
var pending_session_bridge: Dictionary = {}
var last_session_snapshot_summary: Dictionary = {}


# Registers the latest module instance for save-system callbacks.
func _init() -> void:
	instance = self


# Returns the stable global-save key for session progress data.
func get_module_key() -> String:
	return "session_progress"


# Stores session progress in the global save because it spans save slots.
func is_global() -> bool:
	return true


# Captures recent summaries and pending continuation state for serialization.
func collect_data() -> Dictionary:
	return {
		"recent_session_summaries": recent_session_summaries.duplicate(true),
		"pending_session_bridge": pending_session_bridge.duplicate(true),
		"last_session_snapshot_summary": last_session_snapshot_summary.duplicate(true),
	}


# Applies persisted session progress after validating each payload section.
func apply_data(data: Dictionary) -> void:
	recent_session_summaries = _normalize_summaries(data.get("recent_session_summaries", []))
	pending_session_bridge = _normalize_bridge(data.get("pending_session_bridge", {}))
	last_session_snapshot_summary = _normalize_summary(data.get("last_session_snapshot_summary", {}))


# Provides an empty payload for first-run global saves.
func get_default_data() -> Dictionary:
	return {
		"recent_session_summaries": [],
		"pending_session_bridge": {},
		"last_session_snapshot_summary": {},
	}


# Records one closed-session summary and keeps only the newest bounded history.
func record_session_summary(summary: Dictionary) -> void:
	var normalized := _normalize_summary(summary)
	if normalized.is_empty():
		return
	last_session_snapshot_summary = normalized.duplicate(true)
	recent_session_summaries.append(normalized.duplicate(true))
	while recent_session_summaries.size() > MAX_RECENT_SUMMARIES:
		recent_session_summaries.remove_at(0)


# Returns a defensive copy of recent session summaries.
func get_recent_session_summaries() -> Array:
	return recent_session_summaries.duplicate(true)


# Returns a defensive copy of the most recent session summary.
func get_last_session_snapshot_summary() -> Dictionary:
	return last_session_snapshot_summary.duplicate(true)


# Reads the pending bridge without consuming it and clears expired data.
func peek_pending_session_bridge() -> Dictionary:
	if not _is_bridge_valid(pending_session_bridge):
		pending_session_bridge.clear()
		return {}
	return pending_session_bridge.duplicate(true)


# Consumes a valid bridge and schedules global persistence for the cleared state.
func consume_pending_session_bridge() -> Dictionary:
	var bridge := peek_pending_session_bridge()
	if bridge.is_empty():
		return {}
	pending_session_bridge.clear()
	var save_system := _get_save_system_or_report("persist consumed session bridge")
	if save_system != null and save_system.has_method("save_global"):
		save_system.call_deferred("save_global")
	elif save_system != null:
		push_error("SessionProgressModule: cannot persist consumed session bridge because SaveSystem.save_global is missing")
	return bridge


# Stores a normalized bridge for the next session start.
func set_pending_session_bridge(bridge: Dictionary) -> void:
	pending_session_bridge = _normalize_bridge(bridge)


# Clears any pending bridge from module memory.
func clear_pending_session_bridge() -> void:
	pending_session_bridge.clear()


# Reports whether a readable non-expired bridge is pending.
func has_valid_pending_bridge() -> bool:
	return not peek_pending_session_bridge().is_empty()


# Ends the optional host session when SaveSystem receives the window-close hook.
func on_win_closed() -> void:
	var session_state := _get_session_state_optional()
	if session_state != null and session_state.has_method("end_session"):
		session_state.call("end_session", true)
	elif session_state != null:
		push_warning("SessionProgressModule: SessionState.end_session is missing; skipping host-session close")


# Normalizes persisted summary history and trims old entries.
func _normalize_summaries(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for entry in value:
			var normalized := _normalize_summary(entry)
			if not normalized.is_empty():
				result.append(normalized)
	while result.size() > MAX_RECENT_SUMMARIES:
		result.remove_at(0)
	return result


# Converts one summary payload to the stable save schema.
func _normalize_summary(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data := (value as Dictionary).duplicate(true)
	return {
		"session_id": str(data.get("session_id", "")),
		"chain_id": str(data.get("chain_id", "")),
		"started_at": int(data.get("started_at", 0)),
		"ended_at": int(data.get("ended_at", 0)),
		"duration_seconds": int(data.get("duration_seconds", 0)),
		"ended_normally": _is_truthy(data.get("ended_normally", false)),
		"important_flags": _normalize_string_array(data.get("important_flags", [])),
		"important_events": _normalize_string_array(data.get("important_events", [])),
		"continue_reason": str(data.get("continue_reason", "")),
		"is_continued_session": _is_truthy(data.get("is_continued_session", false)),
	}


# Converts one pending bridge payload to the stable save schema.
func _normalize_bridge(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data := (value as Dictionary).duplicate(true)
	var normalized := {
		"source_session_id": str(data.get("source_session_id", "")),
		"chain_id": str(data.get("chain_id", "")),
		"reason": str(data.get("reason", "")),
		"expires_at_unix": int(data.get("expires_at_unix", 0)),
		"inherit_flags": PackedStringArray(_normalize_string_array(data.get("inherit_flags", []))),
		"inherit_counters": PackedStringArray(_normalize_string_array(data.get("inherit_counters", []))),
		"seed_values": (data.get("seed_values", {}) as Dictionary).duplicate(true) if data.get("seed_values", {}) is Dictionary else {},
		"target_scope_hint": str(data.get("target_scope_hint", "")),
	}
	return normalized if _is_bridge_valid(normalized) else {}


# Checks whether a pending bridge can still seed a future session.
func _is_bridge_valid(bridge: Dictionary) -> bool:
	if bridge.is_empty():
		return false
	var expires_at := int(bridge.get("expires_at_unix", 0))
	if expires_at <= 0:
		return false
	return expires_at > Time.get_unix_time_from_system()


# Converts array-like values to unique non-empty strings.
func _normalize_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for entry in value:
			var text := str(entry).strip_edges()
			if not text.is_empty() and text not in result:
				result.append(text)
	return result


# Finds the SaveSystem autoload or reports the missing dependency.
func _get_save_system_or_report(action: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("SessionProgressModule: cannot %s because SceneTree is unavailable" % action)
		return null
	var save_system := tree.root.get_node_or_null("SaveSystem")
	if save_system == null:
		push_error("SessionProgressModule: cannot %s because SaveSystem autoload is missing" % action)
	return save_system


# Finds the optional SessionState autoload supplied by host projects.
func _get_session_state_optional() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("SessionState")


# Coerces common scalar values to bool for summary fields.
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
