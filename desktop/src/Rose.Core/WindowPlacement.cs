using System.Text.Json;

namespace Rose.Core;

/// Working-area coordinates are physical pixels; client sizes are logical (DPI-independent) units.
public readonly record struct DisplayArea(int X, int Y, int Width, int Height, double Scaling, bool Primary = false)
{
    public bool IsUsable => Width > 0 && Height > 0 && double.IsFinite(Scaling) && Scaling > 0;
}

public sealed record WindowPlacement(double Width, double Height, int X, int Y, bool Maximized = false, DisplayArea? Display = null)
{
    public bool IsUsable => double.IsFinite(Width) && double.IsFinite(Height) && Width > 0 && Height > 0;
}

public static class WindowPlacementGeometry
{
    // Leave room for the native frame/title bar as well as the client area.
    public const double FrameWidth = 16;
    public const double FrameHeight = 48;
    public static WindowPlacement Resolve(WindowPlacement? saved, IReadOnlyList<DisplayArea> available)
    {
        var displays = available.Where(x => x.IsUsable).ToArray();
        if (displays.Length == 0) displays = [new(0, 0, 1920, 1080, 1, true)];
        if (saved is { IsUsable: false }) saved = null;
        var primary = displays.FirstOrDefault(x => x.Primary, displays[0]);
        var screen = primary; var found = false;
        if (saved is not null)
        {
            if (saved.Display is { IsUsable: true } oldDisplay)
            {
                var same = Array.FindIndex(displays, x => x.X == oldDisplay.X && x.Y == oldDisplay.Y && x.Width == oldDisplay.Width && x.Height == oldDisplay.Height);
                if (same >= 0) { screen = displays[same]; found = true; }
            }
            if (!found)
            {
                var scaling = saved.Display is { IsUsable: true } old ? old.Scaling : 1;
                var best = displays.Select(x => (Display: x, Area: Intersection(x, saved.X, saved.Y, saved.Width * scaling, saved.Height * scaling))).MaxBy(x => x.Area);
                if (best.Area > 0) { screen = best.Display; found = true; }
            }
        }
        var maximumWidth = Math.Max(1, screen.Width / screen.Scaling - FrameWidth);
        var maximumHeight = Math.Max(1, screen.Height / screen.Scaling - FrameHeight);
        var width = Math.Clamp(saved?.Width ?? maximumWidth * .9, Math.Min(860, maximumWidth), maximumWidth);
        var height = Math.Clamp(saved?.Height ?? maximumHeight * .9, Math.Min(540, maximumHeight), maximumHeight);
        var outerWidth = (width + FrameWidth) * screen.Scaling;
        var outerHeight = (height + FrameHeight) * screen.Scaling;
        var x = found ? saved!.X : screen.X + (screen.Width - outerWidth) / 2;
        var y = found ? saved!.Y : screen.Y + (screen.Height - outerHeight) / 2;
        x = Math.Clamp(x, screen.X, Math.Max(screen.X, screen.X + (double)screen.Width - outerWidth));
        y = Math.Clamp(y, screen.Y, Math.Max(screen.Y, screen.Y + (double)screen.Height - outerHeight));
        return new(width, height, Coordinate(x), Coordinate(y), saved?.Maximized ?? false, screen);
    }
    private static int Coordinate(double value) => (int)Math.Clamp(Math.Floor(value), int.MinValue, int.MaxValue);
    private static double Intersection(DisplayArea screen, double x, double y, double width, double height) =>
        Math.Max(0, Math.Min(screen.X + (double)screen.Width, x + width) - Math.Max(screen.X, x)) *
        Math.Max(0, Math.Min(screen.Y + (double)screen.Height, y + height) - Math.Max(screen.Y, y));
}

/// Small startup settings are separate from the image index, so placement is ready before Show().
public sealed class WindowPlacementStore(string directory)
{
    public string FilePath { get; } = Path.Combine(directory, "window.json");
    private readonly SemaphoreSlim _gate = new(1);
    public WindowPlacement? Load()
    {
        try
        {
            if (new FileInfo(FilePath).Length > 64 * 1024) return null;
            var placement = JsonSerializer.Deserialize<WindowPlacement>(File.ReadAllText(FilePath));
            return placement is { IsUsable: true } ? placement : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return null; }
    }
    public async Task SaveAsync(WindowPlacement placement)
    {
        await _gate.WaitAsync();
        try { await Task.Run(() => AtomicFile.Write(FilePath, JsonSerializer.Serialize(placement))); }
        finally { _gate.Release(); }
    }
}
