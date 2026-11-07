using Avalonia.Threading;
using Rose.Core;
using Rose.Imaging;

namespace Rose.Desktop;

public sealed class LibraryController : IDisposable
{
    public LibraryState State { get; private set; } = new();
    public StateStore Store { get; }
    public AnnotationWrites AnnotationWrites { get; } = new();
    public string Status { get; private set; } = "Files stay in their folders";
    public bool Scanning { get; private set; }
    public bool CanSave { get; private set; } = true;
    public event Action? Changed;
    private readonly List<FileSystemWatcher> _watchers = [];
    private readonly CancellationTokenSource _lifetime = new();
    private readonly DispatcherTimer _watchDelay = new() { Interval = TimeSpan.FromMilliseconds(700) };
    private readonly DispatcherTimer _noteDelay = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private readonly Dictionary<string, Annotation> _edits = new(PathRules.Comparer);
    private CancellationTokenSource? _saveDelay;
    private bool _scanAgain;
    public LibraryController(StateStore store)
    {
        Store = store;
        _watchDelay.Tick += async (_, _) => { _watchDelay.Stop(); await RefreshAsync(); };
        _noteDelay.Tick += async (_, _) => { _noteDelay.Stop(); try { await AnnotationWrites.FlushAsync(); } catch (Exception e) { Report("Notes are unsaved: " + e.Message); } };
    }
    public async Task InitializeAsync(bool scan = true)
    {
        try { State = await Task.Run(Store.Load); }
        catch (Exception e) when (e is IOException or System.Text.Json.JsonException or UnauthorizedAccessException)
        { CanSave = false; Report("Could not load the saved library. Its file is unchanged. " + e.Message); }
        Changed?.Invoke();
        if (scan && CanSave) await RefreshAsync();
    }
    public async Task AddFolderAsync(string path)
    {
        path = PathRules.Canonical(path);
        if (!Directory.Exists(path)) { Report("That folder is unavailable."); return; }
        if (State.Roots.Any(x => PathRules.IsWithin(path, x.Path))) return;
        var replaced = State.Roots.Where(x => PathRules.IsWithin(x.Path, path)).Select(x => x.Path).ToHashSet(PathRules.Comparer);
        State.Roots.RemoveAll(x => replaced.Contains(x.Path));
        State.Assets.RemoveAll(x => replaced.Contains(x.RootPath));
        foreach (var child in replaced) State.Directories.Remove(child);
        State.Roots.Add(new(path));
        State.Preferences.ExpandedFolders = State.Preferences.ExpandedFolders.Append(path).Distinct(PathRules.Comparer).ToArray();
        Touch(); await RefreshAsync();
    }
    public async Task RefreshAsync()
    {
        if (Scanning) { _scanAgain = true; return; }
        if (_lifetime.IsCancellationRequested) return;
        _edits.Clear(); foreach (var (path, annotation) in AnnotationWrites.Snapshot()) _edits[path] = annotation;
        Scanning = true; Status = "Checking your folders…"; Changed?.Invoke();
        try
        {
            do
            {
                _scanAgain = false; var skipped = 0;
                foreach (var root in State.Roots.ToArray())
                {
                    var cached = State.Assets.Where(x => PathRules.Comparer.Equals(x.RootPath, root.Path)).ToArray();
                    var result = await Task.Run(() => LibraryIndexer.Scan(root, cached, ImageDecoder.Metadata, _lifetime.Token));
                    if (!State.Roots.Any(x => PathRules.Comparer.Equals(x.Path, root.Path))) continue;
                    State.Assets.RemoveAll(x => PathRules.Comparer.Equals(x.RootPath, root.Path));
                    State.Assets.AddRange(result.Assets.Select(x => _edits.TryGetValue(x.Path, out var annotation) ? x with { Annotation = annotation } : x));
                    if (result.Available) State.Directories[root.Path] = result.Directories;
                    var i = State.Roots.FindIndex(x => PathRules.Comparer.Equals(x.Path, root.Path));
                    State.Roots[i] = root with
                    {
                        Available = result.Available,
                        FirstIndexedUtc = root.FirstIndexedUtc ?? (result.Available ? DateTime.UtcNow : null)
                    };
                    skipped += result.Skipped;
                    Changed?.Invoke();
                }
                var unique = State.Assets.GroupBy(x => x.Path, PathRules.Comparer).Select(x => x.First()).ToArray();
                State.Assets.Clear(); State.Assets.AddRange(unique);
                Status = skipped > 0 ? $"{skipped:N0} unreadable or unsupported files skipped · Files stay in their folders" :
                    State.Roots.Any(x => !x.Available) ? "Some folders are offline · Showing the saved index" : "Files stay in their folders";
            } while (_scanAgain && !_lifetime.IsCancellationRequested);
            RebuildWatchers(); SaveLater();
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { Report("Could not finish refreshing: " + e.Message); }
        finally { Scanning = false; Changed?.Invoke(); }
    }
    public void SetAnnotation(ImageAsset asset, Annotation annotation)
    {
        var index = State.Assets.FindIndex(x => PathRules.Comparer.Equals(x.Path, asset.Path));
        if (index < 0) return;
        State.Assets[index] = State.Assets[index] with { Annotation = annotation };
        _edits[asset.Path] = annotation; AnnotationWrites.Queue(asset.Path, annotation);
        _noteDelay.Stop(); _noteDelay.Start(); Touch();
    }
    public void RemoveRoot(string path)
    {
        State.Roots.RemoveAll(x => PathRules.Comparer.Equals(x.Path, path));
        State.Assets.RemoveAll(x => PathRules.Comparer.Equals(x.RootPath, path)); State.Directories.Remove(path);
        RebuildWatchers(); Touch();
    }
    public void Remember(ImageAsset asset)
    {
        State.RecentPaths.RemoveAll(x => PathRules.Comparer.Equals(x, asset.Path)); State.RecentPaths.Insert(0, asset.Path);
        if (State.RecentPaths.Count > 200) State.RecentPaths.RemoveRange(200, State.RecentPaths.Count - 200);
        Touch();
    }
    public void Touch() { Changed?.Invoke(); SaveLater(); }
    public void Report(string message) { Status = message; Changed?.Invoke(); }
    private void SaveLater()
    {
        if (!CanSave) return;
        _saveDelay?.Cancel(); _saveDelay?.Dispose(); _saveDelay = new();
        var cancellation = _saveDelay.Token;
        _ = SaveDelayedAsync(cancellation);
    }
    private async Task SaveDelayedAsync(CancellationToken cancellation)
    {
        try { await Task.Delay(350, cancellation); cancellation.ThrowIfCancellationRequested(); await Store.SaveAsync(State.Snapshot()); }
        catch (OperationCanceledException) { }
        catch (Exception e) { Report("Could not save app preferences: " + e.Message); }
    }
    public async Task FlushAsync()
    {
        _saveDelay?.Cancel(); _noteDelay.Stop();
        await AnnotationWrites.FlushAsync();
        if (CanSave) await Store.SaveAsync(State.Snapshot());
    }
    private void RebuildWatchers()
    {
        foreach (var watcher in _watchers) watcher.Dispose(); _watchers.Clear();
        foreach (var root in State.Roots.Where(x => x.Available))
        {
            try
            {
                var watcher = new FileSystemWatcher(root.Path) { IncludeSubdirectories = true,
                    NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size };
                void OnChange(object? _, FileSystemEventArgs e)
                {
                    if (e.FullPath.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase)) return;
                    Dispatcher.UIThread.Post(() => { if (_lifetime.IsCancellationRequested) return; _watchDelay.Stop(); _watchDelay.Start(); });
                }
                watcher.Created += OnChange; watcher.Deleted += OnChange; watcher.Changed += OnChange; watcher.Renamed += OnChange;
                watcher.Error += (_, _) => Dispatcher.UIThread.Post(() => { _watchDelay.Stop(); _watchDelay.Start(); });
                watcher.EnableRaisingEvents = true; _watchers.Add(watcher);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException)
            { Status = "Folder watching is unavailable for " + root.Name + ". Use Refresh folders."; }
        }
    }
    public void Dispose()
    {
        _lifetime.Cancel(); _watchDelay.Stop(); _noteDelay.Stop(); _saveDelay?.Cancel();
        foreach (var watcher in _watchers) watcher.Dispose(); _watchers.Clear();
    }
}
