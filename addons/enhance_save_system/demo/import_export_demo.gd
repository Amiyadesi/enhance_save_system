extends Control
## 导入 / 导出存档 Demo
##
## 演示内容：
##   - 用 authored FileDialog 选择目标路径执行槽位导出
##   - 用 authored FileDialog 选择来源文件执行槽位导入
##   - 操作结果用 authored Label 反馈
##
## 使用：将本脚本挂到 `import_export_demo.tscn` 的根 Control 节点。

# ──────────────────────────────────────────────
# 内部节点引用
# ──────────────────────────────────────────────
@onready var _slot_spin: SpinBox = %SlotSpin
@onready var _export_btn: Button = %ExportButton
@onready var _import_btn: Button = %ImportButton
@onready var _feedback_success_label: Label = %FeedbackSuccessLabel
@onready var _feedback_fail_label: Label = %FeedbackFailLabel
@onready var _feedback_idle_label: Label = %FeedbackIdleLabel
@onready var _feedback_reset_timer: Timer = %FeedbackResetTimer
@onready var _export_dialog: FileDialog = %ExportDialog
@onready var _import_dialog: FileDialog = %ImportDialog


# Binds authored controls and modal dialogs to import/export behavior.
func _ready() -> void:
	_export_btn.pressed.connect(_on_export_pressed)
	_import_btn.pressed.connect(_on_import_pressed)
	_export_dialog.file_selected.connect(_on_export_path_selected)
	_import_dialog.file_selected.connect(_on_import_path_selected)
	_feedback_reset_timer.timeout.connect(_clear_feedback)


# Opens the authored export dialog after validating the selected save slot.
func _on_export_pressed() -> void:
	var slot := int(_slot_spin.value)
	var ss := _get_save_system()
	if not ss:
		_show_feedback("⚠ 未找到 SaveSystem（请检查 AutoLoad）", false)
		return
	if not ss.slot_exists(slot):
		_show_feedback("⚠ 槽位 %d 暂无存档，请先保存游戏" % slot, false)
		return
	_export_dialog.current_file = "slot_%02d.json" % slot
	_export_dialog.popup_centered()


# Opens the authored import dialog for the currently selected slot.
func _on_import_pressed() -> void:
	_import_dialog.popup_centered()


# Exports the selected save slot to the chosen user path.
func _on_export_path_selected(path: String) -> void:
	var slot := int(_slot_spin.value)
	var ss := _get_save_system()
	if not ss:
		_show_feedback("❌ 导出失败：SaveSystem 不可用", false)
		return
	var ok: bool = ss.export_slot(slot, path)
	if ok:
		_show_feedback("✅ 槽位 %d 已导出到：%s" % [slot, path.get_file()], true)
	else:
		_show_feedback("❌ 导出失败：写入文件出错", false)


# Imports the chosen file into the selected save slot.
func _on_import_path_selected(path: String) -> void:
	var slot := int(_slot_spin.value)
	var ss := _get_save_system()
	if not ss:
		_show_feedback("❌ 导入失败：SaveSystem 不可用", false)
		return
	var ok: bool = ss.import_slot(slot, path)
	if ok:
		_show_feedback("✅ 已导入到槽位 %d（来源：%s）" % [slot, path.get_file()], true)
	else:
		_show_feedback("❌ 导入失败：文件无效或格式错误", false)


# Shows one authored feedback label and schedules it to clear.
func _show_feedback(msg: String, success: bool) -> void:
	_feedback_success_label.visible = success
	_feedback_fail_label.visible = not success
	_feedback_idle_label.visible = false
	_feedback_success_label.text = msg if success else ""
	_feedback_fail_label.text = msg if not success else ""
	_feedback_idle_label.text = ""
	_feedback_reset_timer.start(3.6)


# Returns authored feedback labels to the neutral idle state after the result window expires.
func _clear_feedback() -> void:
	_feedback_success_label.visible = false
	_feedback_fail_label.visible = false
	_feedback_idle_label.visible = true
	_feedback_success_label.text = ""
	_feedback_fail_label.text = ""
	_feedback_idle_label.text = ""


# Returns the SaveSystem autoload when the demo is running in a project scene tree.
static func _get_save_system() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	return tree.root.get_node_or_null("SaveSystem")
