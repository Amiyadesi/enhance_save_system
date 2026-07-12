using Godot;
using Godot.Collections;

public partial class SettingsModuleCSharp : RefCounted, ISaveModuleCSharp
{
    public static SettingsModuleCSharp? Instance { get; private set; }

    private readonly Dictionary _values = new()
    {
        ["master_volume"] = 0.8f,
        ["music_volume"] = 0.8f,
        ["sfx_volume"] = 0.8f,
        ["language"] = "zh_CN",
        ["display_mode"] = "windowed",
        ["vsync_enabled"] = true
    };

    // Registers the latest settings module instance.
    public SettingsModuleCSharp()
    {
        Instance = this;
    }

    // Returns the global settings payload key.
    public string GetModuleKey() => "settings";

    // Stores settings globally across slots.
    public bool IsGlobal() => true;

    // Captures settings for serialization.
    public Dictionary CollectData() => _values.Duplicate(true);

    // Applies persisted settings over defaults.
    public void ApplyData(Dictionary data)
    {
        foreach (var key in data.Keys)
            _values[key] = data[key];
    }

    // Returns the active value for one setting key.
    public Variant GetValue(string key, Variant fallback = default)
    {
        return _values.TryGetValue(key, out var value) ? value : fallback;
    }

    // Writes one setting value.
    public void SetValue(string key, Variant value)
    {
        _values[key] = value;
    }
}
