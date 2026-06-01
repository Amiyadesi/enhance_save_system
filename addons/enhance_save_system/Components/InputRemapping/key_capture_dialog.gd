class_name KeyCaptureDialog
extends AcceptDialog
## 按键捕获弹窗
##
## 弹出后显示提示文字，等待玩家按下任意键 / 鼠标键 / 手柄键，
## 捕获到后自动关闭并通过信号回传事件。
##
## 用法（通常由 KeybindingRow / KeybindingUI 内部使用）：
##   通过 key_capture_dialog.tscn 或包含它的父场景实例化。
##   dlg.key_captured.connect(func(ev, action): do_rebind(action, ev))
##   dlg.open_for(action_name, display_name)

## 捕获到输入后触发，携带事件和对应的 action 名称
signal key_captured(event: InputEvent, action: String)
## 用户取消（点击 OK 按钮或按 ESC）
signal capture_cancelled(action: String)

## 当前正在重绑定的 action 名称
var _current_action: String = ""
var _current_display_name: String = ""

## 是否正在等待输入
var _waiting: bool = false

var _pending_conflict_event: InputEvent = null
var _pending_conflict_action: String = ""

@onready var _label: Label = %PromptLabel
@onready var _conflict_dialog: ConfirmationDialog = %ConflictDialog
@onready var _conflict_label: Label = %ConflictLabel


# Wires authored dialog controls and validates the scene contract.
func _ready() -> void:
	if _label == null:
		push_error("KeyCaptureDialog: PromptLabel missing from authored scene")
	if _conflict_dialog == null:
		push_error("KeyCaptureDialog: ConflictDialog missing from authored scene")
	if _conflict_label == null:
		push_error("KeyCaptureDialog: ConflictLabel missing from authored scene")

	# AcceptDialog OK 按钮 → 视为取消
	confirmed.connect(_on_cancelled)
	canceled.connect(_on_cancelled)
	_conflict_dialog.confirmed.connect(_on_conflict_confirmed)
	_conflict_dialog.canceled.connect(_on_conflict_cancelled)

# ──────────────────────────────────────────────
# 公开 API
# ──────────────────────────────────────────────

## 打开弹窗，准备捕获 action 的新绑定
func open_for(action: String, display_name: String = "") -> void:
	_current_action = action
	_current_display_name = display_name if not display_name.is_empty() else action
	_waiting        = true
	_label.text     = "正在设置：%s\n\n请按下新按键…\n（按「取消」保持不变）" % _current_display_name
	popup_centered()

# ──────────────────────────────────────────────
# 输入捕获
# ──────────────────────────────────────────────

# Captures one accepted input event while the dialog is visible.
func _input(event: InputEvent) -> void:
	if not _waiting or not visible:
		return

	var accepted := false

	if event is InputEventKey and event.pressed and not event.is_echo():
		# 忽略纯修饰键（Ctrl / Shift / Alt / Meta 单独按下时不触发）
		var kc: int = event.keycode
		if kc not in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META,
					  KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]:
			accepted = true

	elif event is InputEventMouseButton and event.pressed:
		accepted = true

	elif event is InputEventJoypadButton and event.pressed:
		accepted = true

	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		accepted = true

	if accepted:
		get_viewport().set_input_as_handled()
		_waiting = false
		_handle_captured_event(event)


# Routes a captured event through conflict confirmation when needed.
func _handle_captured_event(captured_event: InputEvent) -> void:
	var conflicts := _check_conflicts(captured_event)
	if conflicts.size() > 0:
		_show_conflict_dialog(conflicts, captured_event)
		return
	hide()
	key_captured.emit(captured_event, _current_action)


# Fills and opens the authored conflict confirmation dialog.
func _show_conflict_dialog(conflicts: Array, captured_event: InputEvent) -> void:
	_pending_conflict_event = captured_event
	_pending_conflict_action = _current_action
	var conflict_text := "检测到按键冲突：\n"
	for action in conflicts:
		if action != _current_action:
			conflict_text += "- %s\n" % action
	conflict_text += "\n是否覆盖？"
	_conflict_label.text = conflict_text
	_conflict_dialog.popup_centered()

# ──────────────────────────────────────────────
# 内部辅助
# ──────────────────────────────────────────────

# Returns actions that already use the captured event.
func _check_conflicts(event: InputEvent) -> Array:
	var km := _get_keybinding_module()
	if km and km.has_method("check_conflict"):
		return km.check_conflict(event)
	return []


# Finds the keybinding module from the SaveSystem autoload when available.
static func _get_keybinding_module() -> KeybindingModule:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var ss := tree.root.get_node_or_null("SaveSystem")
	if ss and ss.has_method("get_module"):
		return ss.get_module("keybindings") as KeybindingModule
	return null

# ──────────────────────────────────────────────
# 内部
# ──────────────────────────────────────────────

# Cancels the active capture request.
func _on_cancelled() -> void:
	if not _waiting:
		return
	_waiting = false
	hide()
	capture_cancelled.emit(_current_action)


# Applies the captured event after the user accepts a conflict warning.
func _on_conflict_confirmed() -> void:
	if _pending_conflict_event == null:
		return
	var captured_event := _pending_conflict_event
	var captured_action := _pending_conflict_action
	_pending_conflict_event = null
	_pending_conflict_action = ""
	_conflict_dialog.hide()
	hide()
	key_captured.emit(captured_event, captured_action)


# Reopens capture after the user rejects a conflict warning.
func _on_conflict_cancelled() -> void:
	_pending_conflict_event = null
	_pending_conflict_action = ""
	_conflict_dialog.hide()
	open_for(_current_action, _current_display_name)
