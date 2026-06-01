extends Control
## 综合功能 Demo
## 演示加密 + 压缩 + 原子写入 + 迁移 + UI 的完整工作流。

const TEST_SLOT := 9  # 使用槽位 9 避免覆盖用户数据。
const DEMO_ENCRYPTION_KEY := "demo-secret-key"
const BENCH_ENCRYPTION_KEY := "bench-key"
const BENCH_NPC_COUNT := 1000

@onready var _log: RichTextLabel = %Log
@onready var _enc_check: CheckBox = %EncCheck
@onready var _comp_check: CheckBox = %CompCheck
@onready var _atomic_check: CheckBox = %AtomicCheck
@onready var _backup_check: CheckBox = %BackupCheck


# Initializes demo defaults and prints the active save format version.
func _ready() -> void:
	_append("[b]综合功能 Demo[/b]")
	_append("FORMAT_VERSION = %d\n" % SaveWriter.FORMAT_VERSION)
	_enc_check.button_pressed = true
	_comp_check.button_pressed = true
	_atomic_check.button_pressed = true


# Writes the small sample save file using the selected option toggles.
func _on_save_pressed() -> void:
	_append("\n[b]── 保存测试 ──[/b]")
	var opts := SaveWriter.WriteOptions.new()
	opts.game_version = "1.0.0"
	opts.encryption_enabled = _enc_check.button_pressed
	opts.encryption_key = DEMO_ENCRYPTION_KEY
	opts.encryption_mode = "aes_gcm"
	opts.compression_enabled = _comp_check.button_pressed
	opts.compression_mode = "gzip"
	opts.atomic_write_enabled = _atomic_check.button_pressed
	opts.backup_enabled = _backup_check.button_pressed

	var payload := {
		"player": {"hp": 100, "name": "Hero", "score": 9999},
		"level": {"current": 5, "unlocked": [1, 2, 3, 4, 5]},
	}

	var path := "user://saves/slot_%02d.json" % TEST_SLOT
	var ok := SaveWriter.write_json(payload, path, opts)

	_append("加密：%s | 压缩：%s | 原子写入：%s | 备份：%s" % [
		_yn(opts.encryption_enabled),
		_yn(opts.compression_enabled),
		_yn(opts.atomic_write_enabled),
		_yn(opts.backup_enabled),
	])
	if ok:
		_append("[color=green]✓ 保存成功：%s[/color]" % path)
		var size := _file_size(path)
		_append("文件大小：%d 字节" % size)
	else:
		_append("[color=red]✗ 保存失败[/color]")


# Loads the small sample save file with the currently selected encryption setting.
func _on_load_pressed() -> void:
	_append("\n[b]── 加载测试 ──[/b]")
	var path := "user://saves/slot_%02d.json" % TEST_SLOT
	if not FileAccess.file_exists(path):
		_append("[color=red]文件不存在，请先保存[/color]")
		return

	var opts := SaveWriter.ReadOptions.new()
	opts.encryption_key = DEMO_ENCRYPTION_KEY if _enc_check.button_pressed else ""

	var payload := SaveWriter.read_json(path, opts)
	if payload.is_empty():
		_append("[color=red]✗ 加载失败（解密/解压错误）[/color]")
		return

	_append("[color=green]✓ 加载成功[/color]")
	_append("数据：" + JSON.stringify(payload, "  "))


# Verifies that encrypted saves reject an incorrect key.
func _on_wrong_key_pressed() -> void:
	_append("\n[b]── 错误密钥测试（验证完整性保护）──[/b]")
	var path := "user://saves/slot_%02d.json" % TEST_SLOT
	if not FileAccess.file_exists(path):
		_append("[color=red]文件不存在，请先保存[/color]")
		return
	var opts := SaveWriter.ReadOptions.new()
	opts.encryption_key = "wrong-key-12345"
	var payload := SaveWriter.read_json(path, opts)
	if payload.is_empty():
		_append("[color=green]✓ 正确：错误密钥被拒绝（完整性验证通过）[/color]")
	else:
		_append("[color=red]✗ 警告：错误密钥未被检测到[/color]")


