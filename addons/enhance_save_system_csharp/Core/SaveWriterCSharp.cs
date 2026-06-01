using Godot;
using Godot.Collections;
using System.Text;

public static class SaveWriterCSharp
{
    public const int FormatVersion = 1;

    public sealed class WriteOptions
    {
        public string GameVersion { get; set; } = "1.0.0";
        public bool AtomicWriteEnabled { get; set; } = true;
        public bool BackupEnabled { get; set; } = false;
        public bool PrettyJsonEnabled { get; set; } = false;
    }

    public sealed class ReadOptions
    {
        public bool AllowLegacyJson { get; set; } = true;
    }

    // Collects all module payloads under their stable module keys.
    public static Dictionary Collect(System.Collections.Generic.IEnumerable<ISaveModuleCSharp> modules)
    {
        var payload = new Dictionary();
        foreach (var module in modules)
        {
            var key = module.GetModuleKey();
            if (string.IsNullOrEmpty(key))
            {
                GD.PushWarning("SaveWriterCSharp.Collect: module has empty key, skipped");
                continue;
            }
            payload[key] = module.CollectData();
        }
        return payload;
    }

    // Writes an existing payload to disk with metadata.
    public static bool WriteJson(Dictionary payload, string path, WriteOptions? opts = null)
    {
        opts ??= new WriteOptions();
        EnsureDir(path);

        var envelope = new Dictionary
        {
            ["_meta"] = BuildMeta(opts)
        };
        foreach (var key in payload.Keys)
            envelope[key] = payload[key];

        var indent = opts.PrettyJsonEnabled ? "\t" : string.Empty;
        var json = Json.Stringify(envelope, indent);
        var data = Encoding.UTF8.GetBytes(json);

        if (opts.AtomicWriteEnabled)
            return AtomicWriterCSharp.Write(path, data, opts.BackupEnabled) == Error.Ok;

        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Write);
        if (file == null)
        {
            GD.PushError($"SaveWriterCSharp: cannot open '{path}' for write (err={(int)FileAccess.GetOpenError()})");
            return false;
        }
        file.StoreBuffer(data);
        return true;
    }

    // Collects module data and writes it to disk.
    public static bool Write(System.Collections.Generic.IEnumerable<ISaveModuleCSharp> modules, string path, WriteOptions? opts = null)
    {
        return WriteJson(Collect(modules), path, opts);
    }

    // Reads a payload dictionary from disk.
    public static Dictionary ReadJson(string path, ReadOptions? opts = null)
    {
        opts ??= new ReadOptions();
        if (!FileAccess.FileExists(path))
            return new Dictionary();

        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError($"SaveWriterCSharp: cannot open '{path}' for read");
            return new Dictionary();
        }

        var text = file.GetAsText();
        var parsed = Json.ParseString(text);
        if (parsed.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError($"SaveWriterCSharp: JSON parse failed or did not produce Dictionary in '{path}'");
            return new Dictionary();
        }
        return parsed.AsGodotDictionary();
    }

    // Applies a payload dictionary to matching modules.
    public static void Apply(Dictionary payload, System.Collections.Generic.IEnumerable<ISaveModuleCSharp> modules)
    {
        foreach (var module in modules)
        {
            var key = module.GetModuleKey();
            if (!payload.ContainsKey(key))
                continue;
            var value = payload[key];
            if (value.VariantType == Variant.Type.Dictionary)
                module.ApplyData(value.AsGodotDictionary());
        }
    }

    // Reads save data from disk and applies it to matching modules.
    public static bool Read(string path, System.Collections.Generic.IEnumerable<ISaveModuleCSharp> modules, ReadOptions? opts = null)
    {
        var payload = ReadJson(path, opts);
        if (payload.Count == 0)
            return false;
        Apply(payload, modules);
        return true;
    }

    // Reads only metadata from a save file.
    public static Dictionary PeekMeta(string path)
    {
        var payload = ReadJson(path);
        if (payload.TryGetValue("_meta", out var meta) && meta.VariantType == Variant.Type.Dictionary)
            return meta.AsGodotDictionary();
        return new Dictionary();
    }

    // Builds standard metadata for save files.
    private static Dictionary BuildMeta(WriteOptions opts)
    {
        return new Dictionary
        {
            ["version"] = FormatVersion,
            ["saved_at"] = Time.GetUnixTimeFromSystem(),
            ["game_version"] = opts.GameVersion,
            ["payload_format"] = "json_compact",
            ["storage_kind"] = "plain_text_json"
        };
    }

    // Ensures the target file's parent directory exists.
    private static void EnsureDir(string path)
    {
        var dir = path.GetBaseDir();
        if (!DirAccess.DirExistsAbsolute(dir))
            DirAccess.MakeDirRecursiveAbsolute(dir);
    }
}
