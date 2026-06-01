class_name SaveWriter
extends RefCounted
## 纯静态读写工具（无状态）
##
## 写入管线：JSON 字符串 → [compress] → [encrypt] → 二进制格式 → AtomicWriter/直接写
## 读取管线：读文件 → 解析格式头 → [decrypt] → [decompress] → JSON.parse → payload
##
## 二进制文件格式（加密或压缩时启用）：
##   [4字节 LE: header_len][header JSON bytes][body bytes]
##   header JSON 包含 _meta（含 iv/tag/hmac 等加密参数）
##
## 纯文本格式（无加密无压缩时）：
##   完整 JSON 文本（向后兼容）

const FORMAT_VERSION := 3
const BODY_ENCODING_VERSION := 1
const PAYLOAD_FORMAT_JSON_COMPACT := "json_compact"
const PAYLOAD_FORMAT_VARIANT_BINARY := "variant_binary"
const PAYLOAD_FORMAT_LEGACY_JSON := "json_legacy"
const STORAGE_KIND_CONTAINER := "container"
const STORAGE_KIND_PLAIN_TEXT_JSON := "plain_text_json"
const STORAGE_KIND_LEGACY_TEXT_JSON := "legacy_text_json"

## 魔数：用于识别新二进制格式（header 长度不可能超过此值的纯文本文件）
const _MAX_HEADER_LEN := 65536

## 写入选项（由 SaveSystem 构建后传入）
class WriteOptions:
	var game_version: String = ""
	var encryption_enabled: bool = false
	var encryption_key: String = ""
	var encryption_mode: String = "xor"   # "xor" / "aes_cbc" / "aes_gcm"
	var compression_enabled: bool = false
	var compression_mode: String = "gzip" # "gzip" / "deflate"
	var atomic_write_enabled: bool = true
	var backup_enabled: bool = false
	var split_modules_enabled: bool = false
	var payload_format: String = PAYLOAD_FORMAT_JSON_COMPACT
	var debug_pretty_json_dump_enabled: bool = false

## 读取选项
class ReadOptions:
	var encryption_key: String = ""
	var split_modules_enabled: bool = false
	var allow_legacy_json: bool = true
	var payload_format_hint: String = ""

# ──────────────────────────────────────────────
# 写入：收集 → 序列化 → 落盘
# ──────────────────────────────────────────────

## 从模块数组收集数据，构建 payload（不含 _meta）
static func collect(modules: Array) -> Dictionary:
	var payload: Dictionary = {}
	for m: ISaveModule in modules:
		var key := m.get_module_key()
		if key.is_empty():
			push_warning("SaveWriter.collect: module has empty key, skipped")
			continue
		payload[key] = m.collect_data()
	return payload

## 将 payload 写入文件（自动添加 _meta 头）
static func write_json(payload: Dictionary, path: String, opts: WriteOptions = null) -> bool:
	if opts == null:
		opts = WriteOptions.new()

	_ensure_dir(path)
	var effective_payload_format := _normalize_payload_format(opts.payload_format, opts.split_modules_enabled)

	# 分模块文件模式
	if opts.split_modules_enabled:
		var split_meta := _build_meta(opts, effective_payload_format)
		var split_ok := _write_split(payload, path, split_meta, opts)
		if split_ok and opts.debug_pretty_json_dump_enabled:
			_write_debug_dump(_make_envelope(payload, split_meta), path)
		return split_ok

	# 构建完整 envelope（含 _meta）
	var meta := _build_meta(opts, effective_payload_format)
	var envelope := _make_envelope(payload, meta)

	# 序列化 payload 为正文 bytes
	var body := _encode_body(payload, envelope, effective_payload_format)
	if body.is_empty() and not payload.is_empty():
		push_error("SaveWriter: failed to encode payload for '%s'" % path)
		return false

	if opts.debug_pretty_json_dump_enabled:
		_write_debug_dump(envelope, path)

	# json_compact 在未压缩/未加密时直接写纯文本 JSON
	if effective_payload_format == PAYLOAD_FORMAT_JSON_COMPACT and not opts.encryption_enabled and not opts.compression_enabled:
		return _flush(body, path, opts)

	# 压缩（先压缩后加密）
	if opts.compression_enabled:
		var cmode := Compressor.mode_from_string(opts.compression_mode)
		body = Compressor.compress(body, cmode)
		if body.is_empty():
			push_error("SaveWriter: compression failed for '%s'" % path)
			return false

	# 加密：执行后把 iv/tag/hmac 写入 meta
	if opts.encryption_enabled:
		var emode := Encryptor.mode_from_string(opts.encryption_mode)
		var enc := Encryptor.encrypt(body, opts.encryption_key, emode)
		if enc.is_empty():
			push_error("SaveWriter: encryption failed for '%s'" % path)
			return false
		_write_encryption_meta(meta, enc)
		body = enc.get("ciphertext", PackedByteArray())

	# 打包为二进制格式：[4字节 header_len][header JSON][body]
	var header_bytes := JSON.stringify(meta).to_utf8_buffer()
	var file_data := _pack_binary(header_bytes, body)
	return _flush(file_data, path, opts)

