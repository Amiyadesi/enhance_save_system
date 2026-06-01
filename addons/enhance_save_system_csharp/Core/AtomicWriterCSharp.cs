using Godot;

public static class AtomicWriterCSharp
{
    // Writes bytes through a temporary file, then renames into place.
    public static Error Write(string path, byte[] data, bool backupEnabled = false)
    {
        EnsureDir(path);
        var tmpPath = GetTmpPath(path);
        var backupPath = GetBackupPath(path);

        using (var file = FileAccess.Open(tmpPath, FileAccess.ModeFlags.Write))
        {
            if (file == null)
            {
                GD.PushError($"AtomicWriterCSharp: cannot open tmp file '{tmpPath}' (err={(int)FileAccess.GetOpenError()})");
                return Error.Failed;
            }
            file.StoreBuffer(data);
        }

        if (!FileAccess.FileExists(tmpPath))
        {
            GD.PushError($"AtomicWriterCSharp: tmp file not found after write '{tmpPath}'");
            return Error.Failed;
        }

        if (backupEnabled && FileAccess.FileExists(path))
        {
            if (FileAccess.FileExists(backupPath))
                DirAccess.RemoveAbsolute(backupPath);
            var backupErr = DirAccess.RenameAbsolute(path, backupPath);
            if (backupErr != Error.Ok)
                GD.PushWarning($"AtomicWriterCSharp: failed to rename '{path}' to '{backupPath}' (err={(int)backupErr})");
        }

        var finalErr = DirAccess.RenameAbsolute(tmpPath, path);
        if (finalErr != Error.Ok)
        {
            GD.PushError($"AtomicWriterCSharp: failed to rename tmp to target '{path}' (err={(int)finalErr})");
            if (FileAccess.FileExists(tmpPath))
                DirAccess.RemoveAbsolute(tmpPath);
            return Error.Failed;
        }

        return Error.Ok;
    }

    // Returns the backup path used for a target save file.
    public static string GetBackupPath(string path)
    {
        return path + ".bak";
    }

    // Returns the temporary path used for a target save file.
    public static string GetTmpPath(string path)
    {
        return path + ".tmp";
    }

    // Ensures the target file's parent directory exists.
    private static void EnsureDir(string path)
    {
        var dir = path.GetBaseDir();
        if (!DirAccess.DirExistsAbsolute(dir))
            DirAccess.MakeDirRecursiveAbsolute(dir);
    }
}
