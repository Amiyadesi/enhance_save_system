class_name ResourceSerializer
extends RefCounted
## 资源序列化器（纯静态工具）
##
## 功能：
##   1. SaveResource 的注册、序列化、反序列化
##   2. InputEvent（Key / MouseButton / JoypadButton / JoypadMotion）的序列化
##   3. 深度序列化：自动递归处理 Array / Dictionary 中嵌套的 SaveResource
##
## 使用流程：
##   # ① 启动时注册所有自定义资源类型（传入 Script 对象）
##   ResourceSerializer.register(WeaponData)
##
##   # ② 序列化（在 ISaveModule.collect_data 中）
##   var d := ResourceSerializer.serialize(my_weapon)
##   # d == { "__type": "WeaponData", "name": "剑", "damage": 10 }
##
##   # ③ 反序列化（在 ISaveModule.apply_data 中）
##   my_weapon = ResourceSerializer.deserialize(d)
##
##   # ④ InputEvent 序列化
##   var ev_dict := ResourceSerializer.serialize_event(input_event)
##   var ev      := ResourceSerializer.deserialize_event(ev_dict)

# 类型注册表：type_id (String) → Script
static var _registry: Dictionary = {}

# ══════════════════════════════════════════════
# SaveResource 注册
# ══════════════════════════════════════════════

## 注册一个 SaveResource 子类脚本
## 参数 script 即 GDScript 脚本对象（如 WeaponData，不是 WeaponData.new()）
static func register(script: Script) -> void:
	# 创建临时实例获取 type_id
	var tmp: SaveResource = script.new() as SaveResource
	if tmp == null:
		push_error("ResourceSerializer.register: script 不是 SaveResource 子类")
		return
	var tid: String = tmp.get_type_id()
	if tid.is_empty():
		push_error("ResourceSerializer.register: get_type_id() 返回空字符串")
		return
	_registry[tid] = script

## 注销
static func unregister(type_id: String) -> void:
	_registry.erase(type_id)

## 是否已注册
static func is_registered(type_id: String) -> bool:
	return _registry.has(type_id)

# ══════════════════════════════════════════════
# SaveResource 序列化 / 反序列化
# ══════════════════════════════════════════════

## 将 SaveResource 序列化为 Dictionary
## 自动注入 "__type" 字段供反序列化使用
static func serialize(res: SaveResource) -> Dictionary:
	if res == null:
		return {}
	var d := res.to_dict()
	d["__type"] = res.get_type_id()
	return d

## 从 Dictionary 重建 SaveResource
## 根据 "__type" 字段在注册表中查找对应脚本并实例化
static func deserialize(data: Dictionary) -> SaveResource:
	var type_id: String = data.get("__type", "")
	if type_id.is_empty():
		push_error("ResourceSerializer.deserialize: 缺少 __type 字段")
		return null
	if not _registry.has(type_id):
		push_error("ResourceSerializer.deserialize: 未注册类型 '%s'，请先调用 register()" % type_id)
		return null
	var script: Script = _registry[type_id]
	var res: SaveResource = script.new() as SaveResource
	if res == null:
		return null
	# 去掉 __type 后再传给 from_dict，保持接口干净
	var clean := data.duplicate()
	clean.erase("__type")
	res.from_dict(clean)
	return res

# ══════════════════════════════════════════════
# 深度序列化：支持 Array / Dictionary 中嵌套的 SaveResource
# ══════════════════════════════════════════════

## 深度序列化任意值（基本类型直接返回，SaveResource 自动展开）
static func serialize_value(v: Variant) -> Variant:
	if v is SaveResource:
		return serialize(v)
	elif v is Array:
		return serialize_array(v)
	elif v is Dictionary:
		return serialize_dict(v)
	# 基本类型：bool / int / float / String 直接返回
	return v

## 深度序列化 Array
static func serialize_array(arr: Array) -> Array:
	var out: Array = []
	for item in arr:
		out.append(serialize_value(item))
	return out

## 深度序列化 Dictionary（只序列化值，键保持 String）
static func serialize_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[k] = serialize_value(d[k])
	return out

## 深度反序列化任意值（发现 __type 的 Dictionary 自动还原为 SaveResource）
static func deserialize_value(v: Variant) -> Variant:
	if v is Dictionary:
		if (v as Dictionary).has("__type"):
			return deserialize(v)
		return deserialize_dict(v)
	elif v is Array:
		return deserialize_array(v)
	return v

## 深度反序列化 Array
static func deserialize_array(arr: Array) -> Array:
	var out: Array = []
	for item in arr:
		out.append(deserialize_value(item))
	return out

## 深度反序列化 Dictionary
static func deserialize_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[k] = deserialize_value(d[k])
	return out

# ══════════════════════════════════════════════
# InputEvent 序列化 / 反序列化
# ══════════════════════════════════════════════
## 支持类型：
##   InputEventKey / InputEventMouseButton /
##   InputEventJoypadButton / InputEventJoypadMotion

