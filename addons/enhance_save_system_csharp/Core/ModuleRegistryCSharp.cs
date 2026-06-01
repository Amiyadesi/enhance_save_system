using Godot;
using Godot.Collections;

public sealed class ModuleRegistryCSharp
{
    // Loads modules from a cfg file in priority order.
    public System.Collections.Generic.List<RegisteredSaveModuleCSharp> LoadFromConfig(string configPath)
    {
        var cfg = new ConfigFile();
        var err = cfg.Load(configPath);
        if (err != Error.Ok)
        {
            GD.PushWarning($"ModuleRegistryCSharp: cannot load config '{configPath}' (err={(int)err})");
            return new System.Collections.Generic.List<RegisteredSaveModuleCSharp>();
        }

        var entries = new System.Collections.Generic.List<Dictionary>();
        foreach (var section in cfg.GetSections())
        {
            var entry = ParseEntry(cfg, section);
            if (entry.Count > 0)
                entries.Add(entry);
        }

        entries.Sort((a, b) => a["priority"].AsInt32().CompareTo(b["priority"].AsInt32()));
        return InstantiateEnabledModules(entries);
    }

    // Instantiates a module script when it implements ISaveModuleCSharp.
    public RegisteredSaveModuleCSharp? LoadModule(string path, int priority = 100)
    {
        if (!ResourceLoader.Exists(path))
        {
            GD.PushWarning($"ModuleRegistryCSharp: script not found '{path}'");
            return null;
        }

        var script = ResourceLoader.Load<CSharpScript>(path);
        if (script == null)
        {
            GD.PushWarning($"ModuleRegistryCSharp: failed to load C# script '{path}'");
            return null;
        }

        var instance = script.New().AsGodotObject();
        if (instance is not ISaveModuleCSharp module)
        {
            GD.PushWarning($"ModuleRegistryCSharp: '{path}' is not an ISaveModuleCSharp implementation");
            instance?.Free();
            return null;
        }

        return new RegisteredSaveModuleCSharp(module, priority);
    }

    // Parses one cfg section into a normalized entry dictionary.
    private static Dictionary ParseEntry(ConfigFile cfg, string section)
    {
        if (!cfg.HasSectionKey(section, "path"))
        {
            GD.PushWarning($"ModuleRegistryCSharp: section '[{section}]' missing 'path' key, skipped");
            return new Dictionary();
        }

        return new Dictionary
        {
            ["section"] = section,
            ["path"] = cfg.GetValue(section, "path", "").AsString(),
            ["enabled"] = IsTruthy(cfg.GetValue(section, "enabled", true)),
            ["priority"] = cfg.GetValue(section, "priority", 100).AsInt32()
        };
    }

    // Instantiates all enabled entries from a sorted config list.
    private System.Collections.Generic.List<RegisteredSaveModuleCSharp> InstantiateEnabledModules(System.Collections.Generic.List<Dictionary> entries)
    {
        var modules = new System.Collections.Generic.List<RegisteredSaveModuleCSharp>();
        foreach (var entry in entries)
        {
            if (!entry["enabled"].AsBool())
                continue;
            var path = entry["path"].AsString();
            var priority = entry["priority"].AsInt32();
            var module = LoadModule(path, priority);
            if (module != null)
                modules.Add(module);
        }
        return modules;
    }

    // Coerces config scalar values into booleans.
    private static bool IsTruthy(Variant value)
    {
        return value.VariantType switch
        {
            Variant.Type.Bool => value.AsBool(),
            Variant.Type.Int => value.AsInt64() != 0,
            Variant.Type.Float => !Mathf.IsZeroApprox(value.AsDouble()),
            Variant.Type.String => value.AsString().StripEdges().ToLowerInvariant() is "true" or "1" or "yes" or "on",
            _ => false
        };
    }
}

public sealed class RegisteredSaveModuleCSharp
{
    public ISaveModuleCSharp Module { get; }
    public int Priority { get; }

    // Stores a module with its execution priority.
    public RegisteredSaveModuleCSharp(ISaveModuleCSharp module, int priority)
    {
        Module = module;
        Priority = priority;
    }
}
