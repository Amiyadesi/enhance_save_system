using Godot;
using Godot.Collections;

public partial class DialogueGlobalModuleCSharp : DialogueSlotModuleCSharp
{
    public static DialogueGlobalModuleCSharp? GlobalInstance { get; private set; }

    // Registers the latest dialogue global module instance.
    public DialogueGlobalModuleCSharp()
    {
        GlobalInstance = this;
    }

    // Returns the global dialogue payload key.
    public override string GetModuleKey() => "dialogue_global";

    // Stores dialogue memory globally across slots.
    public override bool IsGlobal() => true;
}
