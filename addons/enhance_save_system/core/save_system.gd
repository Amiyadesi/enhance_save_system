extends Node
## ════════════════════════════════════════════════════════════════
##  SaveSystem — 唯一全局存档入口（AutoLoad: "SaveSystem"）
## ════════════════════════════════════════════════════════════════
##
## 核心设计理念
## ────────────
##  ① 纯 JSON 存储：快速、人可读、无引用解析开销
##  ② 模块化多态：每个 ISaveModule 子类负责自己数据域
##  ③ 双轨道存档：全局（global.json）+ 槽位（slot_XX.json）
##  ④ Writer 积累模式：先收集所有模块变更 → 一次性写盘
##  ⑤ 可选加密（AES-GCM/AES-CBC/XOR）、压缩（gzip/deflate）、原子写入、版本迁移
##
## 信号列表
## ────────
##  global_saved(ok)                    全局存档写盘完成
##  global_loaded(ok)                   全局存档读取完成
##  slot_saved(slot, ok)                指定槽位写盘完成
##  slot_loaded(slot, ok)               指定槽位读取完成
##  slot_deleted(slot)                  槽位文件已删除
##  slot_changed(slot)                  当前活跃槽位切换
##  slot_load_failed(slot, reason)      槽位加载失败（含原因）
##  slot_backed_up(slot, backup_path)   槽位备份完成
##  save_migrated(slot, old_ver, new_ver) 存档迁移完成
##  quit_save_failed(global_ok, slot_ok) quit_cleanly 存档失败、游戏未退出

signal global_saved(ok: bool)
signal global_loaded(ok: bool)
signal slot_saved(slot: int, ok: bool)
signal slot_loaded(slot: int, ok: bool)
signal slot_deleted(slot: int)
signal slot_changed(new_slot: int)
signal slot_load_failed(slot: int, reason: String)
signal slot_backed_up(slot: int, backup_path: String)
signal save_migrated(slot: int, old_version: int, new_version: int)
signal quit_save_failed(global_ok: bool, slot_ok: bool)

# ──────────────────────────────────────────────
# 配置
# ──────────────────────────────────────────────

const DEFAULT_MAX_SLOTS := 3
@export var max_slots: int = DEFAULT_MAX_SLOTS
@export var auto_register: bool = true
@export var auto_load_global: bool = true
@export var auto_load_slot: int = 0
@export var game_version: String = "1.0.0"

## 自动存档
@export var auto_save_enabled: bool = false
## 自动存档间隔（秒），最小 10
const MIN_AUTO_SAVE_INTERVAL := 10
@export var auto_save_interval: int = 300 :
	set(v):
		auto_save_interval = maxi(MIN_AUTO_SAVE_INTERVAL, v)
@export var auto_save_slot: int = 1

## 存档预览图
@export var save_screenshots_enabled: bool = true
@export var screenshot_width: int = 640
@export var screenshot_height: int = 480

## 加密配置
@export var encryption_enabled: bool = true
@export var encryption_key: String = "your-encryption-key-here"
## 加密模式："xor" / "aes_cbc" / "aes_gcm"
@export var encryption_mode: String = "aes_gcm"

## 原子写入配置
@export var atomic_write_enabled: bool = true
@export var backup_enabled: bool = false

## 压缩配置
@export var compression_enabled: bool = false
## 压缩模式："gzip" / "deflate"
@export var compression_mode: String = "gzip"

## payload 正文编码："json_compact" / "variant_binary"
@export_enum("json_compact", "variant_binary") var payload_format: String = "json_compact"
@export var debug_pretty_json_dump_enabled: bool = false

## 分模块文件存储
@export var split_modules_enabled: bool = false

## 模块注册配置
@export var use_module_config: bool = true
@export var module_config_path: String = DEFAULT_MODULE_CONFIG_PATH

# ──────────────────────────────────────────────
# 路径常量
# ──────────────────────────────────────────────

