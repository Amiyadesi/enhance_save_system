@tool
class_name SavePlugin
extends EditorPlugin
const EDITOR_PANEL_SCENE := preload("res://addons/enhance_save_system/save_editor_panel.tscn")

static var instance: SavePlugin

var _editor_panel: Control
var _slot_tree: Tree
var _status_label: Label
var _export_dialog: FileDialog
var _import_dialog: FileDialog
var _delete_confirm_dialog: ConfirmationDialog
var _pending_export_path: String = ""
var _pending_import_slot: int = -1
var _pending_delete_slot: int = -1
var _pending_delete_path: String = ""

const _SAVE_DIR     := "user://saves"
const _SLOT_PATTERN := "user://saves/slot_%02d.json"
const _MAX_SLOTS    := 8

# Tracks the active plugin instance for plugin-path lookup.
func _init() -> void:
	instance = self


# Registers the runtime save-system autoload when the plugin is enabled.
func _enable_plugin() -> void:
	add_autoload_singleton("SaveSystem", get_plugin_path() + "/core/save_system.gd")


# Removes the runtime save-system autoload when the plugin is disabled.
func _disable_plugin() -> void:
	remove_autoload_singleton("SaveSystem")


# Creates the authored bottom panel and starts the first slot scan.
func _enter_tree() -> void:
	_editor_panel = EDITOR_PANEL_SCENE.instantiate() as Control
	_bind_editor_panel()
	add_control_to_bottom_panel(_editor_panel, "存档管理")
	_refresh_slot_list.call_deferred()


# Removes the bottom panel created by this plugin instance.
func _exit_tree() -> void:
	if is_instance_valid(_editor_panel):
		remove_control_from_bottom_panel(_editor_panel)
		_editor_panel.queue_free()


# Binds signals and required nodes from the authored editor panel scene.
func _bind_editor_panel() -> void:
	if _editor_panel == null:
		push_error("SavePlugin: save_editor_panel.tscn root must be a Control")
		return

	var refresh_button := _editor_panel.get_node("Toolbar/RefreshButton") as Button
	var export_button := _editor_panel.get_node("Toolbar/ExportButton") as Button
	var import_button := _editor_panel.get_node("Toolbar/ImportButton") as Button
	var delete_button := _editor_panel.get_node("Toolbar/DeleteButton") as Button
	_status_label = _editor_panel.get_node("Toolbar/StatusLabel") as Label
	_slot_tree = _editor_panel.get_node("SlotTree") as Tree
	_export_dialog = _editor_panel.get_node("ExportDialog") as FileDialog
	_import_dialog = _editor_panel.get_node("ImportDialog") as FileDialog
	_delete_confirm_dialog = _editor_panel.get_node("DeleteConfirmDialog") as ConfirmationDialog

	if refresh_button == null or export_button == null or import_button == null or delete_button == null:
		push_error("SavePlugin: toolbar buttons missing from authored panel")
		return
	if _status_label == null or _slot_tree == null:
		push_error("SavePlugin: status label or slot tree missing from authored panel")
		return
	if _export_dialog == null or _import_dialog == null or _delete_confirm_dialog == null:
		push_error("SavePlugin: file or confirmation dialogs missing from authored panel")
		return

	refresh_button.pressed.connect(_refresh_slot_list)
	export_button.pressed.connect(_on_export_pressed_toolbar)
	import_button.pressed.connect(_on_import_pressed_toolbar)
	delete_button.pressed.connect(_on_delete_pressed_toolbar)
	_export_dialog.file_selected.connect(_on_export_file_selected)
	_import_dialog.file_selected.connect(_on_import_file_selected)
	_delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	_delete_confirm_dialog.canceled.connect(_clear_delete_request)

	_slot_tree.set_column_title(0, "槽位")
	_slot_tree.set_column_title(1, "存档时间")
	_slot_tree.set_column_title(2, "游戏版本")
	_slot_tree.set_column_title(3, "格式版本")
	_slot_tree.set_column_title(4, "Payload")
	_slot_tree.set_column_title(5, "容器")
	_slot_tree.set_column_title(6, "加密")
	_slot_tree.set_column_title(7, "压缩")

# ──────────────────────────────────────────────
# 槽位列表刷新（直接读文件，不依赖 SaveSystem 运行时）
# ──────────────────────────────────────────────

# Reads save files directly and refreshes the bottom-panel slot tree.
func _refresh_slot_list() -> void:
	if not is_instance_valid(_slot_tree):
		return
	_slot_tree.clear()
	var root_item := _slot_tree.create_item()

	var found := 0
	for i in range(1, _MAX_SLOTS + 1):
		var path := _SLOT_PATTERN % i
		var exists := FileAccess.file_exists(path)

		var item := _slot_tree.create_item(root_item)
		item.set_text(0, "槽位 %d" % i)
		item.set_metadata(0, i)

		if not exists:
			_populate_empty_slot_item(item)
			continue

		found += 1
		_populate_saved_slot_item(item, path)

	_set_status("共 %d 个存档（最多 %d 槽）" % [found, _MAX_SLOTS])


# Writes the placeholder columns for an empty save slot.
func _populate_empty_slot_item(item: TreeItem) -> void:
	item.set_text(1, "（空）")
	item.set_text(2, "—")
	item.set_text(3, "—")
	item.set_text(4, "—")
	item.set_text(5, "—")
	item.set_text(6, "—")
	item.set_text(7, "—")


