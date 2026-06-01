using Godot;
using Godot.Collections;

public interface ISaveModuleCSharp
{
    // Returns the stable key used inside save payload dictionaries.
    string GetModuleKey();

    // Returns true for global.json modules and false for slot_XX.json modules.
    bool IsGlobal();

    // Captures current module state into Godot-serializable data.
    Dictionary CollectData();

    // Applies previously saved module data.
    void ApplyData(Dictionary data);

    // Provides first-run defaults for new games or empty saves.
    Dictionary GetDefaultData()
    {
        return new Dictionary();
    }

    // Resets module state for a new run.
    void OnNewGame()
    {
        ApplyData(GetDefaultData());
    }
}