# Removes the sample save file and its atomic-write leftovers.
func _on_cleanup_pressed() -> void:
	var path := "user://saves/slot_%02d.json" % TEST_SLOT
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_append("\n[color=orange]已清理测试文件[/color]")


# Runs payload-format, compression, and encryption size/readback comparisons.
func _on_compression_bench_pressed() -> void:
	_append("\n[b]── Payload / 压缩 / 加密基准测试 ──[/b]")
	var big_payload := _build_benchmark_payload()
	var pretty_envelope := _build_pretty_envelope(big_payload)
	var benchmark_results: Array = []

	for entry in _benchmark_variants():
		benchmark_results.append(_write_benchmark_variant(entry, big_payload, pretty_envelope))

	_append_benchmark_summary(benchmark_results)
	_verify_benchmark_reads(benchmark_results)
	_cleanup_benchmark_files(benchmark_results)


# Builds a large repetitive payload so compression results are meaningful.
func _build_benchmark_payload() -> Dictionary:
	var npcs: Array = []
	for i in range(BENCH_NPC_COUNT):
		npcs.append({
			"id": i,
			"name": "NPC_%04d" % i,
			"hp": 100,
			"mp": 50,
			"level": (i % 20) + 1,
			"position": {"x": float(i * 3), "y": 0.0, "z": float(i * 2)},
			"inventory": ["sword", "shield", "potion", "potion", "potion"],
			"flags": {"alive": true, "hostile": (i % 3 == 0), "quest_giver": (i % 10 == 0)},
			"stats": {"str": 10, "dex": 8, "int": 6, "vit": 12},
		})
	return {
		"npcs": {"list": npcs},
		"world": {
			"seed": 123456789,
			"time": 72000,
			"weather": "sunny",
			"tiles": range(500),
		},
	}


# Wraps benchmark payload in the same metadata envelope a pretty baseline needs.
func _build_pretty_envelope(payload: Dictionary) -> Dictionary:
	var pretty_envelope := {
		"_meta": {
			"version": SaveWriter.FORMAT_VERSION,
			"saved_at": Time.get_unix_time_from_system(),
			"game_version": "bench",
			"payload_format": SaveWriter.PAYLOAD_FORMAT_JSON_COMPACT,
			"body_encoding_version": SaveWriter.BODY_ENCODING_VERSION,
		}
	}
	for key in payload:
		pretty_envelope[key] = payload[key]
	return pretty_envelope


# Returns the benchmark formats and read keys in one scannable table.
func _benchmark_variants() -> Array:
	return [
		{
			"label": "pretty JSON（人工可读基线）",
			"path": "user://saves/bench_pretty.json",
			"manual_pretty": true,
			"read_key": "",
		},
		{
			"label": "compact JSON",
			"path": "user://saves/bench_compact.json",
			"opts": _make_bench_opts(SaveWriter.PAYLOAD_FORMAT_JSON_COMPACT, false, false),
			"read_key": "",
		},
		{
			"label": "compact JSON + gzip",
			"path": "user://saves/bench_compact_gzip.json",
			"opts": _make_bench_opts(SaveWriter.PAYLOAD_FORMAT_JSON_COMPACT, true, false),
			"read_key": "",
		},
		{
			"label": "variant binary",
			"path": "user://saves/bench_variant_binary.json",
			"opts": _make_bench_opts(SaveWriter.PAYLOAD_FORMAT_VARIANT_BINARY, false, false),
			"read_key": "",
		},
		{
			"label": "variant binary + gzip",
			"path": "user://saves/bench_variant_binary_gzip.json",
			"opts": _make_bench_opts(SaveWriter.PAYLOAD_FORMAT_VARIANT_BINARY, true, false),
			"read_key": "",
		},
		{
			"label": "variant binary + gzip + AES-GCM",
			"path": "user://saves/bench_variant_binary_secure.json",
			"opts": _make_bench_opts(SaveWriter.PAYLOAD_FORMAT_VARIANT_BINARY, true, true),
			"read_key": BENCH_ENCRYPTION_KEY,
		},
	]