## 一步完成：collect + write_json
static func write(modules: Array, path: String, opts: WriteOptions = null) -> bool:
	var payload := collect(modules)
	return write_json(payload, path, opts)

# ──────────────────────────────────────────────
# 读取：从磁盘 → payload → 分发给模块
# ──────────────────────────────────────────────

## 从文件读取 payload（含 _meta）
static func read_json(path: String, opts: ReadOptions = null) -> Dictionary:
	if opts == null:
		opts = ReadOptions.new()

	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveWriter: cannot open '%s' for read" % path)
		return {}
	var raw := file.get_buffer(file.get_length())
	file = null

	var parsed_binary := _try_unpack_binary(raw)
	if parsed_binary.size() != 2:
		return _read_legacy_text_json(raw, path, opts)

	return _read_container_payload(parsed_binary[0], parsed_binary[1], path, opts)

## Reads the current binary container format from already-unpacked header/body data.
static func _read_container_payload(meta: Dictionary, body: PackedByteArray, path: String, opts: ReadOptions) -> Dictionary:
	var payload_format := _resolved_payload_format(meta, opts.payload_format_hint)
	body = _decrypt_body_if_needed(meta, body, path, opts.encryption_key)
	if body.is_empty():
		return {}

	body = _decompress_body_if_needed(meta, body, path)
	if body.is_empty():
		return {}

	var result := _decode_body(body, payload_format, path)
	if result.is_empty():
		return {}

	# 将 header 中的 meta 合并回 result（确保 _meta 完整）
	var body_meta: Dictionary = result.get("_meta", {})
	result["_meta"] = _decorate_meta(_merge_meta(meta, body_meta), payload_format, STORAGE_KIND_CONTAINER)

	# 分模块文件模式
	if result.get("_meta", {}).get("split_modules", false):
		return _read_split(result, path, opts)

	return result


## Decrypts container body bytes when encryption metadata and a key are present.
static func _decrypt_body_if_needed(meta: Dictionary, body: PackedByteArray, path: String, encryption_key: String) -> PackedByteArray:
	var encryption_type: String = meta.get("encryption_type", "")
	if encryption_type.is_empty() or encryption_key.is_empty():
		return body
	var dec_meta := {
		"mode":       encryption_type,
		"ciphertext": body,
		"iv":         Marshalls.base64_to_raw(str(meta.get("iv",   ""))),
		"tag":        Marshalls.base64_to_raw(str(meta.get("tag",  ""))),
		"hmac":       Marshalls.base64_to_raw(str(meta.get("hmac", ""))),
	}
	var decrypted := Encryptor.decrypt(dec_meta, encryption_key)
	if decrypted.is_empty():
		push_error("SaveWriter: decryption failed for '%s'" % path)
	return decrypted


## Decompresses container body bytes when compression metadata is present.
static func _decompress_body_if_needed(meta: Dictionary, body: PackedByteArray, path: String) -> PackedByteArray:
	var compression: String = meta.get("compression", "")
	if compression.is_empty():
		return body
	var cmode := Compressor.mode_from_string(compression)
	var decompressed := Compressor.decompress(body, cmode)
	if decompressed.is_empty():
		push_error("SaveWriter: decompression failed for '%s'" % path)
	return decompressed

## 将 payload 分发给模块
static func apply(payload: Dictionary, modules: Array) -> void:
	for m: ISaveModule in modules:
		var key := m.get_module_key()
		if payload.has(key):
			m.apply_data(payload[key] as Dictionary)

