using System.Text.Json;
using System.Text.Json.Nodes;
using Avalonia;
using Rose.Core;
using Rose.Desktop;
using Rose.Imaging;

internal static partial class Checks
{
    private static void AddedDates()
    {
        var old = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var arrival = old.AddDays(1); var observed = old.AddDays(2);
        Check(AddedDate.Resolve(null, arrival, old, observed, true) == arrival, "Directory arrival wins over original creation");
        Check(AddedDate.Resolve(old, arrival, observed, observed, false) == old, "Known additions retain their recorded date");
        Check(AddedDate.Resolve(null, null, old, observed, true) == old, "Existing images bootstrap from local creation");
        Check(AddedDate.Resolve(null, null, old, observed, false) == observed, "New discoveries ignore inherited creation dates");
        Check(AddedDate.Resolve(null, null, null, observed, true) == observed, "Missing dates fall back to observation");
        Check(AddedDate.Resolve(null, observed.AddDays(1), DateTime.MinValue, observed, true) == observed, "Future and unavailable filesystem dates fall back safely");
        Check(AddedDate.Resolve(observed, null, old, old, false) == observed, "Known dates survive backward clock adjustments");

        var folder = Folder("added-dates");
        var older = Asset(Path.Combine(folder, "A.png"), folder) with { AddedUtc = old, CreatedUtc = observed, ModifiedUtc = observed };
        var newer = Asset(Path.Combine(folder, "Z.png"), folder) with { AddedUtc = arrival, CreatedUtc = old, ModifiedUtc = old };
        var state = new LibraryState { Preferences = new() { Sort = AssetSort.Added, Ascending = false } };
        state.Assets.AddRange([older, newer]);
        Check(LibraryQuery.Filter(state, Location.All, "").SequenceEqual([newer, older]), "Date added order is independent of name, creation, and modification");
        state.Preferences.Ascending = true;
        Check(LibraryQuery.Filter(state, Location.All, "").SequenceEqual([older, newer]), "Date added supports oldest first");
        state.Preferences.Ascending = false;
        var tie = older with { Path = Path.Combine(folder, "B.png") };
        state.Assets.Clear(); state.Assets.AddRange([tie, older]);
        Check(LibraryQuery.Filter(state, Location.All, "").SequenceEqual([older, tie]), "Equal dates have deterministic path ordering");
        state.Assets.Clear(); state.Assets.AddRange([older, newer]); state.RecentPaths.AddRange([older.Path, newer.Path]);
        Check(LibraryQuery.Filter(state, new(LocationKind.Recent), "").SequenceEqual([older, newer]), "Recently viewed keeps its viewing order");
        Check((int)AssetSort.Modified == 1 && (int)AssetSort.Created == 2 && (int)AssetSort.Size == 3 && (int)AssetSort.Dimensions == 4,
            "Existing numeric sort IDs remain compatible");
        var legacy = older with { AddedUtc = null, CreatedUtc = arrival };
        Check(legacy.DateAddedUtc == arrival, "An old warm index has a creation-date estimate before scanning");

        var path = Path.Combine(folder, "Existing.png"); MakeImage(path);
        File.SetCreationTimeUtc(path, old);
        var root = new VaultRoot(folder);
        var first = LibraryIndexer.Scan(root, [], ImageDecoder.Metadata);
        var existing = first.Assets.Single();
        Check(existing.AddedUtc == File.GetCreationTimeUtc(path), "An initial scan uses local creation rather than import time");
        root = root with { FirstIndexedUtc = DateTime.UtcNow };
        existing = existing with { AddedUtc = arrival };
        var second = LibraryIndexer.Scan(root, [existing], ImageDecoder.Metadata);
        Check(second.Assets.Single().AddedUtc == arrival, "Unchanged metadata reuse retains the addition date");
        MakeImage(path, 91, 47);
        var edited = LibraryIndexer.Scan(root, second.Assets, ImageDecoder.Metadata);
        Check(edited.Assets.Single().Width == 91 && edited.Assets.Single().AddedUtc == arrival,
            "Content edits update dimensions without resetting Date added");
        var migrated = LibraryIndexer.Scan(root, [edited.Assets.Single() with { AddedUtc = null }], ImageDecoder.Metadata);
        Check(migrated.Assets.Single().AddedUtc == File.GetCreationTimeUtc(path), "Unchanged legacy entries are migrated from creation dates");
        var addedPath = Path.Combine(folder, "New.png"); MakeImage(addedPath); File.SetCreationTimeUtc(addedPath, old);
        var discoveredAt = DateTime.UtcNow;
        var discovered = LibraryIndexer.Scan(root, edited.Assets, ImageDecoder.Metadata, observedUtc: discoveredAt);
        Check(discovered.Assets.Single(x => x.Path == addedPath).AddedUtc == discoveredAt, "A newly discovered old-dated file records discovery time");

        var store = new StateStore(Folder("added-state"));
        var saved = new LibraryState { Preferences = new() { Sort = AssetSort.Added, Ascending = true } };
        saved.Roots.Add(root); saved.Assets.AddRange(discovered.Assets);
        store.SaveAsync(saved).GetAwaiter().GetResult(); var loaded = store.Load();
        Check(loaded.Roots.Single().FirstIndexedUtc == root.FirstIndexedUtc &&
            loaded.Assets.Select(x => (x.Path, x.AddedUtc)).SequenceEqual(saved.Assets.Select(x => (x.Path, x.AddedUtc))),
            "Arrival dates and first-scan markers survive restart");
        Check(loaded.Preferences.Sort == AssetSort.Added && loaded.Preferences.Ascending, "A manually chosen oldest-first added sort survives restart");
        var json = JsonSerializer.SerializeToNode(saved)!.AsObject();
        foreach (var node in json["Assets"]!.AsArray()) node!.AsObject().Remove("AddedUtc");
        foreach (var node in json["Roots"]!.AsArray()) node!.AsObject().Remove("FirstIndexedUtc");
        json["Preferences"]!["Sort"] = 3;
        File.WriteAllText(store.StatePath, json.ToJsonString()); var previous = store.Load();
        Check(previous.Assets.Count == saved.Assets.Count && previous.Assets.All(x => x.AddedUtc is null) && previous.Roots.Single().FirstIndexedUtc is null,
            "Pre-feature library JSON loads without losing assets");
        Check(previous.Preferences.Sort == AssetSort.Size, "A pre-feature saved File size preference retains its meaning");
        var offline = LibraryIndexer.Scan(new(folder + "-missing"), discovered.Assets, ImageDecoder.Metadata);
        Check(!offline.Available && offline.Assets.SequenceEqual(discovered.Assets), "Offline libraries retain their added dates");
    }

