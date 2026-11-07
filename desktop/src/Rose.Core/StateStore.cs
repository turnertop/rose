using System.Text.Json;

namespace Rose.Core;

public sealed class StateStore
{
    public string DirectoryPath { get; }
    public string CachePath { get; }
    public string StatePath => Path.Combine(DirectoryPath, "library.json");
    private readonly SemaphoreSlim _writeGate = new(1);
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = false, PropertyNameCaseInsensitive = true };
    public StateStore(string? directory = null)
    {
        var overridden = directory ?? Environment.GetEnvironmentVariable("ROSE_DATA_DIRECTORY");
        DirectoryPath = overridden ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RoseDesktop");
        CachePath = Path.Combine(DirectoryPath, "Thumbnails");
        Directory.CreateDirectory(DirectoryPath);
    }
    public LibraryState Load()
    {
        if (!File.Exists(StatePath)) return new();
        var state = JsonSerializer.Deserialize<LibraryState>(File.ReadAllText(StatePath), Options) ?? throw new InvalidDataException("The saved library is empty.");
        if (state.Schema != 1 || state.Roots is null || state.Assets is null || state.Preferences is null ||
            state.Collections is null || state.Directories is null || state.RecentPaths is null)
            throw new InvalidDataException("The saved library has an unsupported format. Its file has been kept unchanged.");
        if (state.Roots.Any(x => x is null || string.IsNullOrWhiteSpace(x.Path)) ||
            state.Assets.Any(x => x is null || string.IsNullOrWhiteSpace(x.Path) || string.IsNullOrWhiteSpace(x.RootPath) ||
                x.RelativePath is null || x.Width <= 0 || x.Height <= 0 || x.ByteSize < 0 || x.Annotation is null || x.Annotation.Tags is null || x.Annotation.Note is null) ||
            state.Directories.Values.Any(x => x is null || x.Any(string.IsNullOrWhiteSpace)) ||
            state.Collections.Any(x => x is null || x.Name is null || x.Id is null || x.Paths is null) || state.RecentPaths.Any(string.IsNullOrWhiteSpace))
            throw new InvalidDataException("The saved library contains invalid entries. Its file has been kept unchanged.");
        state.Preferences.Normalize();
        return state;
    }
    public async Task SaveAsync(LibraryState snapshot)
    {
        await _writeGate.WaitAsync();
        try { await Task.Run(() => AtomicFile.Write(StatePath, JsonSerializer.Serialize(snapshot, Options))); }
        finally { _writeGate.Release(); }
    }
}
