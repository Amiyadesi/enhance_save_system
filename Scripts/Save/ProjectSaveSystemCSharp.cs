public partial class ProjectSaveSystemCSharp : SaveSystemCSharp
{
    // Enables this project's module list before the base lifecycle registers modules.
    public ProjectSaveSystemCSharp()
    {
        AutoRegister = true;
        ModuleConfigPath = "res://Config/save_modules_csharp.cfg";
    }
}
