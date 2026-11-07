using System.Diagnostics;
using System.Text;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Rose.Core;
using Rose.Desktop;
using Rose.Imaging;
using SkiaSharp;
using Location = Rose.Core.Location;

internal static partial class Checks
{
    private static int _passed;
    private static readonly List<string> Failures = [];
    private static readonly string Temporary = Path.Combine(Path.GetTempPath(), "rose-desktop-checks-" + Guid.NewGuid().ToString("N"));
    private static readonly string Artifacts = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../artifacts/checks"));
    [STAThread]
    public static int Main()
    {
        Directory.CreateDirectory(Temporary); Directory.CreateDirectory(Artifacts);
        try
        {
            Run("Sidecars and safe writes", Sidecars);
            Run("Independent local state", State);
            Run("Added dates, legacy state and stable discovery", AddedDates);
            Run("Window placement geometry and storage", WindowPlacementGeometryChecks);
            Run("Search, folders and natural sorting", Query);
            Run("Justified layout and visible-item bounds", Layout);
            Run("Native decoding, orientation and animation", Decode);
            Run("Indexing, cache reuse and offline folders", Indexer);
            Run("Thumbnail cancellation, deduplication and cache", () => Thumbnails().GetAwaiter().GetResult());
            AppBuilder.Configure<RoseApplication>().UseSkia().UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false }).SetupWithoutStarting();
            Run("Window close, reopen and state restoration", WindowPlacementUiChecks);
            Run("Gallery cancellation during scroll and reorder", GalleryRequestCancellation);
            Run("Headless interface, keyboard and persistence", UserInterface);
        }
        finally
        {
            try { Directory.Delete(Temporary, true); } catch (IOException) { }
        }
        Console.WriteLine($"\n{_passed} checks passed; {Failures.Count} groups failed.");
        foreach (var failure in Failures) Console.WriteLine(failure);
        return Failures.Count == 0 ? 0 : 1;
    }
    private static void Run(string name, Action check)
    {
        try { check(); Console.WriteLine("PASS " + name); }
        catch (Exception error) { Failures.Add("FAIL " + name + "\n" + error); Console.WriteLine(Failures[^1]); }
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
        _passed++;
    }
    private static void Near(double expected, double actual, string message) => Check(Math.Abs(expected - actual) < .02, message + $" (expected {expected}, got {actual})");
    private static void Throws<T>(Action action, string message) where T : Exception
    {
        try { action(); } catch (T) { _passed++; return; } throw new Exception(message);
    }
    private static string Folder(string name) { var path = Path.Combine(Temporary, name); Directory.CreateDirectory(path); return path; }
    private static ImageAsset Asset(string path, string root, int width = 800, int height = 600, Annotation? annotation = null)
    {
        var file = new FileInfo(path);
        return new(path, root, Path.GetRelativePath(root, path), file.Exists ? file.Length : 100, file.Exists ? file.LastWriteTimeUtc : DateTime.UnixEpoch,
            file.Exists ? file.CreationTimeUtc : DateTime.UnixEpoch, width, height, annotation ?? Annotation.Empty);
    }
    private static void Sidecars()
    {
        var annotation = new Annotation(["rose", "日本語", "a,b", "quote\""], "# Hello\n\n  Keep indentation.\n", true);
        var decoded = SidecarStore.Decode(SidecarStore.Encode(annotation));
        Check(decoded.Tags.SequenceEqual(annotation.Tags), "Unicode and quoted tags round-trip");
        Check(decoded.Note == annotation.Note && decoded.IsFavorite, "Exact Markdown body and favorite round-trip");
        var yaml = "---\r\nsource: https://example.com\r\nnested:\r\n  keep: true\r\ntags:\r\n  - 'one'\r\n  - \"two\"\r\nfavorite: true\r\n---\r\nOriginal\r\n";
        decoded = SidecarStore.Decode(yaml);
        Check(decoded.Tags.SequenceEqual(new[] { "one", "two" }), "Common YAML block tags supported");
        Check(decoded.Note == "Original\n", "CRLF normalized to Mac sidecar format");
        var encoded = SidecarStore.Encode(annotation, yaml);
        Check(encoded.Contains("source: https://example.com\nnested:\n  keep: true"), "Unknown frontmatter preserved");
        Check(!encoded.Contains("  - 'one'"), "Previous managed block tags removed");
        Check(SidecarStore.Decode("Plain\n\nMarkdown").Note == "Plain\n\nMarkdown", "Plain Markdown supported");
        Check(SidecarStore.Decode("---\n---\nBody").Note == "Body", "Empty frontmatter supported");
        Check(SidecarStore.Decode("---\nUnclosed").Note == "---\nUnclosed", "Unclosed frontmatter remains text");
        var root = Folder("sidecars"); var path = Path.Combine(root, "same.jpg");
        File.WriteAllText(path, "original image bytes"); var original = File.ReadAllBytes(path);
        SidecarStore.Write(path, annotation);
        Check(File.ReadAllBytes(path).SequenceEqual(original), "Annotation writes do not modify images");
        Check(SidecarStore.PathFor(path) != SidecarStore.PathFor(Path.ChangeExtension(path, ".png")), "Sidecar names distinguish image extensions");
        Check(SidecarStore.Read(path).Note == annotation.Note, "Atomic sidecar saved and read");
        var blocked = Path.Combine(root, "blocked.png"); Directory.CreateDirectory(SidecarStore.PathFor(blocked));
        Throws<UnauthorizedAccessException>(() => SidecarStore.Write(blocked, annotation), "Existing unreadable sidecar must not be replaced");
        Check(Directory.Exists(SidecarStore.PathFor(blocked)), "Unreadable original left untouched");
        var queue = new AnnotationWrites(); queue.Queue(path, annotation); queue.Queue(path, annotation with { Note = "Latest" }); queue.FlushAsync().GetAwaiter().GetResult();
        Check(SidecarStore.Read(path).Note == "Latest" && queue.PendingCount == 0, "Queued note edits coalesce and flush");
        queue.Queue(blocked, annotation);
        Throws<UnauthorizedAccessException>(() => queue.FlushAsync().GetAwaiter().GetResult(), "Failed note write reported");
        Check(queue.PendingCount == 1, "Failed note retained for retry");
    }
    private static void State()
    {
        var store = new StateStore(Folder("state-a")); var other = new StateStore(Folder("state-b"));
        var state = new LibraryState { Preferences = new() { ThumbnailSize = 300, DisplayMode = DisplayMode.List, Theme = "Dark rose", ScrollToZoom = true, SidebarVisible = false } };
        state.Roots.Add(new(Path.Combine(Temporary, "vault"))); state.Collections.Add(new("c", "References", ["a.png"]));
        state.RecentPaths.Add("a.png"); store.SaveAsync(state).GetAwaiter().GetResult(); var loaded = store.Load();
        Check(loaded.Preferences.ThumbnailSize == 300 && loaded.Preferences.DisplayMode == DisplayMode.List, "Zoom and view survive restart");
        Check(loaded.Preferences.Theme == "Dark rose" && loaded.Preferences.ScrollToZoom && !loaded.Preferences.SidebarVisible, "Appearance, gesture and panel preferences survive restart");
        Check(loaded.Collections.Single().Name == "References" && loaded.RecentPaths.Single() == "a.png", "Collections and recents persist");
        Check(other.Load().Roots.Count == 0, "Separate installation directories have independent libraries");
        var snapshot = state.Snapshot(); state.Roots.Clear(); state.Preferences.ThumbnailSize = 125;
        Check(snapshot.Roots.Count == 1 && snapshot.Preferences.ThumbnailSize == 300, "Background save snapshot unaffected by later UI edits");
        var invalid = new Preferences { ThumbnailSize = double.NaN, WindowWidth = double.PositiveInfinity, Theme = "invalid" }; invalid.Normalize();
        Check(invalid.ThumbnailSize == 190 && invalid.WindowWidth == 1280 && invalid.Theme == "Pink", "Invalid numeric preferences bounded");
        File.WriteAllText(store.StatePath, "{ malformed"); var before = File.ReadAllText(store.StatePath);
        Throws<System.Text.Json.JsonException>(() => store.Load(), "Corrupt state reported");
        Check(File.ReadAllText(store.StatePath) == before, "Corrupt state not overwritten");
        File.WriteAllText(store.StatePath, "{\"Schema\":999}");
        Throws<InvalidDataException>(() => store.Load(), "Future state schema not silently downgraded");
        File.WriteAllText(store.StatePath, "{\"Assets\":[null]}");
        Throws<InvalidDataException>(() => store.Load(), "Malformed asset entries are reported before reaching the UI");
    }
    private static void Query()
    {
        var root = Folder("query"); var child = Path.Combine(root, "sub"); var sibling = root + "-other";
        var a = Asset(Path.Combine(root, "image10.png"), root, annotation: new(["pink"], "", false));
        var b = Asset(Path.Combine(root, "image2.jpg"), root, annotation: new(["rose"], "", true));
        var c = Asset(Path.Combine(child, "image1.png"), root); var d = Asset(Path.Combine(sibling, "image3.png"), sibling);
        var state = new LibraryState(); state.Assets.AddRange([a, b, c, d]);
        Check(LibraryQuery.Filter(state, Location.All, "").Select(x => x.Name).SequenceEqual(new[] { "image1.png", "image2.jpg", "image3.png", "image10.png" }), "Natural numeric filename ordering");
        Check(LibraryQuery.Filter(state, new(LocationKind.Folder, root), "").Length == 3, "Recursive folder selection excludes prefix siblings");
        state.Preferences.IncludeSubfolders = false;
        Check(LibraryQuery.Filter(state, new(LocationKind.Folder, root), "").Length == 2, "Direct-folder filter excludes nested images");
        Check(LibraryQuery.Filter(state, new(LocationKind.Favorites), "").Single() == b, "Favorites filter");
        Check(LibraryQuery.Filter(state, Location.All, "IMAGE pink png").Single() == a, "Multiple search terms combine across tags and filename");
        Check(LibraryQuery.Filter(state, Location.All, "zzzz").Length == 0, "No-results search");
        state.Collections.Add(new("c", "Ideas", [b.Path]));
        Check(LibraryQuery.Filter(state, new(LocationKind.Collection, "c"), "").Single() == b, "Virtual collection membership");
        Check(LibraryQuery.Filter(state, new(LocationKind.Tag, "PINK"), "").Single() == a, "Tag case insensitive");
        state.RecentPaths.AddRange([a.Path, c.Path]);
        Check(LibraryQuery.Filter(state, new(LocationKind.Recent), "").Select(x => x.Path).SequenceEqual(new[] { a.Path, c.Path }), "Recently viewed ordering");
        state.Preferences.Ascending = false;
        Check(LibraryQuery.Filter(state, Location.All, "")[0] == a, "Descending sort");
        Check(LibraryQuery.NaturalCompare("a99999999999999999999", "a100000000000000000000") < 0, "Numeric sort does not overflow");
        Check(PathRules.IsWithin(child, root) && !PathRules.IsWithin(sibling, root), "Folder containment checks directory boundaries");
    }
    private static void Layout()
    {
        var fit = GalleryLayout.Calculate([1d, 1, 1], 630, 200, DisplayMode.Fit);
        Check(fit.Rows.Length == 1 && fit.Frames.Length == 3, "Square images form justified row");
        Near(191.3333 + 34, fit.Frames[0].Height, "Expected justified row height");
        Near(626, fit.Frames[^1].X + fit.Frames[^1].Width, "Justified row fills available width");
        var last = GalleryLayout.Calculate([1d], 630, 200, DisplayMode.Fit);
        Near(234, last.Frames[0].Height, "Incomplete final row stays at target height");
        var varied = Enumerable.Range(0, 1057).Select(i => i % 3 == 0 ? 1.8 : i % 3 == 1 ? .55 : 1).ToArray();
        foreach (var mode in Enum.GetValues<DisplayMode>())
        {
            var layout = GalleryLayout.Calculate(varied, 1500, 190, mode);
            Check(layout.Frames.Length == 1057, mode + " contains every item");
            Check(layout.Visible(layout.Height / 2, 800).Count() is > 0 and < 100, mode + " viewport work bounded for 1,057 images");
            Check(layout.Frames.All(x => double.IsFinite(x.Width) && x.Width > 0 && x.Height > 0 && x.X >= 0 && x.X + x.Width <= 1501), mode + " finite frames contained");
            var frame = layout.Frames[517]; Check(layout.HitTest(frame.X + 1, frame.Y + 1) == 517, mode + " hit test follows visual layout");
            Check(layout.Visible(-100, 50).Count() == 0, mode + " ignores viewport above content");
            var next = layout.Navigate(5, 0, 1); Check(next >= 0 && next < 1057 && layout.Frames[next].Y >= layout.Frames[5].Y, mode + " vertical keyboard navigation follows rows");
        }
        Check(GalleryLayout.Calculate([1d], double.NaN, 190, DisplayMode.Fit).Frames.Length == 0, "Invalid layout size safe");
        var extreme = GalleryLayout.Calculate([double.NaN, double.PositiveInfinity, 0, 1e9, .0000001], 300, 190, DisplayMode.Fit);
        Check(extreme.Frames.Length == 5 && extreme.Frames.All(x => double.IsFinite(x.Height)), "Pathological aspect ratios bounded");
    }
    private static void MakeImage(string path, int width = 100, int height = 160, SKEncodedImageFormat format = SKEncodedImageFormat.Png)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using var bitmap = new SKBitmap(width, height); using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColor.Parse("#F1CDD9"));
        using var paint = new SKPaint { Color = SKColor.Parse("#CF6390"), IsAntialias = true };
        canvas.DrawCircle(width * .5f, height * .32f, width * .25f, paint);
        paint.Color = SKColor.Parse("#875578"); canvas.DrawRect(width * .23f, height * .62f, width * .54f, height * .4f, paint);
        using var image = SKImage.FromBitmap(bitmap); using var data = image.Encode(format, 90); using var stream = File.Create(path); data.SaveTo(stream);
    }
    private static byte[] Gif() => [71,73,70,56,57,97, 1,0,1,0,128,0,0, 255,0,0,0,255,0,
        33,255,11,78,69,84,83,67,65,80,69,50,46,48,3,1,0,0,0,
        33,249,4,4,5,0,0,0,44,0,0,0,0,1,0,1,0,0,2,2,68,1,0,
        33,249,4,4,5,0,0,0,44,0,0,0,0,1,0,1,0,0,2,2,76,1,0,59];
    private static void Decode()
    {
        var folder = Folder("decode");
        foreach (var (extension, format) in new[] { ("png", SKEncodedImageFormat.Png), ("jpg", SKEncodedImageFormat.Jpeg), ("webp", SKEncodedImageFormat.Webp) })
        {
            var path = Path.Combine(folder, "image." + extension); MakeImage(path, 800, 600, format);
            var metadata = ImageDecoder.Metadata(path); Check(metadata is { Width: 800, Height: 600 }, extension + " metadata");
            using var decoded = SKBitmap.Decode(ImageDecoder.Decode(path, 128)); Check(decoded.Width <= 128 && decoded.Height <= 128, extension + " bounded thumbnail dimensions");
        }
        var jpeg = Path.Combine(folder, "oriented.jpg"); MakeImage(jpeg, 80, 40, SKEncodedImageFormat.Jpeg);
        var raw = File.ReadAllBytes(jpeg); byte[] exif = [69,120,105,102,0,0,73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,6,0,0,0,0,0,0,0];
        File.WriteAllBytes(jpeg, raw[..2].Concat(new byte[] { 255,225,0,(byte)(exif.Length + 2) }).Concat(exif).Concat(raw[2..]).ToArray());
        Check(ImageDecoder.Metadata(jpeg) is { Width: 40, Height: 80 }, "EXIF rotated dimensions applied before layout");
        using (var rotated = SKBitmap.Decode(ImageDecoder.Decode(jpeg, 100))) Check(rotated.Width == 40 && rotated.Height == 80, "EXIF orientation applied to decoded image");
        var alphaPath = Path.Combine(folder, "alpha.png"); using (var bitmap = new SKBitmap(20, 20)) { bitmap.Erase(SKColors.Transparent); using var image = SKImage.FromBitmap(bitmap); using var data = image.Encode(SKEncodedImageFormat.Png, 90); File.WriteAllBytes(alphaPath, data.ToArray()); }
        using (var transparent = SKBitmap.Decode(ImageDecoder.Decode(alphaPath, 128))) Check(transparent.GetPixel(0, 0).Alpha == 0, "Transparency preserved");
        var corrupt = Path.Combine(folder, "broken.png"); File.WriteAllText(corrupt, "not an image"); Check(ImageDecoder.Metadata(corrupt) is null, "Corrupt image rejected");
        Throws<InvalidDataException>(() => ImageDecoder.Decode(corrupt, 128), "Corrupt preview reports useful error");
        var gif = Path.Combine(folder, "animated.gif"); File.WriteAllBytes(gif, Gif());
        using var playback = GifPlayback.Open(gif); Check(playback is not null, "GIF playback recognized");
        var first = playback!.Next(); var second = playback.Next();
        using var one = SKBitmap.Decode(first!.Value.Data); using var two = SKBitmap.Decode(second!.Value.Data);
        Check(one.GetPixel(0, 0).Red > 200 && two.GetPixel(0, 0).Green > 200, "GIF frames composite in order");
        Check(first.Value.Delay == 50 && playback.Next() is not null, "GIF duration and looping honored");
        if (OperatingSystem.IsWindowsVersionAtLeast(6, 1))
        {
            var tiff = Path.Combine(folder, "system-codec.tiff");
            using (var bitmap = new System.Drawing.Bitmap(40, 60)) bitmap.Save(tiff, System.Drawing.Imaging.ImageFormat.Tiff);
            Check(ImageDecoder.Metadata(tiff) is { Width: 40, Height: 60 }, "Windows TIFF metadata fallback");
            using var decoded = SKBitmap.Decode(ImageDecoder.Decode(tiff, 32)); Check(decoded.Height == 32, "Windows TIFF preview fallback");
        }
    }
    private static void Indexer()
    {
        var root = Folder("index"); var nested = Path.Combine(root, "nested"); Directory.CreateDirectory(Path.Combine(root, "empty"));
        MakeImage(Path.Combine(root, "one.png")); MakeImage(Path.Combine(nested, "two.jpg"), format: SKEncodedImageFormat.Jpeg);
        File.WriteAllText(Path.Combine(root, "bad.jpg"), "not an image"); File.WriteAllText(Path.Combine(root, "readme.md"), "not an image");
        var first = LibraryIndexer.Scan(new(root), [], ImageDecoder.Metadata);
        Check(first.Assets.Length == 2 && first.Skipped == 1, "Supported images indexed; corrupt image skipped");
        Check(first.Directories.Length == 3, "Empty and nested folders retained");
        var asset = first.Assets.Single(x => x.Name == "one.png"); SidecarStore.Write(asset.Path, new(["updated"], "Note", true));
        var calls = 0; var second = LibraryIndexer.Scan(new(root), first.Assets, path => { calls++; return ImageDecoder.Metadata(path); });
        Check(calls == 1, "Unchanged valid image metadata reused; corrupt file retried");
        Check(second.Assets.Single(x => x.Name == "one.png").Annotation.IsFavorite, "Sidecars refreshed independently of image modification");
        MakeImage(Path.Combine(root, "new.png"));
        Check(LibraryIndexer.Scan(new(root), second.Assets, ImageDecoder.Metadata).Assets.Length == 3, "New image discovered");
        var offline = LibraryIndexer.Scan(new(root + "-missing"), first.Assets, ImageDecoder.Metadata);
        Check(!offline.Available && offline.Assets.Length == 2, "Offline root retains saved index");
        var cancellation = new CancellationToken(true);
        Throws<OperationCanceledException>(() => LibraryIndexer.Scan(new(root), [], ImageDecoder.Metadata, cancellation), "Index scan cancellation honored");
        if (!OperatingSystem.IsWindows())
        {
            Directory.CreateSymbolicLink(Path.Combine(root, "loop"), root);
            Check(LibraryIndexer.Scan(new(root), [], ImageDecoder.Metadata).Directories.Length == 3, "Directory symlinks skipped, preventing recursion loops");
        }
    }
    private static async Task Thumbnails()
    {
        var root = Folder("thumbs"); var path = Path.Combine(root, "image.png"); MakeImage(path, 800, 600); var asset = Asset(path, root);
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var calls = 0;
        using var service = new ThumbnailService(Path.Combine(root, "cache"), decode: (p, edge, token) =>
        { Interlocked.Increment(ref calls); started.TrySetResult(); release.Task.Wait(token); return ImageDecoder.Decode(p, edge, token); });
        using var canceled = new CancellationTokenSource();
        var a = service.RequestAsync(asset, 128, canceled.Token); var b = service.RequestAsync(asset, 128);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(10)); canceled.Cancel(); release.SetResult();
        try { await a; throw new Exception("Canceled subscriber succeeded"); } catch (OperationCanceledException) { _passed++; }
        var bytes = await b; Check(calls == 1 && bytes.Length > 8, "Concurrent subscribers share one decode; one cancellation does not cancel the other");
        var warm = await service.RequestAsync(asset, 128); Check(calls == 1 && warm.SequenceEqual(bytes), "Warm disk cache avoids source decode");
        File.Delete(path);
        try { await service.RequestAsync(asset, 128); throw new Exception("Missing original served stale thumbnail"); } catch (FileNotFoundException) { _passed++; }
        MakeImage(path, 800, 600); asset = Asset(path, root);
        var active = 0; var maximum = 0;
        using var bounded = new ThumbnailService(Path.Combine(root, "bounded"), decode: (p, edge, token) =>
        {
            var count = Interlocked.Increment(ref active); InterlockedExtensions.Max(ref maximum, count);
            try { Thread.Sleep(10); token.ThrowIfCancellationRequested(); return ImageDecoder.Decode(p, edge, token); }
            finally { Interlocked.Decrement(ref active); }
        });
        var requests = new List<Task>();
        for (var i = 0; i < 40; i++)
        {
            var copy = Path.Combine(root, "copy" + i + ".png"); File.Copy(path, copy);
            var token = new CancellationTokenSource(); var task = bounded.RequestAsync(Asset(copy, root), 128, token.Token);
            if (i < 35) token.Cancel(); requests.Add(IgnoreCancellation(task));
        }
        await Task.WhenAll(requests); Check(maximum <= 2 && active == 0, "Fling request burst respects two-decoder limit");
        Check(bounded.PendingCount == 0, "Canceled and completed subscriptions released");
        var key = ThumbnailService.Key(asset, 128); File.WriteAllText(Path.Combine(root, "cache", key + ".png"), "bad cache");
        await service.RequestAsync(asset, 128); Check(calls == 2, "Invalid cached thumbnail regenerated");
    }
    private static async Task IgnoreCancellation(Task task) { try { await task; } catch (OperationCanceledException) { } }
    private static void PumpUntil(Func<bool> condition, int milliseconds = 10000)
    {
        var timer = Stopwatch.StartNew();
        while (!condition()) { Dispatcher.UIThread.RunJobs(); if (timer.ElapsedMilliseconds > milliseconds) throw new TimeoutException("Headless operation timed out"); Thread.Sleep(5); }
        Dispatcher.UIThread.RunJobs();
    }
    private static void Await(Task task) { PumpUntil(() => task.IsCompleted); task.GetAwaiter().GetResult(); }
    private static void Pump() { Dispatcher.UIThread.RunJobs(); }
    private static void Key(MainWindow window, Avalonia.Input.Key key, RawInputModifiers modifiers = RawInputModifiers.None)
    { window.KeyPress(key, modifiers, PhysicalKey.None, null); window.KeyRelease(key, modifiers, PhysicalKey.None, null); Pump(); }
    private static void Click(MainWindow window, Point point)
    { window.MouseDown(point, MouseButton.Left); window.MouseUp(point, MouseButton.Left); Pump(); }
    private static void UserInterface()
    {
        var vault = Folder("ui-vault");
        for (var i = 0; i < 12; i++) MakeImage(Path.Combine(vault, $"Reference {i + 1}.png"), i % 3 == 0 ? 300 : 100, i % 3 == 0 ? 180 : 160);
        var store = new StateStore(Folder("ui-state")); var state = new LibraryState(); state.Roots.Add(new(vault));
        var scanned = LibraryIndexer.Scan(state.Roots[0], [], ImageDecoder.Metadata); state.Assets.AddRange(scanned.Assets); state.Directories[vault] = scanned.Directories;
        // Repeated metadata creates a large scrollable gallery without loading thousands of originals.
        for (var i = 0; i < 1057; i++) state.Assets.Add(Asset(Path.Combine(vault, $"Virtual {i:0000}.png"), vault));
        Await(store.SaveAsync(state));
        var window = new MainWindow(store, false); window.Show(); Await(window.Library.InitializeAsync(false)); window.RefreshView(); window.ReturnToBrowsing(false); Pump();
        try
        {
            Check(window.Gallery.IsFocused && !window.SearchField.IsKeyboardFocusWithin, "Startup has gallery focus and no search caret");
            Check(window.Gallery.Geometry.Frames.Length == 1069, "Large saved library appears immediately");
            var sortField = window.GetVisualDescendants().OfType<ComboBox>().Single(x => x.Name == "SortField");
            Check(window.Library.State.Preferences.Sort == AssetSort.Name && Equals(sortField.SelectedItem, "Name"), "Date added is an extra option rather than a new default");
            sortField.SelectedItem = "Date added"; Pump();
            Check(window.Library.State.Preferences.Sort == AssetSort.Added && !window.Library.State.Preferences.Ascending,
                "Selecting Date added through the real control starts newest first");
            window.Library.State.Preferences.Ascending = true; window.RefreshView(); Pump();
            Check(window.Library.State.Preferences.Ascending && Equals(sortField.SelectedItem, "Date added"), "Refreshing controls preserves a chosen oldest-first added order");
            sortField.SelectedItem = "Date created"; Pump();
            Check(window.Library.State.Preferences.Sort == AssetSort.Created, "Sort labels map to stable preference IDs after inserting Date added");
            sortField.SelectedItem = "Name"; window.Library.State.Preferences.Ascending = true; window.Library.Touch(); Pump();
            Key(window, Avalonia.Input.Key.Space); Check(window.GalleryScroll.Offset.Y > 0 && string.IsNullOrEmpty(window.SearchField.Text), "Startup Space pages rather than adding search spaces");
            var position = window.GalleryScroll.Offset.Y;
            window.KeyTextInput("y"); Pump(); Check(window.SearchField.IsKeyboardFocusWithin && window.SearchField.Text == "y", "Typing activates search and enters first character once");
            Key(window, Avalonia.Input.Key.Back); Pump(); Check(string.IsNullOrEmpty(window.SearchField.Text) && window.Gallery.IsFocused, "Backspace to empty leaves search editing");
            Near(position, window.GalleryScroll.Offset.Y, "Clearing search preserves browsing position");
            Key(window, Avalonia.Input.Key.F, RawInputModifiers.Control); window.KeyTextInput(" "); Pump();
            Check(window.SearchField.Text == " ", "Explicit search editing permits leading spaces");
            Key(window, Avalonia.Input.Key.Escape); Check(window.Gallery.IsFocused && window.SearchField.Text == " ", "Escape leaves caret while preserving query");
            window.SearchField.Text = ""; window.SetOffset(0); Pump();
            window.Gallery.Select(0); Check(window.Gallery.Selected.Count == 1, "Gallery selection");
            Click(window, new Point(500, 30)); Check(window.Gallery.Selected.Count == 0 && !window.SearchField.IsKeyboardFocusWithin, "Blank toolbar click clears selection and search focus");
            window.Gallery.Select(0); Click(window, new Point(500, 110)); Check(window.Gallery.Selected.Count == 0, "Blank gallery heading click clears selection");
            window.Gallery.Select(0); Key(window, Avalonia.Input.Key.Escape); Check(window.Gallery.Selected.Count == 0, "Escape clears selection");
            Key(window, Avalonia.Input.Key.A, RawInputModifiers.Control); Check(window.Gallery.Selected.Count == 1069, "Ctrl+A selects displayed images"); window.Gallery.ClearSelection();
            Key(window, Avalonia.Input.Key.D1, RawInputModifiers.Control); Check(window.Library.State.Preferences.DisplayMode == DisplayMode.Fill, "Fill shortcut");
            Key(window, Avalonia.Input.Key.D3, RawInputModifiers.Control); Check(window.Library.State.Preferences.DisplayMode == DisplayMode.List, "List shortcut");
            Key(window, Avalonia.Input.Key.D2, RawInputModifiers.Control); Check(window.Library.State.Preferences.DisplayMode == DisplayMode.Fit, "Fit shortcut");
            Key(window, Avalonia.Input.Key.B, RawInputModifiers.Control); Check(!window.Library.State.Preferences.SidebarVisible, "Sidebar toggle");
            Key(window, Avalonia.Input.Key.B, RawInputModifiers.Control); Key(window, Avalonia.Input.Key.I, RawInputModifiers.Control); Check(!window.Library.State.Preferences.InspectorVisible, "Inspector toggle");
            Key(window, Avalonia.Input.Key.I, RawInputModifiers.Control);
            var actual = window.Gallery.Items.First(x => File.Exists(x.Path)); var index = Array.IndexOf(window.Gallery.Items, actual); window.Gallery.Select(index);
            var notes = window.GetVisualDescendants().OfType<TextBox>().Single(x => x.AcceptsReturn); notes.Focus(); notes.Text = "A note that survives an immediate quit."; Pump();
            Await(window.Library.FlushAsync()); Check(SidecarStore.Read(actual.Path).Note == notes.Text, "Inspector note persisted without modifying image");
            window.ReturnToBrowsing(false); Key(window, Avalonia.Input.Key.D, RawInputModifiers.Control); Await(window.Library.FlushAsync()); Check(SidecarStore.Read(actual.Path).IsFavorite, "Favorite shortcut writes compatible sidecar");
            Await(window.OpenViewerAsync(actual)); Check(window.ViewerOpen, "Selected image opens viewer");
            Pump(); Check(window.Gallery.ActiveRequestCount == 0, "Gallery decoding remains suspended behind viewer");
            var zoom = window.Viewport.Zoom; Key(window, Avalonia.Input.Key.OemPlus); Check(window.Viewport.Zoom > zoom, "Viewer zoom shortcut");
            Key(window, Avalonia.Input.Key.D0); Near(1, window.Viewport.Zoom, "Viewer fit shortcut");
            Key(window, Avalonia.Input.Key.D1); Near(1, window.Viewport.SourcePixelScale, "Actual-size zoom maps source pixels to screen pixels");
            Key(window, Avalonia.Input.Key.Escape); Check(!window.ViewerOpen && window.Gallery.IsFocused, "Viewer closes back to browsing");
            window.KeyPress(Avalonia.Input.Key.Space, RawInputModifiers.None, PhysicalKey.Space, " "); Pump();
            Check(window.ViewerOpen, "Space opens current selection");
            window.KeyPress(Avalonia.Input.Key.Space, RawInputModifiers.None, PhysicalKey.Space, " "); Pump();
            Check(window.ViewerOpen, "Held Space repeat does not immediately close viewer");
            window.KeyRelease(Avalonia.Input.Key.Space, RawInputModifiers.None, PhysicalKey.Space, " "); Key(window, Avalonia.Input.Key.Space);
            Check(!window.ViewerOpen, "A fresh Space press closes viewer");
            window.Library.State.Preferences.ThumbnailSize = 300; window.Library.State.Preferences.Theme = "Dark rose"; window.Library.Touch(); Pump();
            Check(window.ActualThemeVariant == Avalonia.Styling.ThemeVariant.Dark, "Dark rose applies without restart");
            Await(window.Library.FlushAsync()); Check(store.Load().Preferences.ThumbnailSize == 300, "Slider choice persisted");
            window.Library.State.Preferences.Theme = "Pink"; window.Library.Touch(); window.Gallery.ClearSelection();
            window.SetOffset(0); PumpUntil(() => window.Gallery.ActiveRequestCount == 0);
            Check(window.Gallery.ResidentBitmapBytes <= 80L * 1024 * 1024, "Gallery bitmap memory bounded");
            Check(window.Gallery.ResidentBitmapCount < 100, "Large library does not create a bitmap for every image");
            window.Width = 1440; window.Height = 900; Pump(); window.SetOffset(0);
            using (var frame = window.CaptureRenderedFrame()) { Check(frame is not null, "Headless gallery rendering succeeds"); frame!.Save(Path.Combine(Artifacts, "pink-fit.png"), Avalonia.Media.Imaging.PngBitmapEncoderOptions.Default); }
            window.Library.State.Preferences.Theme = "Dark rose"; window.Library.Touch(); Pump();
            using (var frame = window.CaptureRenderedFrame()) frame!.Save(Path.Combine(Artifacts, "dark-fit.png"), Avalonia.Media.Imaging.PngBitmapEncoderOptions.Default);
            window.ReturnToBrowsing(); window.Page(1); var before = window.GalleryScroll.Offset.Y;
            window.SearchField.Focus(); window.SearchField.Text = "no-match-xyz"; PumpUntil(() => window.Gallery.Items.Length == 0); window.SearchField.Text = ""; Pump();
            Check(window.Gallery.Items.Length == 1069 && window.Gallery.IsFocused, "Zero-result search can clear back to browsing");
            Near(before, window.GalleryScroll.Offset.Y, "Zero-result search retains the previous browsing position");
            var nested = Path.Combine(vault, "nested"); Directory.CreateDirectory(nested); MakeImage(Path.Combine(nested, "nested.png"));
            var controller = new LibraryController(new StateStore(Folder("overlap-state"))); Await(controller.AddFolderAsync(nested)); Await(controller.AddFolderAsync(vault));
            Check(controller.State.Roots.Count == 1 && controller.State.Assets.All(x => PathRules.Comparer.Equals(x.RootPath, vault)), "Adding parent folder replaces nested connection without orphaned asset ownership");
            var edited = controller.State.Assets[0];
            controller.SetAnnotation(edited, edited.Annotation with { Note = "Pending before refresh" });
            Await(controller.RefreshAsync());
            Check(controller.State.Assets.Single(x => x.Path == edited.Path).Annotation.Note == "Pending before refresh", "Refresh retains a note still waiting to autosave");
            var rescan = controller.RefreshAsync();
            controller.SetAnnotation(edited, edited.Annotation with { Note = "Edited during repeated scans" });
            _ = controller.RefreshAsync(); Await(rescan);
            Check(controller.State.Assets.Single(x => x.Path == edited.Path).Annotation.Note == "Edited during repeated scans", "A repeated scan cannot revert an in-progress edit");
            Await(controller.FlushAsync()); Check(SidecarStore.Read(edited.Path).Note == "Edited during repeated scans", "Latest edit survives refresh and flush");
            controller.Dispose();
            var emptyVault = Folder("empty-added-vault");
            var emptyController = new LibraryController(new StateStore(Folder("empty-added-state")));
            Await(emptyController.AddFolderAsync(emptyVault));
            Check(emptyController.State.Roots.Single().FirstIndexedUtc is not null, "An empty connected folder is marked as initially scanned");
            var beforeNewFile = DateTime.UtcNow; var newPath = Path.Combine(emptyVault, "New.png"); MakeImage(newPath);
            File.SetCreationTimeUtc(newPath, DateTime.UnixEpoch.AddDays(20_000));
            Await(emptyController.RefreshAsync());
            Check(emptyController.State.Assets.Single().AddedUtc >= beforeNewFile, "The first later image in an empty folder is a new addition, not an initial import");
            Await(emptyController.FlushAsync()); emptyController.Dispose();
        }
        finally { Await(window.Library.FlushAsync()); window.Close(); PumpUntil(() => !window.IsVisible); window.DisposeResources(); }
        var startup = new MainWindow(store, true); startup.Show(); startup.KeyTextInput("Reference");
        try
        {
            PumpUntil(() => startup.Library.State.Roots.Count > 0 && !startup.Library.Scanning && startup.Gallery.Items.Length > 0);
            Check(startup.SearchField.IsKeyboardFocusWithin && startup.SearchField.Text == "Reference", "Finishing startup does not steal focus from a user who already started searching");
        }
        finally { Await(startup.Library.FlushAsync()); startup.Close(); PumpUntil(() => !startup.IsVisible); }
    }
}

internal static class InterlockedExtensions
{
    public static void Max(ref int location, int value) { int old; do { old = Volatile.Read(ref location); if (old >= value) return; } while (Interlocked.CompareExchange(ref location, value, old) != old); }
}