# Writes one benchmark variant and returns its result record.
func _write_benchmark_variant(entry: Dictionary, payload: Dictionary, pretty_envelope: Dictionary) -> Dictionary:
	var target_path := str(entry["path"])
	var ok := false
	if entry.get("manual_pretty", false):
		ok = _write_pretty_benchmark(target_path, pretty_envelope)
	else:
		ok = SaveWriter.write_json(payload, target_path, entry["opts"])
	return {
		"label": entry["label"],
		"path": target_path,
		"ok": ok,
		"size": _file_size(target_path),
		"read_key": str(entry.get("read_key", "")),
	}


# Writes the human-readable JSON baseline used by the benchmark.
func _write_pretty_benchmark(target_path: String, pretty_envelope: Dictionary) -> bool:
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(JSON.stringify(pretty_envelope, "\t").to_utf8_buffer())
	return true


# Prints each benchmark file size and its relative saving against the pretty baseline.
func _append_benchmark_summary(benchmark_results: Array) -> void:
	var baseline_size := maxi(1, int(benchmark_results[0]["size"]))
	_append("数据规模：%d 个 NPC + 世界数据" % BENCH_NPC_COUNT)
	for result in benchmark_results:
		var ratio := 100.0 * (1.0 - float(result["size"]) / float(baseline_size))
		_append("%s： [color=%s]%s[/color]（相对 pretty %.1f%%）" % [
			result["label"],
			"green" if bool(result["ok"]) else "red",
			_fmt_size(int(result["size"])),
			ratio,
		])


# Reads every written benchmark variant back and reports decode correctness.
func _verify_benchmark_reads(benchmark_results: Array) -> void:
	for result in benchmark_results:
		if not bool(result["ok"]):
			continue
		var read_opts := SaveWriter.ReadOptions.new()
		read_opts.encryption_key = str(result["read_key"])
		var loaded := SaveWriter.read_json(str(result["path"]), read_opts)
		var npc_count: int = (loaded.get("npcs", {}) as Dictionary).get("list", []).size()
		if npc_count == BENCH_NPC_COUNT:
			_append("[color=green]✓ 读取验证通过：%s[/color]" % result["label"])
		else:
			_append("[color=red]✗ 读取验证失败：%s（NPC=%d）[/color]" % [result["label"], npc_count])


# Removes temporary benchmark files after their sizes and readbacks are reported.
func _cleanup_benchmark_files(benchmark_results: Array) -> void:
	for result in benchmark_results:
		var p := str(result["path"])
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# Creates a SaveWriter option bundle for one benchmark variant.
func _make_bench_opts(payload_format: String, enable_gzip: bool, enable_aes: bool) -> SaveWriter.WriteOptions:
	var opts := SaveWriter.WriteOptions.new()
	opts.game_version = "bench"
	opts.payload_format = payload_format
	opts.atomic_write_enabled = false
	opts.compression_enabled = enable_gzip
	opts.compression_mode = "gzip"
	opts.encryption_enabled = enable_aes
	opts.encryption_key = BENCH_ENCRYPTION_KEY
	opts.encryption_mode = "aes_gcm"
	return opts


# Returns the current file size or zero when the target does not exist.
func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


# Formats byte counts for compact benchmark output.
func _fmt_size(bytes: int) -> String:
	if bytes >= 1024:
		return "%.1f KB (%d B)" % [bytes / 1024.0, bytes]
	return "%d B" % bytes


# Formats a boolean as colored rich text.
func _yn(v: bool) -> String:
	return "[color=green]是[/color]" if v else "[color=gray]否[/color]"


# Appends one rich-text line to the authored log.
func _append(text: String) -> void:
	_log.append_text(text + "\n")
