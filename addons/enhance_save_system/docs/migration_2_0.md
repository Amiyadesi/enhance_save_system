# Migration from 1.1.1

Enhanced Save System 2.0 no longer ships project data modules or `save_modules.cfg` inside the core addon.

1. Copy the old `Modules/` directory to `addons/enhance_save_system_modules/Modules/`.
2. Add a project-owned `Config/save_modules.cfg` with those module paths.
3. Enable the addon. It registers the core `SaveSystem` autoload automatically and loads `res://Config/save_modules.cfg` by default.
4. Keep existing module keys and priorities. Existing save payloads continue to load because their keys and data shapes do not change.

The core input-remapping scenes now retrieve the `keybindings` module through `SaveSystem.get_module("keybindings")`. No module class needs to live inside the core addon.

For the C# runtime, move `addons/enhance_save_system_csharp/Modules/` to a project directory such as `Scripts/Save/Modules/`, create `Config/save_modules_csharp.cfg`, and point a project-owned `SaveSystemCSharp` subclass at that file before `_Ready()` runs.
