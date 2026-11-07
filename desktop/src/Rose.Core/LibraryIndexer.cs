namespace Rose.Core;

public sealed record ImageMetadata(int Width, int Height);
public sealed record ScanResult(ImageAsset[] Assets, string[] Directories, bool Available, int Skipped);

public static class LibraryIndexer
{
    public static readonly HashSet<string> Extensions = new(StringComparer.OrdinalIgnoreCase)
        { ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff", ".ico", ".avif", ".heic", ".heif", ".jxl" };
    public static ScanResult Scan(VaultRoot root, IEnumerable<ImageAsset> cached,
        Func<string, ImageMetadata?> metadata, CancellationToken cancellation = default, DateTime? observedUtc = null)
    {
        var observed = observedUtc ?? DateTime.UtcNow;
        var previous = cached.GroupBy(x => x.Path, PathRules.Comparer).ToDictionary(x => x.Key, x => x.First(), PathRules.Comparer);
        if (!Directory.Exists(root.Path)) return new(previous.Values.ToArray(), [], false, 0);
        var directories = new List<string>(); var assets = new List<ImageAsset>(); var skipped = 0;
        var stack = new Stack<string>(); stack.Push(root.Path);
        while (stack.TryPop(out var folder))
        {
            cancellation.ThrowIfCancellationRequested();
            string[] entries;
            try { entries = Directory.GetFileSystemEntries(folder); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                skipped++;
                assets.AddRange(previous.Values.Where(x => PathRules.IsWithin(x.Path, folder)));
                if (PathRules.Comparer.Equals(folder, root.Path)) return new(previous.Values.ToArray(), [], false, skipped);
                continue;
            }
            directories.Add(folder);
            foreach (var path in entries)
            {
                cancellation.ThrowIfCancellationRequested();
                try
                {
                    var attributes = File.GetAttributes(path);
                    if ((attributes & (FileAttributes.Hidden | FileAttributes.ReparsePoint)) != 0) continue;
                    if ((attributes & FileAttributes.Directory) != 0) { stack.Push(path); continue; }
                    if (!Extensions.Contains(Path.GetExtension(path))) continue;
                    var info = new FileInfo(path);
                    ImageMetadata? size;
                    if (previous.TryGetValue(path, out var old) && old.ByteSize == info.Length && old.ModifiedUtc == info.LastWriteTimeUtc)
                        size = new(old.Width, old.Height);
                    else size = metadata(path);
                    if (size is null || size.Width <= 0 || size.Height <= 0) { skipped++; continue; }
                    Annotation annotation;
                    try { annotation = SidecarStore.Read(path); }
                    catch (Exception e) when (e is IOException or UnauthorizedAccessException)
                    { annotation = old?.Annotation ?? Annotation.Empty; skipped++; }
                    var added = AddedDate.Resolve(old?.AddedUtc, null, info.CreationTimeUtc, observed,
                        isExisting: old is not null || root.FirstIndexedUtc is null);
                    assets.Add(new(path, root.Path, Path.GetRelativePath(root.Path, path), info.Length,
                        info.LastWriteTimeUtc, info.CreationTimeUtc, size.Width, size.Height, annotation) { AddedUtc = added });
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { skipped++; }
            }
        }
        return new(assets.ToArray(), directories.ToArray(), true, skipped);
    }
}
