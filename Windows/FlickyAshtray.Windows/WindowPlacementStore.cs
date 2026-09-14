using System.Text.Json;

namespace FlickyAshtray.Windows;

internal sealed record WindowPlacement(double Left, double Top);

internal static class WindowPlacementStore
{
    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Flicky Ashtray",
        "window.json"
    );

    public static WindowPlacement? Load()
    {
        try
        {
            return File.Exists(FilePath)
                ? JsonSerializer.Deserialize<WindowPlacement>(File.ReadAllText(FilePath))
                : null;
        }
        catch
        {
            return null;
        }
    }

    public static void Save(double left, double top)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            var temporary = FilePath + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(new WindowPlacement(left, top)));
            File.Move(temporary, FilePath, true);
        }
        catch
        {
            // Window placement is a convenience only; count persistence must never depend on it.
        }
    }
}