## 将 InputEvent 序列化为 Dictionary（JSON 安全）
static func serialize_event(event: InputEvent) -> Dictionary:
	if event == null:
		return {}
	if event is InputEventKey:
		return _serialize_key_event(event)
	elif event is InputEventMouseButton:
		return _serialize_mouse_button_event(event)
	elif event is InputEventJoypadButton:
		return _serialize_joypad_button_event(event)
	elif event is InputEventJoypadMotion:
		return _serialize_joypad_motion_event(event)
	push_warning("ResourceSerializer.serialize_event: 不支持的 InputEvent 类型 %s" % event.get_class())
	return {}

## 从 Dictionary 重建 InputEvent
static func deserialize_event(data: Dictionary) -> InputEvent:
	if data.is_empty():
		return null
	var t: String = data.get("event_type", "")
	match t:
		"key":
			return _deserialize_key_event(data)
		"mouse_button":
			return _deserialize_mouse_button_event(data)
		"joypad_button":
			return _deserialize_joypad_button_event(data)
		"joypad_motion":
			return _deserialize_joypad_motion_event(data)
	push_warning("ResourceSerializer.deserialize_event: 未知 event_type '%s'" % t)
	return null

## 将 InputEvent 转为人类可读字符串（用于按键 Button 显示）
static func event_to_display_string(event: InputEvent) -> String:
	if event == null:
		return "（未绑定）"
	if event is InputEventKey:
		return _key_event_to_display_string(event)
	elif event is InputEventMouseButton:
		return _mouse_button_event_to_display_string(event)
	elif event is InputEventJoypadButton:
		return "手柄键%d" % event.button_index
	elif event is InputEventJoypadMotion:
		return "摇杆轴%d(%.1f)" % [event.axis, event.axis_value]
	return event.as_text()

## Serializes keyboard events including modifier state.
static func _serialize_key_event(event: InputEventKey) -> Dictionary:
	return {
		"event_type"  : "key",
		"keycode"     : event.keycode,
		"physical"    : event.physical_keycode,
		"key_label"   : event.key_label,
		"ctrl"        : event.ctrl_pressed,
		"shift"       : event.shift_pressed,
		"alt"         : event.alt_pressed,
		"meta"        : event.meta_pressed,
	}

## Serializes mouse-button events including keyboard modifiers.
static func _serialize_mouse_button_event(event: InputEventMouseButton) -> Dictionary:
	return {
		"event_type"  : "mouse_button",
		"button_index": event.button_index,
		"ctrl"        : event.ctrl_pressed,
		"shift"       : event.shift_pressed,
		"alt"         : event.alt_pressed,
	}

## Serializes joypad button events.
static func _serialize_joypad_button_event(event: InputEventJoypadButton) -> Dictionary:
	return {
		"event_type"   : "joypad_button",
		"button_index" : event.button_index,
	}

## Serializes joypad axis motion events.
static func _serialize_joypad_motion_event(event: InputEventJoypadMotion) -> Dictionary:
	return {
		"event_type"   : "joypad_motion",
		"axis"         : event.axis,
		"axis_value"   : event.axis_value,
	}

## Restores keyboard events from JSON-safe event data.
static func _deserialize_key_event(data: Dictionary) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode          = int(data.get("keycode",    0))
	ev.physical_keycode = int(data.get("physical",   0))
	ev.key_label        = int(data.get("key_label",  0))
	ev.ctrl_pressed     = bool(data.get("ctrl",      false))
	ev.shift_pressed    = bool(data.get("shift",     false))
	ev.alt_pressed      = bool(data.get("alt",       false))
	ev.meta_pressed     = bool(data.get("meta",      false))
	return ev

## Restores mouse-button events from JSON-safe event data.
static func _deserialize_mouse_button_event(data: Dictionary) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index  = int(data.get("button_index", 0))
	ev.ctrl_pressed  = bool(data.get("ctrl",  false))
	ev.shift_pressed = bool(data.get("shift", false))
	ev.alt_pressed   = bool(data.get("alt",   false))
	return ev

## Restores joypad button events from JSON-safe event data.
static func _deserialize_joypad_button_event(data: Dictionary) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = int(data.get("button_index", 0))
	return ev

## Restores joypad axis motion events from JSON-safe event data.
static func _deserialize_joypad_motion_event(data: Dictionary) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis       = int(data.get("axis", 0))
	ev.axis_value = float(data.get("axis_value", 0.0))
	return ev

## Formats keyboard events with modifier names before the key label.
static func _key_event_to_display_string(event: InputEventKey) -> String:
	var parts: PackedStringArray = []
	if event.ctrl_pressed:  parts.append("Ctrl")
	if event.shift_pressed: parts.append("Shift")
	if event.alt_pressed:   parts.append("Alt")
	if event.meta_pressed:  parts.append("Meta")
	var kname := OS.get_keycode_string(event.keycode)
	if kname.is_empty():
		kname = OS.get_keycode_string(event.physical_keycode)
	parts.append(kname if not kname.is_empty() else "Key(%d)" % event.keycode)
	return "+".join(parts)

## Formats common mouse buttons with localized names.
static func _mouse_button_event_to_display_string(event: InputEventMouseButton) -> String:
	const BTN_NAMES := {
		MOUSE_BUTTON_LEFT  : "鼠标左键",
		MOUSE_BUTTON_RIGHT : "鼠标右键",
		MOUSE_BUTTON_MIDDLE: "鼠标中键",
	}
	return BTN_NAMES.get(event.button_index, "鼠标键%d" % event.button_index)
