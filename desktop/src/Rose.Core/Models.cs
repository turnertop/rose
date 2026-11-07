namespace Rose.Core;

public sealed record Annotation(string[] Tags, string Note, bool IsFavorite)
{
    public static Annotation Empty => new([], "", false);
}

public sealed record ImageAsset(string Path, string RootPath, string RelativePath,
    long ByteSize, DateTime ModifiedUtc, DateTime CreatedUtc, int Width, int Height, Annotation Annotation)
{
    public DateTime? AddedUtc { get; init; }
    [System.Text.Json.Serialization.JsonIgnore]
    public DateTime DateAddedUtc => AddedUtc ?? CreatedUtc;
    public string Name => System.IO.Path.GetFileName(Path);
    public string FolderPath => System.IO.Path.GetDirectoryName(Path) ?? RootPath;
    public string Extension => System.IO.Path.GetExtension(Path).TrimStart('.').ToUpperInvariant();
    public string Details => $"{Width:N0} × {Height:N0}  ·  {Extension}  ·  {FormatSize(ByteSize)}";
    public double AspectRatio => Height > 0 ? (double)Width / Height : 1;
    public static string FormatSize(long bytes) => bytes >= 1L << 30 ? $"{bytes / (double)(1L << 30):0.#} GB" :
        bytes >= 1L << 20 ? $"{bytes / (double)(1L << 20):0.#} MB" : $"{bytes / 1024.0:0.#} KB";
}

public sealed record VaultRoot(string Path, bool Available = true)
{
    public DateTime? FirstIndexedUtc { get; init; }
    public string Name => System.IO.Path.GetFileName(System.IO.Path.TrimEndingDirectorySeparator(Path)) is { Length: > 0 } name ? name : Path;
}
public sealed record ImageCollection(string Id, string Name, string[] Paths);
public enum DisplayMode { Fill, Fit, List }
// Append values to preserve sort IDs in existing JSON preferences.
public enum AssetSort { Name, Modified, Created, Size, Dimensions, Added }
public enum LocationKind { All, Favorites, Recent, Folder, Collection, Tag }
public sealed record Location(LocationKind Kind, string Value = "")
{
    public static Location All => new(LocationKind.All);
}

public sealed record Preferences
{
    public DisplayMode DisplayMode { get; set; } = DisplayMode.Fit;
    public double ThumbnailSize { get; set; } = 190;
    public bool SidebarVisible { get; set; } = true;
    public bool InspectorVisible { get; set; } = true;
    public double SidebarWidth { get; set; } = 240;
    public double InspectorWidth { get; set; } = 280;
    public bool IncludeSubfolders { get; set; } = true;
    public bool ScrollToZoom { get; set; }
    public string Theme { get; set; } = "Pink";
    public bool AutomaticDayNight { get; set; }
    public AssetSort Sort { get; set; }
    public bool Ascending { get; set; } = true;
    // Legacy normal-size fields remain compatible with preview 0.1.0. Startup
    // placement now comes from the small window.json file, before the index loads.
    public double WindowWidth { get; set; } = 1280;
    public double WindowHeight { get; set; } = 840;
    public string[] ExpandedFolders { get; set; } = [];
    public void Normalize()
    {
        ThumbnailSize = double.IsFinite(ThumbnailSize) ? Math.Clamp(ThumbnailSize, 125, 300) : 190;
        WindowWidth = double.IsFinite(WindowWidth) ? Math.Clamp(WindowWidth, 860, 3840) : 1280;
        WindowHeight = double.IsFinite(WindowHeight) ? Math.Clamp(WindowHeight, 540, 2160) : 840;
        SidebarWidth = double.IsFinite(SidebarWidth) ? Math.Clamp(SidebarWidth, 180, 420) : 240;
        InspectorWidth = double.IsFinite(InspectorWidth) ? Math.Clamp(InspectorWidth, 240, 480) : 280;
        if (Theme is not ("Pink" or "Dark rose" or "Follow system")) Theme = "Pink";
        if (!Enum.IsDefined(DisplayMode)) DisplayMode = DisplayMode.Fit;
        if (!Enum.IsDefined(Sort)) Sort = AssetSort.Name;
        ExpandedFolders ??= [];
    }
}

public sealed record LibraryState
{
    public int Schema { get; init; } = 1;
    public List<VaultRoot> Roots { get; init; } = [];
    public List<ImageAsset> Assets { get; init; } = [];
    public Dictionary<string, string[]> Directories { get; init; } = new(PathRules.Comparer);
    public List<ImageCollection> Collections { get; init; } = [];
    public List<string> RecentPaths { get; init; } = [];
    public Preferences Preferences { get; init; } = new();
    public LibraryState Snapshot() => this with
    {
        Roots = [.. Roots], Assets = [.. Assets], Directories = new(Directories, PathRules.Comparer),
        Collections = [.. Collections], RecentPaths = [.. RecentPaths], Preferences = Preferences with { }
    };
}

public static class PathRules
{
    public static StringComparer Comparer => OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    public static string Canonical(string path) => System.IO.Path.TrimEndingDirectorySeparator(System.IO.Path.GetFullPath(path));
    public static bool IsWithin(string path, string parent)
    {
        var relative = System.IO.Path.GetRelativePath(parent, path);
        return relative == "." || (!System.IO.Path.IsPathRooted(relative) && relative != ".." &&
            !relative.StartsWith(".." + System.IO.Path.DirectorySeparatorChar, StringComparison.Ordinal));
    }
}
