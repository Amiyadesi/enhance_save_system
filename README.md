# Enhanced Save System

Godot 4 modular save-system addon. This repository ships two variants:

- `addons/enhance_save_system`: GDScript core with editor panel, input-remapping UI, encryption, compression, migration, atomic writes, and import/export.
- `addons/enhance_save_system_modules`: project data modules kept outside the core addon.
- `addons/enhance_save_system_csharp`: C# core runtime with project-owned module registration, JSON saves, and import/export.

The GDScript version is the feature-complete version. The C# version is a clean runtime base for Mono projects that want C# modules.

## Install

### GDScript

1. Copy both GDScript addon folders into your Godot project.
2. Enable **Enhanced Save System** in `Project > Project Settings > Plugins`.
3. The plugin registers `SaveSystem` automatically, pointing at `addons/enhance_save_system/core/save_system.gd`.

### C#

1. Copy `addons/enhance_save_system_csharp` into a Godot Mono project.
2. Make sure the project has a `.csproj` using `Godot.NET.Sdk` for your Godot version.
3. Enable **Enhanced Save System C#** in `Project > Project Settings > Plugins`.
4. Add a project-owned `SaveSystemCSharp` subclass as the `SaveSystemCSharp` autoload.

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

- GDScript default path: `res://Config/save_modules.cfg`
- C# default path: `res://Config/save_modules_csharp.cfg`

The GDScript core does not scan addon-local modules. Projects own their module configuration and fail loudly when an enabled SaveSystem cannot load it. No project wrapper script is required.

For exported games, include the cfg files in the export preset when you rely on explicit module ordering:

- `Config/save_modules.cfg`
- `Config/save_modules_csharp.cfg`

Example:

```ini
[player_module]
path = "res://addons/enhance_save_system_modules/Modules/player_module.gd"
enabled = true
priority = 20
```

## Project Modules

The companion module package includes:

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

Dialogue modules store resource paths, dialogue title, chapter/character labels, snippets, and variables without depending on Dialogue Manager classes. Register them in the project cfg when needed.

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

Add it to the relevant project-owned cfg. The core addons never scan or overwrite project module directories.

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

## Version 2.0

See `addons/enhance_save_system/docs/migration_2_0.md` when updating from 1.1.1. Core updates no longer overwrite project data modules or module registration.

## Compatibility

- Godot 4.6 tested in this repo.
- GDScript addon is pure GDScript.
- C# addon targets `Godot.NET.Sdk/4.7.0` in this standalone project; change the SDK version in the `.csproj` if your project uses another Godot 4.x Mono version.

## License

MIT License