## 一步完成：read_json + apply
static func read(path: String, modules: Array, opts: ReadOptions = null) -> bool:
	var payload := read_json(path, opts)
	if payload.is_empty():
		return false
	apply(payload, modules)
	return true

# ──────────────────────────────────────────────
# 槽位元信息辅助
# ──────────────────────────────────────────────

static func get_meta_data(payload: Dictionary) -> Dictionary:
	return payload.get("_meta", {}) as Dictionary


static func inspect_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_buffer(file.get_length())
	file = null

	var parsed := _try_unpack_binary(raw)
	if parsed.size() == 2:
		var meta := parsed[0] as Dictionary
		var payload_format := _resolved_payload_format(meta)
		return {
			"meta": _decorate_meta(meta, payload_format, STORAGE_KIND_CONTAINER),
			"payload_format": payload_format,
			"storage_kind": STORAGE_KIND_CONTAINER,
			"is_legacy": payload_format == PAYLOAD_FORMAT_LEGACY_JSON,
		}

	var text := raw.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		var meta := (json.data as Dictionary).get("_meta", {}) as Dictionary
		var payload_format := _resolved_payload_format(meta)
		var storage_kind := _infer_text_storage_kind(meta)
		return {
			"meta": _decorate_meta(meta, payload_format, storage_kind),
			"payload_format": payload_format,
			"storage_kind": storage_kind,
			"is_legacy": payload_format == PAYLOAD_FORMAT_LEGACY_JSON,
		}
	return {}

## 只读取文件的 _meta 头，不解密/解压 body
## 对加密文件同样有效（meta 存在 header 中，明文可读）
static func peek_meta(path: String) -> Dictionary:
	var info := inspect_file(path)
	return info.get("meta", {}) as Dictionary

# ──────────────────────────────────────────────
# 二进制格式打包/解包
# ──────────────────────────────────────────────

## 打包：[4字节 LE header_len][header bytes][body bytes]
static func _pack_binary(header: PackedByteArray, body: PackedByteArray) -> PackedByteArray:
	var hlen := header.size()
	var result := PackedByteArray()
	result.resize(4 + hlen + body.size())
	# 写入 header 长度（小端序 4 字节）
	result[0] = hlen & 0xFF
	result[1] = (hlen >> 8) & 0xFF
	result[2] = (hlen >> 16) & 0xFF
	result[3] = (hlen >> 24) & 0xFF
	# 写入 header
	for i in range(hlen):
		result[4 + i] = header[i]
	# 写入 body
	for i in range(body.size()):
		result[4 + hlen + i] = body[i]
	return result

## 解包：返回 [meta_dict, body_bytes]，失败返回空数组 []
static func _try_unpack_binary(data: PackedByteArray) -> Array:
	if data.size() < 4:
		return []

	# 读取 header 长度（小端序）
	var hlen: int = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24)

	# 合理性检查：header 长度必须在合理范围内
	if hlen <= 0 or hlen > _MAX_HEADER_LEN or (4 + hlen) > data.size():
		return []

	# 尝试解析 header JSON
	var header_bytes := data.slice(4, 4 + hlen)
	var header_text := header_bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(header_text) != OK:
		return []
	var parsed = json.data
	if not (parsed is Dictionary):
		return []

	var meta := parsed as Dictionary
	# 验证：必须包含 version 字段（确认是我们的格式）
	if not meta.has("version"):
		return []

	var body := data.slice(4 + hlen)
	return [meta, body]

# ──────────────────────────────────────────────
# 分模块文件写入/读取
# ──────────────────────────────────────────────

static func _write_split(payload: Dictionary, path: String, meta: Dictionary, opts: WriteOptions) -> bool:
	var base := path.get_basename()
	var index: Dictionary = {}

	for key in payload:
		var module_path := "%s_%s.json" % [base, key]
		index[key] = module_path
		var module_envelope := { "_meta": meta, key: payload[key] }
		var module_text := JSON.stringify(module_envelope)
		var module_data := module_text.to_utf8_buffer()
		var f := FileAccess.open(module_path, FileAccess.WRITE)
		if f == null:
			push_error("SaveWriter: cannot write split module file '%s'" % module_path)
			return false
		f.store_buffer(module_data)

	var main_envelope := { "_meta": meta, "_index": index }
	var main_data := JSON.stringify(main_envelope).to_utf8_buffer()
	return _flush(main_data, path, opts)

