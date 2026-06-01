class_name DialogueSlotModule
extends ISaveModule
## Optional slot-scoped dialogue progress module.
##
## This module stores only plain paths, titles, labels, snippets, and variables.
## It intentionally avoids hard type references to Dialogue Manager classes so
## the save plugin can ship without requiring that addon.

static var instance: DialogueSlotModule

var dialogue_resource_path: String = ""
var dialogue_title: String = ""
var chapter_name: String = ""
var character_name: String = ""
var dialogue_snippet: String = ""
var dialogue_variables: Dictionary = {}


# Registers the latest dialogue slot module instance.
func _init() -> void:
	instance = self


# Returns the stable slot-save key used by dialogue progress.
func get_module_key() -> String:
	return "dialogue"


# Stores dialogue progress per save slot.
func is_global() -> bool:
	return false


# Captures dialogue progress and variables for serialization.
func collect_data() -> Dictionary:
	return {
		"dialogue_resource_path": dialogue_resource_path,
		"dialogue_title": dialogue_title,
		"chapter_name": chapter_name,
		"character_name": character_name,
		"dialogue_snippet": dialogue_snippet,
		"dialogue_variables": dialogue_variables.duplicate(true),
	}


# Applies saved dialogue progress from a slot payload.
func apply_data(data: Dictionary) -> void:
	dialogue_resource_path = str(data.get("dialogue_resource_path", ""))
	dialogue_title = str(data.get("dialogue_title", ""))
	chapter_name = str(data.get("chapter_name", ""))
	character_name = str(data.get("character_name", ""))
	dialogue_snippet = str(data.get("dialogue_snippet", ""))
	dialogue_variables = (data.get("dialogue_variables", {}) as Dictionary).duplicate(true) if data.get("dialogue_variables", {}) is Dictionary else {}


# Provides an empty first-run dialogue payload.
func get_default_data() -> Dictionary:
	return {
		"dialogue_resource_path": "",
		"dialogue_title": "",
		"chapter_name": "",
		"character_name": "",
		"dialogue_snippet": "",
		"dialogue_variables": {},
	}


# Saves a generic dialogue progress snapshot without requiring Dialogue Manager types.
func save_progress(resource_or_path: Variant, title: String, chapter: String = "", character: String = "", snippet: String = "") -> void:
	dialogue_resource_path = _resource_path_from(resource_or_path)
	dialogue_title = title
	chapter_name = chapter
	character_name = character
	dialogue_snippet = _plain_text(snippet).left(60)


# Writes one dialogue variable.
func set_variable(key: String, value: Variant) -> void:
	dialogue_variables[key] = value


# Reads one dialogue variable.
func get_variable(key: String, default: Variant = null) -> Variant:
	return dialogue_variables.get(key, default)


# Reports whether this slot has resumable dialogue state.
func has_progress() -> bool:
	return not dialogue_resource_path.is_empty() and not dialogue_title.is_empty()


# Loads the recorded dialogue resource if it still exists.
func load_dialogue_resource() -> Resource:
	if dialogue_resource_path.is_empty():
		return null
	if not ResourceLoader.exists(dialogue_resource_path):
		push_warning("DialogueSlotModule: resource not found: %s" % dialogue_resource_path)
		return null
	return load(dialogue_resource_path)


# Extracts a resource path from a Resource or String.
func _resource_path_from(resource_or_path: Variant) -> String:
	if resource_or_path is String:
		return str(resource_or_path)
	if resource_or_path is Resource:
		var resource := resource_or_path as Resource
		return resource.resource_path if is_instance_valid(resource) else ""
	return ""


# Removes common bbcode tags without depending on DialogueLabel helpers.
func _plain_text(text: String) -> String:
	var result := ""
	var inside_tag := false
	for i in text.length():
		var ch := text[i]
		if ch == "[":
			inside_tag = true
			continue
		if ch == "]":
			inside_tag = false
			continue
		if not inside_tag:
			result += ch
	return result.strip_edges()