## 公开给编辑器面板等外部工具，避免各处重复硬编码
const SAVE_DIR       := "user://saves"
const SLOT_PATTERN   := "user://saves/slot_%02d.json"
const DEFAULT_MODULE_CONFIG_PATH := "res://Config/save_modules.cfg"

const _SAVE_DIR      := SAVE_DIR
const _GLOBAL_PATH   := "user://saves/global.json"
const _SLOT_PATTERN  := SLOT_PATTERN
const _SCREENSHOT_DIR := "user://saves/screenshots"
const _SCREENSHOT_PATTERN := "user://saves/screenshots/slot_%02d.png"

# ──────────────────────────────────────────────
# 内部状态
# ──────────────────────────────────────────────

## 已注册的全局模块（key → { module, priority }）
var _global_modules: Dictionary = {}
## 已注册的槽位模块（key → { module, priority }）
var _slot_modules: Dictionary = {}

var current_slot: int = 1 :
	set(v):
		current_slot = clampi(v, 1, max_slots)

var _auto_save_elapsed: float = 0.0
var _register_serial: int = 0
var _migration_manager: MigrationManager

# ──────────────────────────────────────────────
# 生命周期
# ──────────────────────────────────────────────

## Initializes directories, module registration, optional initial load, and auto-save.
func _ready() -> void:
	_ensure_save_dir()
	if save_screenshots_enabled:
		_ensure_screenshot_dir()
	_migration_manager = MigrationManager.new()
	if auto_register:
		_auto_register_modules()
	if auto_load_global:
		load_global()
	if auto_load_slot > 0:
		load_slot(auto_load_slot)
	if auto_save_enabled:
		_setup_auto_save()
	else:
		_stop_auto_save()

## Advances the script-owned auto-save clock when periodic saving is enabled.
func _process(delta: float) -> void:
	if not auto_save_enabled:
		return
	_auto_save_elapsed += delta
	if _auto_save_elapsed < float(auto_save_interval):
		return
	_auto_save_elapsed = 0.0
	_on_auto_save_timeout()
# ──────────────────────────────────────────────
# 自动存档
# ──────────────────────────────────────────────

## Starts periodic auto-save without creating runtime Timer nodes.
func _setup_auto_save() -> void:
	_auto_save_elapsed = 0.0
	set_process(true)

## Stops periodic auto-save and clears pending elapsed time.
func _stop_auto_save() -> void:
	_auto_save_elapsed = 0.0
	set_process(false)

## Writes the configured auto-save slot when the timer fires.
func _on_auto_save_timeout() -> void:
	save_slot(auto_save_slot)
	if save_screenshots_enabled:
		_capture_screenshot(auto_save_slot)

## Turns periodic slot saving on or off without rebuilding save state.
func enable_auto_save(enabled: bool) -> void:
	auto_save_enabled = enabled
	if enabled:
		_setup_auto_save()
	else:
		_stop_auto_save()

## Updates the auto-save cadence and clamps unsafe short intervals.
func set_auto_save_interval(seconds: int) -> void:
	auto_save_interval = seconds
	_auto_save_elapsed = minf(_auto_save_elapsed, float(auto_save_interval))

# ──────────────────────────────────────────────
# 存档预览图
# ──────────────────────────────────────────────

## Ensures the preview screenshot directory exists before image writes.
func _ensure_screenshot_dir() -> void:
	if not DirAccess.dir_exists_absolute(_SCREENSHOT_DIR):
		DirAccess.make_dir_recursive_absolute(_SCREENSHOT_DIR)

