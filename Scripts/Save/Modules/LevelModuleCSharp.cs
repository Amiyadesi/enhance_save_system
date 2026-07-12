using Godot;
using Godot.Collections;

public partial class LevelModuleCSharp : RefCounted, ISaveModuleCSharp
{
    public static LevelModuleCSharp? Instance { get; private set; }

    private Dictionary _levels = new();
    public string CurrentLevelId { get; set; } = "";

    // Registers the latest level module instance.
    public LevelModuleCSharp()
    {
        Instance = this;
    }

    // Returns the slot level payload key.
    public string GetModuleKey() => "level";

    // Stores level state per slot.
    public bool IsGlobal() => false;

    // Captures level records for serialization.
    public Dictionary CollectData()
    {
        return new Dictionary
        {
            ["levels"] = _levels.Duplicate(true),
            ["current_level_id"] = CurrentLevelId
        };
    }

    // Applies saved level records.
    public void ApplyData(Dictionary data)
    {
        _levels = data.TryGetValue("levels", out var levels) && levels.VariantType == Variant.Type.Dictionary ? levels.AsGodotDictionary().Duplicate(true) : new Dictionary();
        CurrentLevelId = data.TryGetValue("current_level_id", out var id) ? id.AsString() : "";
    }

    // Resets level progress for a new game.
    public void OnNewGame()
    {
        _levels.Clear();
        CurrentLevelId = "";
    }

    // Marks a level unlocked.
    public void UnlockLevel(string levelId)
    {
        var entry = GetOrCreate(levelId);
        entry["unlocked"] = true;
        _levels[levelId] = entry;
    }

    // Marks a level completed and records score metadata.
    public void CompleteLevel(string levelId, int score = 0, int stars = 0)
    {
        var entry = GetOrCreate(levelId);
        entry["unlocked"] = true;
        entry["completed"] = true;
        entry["best_score"] = Mathf.Max(entry["best_score"].AsInt32(), score);
        entry["stars"] = Mathf.Max(entry["stars"].AsInt32(), stars);
        _levels[levelId] = entry;
    }

    // Reports whether a level is unlocked.
    public bool IsUnlocked(string levelId) => GetOrCreate(levelId)["unlocked"].AsBool();

    // Reports whether a level is completed.
    public bool IsCompleted(string levelId) => GetOrCreate(levelId)["completed"].AsBool();

    // Returns an existing level record or creates defaults.
    private Dictionary GetOrCreate(string levelId)
    {
        if (_levels.TryGetValue(levelId, out var value) && value.VariantType == Variant.Type.Dictionary)
            return value.AsGodotDictionary();
        return new Dictionary
        {
            ["unlocked"] = false,
            ["completed"] = false,
            ["best_score"] = 0,
            ["stars"] = 0
        };
    }
}
