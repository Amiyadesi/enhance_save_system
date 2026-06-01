using Godot;
using Godot.Collections;

public partial class PlayerModuleCSharp : RefCounted, ISaveModuleCSharp
{
    public static PlayerModuleCSharp? Instance { get; private set; }

    public int Hp { get; set; } = 100;
    public int MaxHp { get; set; } = 100;
    public int Level { get; set; } = 1;
    public int Experience { get; set; } = 0;
    public int Gold { get; set; } = 0;
    public string ScenePath { get; set; } = "";
    public Vector2 Position { get; set; } = Vector2.Zero;
    public Array Inventory { get; private set; } = new();
    public Dictionary Custom { get; private set; } = new();

    // Registers the latest player module instance.
    public PlayerModuleCSharp()
    {
        Instance = this;
    }

    // Returns the slot player payload key.
    public string GetModuleKey() => "player";

    // Stores player state per slot.
    public bool IsGlobal() => false;

    // Captures player state for serialization.
    public Dictionary CollectData()
    {
        return new Dictionary
        {
            ["hp"] = Hp,
            ["max_hp"] = MaxHp,
            ["level"] = Level,
            ["experience"] = Experience,
            ["gold"] = Gold,
            ["scene_path"] = ScenePath,
            ["position"] = new Dictionary { ["x"] = Position.X, ["y"] = Position.Y },
            ["inventory"] = Inventory.Duplicate(true),
            ["custom"] = Custom.Duplicate(true)
        };
    }

    // Applies saved player state.
    public void ApplyData(Dictionary data)
    {
        Hp = ReadInt(data, "hp", 100);
        MaxHp = ReadInt(data, "max_hp", 100);
        Level = ReadInt(data, "level", 1);
        Experience = ReadInt(data, "experience", 0);
        Gold = ReadInt(data, "gold", 0);
        ScenePath = ReadString(data, "scene_path", "");
        if (data.TryGetValue("position", out var posValue) && posValue.VariantType == Variant.Type.Dictionary)
        {
            var pos = posValue.AsGodotDictionary();
            Position = new Vector2(ReadFloat(pos, "x", 0f), ReadFloat(pos, "y", 0f));
        }
        Inventory = data.TryGetValue("inventory", out var inv) && inv.VariantType == Variant.Type.Array ? inv.AsGodotArray().Duplicate(true) : new Array();
        Custom = data.TryGetValue("custom", out var custom) && custom.VariantType == Variant.Type.Dictionary ? custom.AsGodotDictionary().Duplicate(true) : new Dictionary();
    }

    // Returns a default player payload.
    public Dictionary GetDefaultData() => new PlayerModuleCSharp().CollectData();

    // Resets player state for a new game.
    public void OnNewGame() => ApplyData(GetDefaultData());

    // Adds one item payload to the inventory array.
    public void AddItem(string itemId, int count = 1, Dictionary? itemData = null)
    {
        itemData ??= new Dictionary();
        Inventory.Add(new Dictionary { ["id"] = itemId, ["count"] = count, ["data"] = itemData.Duplicate(true) });
    }

    // Reads one optional int from a payload dictionary.
    private static int ReadInt(Dictionary data, string key, int fallback) => data.TryGetValue(key, out var value) ? value.AsInt32() : fallback;

    // Reads one optional float from a payload dictionary.
    private static float ReadFloat(Dictionary data, string key, float fallback) => data.TryGetValue(key, out var value) ? value.AsSingle() : fallback;

    // Reads one optional string from a payload dictionary.
    private static string ReadString(Dictionary data, string key, string fallback) => data.TryGetValue(key, out var value) ? value.AsString() : fallback;
}
