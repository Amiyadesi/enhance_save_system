using Godot;
using Godot.Collections;

public partial class SaveSystemCSharp : Node
{
    [Signal] public delegate void GlobalSavedEventHandler(bool ok);
    [Signal] public delegate void GlobalLoadedEventHandler(bool ok);
    [Signal] public delegate void SlotSavedEventHandler(int slot, bool ok);
    [Signal] public delegate void SlotLoadedEventHandler(int slot, bool ok);
    [Signal] public delegate void SlotDeletedEventHandler(int slot);
    [Signal] public delegate void SlotChangedEventHandler(int newSlot);

    [Export] public int MaxSlots { get; set; } = 3;
    [Export] public bool AutoRegister { get; set; } = true;
    [Export] public bool AutoLoadGlobal { get; set; } = true;
    [Export] public int AutoLoadSlot { get; set; } = 0;
    [Export] public string GameVersion { get; set; } = "1.0.0";
    [Export] public bool UseModuleConfig { get; set; } = true;
    [Export] public string ModuleConfigPath { get; set; } = "res://addons/enhance_save_system_csharp/save_modules.cfg";
    [Export] public bool AtomicWriteEnabled { get; set; } = true;
    [Export] public bool BackupEnabled { get; set; } = false;
    [Export] public bool PrettyJsonEnabled { get; set; } = false;

    private const string SaveDir = "user://saves";
    private const string GlobalPath = "user://saves/global_csharp.json";
    private const string SlotPattern = "user://saves/slot_csharp_{0:00}.json";

    private readonly System.Collections.Generic.Dictionary<string, RegisteredSaveModuleCSharp> _globalModules = new();
    private readonly System.Collections.Generic.Dictionary<string, RegisteredSaveModuleCSharp> _slotModules = new();
    private int _currentSlot = 1;

    public int CurrentSlot
    {
        get => _currentSlot;
        set
        {
            _currentSlot = Mathf.Clamp(value, 1, MaxSlots);
            EmitSignal(SignalName.SlotChanged, _currentSlot);
        }
    }

    // Initializes directories, module registration, and optional first load.
    public override void _Ready()
    {
        EnsureSaveDir();
        if (AutoRegister)
            AutoRegisterModules();
        if (AutoLoadGlobal)
            LoadGlobal();
        if (AutoLoadSlot > 0)
            LoadSlot(AutoLoadSlot);
    }

    // Registers a module under its global or slot registry.
    public void RegisterModule(ISaveModuleCSharp module, int priority = 100)
    {
        var key = module.GetModuleKey();
        if (string.IsNullOrEmpty(key))
        {
            GD.PushError("SaveSystemCSharp.RegisterModule: module key is empty");
            return;
        }

        var entry = new RegisteredSaveModuleCSharp(module, priority);
        if (module.IsGlobal())
            _globalModules[key] = entry;
        else
            _slotModules[key] = entry;
    }

    // Removes a module key from both registries.
    public void UnregisterModule(string key)
    {
        _globalModules.Remove(key);
        _slotModules.Remove(key);
    }

    // Returns a registered module by key.
    public ISaveModuleCSharp? GetModule(string key)
    {
        if (_globalModules.TryGetValue(key, out var globalEntry))
            return globalEntry.Module;
        return _slotModules.TryGetValue(key, out var slotEntry) ? slotEntry.Module : null;
    }

    // Writes all global modules to the global save file.
    public bool SaveGlobal()
    {
        var ok = SaveWriterCSharp.Write(SortedModules(_globalModules), GlobalPath, MakeWriteOptions());
        EmitSignal(SignalName.GlobalSaved, ok);
        return ok;
    }

    // Reads the global save file into all global modules.
    public bool LoadGlobal()
    {
        var ok = SaveWriterCSharp.Read(GlobalPath, SortedModules(_globalModules));
        EmitSignal(SignalName.GlobalLoaded, ok);
        return ok;
    }