# Inspects one save file and writes its metadata into the slot tree row.
func _populate_saved_slot_item(item: TreeItem, path: String) -> void:
	var info := SaveWriter.inspect_file(path)
	var meta := info.get("meta", {}) as Dictionary
	var saved_at: float = float(meta.get("saved_at", 0))
	if saved_at > 0:
		item.set_text(1, _format_unix_for_player(int(saved_at)).replace("  ", " "))
	else:
		item.set_text(1, "未知时间")
	item.set_text(2, str(meta.get("game_version", "—")))
	item.set_text(3, str(meta.get("version", "—")))
	item.set_text(4, _format_payload_label(str(meta.get("payload_format", ""))))
	item.set_text(5, _format_storage_label(str(meta.get("storage_kind", ""))))
	item.set_text(6, str(meta.get("encryption_type", "无")))
	item.set_text(7, str(meta.get("compression", "无")))

# ──────────────────────────────────────────────
# 工具栏操作
# ──────────────────────────────────────────────

# Opens the authored export dialog for the selected save slot.
func _on_export_pressed_toolbar() -> void:
	var slot := _get_selected_slot()
	if slot < 0:
		_set_status("请先选择一个槽位")
		return
	var path := _SLOT_PATTERN % slot
	if not FileAccess.file_exists(path):
		_set_status("槽位 %d 无存档" % slot)
		return
	_pending_export_path = path
	_export_dialog.current_file = "slot_%02d.json" % slot
	_export_dialog.title = "导出槽位 %d 存档" % slot
	_export_dialog.popup_centered()


# Opens the authored import dialog for the selected save slot.
func _on_import_pressed_toolbar() -> void:
	var slot := _get_selected_slot()
	if slot < 0:
		_set_status("请先选择一个槽位")
		return
	_pending_import_slot = slot
	_import_dialog.title = "导入到槽位 %d" % slot
	_import_dialog.popup_centered()


# Opens the authored delete confirmation dialog for the selected save slot.
func _on_delete_pressed_toolbar() -> void:
	var slot := _get_selected_slot()
	if slot < 0:
		_set_status("请先选择一个槽位")
		return
	var path := _SLOT_PATTERN % slot
	if not FileAccess.file_exists(path):
		_set_status("槽位 %d 无存档可删除" % slot)
		return
	_pending_delete_slot = slot
	_pending_delete_path = path
	_delete_confirm_dialog.dialog_text = "确定要删除槽位 %d 的存档吗？" % slot
	_delete_confirm_dialog.popup_centered()


# Copies the selected save slot to the export destination.
func _on_export_file_selected(dst: String) -> void:
	if _pending_export_path.is_empty():
		_set_status("没有可导出的槽位")
		return
	var ok := DirAccess.copy_absolute(_pending_export_path, dst) == OK
	_set_status("导出%s：%s" % ["成功" if ok else "失败", dst])
	_pending_export_path = ""


# Copies an imported save file into the pending slot path.
func _on_import_file_selected(src: String) -> void:
	if _pending_import_slot < 0:
		_set_status("没有可导入的目标槽位")
		return
	var dst := _SLOT_PATTERN % _pending_import_slot
	_ensure_save_dir()
	var ok := DirAccess.copy_absolute(src, dst) == OK
	_set_status("导入%s：%s" % ["成功" if ok else "失败", src])
	_pending_import_slot = -1
	_refresh_slot_list()


# Deletes the pending save slot after confirmation.
func _on_delete_confirmed() -> void:
	if _pending_delete_slot < 0 or _pending_delete_path.is_empty():
		_set_status("没有可删除的槽位")
		return
	var abs_path := ProjectSettings.globalize_path(_pending_delete_path)
	var err := OS.move_to_trash(abs_path)
	if err != OK:
		err = DirAccess.remove_absolute(_pending_delete_path)
	_set_status("删除槽位 %d %s" % [_pending_delete_slot, "成功" if err == OK else "失败"])
	_clear_delete_request()
	_refresh_slot_list()


# Clears the pending delete request when the confirmation is dismissed.
func _clear_delete_request() -> void:
	_pending_delete_slot = -1
	_pending_delete_path = ""

# ──────────────────────────────────────────────
# 内部工具
# ──────────────────────────────────────────────

# Returns the selected slot number from the authored slot tree.
func _get_selected_slot() -> int:
	if not is_instance_valid(_slot_tree):
		return -1
	var selected := _slot_tree.get_selected()
	if selected == null:
		return -1
	return int(selected.get_metadata(0))


# Updates the toolbar status text when the authored label is available.
func _set_status(text: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = text


# Ensures the user save directory exists before importing a save file.
func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(_SAVE_DIR)


# Converts save payload ids into compact editor-facing labels.
func _format_payload_label(value: String) -> String:
	match value:
		SaveWriter.PAYLOAD_FORMAT_VARIANT_BINARY:
			return "variant_binary"
		SaveWriter.PAYLOAD_FORMAT_JSON_COMPACT:
			return "json_compact"
		SaveWriter.PAYLOAD_FORMAT_LEGACY_JSON:
			return "legacy_json"
		_:
			return "—"


# Converts storage-kind ids into compact editor-facing labels.
func _format_storage_label(value: String) -> String:
	match value:
		SaveWriter.STORAGE_KIND_CONTAINER:
			return "新容器"
		SaveWriter.STORAGE_KIND_PLAIN_TEXT_JSON:
			return "文本"
		SaveWriter.STORAGE_KIND_LEGACY_TEXT_JSON:
			return "旧文本"
		_:
			return "—"


# Formats save timestamps without depending on host-project utility scripts.
static func _format_unix_for_player(unix_time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
	]


# Returns this plugin folder so autoload paths stay valid after relocation.
static func get_plugin_path() -> String:
	if not is_instance_valid(instance):
		return ""
	return instance.get_script().resource_path.get_base_dir()
