# Enhanced Save System

Godot 4 modular save-system addon. This repository ships two variants:

- `addons/enhance_save_system`: full GDScript version with editor panel, input-remapping UI, encryption, compression, migration, atomic writes, import/export, and demos.
- `addons/enhance_save_system_csharp`: C# runtime version with module registration, JSON saves, cfg fallback, import/export, and bundled example modules.

The GDScript version is the feature-complete version. The C# version is a clean runtime base for Mono projects that want C# modules.

## Install

### GDScript

1. Copy `addons/enhance_save_system` into your Godot project.
2. Enable **Enhanced Save System** in `Project > Project Settings > Plugins`.
3. The plugin registers the `SaveSystem` autoload.

### C#

1. Copy `addons/enhance_save_system_csharp` into a Godot Mono project.
2. Make sure the project has a `.csproj` using `Godot.NET.Sdk` for your Godot version.
3. Enable **Enhanced Save System C#** in `Project > Project Settings > Plugins`.
4. The plugin registers the `SaveSystemCSharp` autoload.

## Quick Start

```gdscript
SaveSystem.save_slot(1)
SaveSystem.load_slot(1)
SaveSystem.quick_save()
SaveSystem.quick_load()

SaveSystem.delete_slot(1)
SaveSystem.slot_exists(1)
var slots: Array[SlotInfo] = SaveSystem.list_slots()
```

```csharp
var saveSystem = GetNode<SaveSystemCSharp>("/root/SaveSystemCSharp");
saveSystem.SaveSlot(1);
saveSystem.LoadSlot(1);
saveSystem.QuickSave();
saveSystem.QuickLoad();
```

## Module Registration

Both variants support `save_modules.cfg`.

- GDScript default path: `res://addons/enhance_save_system/save_modules.cfg`
- C# default path: `res://addons/enhance_save_system_csharp/save_modules.cfg`

If the cfg is missing or contains no loadable modules, the save system now falls back to scanning its own `Modules/` directory. This makes exported builds safer when a cfg is accidentally omitted, while still allowing explicit ordering when the cfg is present.

For exported games, include the cfg files in the export preset when you rely on explicit module ordering:

- `addons/enhance_save_system/save_modules.cfg`
- `addons/enhance_save_system_csharp/save_modules.cfg`

If you omit them, the fallback scanner still loads addon-local modules from `Modules/`.

Example:

```ini
[player_module]
path = "res://addons/enhance_save_system/Modules/player_module.gd"
enabled = true
priority = 20
```

## Bundled Modules

GDScript default modules include:

- `settings`
- `keybindings`
- `stats`
- `session_progress`
- `app_state`
- `narrative_global`
- `narrative_slot`
- `dialogue_global`
- `dialogue`
- `player`
- `level`

Dialogue modules are bundled inside this addon as optional generic modules. They store resource paths, dialogue title, chapter/character labels, snippets, and variables without depending on Dialogue Manager classes. Projects that use Dialogue Manager can feed these modules with their current dialogue progress; projects that do not use Dialogue Manager can leave them registered harmlessly or disable them in cfg.

## Custom GDScript Module

```gdscript
class_name MyModule
extends ISaveModule

func get_module_key() -> String:
	return "my_module"

func is_global() -> bool:
	return false

func collect_data() -> Dictionary:
	return {"score": 100}

func apply_data(data: Dictionary) -> void:
	var score := int(data.get("score", 0))
```

## Custom C# Module

```csharp
using Godot;
using Godot.Collections;

public partial class MyModuleCSharp : RefCounted, ISaveModuleCSharp
{
    public string GetModuleKey() => "my_module";
    public bool IsGlobal() => false;

    public Dictionary CollectData()
    {
        return new Dictionary { ["score"] = 100 };
    }

    public void ApplyData(Dictionary data)
    {
        var score = data.TryGetValue("score", out var value) ? value.AsInt32() : 0;
    }
}
```

Add it to the relevant cfg or place it in `addons/enhance_save_system_csharp/Modules/` for fallback scanning.

## GDScript Features

| Feature | Notes |
| --- | --- |
| JSON saves | Human-readable when encryption/compression is disabled |
| AES-GCM / AES-CBC / XOR | AES-GCM recommended; XOR retained for legacy compatibility |
| gzip / deflate compression | Useful for large payloads |
| Atomic writes + `.bak` | Protects against interrupted writes |
| Version migration | Per-save and per-module migration hooks |
| Split modules | Optional separate files per module |
| Editor panel | View, delete, import, and export slots in the editor |
| Input remapping UI | Authored scenes under `Components/InputRemapping` |

## File Format

Plain mode writes JSON with `_meta`.

Encrypted or compressed mode writes:

```text
[4 bytes LE: header_len][header JSON][body]
```

The header keeps metadata readable for editor inspection. Old text JSON saves remain readable.

## Demos

GDScript demo scenes live in `addons/enhance_save_system/demo/`:

- `full_feature_demo.tscn`
- `atomic_write_demo.tscn`
- `migration_demo.tscn`
- `import_export_demo.tscn`
- `SaveDemo.tscn`

## Compatibility

- Godot 4.6 tested in this repo.
- GDScript addon is pure GDScript.
- C# addon targets `Godot.NET.Sdk/4.6.2` in this standalone project; change the SDK version in the `.csproj` if your project uses another Godot 4.x Mono version.

## License

MIT License