    // Writes all slot modules to the chosen save slot.
    public bool SaveSlot(int slot = -1)
    {
        var resolved = ResolveSlot(slot);
        if (!ValidSlot(resolved))
            return false;
        var ok = SaveWriterCSharp.Write(SortedModules(_slotModules), SlotPath(resolved), MakeWriteOptions());
        EmitSignal(SignalName.SlotSaved, resolved, ok);
        return ok;
    }

    // Reads the chosen save slot into all slot modules.
    public bool LoadSlot(int slot = -1)
    {
        var resolved = ResolveSlot(slot);
        if (!ValidSlot(resolved))
            return false;
        var ok = SaveWriterCSharp.Read(SlotPath(resolved), SortedModules(_slotModules));
        if (ok)
            CurrentSlot = resolved;
        EmitSignal(SignalName.SlotLoaded, resolved, ok);
        return ok;
    }

    // Deletes a save slot from disk.
    public bool DeleteSlot(int slot)
    {
        if (!ValidSlot(slot))
            return false;
        var path = SlotPath(slot);
        if (!FileAccess.FileExists(path))
            return true;
        var err = DirAccess.RemoveAbsolute(path);
        if (err != Error.Ok)
            GD.PushError($"SaveSystemCSharp.DeleteSlot: failed to delete '{path}' (err={(int)err})");
        else
            EmitSignal(SignalName.SlotDeleted, slot);
        return err == Error.Ok;
    }

    // Reports whether a save slot exists.
    public bool SlotExists(int slot)
    {
        return ValidSlot(slot) && FileAccess.FileExists(SlotPath(slot));
    }

    // Saves global state plus the active slot.
    public bool QuickSave()
    {
        return SaveGlobal() & SaveSlot(CurrentSlot);
    }

    // Loads global state plus the active slot, accepting partial recovery.
    public bool QuickLoad()
    {
        return LoadGlobal() | LoadSlot(CurrentSlot);
    }

    // Resets slot modules for a new game.
    public void NewGame(int slot = -1)
    {
        var resolved = ResolveSlot(slot);
        CurrentSlot = resolved;
        foreach (var entry in _slotModules.Values)
            entry.Module.OnNewGame();
    }

    // Copies a save slot to an external path.
    public bool ExportSlot(int slot, string outPath)
    {
        var src = SlotPath(ResolveSlot(slot));
        if (!FileAccess.FileExists(src))
        {
            GD.PushWarning($"SaveSystemCSharp.ExportSlot: slot {slot} not found");
            return false;
        }
        EnsureDir(outPath);
        return DirAccess.CopyAbsolute(src, outPath) == Error.Ok;
    }

    // Validates and imports an external save into a slot.
    public bool ImportSlot(int slot, string inPath)
    {
        if (!ValidSlot(slot))
            return false;
        if (!FileAccess.FileExists(inPath))
        {
            GD.PushWarning($"SaveSystemCSharp.ImportSlot: file not found '{inPath}'");
            return false;
        }
        if (SaveWriterCSharp.ReadJson(inPath).Count == 0)
        {
            GD.PushError($"SaveSystemCSharp.ImportSlot: invalid or unreadable save file '{inPath}'");
            return false;
        }
        EnsureDir(SlotPath(slot));
        return DirAccess.CopyAbsolute(inPath, SlotPath(slot)) == Error.Ok;
    }

    // Loads modules from cfg, otherwise falls back to scanning the local Modules directory.
    private void AutoRegisterModules()
    {
        if (UseModuleConfig)
        {
            var modules = LoadConfigModules();
            if (modules.Count > 0)
            {
                foreach (var entry in modules)
                    RegisterModule(entry.Module, entry.Priority);
                return;
            }
        }
        RegisterModulesFromDirectory();
    }

