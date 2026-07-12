class_name StatsModule
extends ISaveModule
## 全局存档模块 — 游玩统计（可触发彩蛋）
##
## 存储全局累计数据：总游玩时长、总游戏次数、首次游玩时间等。
## 属于全局存档（is_global = true），跨槽位共享。
##
## 用法：
##   SaveSystem.register_module(StatsModule.new())
##
## 每帧更新时长（在主场景 _process 里调用）：
##   StatsModule.instance.tick(delta)
##
## 检查彩蛋：
##   if StatsModule.instance.total_play_time >= 3600.0:
##       unlock_easter_egg("1hour_veteran")

signal easter_egg_triggered(egg_id: String)
signal milestone_reached(key: String, value: Variant)

## 单例引用
static var instance: StatsModule

# ──────────────────────────────────────────────
# 状态
# ──────────────────────────────────────────────

## 累计游玩时长（秒，跨所有存档槽位）
var total_play_time: float = 0.0

## 总游戏次数（每次 new_game 或首次启动游戏 +1）
var total_play_count: int = 0

## 首次游玩 Unix 时间戳
var first_played_at: int = 0

## 最近一次会话开始/结束时间（Unix 时间戳）
var last_session_start: int = 0
var last_session_end: int = 0

## 会话历史（[{start:int,end:int}]）
var session_history: Array = []

## 自定义统计（可扩展，key → int/float/bool）
var custom: Dictionary = {}

## 是否正常退出（true = 正常退出，false = 崩溃/强杀/断电）
## 每次启动时读取，若为 false 则触发崩溃回归对话
## 正常退出路径写 true，启动时读取后立即重置为 false
var clean_exit: bool = true
var _previous_clean_exit: bool = true
var _session_tracking_started: bool = false


# 彩蛋触发记录（egg_id → true）
var _triggered_eggs: Dictionary = {}

# Registers the latest stats module instance and hooks global-load session tracking.
func _init() -> void:
	instance = self
	# 自动在全局存档读取后记录本次会话开始（以便获取上次退出时间）
	var save_system := _get_save_system()
	if save_system != null and save_system.has_signal("global_loaded"):
		save_system.global_loaded.connect(_on_global_loaded)


# ──────────────────────────────────────────────
# ISaveModule 接口
# ──────────────────────────────────────────────

# Returns the stable global-save key for play statistics.
func get_module_key() -> String:
	return "stats"

# Stores statistics globally because they span all save slots.
func is_global() -> bool:
	return true

# Captures cumulative stats, session history, egg markers, and exit state.
func collect_data() -> Dictionary:
	return {
		"total_play_time"  : total_play_time,
		"total_play_count" : total_play_count,
		"first_played_at"  : first_played_at,
		"last_session_start" : last_session_start,
		"last_session_end"   : last_session_end,
		"session_history"    : session_history.duplicate(true),
		"custom"           : custom.duplicate(true),
		"triggered_eggs"   : _triggered_eggs.duplicate(true),
		"clean_exit"       : clean_exit,
	}

# Applies persisted stats and records the previous session's exit state.
func apply_data(data: Dictionary) -> void:
	total_play_time   = float(data.get("total_play_time",   0.0))
	total_play_count  = int(data.get("total_play_count",    0))
	first_played_at   = int(data.get("first_played_at",     0))
	last_session_start = int(data.get("last_session_start", 0))
	last_session_end   = int(data.get("last_session_end",   0))
	session_history    = (data.get("session_history", []) as Array).duplicate(true)
	custom            = (data.get("custom",          {}) as Dictionary).duplicate(true)
	_triggered_eggs   = (data.get("triggered_eggs",  {}) as Dictionary).duplicate(true)
	# 读取上次退出状态，读取后立即标记为"未正常退出"（等待本次正常退出时再写 true）
	clean_exit        = _is_truthy(data.get("clean_exit", true))
	_previous_clean_exit = clean_exit
	_session_tracking_started = false

# Records a new playthrough start in cumulative stats.
func on_new_game() -> void:
	total_play_count += 1
	if first_played_at == 0:
		first_played_at = Time.get_unix_time_from_system()

# ──────────────────────────────────────────────
# 公开 API
# ──────────────────────────────────────────────

## 每帧调用以累计游玩时长
func tick(delta: float) -> void:
	total_play_time += delta

## 记录本次游戏启动（每次程序启动或进入主菜单时触发）
func _record_session_start() -> void:
	# 如果已经记录了本次会话的开始时间，则不重复记录（避免在不同场景间切换时重复计次）
	if last_session_start != 0 and last_session_end == 0:
		return
	var now := Time.get_unix_time_from_system()
	if first_played_at == 0:
		first_played_at = now
	last_session_start = now
	# 记录会话开始，稍后会话结束时补全 end 时间
	session_history.append({"start": now, "end": 0})

# Starts a session-tracking pass after global stats load.
func _on_global_loaded(_ok: bool) -> void:
	_record_session_start()
	_begin_session_tracking()

# Records clean shutdown state and asks SaveSystem to persist it.
func on_win_closed() -> void:
	# 在程序退出时自动记录结束并保存全局数据
	_record_session_end()
	# 标记为正常退出
	clean_exit = true
	var save_system := _get_save_system()
	if save_system != null and save_system.has_method("save_global"):
		save_system.call("save_global")

## 记录本次游戏退出（退出前调用一次）
func _record_session_end() -> void:
	var now := Time.get_unix_time_from_system()
	last_session_end = now
	if session_history.size() > 0:
		var idx := session_history.size() - 1
		var last := session_history[idx] as Dictionary
		if int(last.get("end", 0)) == 0:
			last["end"] = now
			session_history[idx] = last

# Reports whether the previous saved session ended unclearly.
func had_unclean_exit() -> bool:
	return not _previous_clean_exit


# Reports the previous saved session's clean-exit flag.
func was_previous_clean_exit() -> bool:
	return _previous_clean_exit

## 获取距离上次退出过去的秒数；若无记录则返回 -1
func get_seconds_since_last_exit() -> float:
	if last_session_end == 0:
		return -1
	return float(Time.get_unix_time_from_system() - last_session_end)

# Marks this running session as not cleanly closed until shutdown proves otherwise.
func _begin_session_tracking() -> void:
	if _session_tracking_started:
		return
	_session_tracking_started = true
	clean_exit = false
	var save_system := _get_save_system()
	if save_system != null and save_system.has_method("save_global"):
		save_system.call("save_global")

## 递增自定义计数器
func increment(key: String, amount: int = 1) -> void:
	custom[key] = int(custom.get(key, 0)) + amount
	milestone_reached.emit(key, custom[key])

## 触发彩蛋（确保每个 egg_id 只触发一次）
func trigger_egg(egg_id: String) -> bool:
	if _triggered_eggs.has(egg_id):
		return false
	_triggered_eggs[egg_id] = true
	easter_egg_triggered.emit(egg_id)
	return true

## 是否已触发某彩蛋
func has_egg(egg_id: String) -> bool:
	return _triggered_eggs.has(egg_id)


# Coerces common scalar values to bool for persisted flags.
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

## 获取已触发的所有彩蛋 ID
func get_all_eggs() -> Array:
	return _triggered_eggs.keys()


# Finds the SaveSystem autoload when running inside a SceneTree.
func _get_save_system() -> Node:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("SaveSystem")
