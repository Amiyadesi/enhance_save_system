#if TOOLS
using Godot;

[Tool]
public partial class CSharpSavePlugin : EditorPlugin
{
    // Registers the C# runtime singleton when the plugin is enabled.
    public override void _EnablePlugin()
    {
        AddAutoloadSingleton("SaveSystemCSharp", GetScript().As<Script>().ResourcePath.GetBaseDir() + "/Core/SaveSystemCSharp.cs");
    }

    // Removes the C# runtime singleton when the plugin is disabled.
    public override void _DisablePlugin()
    {
        RemoveAutoloadSingleton("SaveSystemCSharp");
    }
}
#endif