    private static void GalleryRequestCancellation()
    {
        var folder = Folder("gallery-cancel"); var seed = Path.Combine(folder, "0.png"); MakeImage(seed);
        var assets = new List<ImageAsset>();
        for (var i = 0; i < 60; i++)
        {
            var path = Path.Combine(folder, i + ".png");
            if (i != 0) File.Copy(seed, path);
            assets.Add(Asset(path, folder));
        }
        using var release = new ManualResetEventSlim(false);
        using var service = new ThumbnailService(Path.Combine(folder, "cache"), decode: (path, edge, token) =>
        {
            release.Wait(token);
            return ImageDecoder.Decode(path, edge, token);
        });
        using var gallery = new GalleryControl(service);
        try
        {
            gallery.SetItems(assets.ToArray(), DisplayMode.Fit, 190);
            gallery.Measure(new Size(900, double.PositiveInfinity));
            gallery.SetViewport(0, 700);
            Check(gallery.ActiveRequestCount > 2, "The cancellation fixture queues requests behind blocked decodes");
            gallery.SetViewport(gallery.Geometry.Height - 400, 700);
            Check(gallery.ActiveRequestCount > 0, "Moving the viewport cancels obsolete queued requests safely");
            gallery.SuspendRequests();
            Check(gallery.ActiveRequestCount == 0, "Suspending a gallery safely cancels queued and active requests");
            gallery.ResumeRequests();
            Check(gallery.ActiveRequestCount > 0, "A suspended gallery can request its new viewport again");
            gallery.SetItems(assets.AsEnumerable().Reverse().ToArray(), DisplayMode.Fit, 190);
            gallery.SetViewport(0, 700);
            gallery.SuspendRequests();
            Check(gallery.ActiveRequestCount == 0, "Reordering and suspending while decode is blocked remains safe");
        }
        finally { release.Set(); gallery.SuspendRequests(); }
    }
}