static func _read_split(main_data: Dictionary, _path: String, _opts: ReadOptions) -> Dictionary:
	var index: Dictionary = main_data.get("_index", {})
	var result: Dictionary = { "_meta": main_data.get("_meta", {}) }
	for key in index:
		var module_path: String = index[key]
		if not FileAccess.file_exists(module_path):
			push_warning("SaveWriter: split module file not found '%s'" % module_path)
			continue
		var f := FileAccess.open(module_path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		var json := JSON.new()
		if json.parse(text) != OK:
			continue
		var module_data = json.data
		if module_data is Dictionary and (module_data as Dictionary).has(key):
			result[key] = (module_data as Dictionary)[key]
	return result

## Reads plain or legacy-XOR text JSON files for backward compatibility.
static func _read_legacy_text_json(raw: PackedByteArray, path: String, opts: ReadOptions) -> Dictionary:
	if not opts.allow_legacy_json:
		push_error("SaveWriter: legacy JSON disabled for '%s'" % path)
		return {}

	var parsed := _parse_json_dictionary(raw.get_string_from_utf8())
	if parsed.is_empty():
		if not opts.encryption_key.is_empty():
			var fallback := _read_legacy_xor_text_json(raw, path, opts.encryption_key)
			if not fallback.is_empty():
				return fallback
		push_error("SaveWriter: JSON parse error in '%s'" % path)
		return {}

	var old_meta: Dictionary = parsed.get("_meta", {})
	if old_meta.get("encrypted", false) and old_meta.get("encryption_type", "") == "":
		return _read_legacy_xor_text_json(raw, path, opts.encryption_key, opts.payload_format_hint)

	parsed["_meta"] = _decorate_meta(old_meta, _resolved_payload_format(old_meta, opts.payload_format_hint), _infer_text_storage_kind(old_meta))
	return parsed


## Reads the old whole-file XOR text JSON format.
static func _read_legacy_xor_text_json(raw: PackedByteArray, path: String, encryption_key: String, payload_format_hint: String = "") -> Dictionary:
	var decrypted := Encryptor.decrypt_xor(raw, encryption_key)
	var parsed := _parse_json_dictionary(decrypted.get_string_from_utf8())
	if parsed.is_empty():
		push_error("SaveWriter: XOR decrypt failed for '%s'" % path)
		return {}
	var legacy_meta: Dictionary = parsed.get("_meta", {})
	parsed["_meta"] = _decorate_meta(legacy_meta, _resolved_payload_format(legacy_meta, payload_format_hint), STORAGE_KIND_LEGACY_TEXT_JSON)
	return parsed


## Parses JSON text and returns a Dictionary payload or an empty Dictionary.
static func _parse_json_dictionary(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}

# ──────────────────────────────────────────────
# 内部工具
# ──────────────────────────────────────────────

## 构建 _meta 字典（不含加密参数，加密后再填入）
static func _build_meta(opts: WriteOptions, payload_format: String) -> Dictionary:
	var meta: Dictionary = {
		"version":      FORMAT_VERSION,
		"saved_at":     Time.get_unix_time_from_system(),
		"game_version": opts.game_version,
		"encrypted":    opts.encryption_enabled,
		"payload_format": payload_format,
		"body_encoding_version": BODY_ENCODING_VERSION,
	}
	if opts.encryption_enabled:
		meta["encryption_type"] = opts.encryption_mode
	if opts.compression_enabled:
		meta["compression"] = opts.compression_mode
	if opts.split_modules_enabled:
		meta["split_modules"] = true
	return meta

## Builds the save envelope by attaching _meta beside module payload entries.
static func _make_envelope(payload: Dictionary, meta: Dictionary) -> Dictionary:
	var envelope: Dictionary = { "_meta": meta }
	for key in payload:
		envelope[key] = payload[key]
	return envelope

## Stores encryption parameters in metadata as base64 strings.
static func _write_encryption_meta(meta: Dictionary, encrypted: Dictionary) -> void:
	var iv: PackedByteArray  = encrypted.get("iv", PackedByteArray())
	var tag: PackedByteArray = encrypted.get("tag", PackedByteArray())
	var hmac: PackedByteArray = encrypted.get("hmac", PackedByteArray())
	if not iv.is_empty():
		meta["iv"] = Marshalls.raw_to_base64(iv)
	if not tag.is_empty():
		meta["tag"] = Marshalls.raw_to_base64(tag)
	if not hmac.is_empty():
		meta["hmac"] = Marshalls.raw_to_base64(hmac)

## 将数据写入文件（原子或直接）
static func _flush(data: PackedByteArray, path: String, opts: WriteOptions) -> bool:
	if opts.atomic_write_enabled:
		return AtomicWriter.write(path, data, opts.backup_enabled) == OK
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveWriter: cannot open '%s' for write (err=%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_buffer(data)
	return true

static func _ensure_dir(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


static func _normalize_payload_format(payload_format: String, split_modules_enabled: bool = false) -> String:
	if split_modules_enabled and payload_format == PAYLOAD_FORMAT_VARIANT_BINARY:
		push_warning("SaveWriter: split_modules_enabled 当前只支持 json_compact，已回退")
		return PAYLOAD_FORMAT_JSON_COMPACT
	match payload_format:
		PAYLOAD_FORMAT_VARIANT_BINARY:
			return PAYLOAD_FORMAT_VARIANT_BINARY
		PAYLOAD_FORMAT_JSON_COMPACT:
			return PAYLOAD_FORMAT_JSON_COMPACT
		_:
			return PAYLOAD_FORMAT_JSON_COMPACT


static func _resolved_payload_format(meta: Dictionary, payload_format_hint: String = "") -> String:
	var stored := str(meta.get("payload_format", "")).strip_edges()
	match stored:
		PAYLOAD_FORMAT_JSON_COMPACT, PAYLOAD_FORMAT_VARIANT_BINARY:
			if not payload_format_hint.is_empty() and payload_format_hint != stored:
				push_warning("SaveWriter: payload_format_hint '%s' 与文件实际格式 '%s' 不一致" % [payload_format_hint, stored])
			return stored
		_:
			return PAYLOAD_FORMAT_LEGACY_JSON


static func _encode_body(payload: Dictionary, envelope: Dictionary, payload_format: String) -> PackedByteArray:
	match payload_format:
		PAYLOAD_FORMAT_VARIANT_BINARY:
			return var_to_bytes(payload)
		_:
			return JSON.stringify(envelope).to_utf8_buffer()


static func _decode_body(body: PackedByteArray, payload_format: String, path: String) -> Dictionary:
	match payload_format:
		PAYLOAD_FORMAT_VARIANT_BINARY:
			var decoded = bytes_to_var(body)
			if decoded is Dictionary:
				return (decoded as Dictionary).duplicate(true)
			push_error("SaveWriter: variant binary body in '%s' did not decode to Dictionary" % path)
			return {}
		_:
			var text := body.get_string_from_utf8()
			var json := JSON.new()
			if json.parse(text) != OK:
				push_error("SaveWriter: JSON parse error in body of '%s': %s" % [path, json.get_error_message()])
				return {}
			if json.data is Dictionary:
				return json.data as Dictionary
			push_error("SaveWriter: JSON body in '%s' did not decode to Dictionary" % path)
			return {}


static func _merge_meta(header_meta: Dictionary, body_meta: Dictionary) -> Dictionary:
	var merged := body_meta.duplicate(true)
	for key in header_meta:
		merged[key] = header_meta[key]
	return merged


static func _decorate_meta(raw_meta: Dictionary, payload_format: String, storage_kind: String) -> Dictionary:
	var meta := raw_meta.duplicate(true)
	if not meta.has("payload_format"):
		meta["payload_format"] = payload_format
	if not meta.has("body_encoding_version") and payload_format != PAYLOAD_FORMAT_LEGACY_JSON:
		meta["body_encoding_version"] = BODY_ENCODING_VERSION
	meta["storage_kind"] = storage_kind
	meta["is_legacy"] = payload_format == PAYLOAD_FORMAT_LEGACY_JSON
	return meta


static func _infer_text_storage_kind(meta: Dictionary) -> String:
	return STORAGE_KIND_PLAIN_TEXT_JSON if meta.has("payload_format") else STORAGE_KIND_LEGACY_TEXT_JSON


static func _write_debug_dump(envelope: Dictionary, path: String) -> void:
	var debug_path := path + ".debug.json"
	_ensure_dir(debug_path)
	var file := FileAccess.open(debug_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveWriter: failed to open debug dump '%s'" % debug_path)
		return
	file.store_buffer(JSON.stringify(envelope, "\t").to_utf8_buffer())