    // Loads configured modules when the cfg exists and has valid entries.
    private System.Collections.Generic.List<RegisteredSaveModuleCSharp> LoadConfigModules()
    {
        if (!FileAccess.FileExists(ModuleConfigPath))
        {
            GD.PushWarning($"SaveSystemCSharp: module config not found '{ModuleConfigPath}'; falling back to Modules/");
            return new System.Collections.Generic.List<RegisteredSaveModuleCSharp>();
        }
        var registry = new ModuleRegistryCSharp();
        var modules = registry.LoadFromConfig(ModuleConfigPath);
        if (modules.Count == 0)
            GD.PushWarning($"SaveSystemCSharp: module config loaded no modules '{ModuleConfigPath}'; falling back to Modules/");
        return modules;
    }

    // Scans addon-local C# module scripts.
    private void RegisterModulesFromDirectory()
    {
        var modulesDir = ResolveModulesDir();
        var dir = DirAccess.Open(modulesDir);
        if (dir == null)
        {
            GD.PushError($"SaveSystemCSharp: cannot open module directory '{modulesDir}'");
            return;
        }

        var registry = new ModuleRegistryCSharp();
        dir.ListDirBegin();
        var fileName = dir.GetNext();
        while (!string.IsNullOrEmpty(fileName))
        {
            if (!dir.CurrentIsDir() && fileName.EndsWith(".cs"))
            {
                var loaded = registry.LoadModule(modulesDir.PathJoin(fileName));
                if (loaded != null)
                    RegisterModule(loaded.Module, loaded.Priority);
            }
            fileName = dir.GetNext();
        }
        dir.ListDirEnd();
    }

    // Resolves the module scan directory next to this addon.
    private string ResolveModulesDir()
    {
        var script = GetScript().As<Script>();
        var addonDir = script.ResourcePath.GetBaseDir().GetBaseDir();
        return addonDir.PathJoin("Modules");
    }

    // Creates write options from exported settings.
    private SaveWriterCSharp.WriteOptions MakeWriteOptions()
    {
        return new SaveWriterCSharp.WriteOptions
        {
            GameVersion = GameVersion,
            AtomicWriteEnabled = AtomicWriteEnabled,
            BackupEnabled = BackupEnabled,
            PrettyJsonEnabled = PrettyJsonEnabled
        };
    }

    // Sorts registry entries by priority and returns just modules.
    private static System.Collections.Generic.List<ISaveModuleCSharp> SortedModules(System.Collections.Generic.Dictionary<string, RegisteredSaveModuleCSharp> registry)
    {
        var entries = new System.Collections.Generic.List<RegisteredSaveModuleCSharp>();
        foreach (var entry in registry.Values)
            entries.Add(entry);
        entries.Sort((a, b) => a.Priority.CompareTo(b.Priority));
        var modules = new System.Collections.Generic.List<ISaveModuleCSharp>();
        foreach (var entry in entries)
            modules.Add(entry.Module);
        return modules;
    }

    // Ensures the root user save directory exists.
    private static void EnsureSaveDir()
    {
        if (!DirAccess.DirExistsAbsolute(SaveDir))
            DirAccess.MakeDirRecursiveAbsolute(SaveDir);
    }

    // Ensures a target path's parent directory exists.
    private static void EnsureDir(string path)
    {
        var dir = path.GetBaseDir();
        if (!DirAccess.DirExistsAbsolute(dir))
            DirAccess.MakeDirRecursiveAbsolute(dir);
    }

    // Validates slot range.
    private bool ValidSlot(int slot)
    {
        if (slot >= 1 && slot <= MaxSlots)
            return true;
        GD.PushWarning($"SaveSystemCSharp: slot {slot} out of range (1-{MaxSlots})");
        return false;
    }

    // Resolves -1 to active slot.
    private int ResolveSlot(int slot)
    {
        return slot < 0 ? CurrentSlot : slot;
    }

    // Formats slot file path.
    private static string SlotPath(int slot)
    {
        return string.Format(SlotPattern, slot);
    }
}
