using Godot;
using Godot.Collections;

public partial class DialogueSlotModuleCSharp : RefCounted, ISaveModuleCSharp
{
    public static DialogueSlotModuleCSharp? Instance { get; private set; }

    public string DialogueResourcePath { get; set; } = "";
    public string DialogueTitle { get; set; } = "";
    public string ChapterName { get; set; } = "";
    public string CharacterName { get; set; } = "";
    public string DialogueSnippet { get; set; } = "";
    public Dictionary DialogueVariables { get; private set; } = new();

    // Registers the latest dialogue slot module instance.
    public DialogueSlotModuleCSharp()
    {
        Instance = this;
    }

    // Returns the slot dialogue payload key.
    public virtual string GetModuleKey() => "dialogue";

    // Stores dialogue progress per slot.
    public virtual bool IsGlobal() => false;

    // Captures dialogue state for serialization.
    public Dictionary CollectData() => BuildPayload();

    // Applies saved dialogue state.
    public void ApplyData(Dictionary data)
    {
        DialogueResourcePath = ReadString(data, "dialogue_resource_path");
        DialogueTitle = ReadString(data, "dialogue_title");
        ChapterName = ReadString(data, "chapter_name");
        CharacterName = ReadString(data, "character_name");
        DialogueSnippet = ReadString(data, "dialogue_snippet");
        DialogueVariables = data.TryGetValue("dialogue_variables", out var vars) && vars.VariantType == Variant.Type.Dictionary ? vars.AsGodotDictionary().Duplicate(true) : new Dictionary();
    }

    // Saves a dialogue progress snapshot from a path or Resource.
    public void SaveProgress(Variant resourceOrPath, string title, string chapter = "", string character = "", string snippet = "")
    {
        DialogueResourcePath = ResourcePathFrom(resourceOrPath);
        DialogueTitle = title;
        ChapterName = chapter;
        CharacterName = character;
        DialogueSnippet = PlainText(snippet).Left(60);
    }

    // Reports whether dialogue progress exists.
    public bool HasProgress() => !string.IsNullOrEmpty(DialogueResourcePath) && !string.IsNullOrEmpty(DialogueTitle);

    // Loads the recorded resource when it exists.
    public Resource? LoadDialogueResource() => ResourceLoader.Exists(DialogueResourcePath) ? ResourceLoader.Load<Resource>(DialogueResourcePath) : null;

    private Dictionary BuildPayload()
    {
        return new Dictionary
        {
            ["dialogue_resource_path"] = DialogueResourcePath,
            ["dialogue_title"] = DialogueTitle,
            ["chapter_name"] = ChapterName,
            ["character_name"] = CharacterName,
            ["dialogue_snippet"] = DialogueSnippet,
            ["dialogue_variables"] = DialogueVariables.Duplicate(true)
        };
    }

    // Reads one optional string from a payload dictionary.
    private static string ReadString(Dictionary data, string key) => data.TryGetValue(key, out var value) ? value.AsString() : "";

    // Extracts a resource path from either a string or Resource variant.
    private static string ResourcePathFrom(Variant value) => value.VariantType == Variant.Type.String ? value.AsString() : value.AsGodotObject() is Resource res ? res.ResourcePath : "";

    // Removes common bbcode tags without depending on DialogueLabel helpers.
    private static string PlainText(string text)
    {
        var result = "";
        var insideTag = false;
        foreach (var ch in text)
        {
            if (ch == '[') { insideTag = true; continue; }
            if (ch == ']') { insideTag = false; continue; }
            if (!insideTag) result += ch;
        }
        return result.StripEdges();
    }
}