## Captures the current viewport into the slot preview image.
func _capture_screenshot(slot: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_screenshot_dir()
	var screenshot_path := _screenshot_path(slot)
	var viewport := get_viewport()
	if not viewport:
		return
	var texture := viewport.get_texture()
	if not texture:
		return
	var image := texture.get_image()
	if not image:
		return
	image.resize(screenshot_width, screenshot_height)
	var err := image.save_png(screenshot_path)
	if err != OK:
		push_warning("SaveSystem: failed to write screenshot '%s' (err=%d)" % [screenshot_path, err])

## Returns the user:// path for a slot preview image.
func get_screenshot_path(slot: int) -> String:
	return _screenshot_path(slot)

## Formats the preview image path for a save slot.
func _screenshot_path(slot: int) -> String:
	return _SCREENSHOT_PATTERN % slot

# ──────────────────────────────────────────────
# 模块注册
# ──────────────────────────────────────────────

## Registers modules from the project-owned configuration file.
func _auto_register_modules() -> void:
	if not use_module_config:
		return
	for entry in _load_config_modules():
		register_module(entry["module"], entry["priority"])


## Loads the explicit project module configuration as { module, priority } entries.
func _load_config_modules() -> Array:
	if not FileAccess.file_exists(module_config_path):
		push_error("SaveSystem: module config not found '%s'. Create it (the editor plugin writes a starter file when the addon is enabled; see templates/save_modules.cfg.example), or set use_module_config = false and call register_module() yourself." % module_config_path)
		return []
	var registry := ModuleRegistry.new()
	var entries := registry.load_entries_from_config(module_config_path)
	# 一个还没登记任何模块的配置文件是合法的起始状态；登记了却一个都加载不出来才报错
	if entries.is_empty() and registry.count_config_sections(module_config_path) != 0:
		push_error("SaveSystem: module config '%s' loaded no modules" % module_config_path)
	return entries

## 注册存档模块
## priority: 执行优先级，数值越小越先执行 collect_data / apply_data（默认 100）
func register_module(module: ISaveModule, priority: int = 100) -> void:
	var key := module.get_module_key()
	if key.is_empty():
		push_error("SaveSystem.register_module: module key is empty")
		return
	_register_serial += 1
	var entry := { "module": module, "priority": priority, "order": _register_serial }
	if module.is_global():
		_global_modules[key] = entry
	else:
		_slot_modules[key] = entry

## Removes a module key from both global and slot registries.
func unregister_module(key: String) -> void:
	_global_modules.erase(key)
	_slot_modules.erase(key)

## Returns the registered module for a key regardless of persistence scope.
func get_module(key: String) -> ISaveModule:
	if _global_modules.has(key):
		return _global_modules[key]["module"]
	var entry = _slot_modules.get(key, null)
	return entry["module"] if entry != null else null

## Reports registered module keys grouped by global and slot scope.
func get_registered_keys() -> Dictionary:
	return {
		"global": _global_modules.keys(),
		"slot":   _slot_modules.keys(),
	}

## 注册全局迁移函数（供开发者在游戏启动时调用）
## from_version: 旧版本号
## migration_fn: func(payload: Dictionary) -> Dictionary
func register_migration(from_version: int, migration_fn: Callable) -> void:
	_migration_manager.register(from_version, migration_fn)

# ──────────────────────────────────────────────
# 内部：构建 WriteOptions / ReadOptions
# ──────────────────────────────────────────────

## Copies SaveSystem write settings into the writer options object.
func _make_write_opts() -> SaveWriter.WriteOptions:
	var opts := SaveWriter.WriteOptions.new()
	opts.game_version         = game_version
	opts.encryption_enabled   = encryption_enabled
	opts.encryption_key       = encryption_key
	opts.encryption_mode      = encryption_mode
	opts.compression_enabled  = compression_enabled
	opts.compression_mode     = compression_mode
	opts.atomic_write_enabled = atomic_write_enabled
	opts.backup_enabled       = backup_enabled
	opts.split_modules_enabled = split_modules_enabled
	opts.payload_format       = payload_format
	opts.debug_pretty_json_dump_enabled = debug_pretty_json_dump_enabled
	return opts

## Copies SaveSystem read settings into the writer options object.
func _make_read_opts() -> SaveWriter.ReadOptions:
	var opts := SaveWriter.ReadOptions.new()
	opts.encryption_key        = encryption_key if encryption_enabled else ""
	opts.split_modules_enabled = split_modules_enabled
	opts.allow_legacy_json     = true
	opts.payload_format_hint   = payload_format
	return opts

## 按 priority 升序排列模块数组
func _sorted_modules(registry: Dictionary) -> Array:
	var entries := registry.values()
	# sort_custom 不稳定：priority 相同时按注册先后
	entries.sort_custom(func(a, b):
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["order"] < b["order"])
	var result: Array = []
	for e in entries:
		result.append(e["module"])
	return result

# ──────────────────────────────────────────────
# 全局存档 API
# ──────────────────────────────────────────────

## Writes all registered global modules to the global save file.
func save_global() -> bool:
	var modules := _sorted_modules(_global_modules)
	var ok := SaveWriter.write(modules, _GLOBAL_PATH, _make_write_opts())
	global_saved.emit(ok)
	return ok

## Reads the global save file into all registered global modules.
func load_global() -> bool:
	var modules := _sorted_modules(_global_modules)
	var ok := SaveWriter.read(_GLOBAL_PATH, modules, _make_read_opts())
	global_loaded.emit(ok)
	return ok

## Marks a normal close, saves current state, and quits after both writes succeed.
## A failed save keeps the game open (so the player can retry) and emits quit_save_failed;
## pass quit_on_save_failure = true to quit anyway.
func quit_cleanly(quit_on_save_failure: bool = false) -> void:
	var stats := get_module("stats")
	if stats != null and "clean_exit" in stats:
		stats.clean_exit = true
	notify_app_close(true)
	var global_ok := save_global()
	var slot_ok := true
	if current_slot > 0 and slot_exists(current_slot):
		slot_ok = save_slot(current_slot)
	var saved := global_ok and slot_ok
	if not saved:
		push_error("SaveSystem.quit_cleanly: save failed (global=%s, slot=%s)" % [global_ok, slot_ok])
		quit_save_failed.emit(global_ok, slot_ok)
	if (saved or quit_on_save_failure) and get_tree() != null:
		get_tree().quit()

# ──────────────────────────────────────────────
# 单模块读写 API
# ──────────────────────────────────────────────

## Writes one registered module back into its owning global or slot save file.
func save_module(module_key: String, slot: int = -1) -> bool:
	var module := get_module(module_key)
	if module == null:
		push_warning("SaveSystem.save_module: module '%s' not registered" % module_key)
		return false
	var path: String
	if module.is_global():
		path = _GLOBAL_PATH
	else:
		var s := _resolve_slot(slot)
		if not _valid(s):
			return false
		path = _slot_path(s)
	return _write_module_to_file(module, path)

## Reads one registered module from its owning global or slot save file.
func load_module(module_key: String, slot: int = -1) -> bool:
	var module := get_module(module_key)
	if module == null:
		push_warning("SaveSystem.load_module: module '%s' not registered" % module_key)
		return false
	var path: String
	if module.is_global():
		path = _GLOBAL_PATH
	else:
		var s := _resolve_slot(slot)
		if not _valid(s):
			return false
		path = _slot_path(s)
	return _read_module_from_file(module, path)

## Rewrites a single module payload while preserving sibling module payloads.
func _write_module_to_file(module: ISaveModule, path: String) -> bool:
	var opts := _make_write_opts()
	var payload := SaveWriter.read_json(path, _make_read_opts())
	# 如果文件不存在或解析失败，payload 为空；此时直接创建一个新 payload
	if payload.is_empty():
		payload = {}
	# 更新当前模块对应的数据
	payload[module.get_module_key()] = module.collect_data()
	return SaveWriter.write_json(payload, path, opts)

## Applies one module payload from a save file when that key is present.
func _read_module_from_file(module: ISaveModule, path: String) -> bool:
	var payload := SaveWriter.read_json(path, _make_read_opts())
	if payload.is_empty():
		return false
	var key := module.get_module_key()
	if payload.has(key):
		module.apply_data(payload[key] as Dictionary)
		return true
	return false

# ──────────────────────────────────────────────
# 槽位存档 API
# ──────────────────────────────────────────────

## Writes all registered slot modules to the resolved save slot.
func save_slot(slot: int = -1) -> bool:
	var s := _resolve_slot(slot)
	if not _valid(s):
		return false
	var modules := _sorted_modules(_slot_modules)
	AtomicWriter.last_backup_path = ""
	var ok := SaveWriter.write(modules, _slot_path(s), _make_write_opts())
	if ok:
		if save_screenshots_enabled:
			_capture_screenshot(s)
		# 只有这次写入真的留下了 .bak 才通知（首次存档、备份改名失败时没有）
		var bak_path := AtomicWriter.last_backup_path
		if backup_enabled and not bak_path.is_empty() and FileAccess.file_exists(bak_path):
			slot_backed_up.emit(s, bak_path)
	slot_saved.emit(s, ok)
	return ok

## Reads, migrates, and applies all registered modules from the resolved save slot.
func load_slot(slot: int = -1) -> bool:
	var s := _resolve_slot(slot)
	if not _valid(s):
		return false
	var path := _slot_path(s)
	var payload := SaveWriter.read_json(path, _make_read_opts())
	if payload.is_empty():
		_emit_slot_load_failure(s, "read_failed")
		return false

	var migrated_payload := _migrate_slot_payload_if_needed(s, path, payload)
	if migrated_payload.is_empty():
		return false

	_apply_loaded_slot_payload(s, migrated_payload)
	return true

## Emits the standard failure signal pair for slot-load errors.
func _emit_slot_load_failure(slot: int, reason: String) -> void:
	slot_load_failed.emit(slot, reason)
	slot_loaded.emit(slot, false)

## Migrates slot payloads before module application when the stored format is old.
func _migrate_slot_payload_if_needed(slot: int, path: String, payload: Dictionary) -> Dictionary:
	var meta: Dictionary = payload.get("_meta", {})
	var file_version := int(meta.get("version", 0))
	if not _migration_manager.needs_migration(payload, SaveWriter.FORMAT_VERSION):
		return payload

	_backup_slot_before_migration(path)
	var migrated := _migration_manager.migrate(payload, file_version, SaveWriter.FORMAT_VERSION, _sorted_modules(_slot_modules))
	if not _migration_manager.last_error.is_empty():
		push_error("SaveSystem: migration failed for slot %d: %s" % [slot, _migration_manager.last_error])
		_emit_slot_load_failure(slot, "migration_failed")
		return {}

	save_migrated.emit(slot, file_version, SaveWriter.FORMAT_VERSION)
	return migrated

## Copies the original slot file before attempting version migration.
func _backup_slot_before_migration(path: String) -> void:
	var pre_bak := path + ".pre_migration.bak"
	DirAccess.copy_absolute(path, pre_bak)

## Applies loaded slot data and publishes the successful slot-change signals.
func _apply_loaded_slot_payload(slot: int, payload: Dictionary) -> void:
	SaveWriter.apply(payload, _sorted_modules(_slot_modules))
	current_slot = slot
	slot_changed.emit(slot)
	slot_loaded.emit(slot, true)

## Loads a slot and makes it the active slot when the load succeeds.
func set_slot(slot: int) -> bool:
	if not _valid(slot):
		return false
	var ok := load_slot(slot)
	if ok:
		current_slot = slot
		slot_changed.emit(slot)
	return ok

## Deletes the resolved slot save plus related screenshots, temp, backup, and split files.
func delete_slot(slot: int = -1) -> bool:
	var s := _resolve_slot(slot)
	if not _valid(s):
		return false

	var related_paths := _collect_slot_related_paths(s)
	var removed_any := false
	for path in related_paths:
		removed_any = _remove_save_file_if_exists(path) or removed_any

	if not removed_any:
		return false

	slot_deleted.emit(s)
	return true


## Lists every file that belongs to a slot so deletion stays complete.
func _collect_slot_related_paths(slot: int) -> Array[String]:
	var paths: Array[String] = []
	var slot_path := _slot_path(slot)
	paths.append(slot_path)
	paths.append(_screenshot_path(slot))
	paths.append(AtomicWriter.get_tmp_path(slot_path))
	paths.append(AtomicWriter.get_backup_path(slot_path))
	paths.append(slot_path + ".pre_migration.bak")

	if split_modules_enabled:
		var split_base := slot_path.get_basename()
		for key_variant in _slot_modules.keys():
			var module_key := str(key_variant)
			var module_path := "%s_%s.json" % [split_base, module_key]
			paths.append(module_path)
			paths.append(AtomicWriter.get_tmp_path(module_path))
			paths.append(AtomicWriter.get_backup_path(module_path))
			paths.append(module_path + ".pre_migration.bak")

	return paths


## Removes a save-related file if present and reports file-system errors.
func _remove_save_file_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var abs_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.remove_absolute(abs_path)
	if err != OK:
		push_error("SaveSystem.delete_slot: failed to delete '%s' (err=%d)" % [path, err])
		return false
	return true

## Checks whether the resolved slot has a primary save file.
func slot_exists(slot: int = -1) -> bool:
	return FileAccess.file_exists(_slot_path(_resolve_slot(slot)))

## Returns display metadata for every configured save slot.
func list_slots() -> Array[SlotInfo]:
	var result: Array[SlotInfo] = []
	for i in range(1, max_slots + 1):
		var path := _slot_path(i)
		var exists := FileAccess.file_exists(path)
		var meta: Dictionary = {}
		if exists:
			meta = SaveWriter.peek_meta(path)
		if save_screenshots_enabled:
			var screenshot_path := _screenshot_path(i)
			if FileAccess.file_exists(screenshot_path):
				meta["screenshot_path"] = screenshot_path
		result.append(SlotInfo.make(i, exists, meta))
	return result

# ──────────────────────────────────────────────
# 快捷存档
# ──────────────────────────────────────────────

## Writes both global state and the active slot as one player-facing quick save.
func quick_save() -> bool:
	var g := save_global()
	var s := save_slot(current_slot)
	return g and s

## Loads global state and the active slot, accepting partial recovery.
func quick_load() -> bool:
	var g := load_global()
	var s := load_slot(current_slot)
	return g or s

## Resets slot modules for a new run and makes the resolved slot active.
func new_game(slot: int = -1) -> void:
	var s := _resolve_slot(slot)
	current_slot = s
	for entry in _slot_modules.values():
		(entry["module"] as ISaveModule).on_new_game()

# ──────────────────────────────────────────────
# 导入 / 导出
# ──────────────────────────────────────────────

## Writes a slot to one self-contained external file for manual backup or transfer.
## A split-module slot is merged into a single file; the preview image, when present,
## is exported beside it as "<out_path basename>.png".
func export_slot(slot: int, out_path: String) -> bool:
	var s := _resolve_slot(slot)
	var src := _slot_path(s)
	if not FileAccess.file_exists(src):
		push_warning("SaveSystem.export_slot: slot %d not found" % slot)
		return false
	SaveWriter._ensure_dir(out_path)
	var ok := false
	if SaveWriter.peek_meta(src).get("split_modules", false):
		var payload := SaveWriter.read_json(src, _make_read_opts())
		if payload.is_empty() or _has_missing_split_modules(payload):
			push_error("SaveSystem.export_slot: cannot read every module of split slot %d" % s)
			return false
		var opts := _make_write_opts()
		opts.split_modules_enabled = false
		opts.backup_enabled = false
		opts.debug_pretty_json_dump_enabled = false
		ok = SaveWriter.write_json(payload, out_path, opts)
	else:
		ok = DirAccess.copy_absolute(src, out_path) == OK
	if ok and FileAccess.file_exists(_screenshot_path(s)):
		var shot_err := DirAccess.copy_absolute(_screenshot_path(s), _export_screenshot_path(out_path))
		if shot_err != OK:
			push_warning("SaveSystem.export_slot: screenshot not exported (err=%d)" % shot_err)
	return ok

## Validates an external save file and installs it into the chosen slot.
## With split_modules_enabled the payload is rewritten as split files; otherwise the file is copied.
func import_slot(slot: int, in_path: String) -> bool:
	if not _valid(slot):
		return false
	if not FileAccess.file_exists(in_path):
		push_warning("SaveSystem.import_slot: file not found '%s'" % in_path)
		return false
	# 传入 ReadOptions（含解密密钥），确保加密存档能正确解析
	var payload := SaveWriter.read_json(in_path, _make_read_opts())
	if payload.is_empty():
		push_error("SaveSystem.import_slot: invalid or unreadable save file '%s'" % in_path)
		return false
	var meta: Dictionary = payload.get("_meta", {})
	if _has_missing_split_modules(payload):
		push_error("SaveSystem.import_slot: '%s' is missing split module files %s" % [in_path, meta[SaveWriter.META_SPLIT_MISSING]])
		return false
	var has_module_data := false
	for key in payload:
		if not SaveWriter._is_reserved_key(key):
			has_module_data = true
			break
	if meta.get("split_modules", false) and not has_module_data:
		push_error("SaveSystem.import_slot: '%s' is a split-module main file without its module files; export it with export_slot() first" % in_path)
		return false
	var dst := _slot_path(slot)
	SaveWriter._ensure_dir(dst)
	var ok := false
	if split_modules_enabled or meta.get("split_modules", false):
		ok = SaveWriter.write_json(payload, dst, _make_write_opts())
	else:
		ok = DirAccess.copy_absolute(in_path, dst) == OK
	var shot := _export_screenshot_path(in_path)
	if ok and FileAccess.file_exists(shot):
		_ensure_screenshot_dir()
		DirAccess.copy_absolute(shot, _screenshot_path(slot))
	return ok

## True when a split save's index names modules whose files could not be read.
func _has_missing_split_modules(payload: Dictionary) -> bool:
	var meta: Dictionary = payload.get("_meta", {})
	return not (meta.get(SaveWriter.META_SPLIT_MISSING, []) as Array).is_empty()

## Preview image path that travels with an exported save file.
func _export_screenshot_path(save_path: String) -> String:
	return save_path.get_basename() + ".png"

# ──────────────────────────────────────────────
# Debug
# ──────────────────────────────────────────────

## Exposes a compact state snapshot for debug panels and diagnostics.
func get_component_data() -> Dictionary:
	return {
		"current_slot":   current_slot,
		"max_slots":      max_slots,
		"global_modules": _global_modules.keys(),
		"slot_modules":   _slot_modules.keys(),
		"global_exists":  FileAccess.file_exists(_GLOBAL_PATH),
		"slot_exists":    slot_exists(current_slot),
		"payload_format": payload_format,
		"debug_pretty_json_dump_enabled": debug_pretty_json_dump_enabled,
	}

# ──────────────────────────────────────────────
# 内部辅助
# ──────────────────────────────────────────────

## Ensures the root user:// save directory exists before any write.
func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(_SAVE_DIR)

## Validates that a slot id is inside the configured save-slot range.
func _valid(slot: int) -> bool:
	if slot < 1 or slot > max_slots:
		push_warning("SaveSystem: slot %d out of range (1–%d)" % [slot, max_slots])
		return false
	return true

## Resolves -1 to the active slot while leaving explicit slots unchanged.
func _resolve_slot(slot: int) -> int:
	return current_slot if slot < 0 else slot

## Formats the primary save-file path for a slot id.
func _slot_path(slot: int) -> String:
	return _SLOT_PATTERN % slot

## Notifies global modules that the app is closing so they can flush final state.
func notify_app_close(_normal_exit: bool = true) -> void:
	for i:Dictionary in _global_modules.values():
		var module = i["module"]
		if module.has_method("on_win_closed"):
			module.on_win_closed()
			
