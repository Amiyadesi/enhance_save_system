class_name KeybindingRow
extends HBoxContainer
## 按键绑定单行组件（场景版）
##
## 场景结构（keybinding_row.tscn）：
##   HBoxContainer  ← 本脚本
##   ├── ActionLabel  (Label)   — unique_name_in_owner
##   ├── VBoxContainer (BindingsContainer) — unique_name_in_owner
##   └── AddButton    (Button)  — unique_name_in_owner
##
## KeybindingUI 实例化场景后调用 setup() 完成初始化。

signal binding_changed(action: String, new_event: InputEvent)

## 对应的 InputMap 动作名
var action: String = ""

## 本地化显示名（空则直接显示 action）
var display_name: String = ""

## 共享弹窗（由 KeybindingUI 传入）
var _capture_dialog: KeyCaptureDialog

## 单个绑定按钮的 authored 场景
@export var binding_button_scene: PackedScene = preload("res://addons/enhance_save_system/Components/InputRemapping/keybinding_event_button.tscn")

@onready var _label: Label        = %ActionLabel
@onready var _bindings_container: VBoxContainer = %BindingsContainer
@onready var _add_button: Button  = %AddButton

var _binding_buttons: Array[Button] = []
var _pending_binding_index: int = -1

# ──────────────────────────────────────────────
# 公开 API
# ──────────────────────────────────────────────

## 初始化行数据，必须在 add_child 之后调用
func setup(p_action: String, p_display: String, capture_dialog: KeyCaptureDialog) -> void:
	action          = p_action
	display_name    = p_display
	_capture_dialog = capture_dialog
	_label.text     = p_display if not p_display.is_empty() else p_action
	_add_button.pressed.connect(_on_add_button_pressed)
	refresh()

## 直接从 InputMap 读取当前绑定刷新按钮文字
## ⚠ 不依赖 SaveSystem，InputMap 全局随时可用，无初始化时序问题
func refresh() -> void:
	_clear_binding_buttons()
	_refresh_bound_events()
	if _binding_buttons.size() == 0:
		_refresh_empty_binding()


# Removes previous authored binding-button instances before a refresh.
func _clear_binding_buttons() -> void:
	for button in _binding_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_binding_buttons.clear()


# Adds one button for each currently registered InputMap event.
func _refresh_bound_events() -> void:
	if not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	for i in range(events.size()):
		_add_binding_button(ResourceSerializer.event_to_display_string(events[i]), i)


# Adds the visible placeholder button when an action has no bindings.
func _refresh_empty_binding() -> void:
	_add_binding_button("未绑定", -1)


# Instantiates, attaches, and tracks one authored binding button.
func _add_binding_button(text: String, index: int) -> void:
	var button := _create_binding_button(text, index)
	if button == null:
		return
	_bindings_container.add_child(button)
	_binding_buttons.append(button)

# ──────────────────────────────────────────────
# 内部
# ──────────────────────────────────────────────

# Instantiates one authored binding button and binds it to an event index.
func _create_binding_button(text: String, index: int) -> Button:
	if binding_button_scene == null:
		push_error("KeybindingRow: binding_button_scene 未设置")
		return null
	var button := binding_button_scene.instantiate() as Button
	if button == null:
		push_error("KeybindingRow: binding_button_scene 根节点必须是 Button")
		return null
	button.text = text
	button.pressed.connect(_create_binding_pressed_func(index))
	return button


# Wraps a binding index into a button callback.
func _create_binding_pressed_func(index: int) -> Callable:
	return func():
		_on_binding_button_pressed(index)


# Opens capture for a new binding entry.
func _on_add_button_pressed() -> void:
	_on_binding_button_pressed(-1)


# Opens capture for an existing binding entry.
func _on_binding_button_pressed(index: int) -> void:
	if not is_instance_valid(_capture_dialog):
		push_error("KeybindingRow: _capture_dialog 未设置")
		return
	_pending_binding_index = index
	if _capture_dialog.key_captured.is_connected(_on_key_captured):
		_capture_dialog.key_captured.disconnect(_on_key_captured)
	_capture_dialog.key_captured.connect(_on_key_captured, CONNECT_ONE_SHOT)
	_capture_dialog.open_for(action, display_name)


# Applies a captured event to the row action and refreshes display text.
func _on_key_captured(event: InputEvent, captured_action: String) -> void:
	if captured_action != action:
		return
	var applied := _apply_captured_event(event)
	_pending_binding_index = -1
	if not applied:
		return
	refresh()
	binding_changed.emit(action, event)


# Applies captured input through SaveSystem first, then direct InputMap when unavailable.
func _apply_captured_event(event: InputEvent) -> bool:
	if not _can_apply_captured_event():
		return false
	var km := _get_keybinding_module()
	if km:
		_apply_captured_event_to_module(km, event)
		return true
	return _apply_captured_event_to_input_map(event)


# Validates the target action and binding index before mutating module or InputMap state.
func _can_apply_captured_event() -> bool:
	if not InputMap.has_action(action):
		push_error("KeybindingRow: InputMap 缺少 action=%s" % action)
		return false
	if _pending_binding_index == -1:
		return true
	var old_events := InputMap.action_get_events(action)
	if _pending_binding_index >= old_events.size():
		push_error("KeybindingRow: 绑定索引越界 action=%s index=%d" % [action, _pending_binding_index])
		return false
	return true


# Updates the keybinding module so it can broadcast and persist the new event.
func _apply_captured_event_to_module(km: KeybindingModule, event: InputEvent) -> void:
	if _pending_binding_index == -1:
		km.add_action_event(action, event)
	else:
		km.rebind_action_event(action, _pending_binding_index, event)
	var ss := _get_save_system()
	if ss and ss.has_method("save_global"):
		ss.save_global()


# Updates InputMap directly for tests or projects without the SaveSystem autoload.
func _apply_captured_event_to_input_map(event: InputEvent) -> bool:
	if _pending_binding_index == -1:
		InputMap.action_add_event(action, event)
		return true
	var old_events := InputMap.action_get_events(action)
	InputMap.action_erase_event(action, old_events[_pending_binding_index])
	InputMap.action_add_event(action, event)
	return true


# Finds the keybinding module from the SaveSystem autoload when available.
static func _get_keybinding_module() -> KeybindingModule:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var ss := tree.root.get_node_or_null("SaveSystem")
	if ss and ss.has_method("get_module"):
		return ss.get_module("keybindings") as KeybindingModule
	return null


# Finds the SaveSystem autoload for persisting edited bindings.
static func _get_save_system() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	return tree.root.get_node_or_null("SaveSystem")
