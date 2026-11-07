using System.Text;
using System.Text.Json;

namespace Rose.Core;

public static class SidecarStore
{
    public static string PathFor(string imagePath) => imagePath + ".md";
    public static Annotation Read(string imagePath)
    {
        try { return Decode(File.ReadAllText(PathFor(imagePath), Encoding.UTF8)); }
        catch (FileNotFoundException) { return Annotation.Empty; }
        catch (DirectoryNotFoundException) { return Annotation.Empty; }
    }
    public static Annotation Decode(string text)
    {
        var (header, body) = Split(text);
        string[] tags = []; var favorite = false;
        for (var i = 0; i < header.Length; i++)
        {
            var line = header[i];
            if (line.StartsWith("favorite:", StringComparison.Ordinal)) favorite = Value(line) == "true";
            if (!line.StartsWith("tags:", StringComparison.Ordinal)) continue;
            var raw = Value(line);
            try { tags = JsonSerializer.Deserialize<string[]>(raw) ?? []; }
            catch (JsonException)
            {
                if (raw.Length == 0)
                    tags = header.Skip(i + 1).TakeWhile(Indented).Select(x => x.Trim()).Where(x => x.StartsWith("- "))
                        .Select(x => Scalar(x[2..])).Where(x => x.Length > 0).ToArray();
                else tags = raw.Trim('[', ']').Split(',').Select(Scalar).Where(x => x.Length > 0).ToArray();
            }
        }
        return new(tags, body, favorite);
    }
    public static string Encode(Annotation annotation, string existing = "")
    {
        var (header, _) = Split(existing);
        List<string> retained = []; var skip = false;
        foreach (var line in header)
        {
            if (line.StartsWith("tags:") || line.StartsWith("favorite:") || line.StartsWith("rose:")) { skip = true; continue; }
            if (skip && Indented(line)) continue;
            skip = false; retained.Add(line);
        }
        var lines = new[] { "rose: 1", $"favorite: {annotation.IsFavorite.ToString().ToLowerInvariant()}", $"tags: {JsonSerializer.Serialize(annotation.Tags)}" }.Concat(retained);
        return "---\n" + string.Join('\n', lines) + "\n---\n" + annotation.Note;
    }
    public static void Write(string imagePath, Annotation annotation)
    {
        var path = PathFor(imagePath);
        // Read failures must propagate: never replace an existing unreadable sidecar with an empty note.
        string existing;
        try { existing = File.ReadAllText(path, Encoding.UTF8); }
        catch (FileNotFoundException) { existing = ""; }
        AtomicFile.Write(path, Encode(annotation, existing));
    }
    private static (string[] Header, string Body) Split(string text)
    {
        text = text.Replace("\r\n", "\n");
        if (text.StartsWith("---\n---\n")) return ([], text[8..]);
        var end = text.StartsWith("---\n") ? text.IndexOf("\n---\n", 3, StringComparison.Ordinal) : -1;
        return end < 0 ? ([], text) : (text[4..end].Split('\n'), text[(end + 5)..]);
    }
    private static bool Indented(string line) => line.StartsWith(' ') || line.StartsWith('\t');
    private static string Value(string line) => line[(line.IndexOf(':') + 1)..].Trim();
    private static string Scalar(string value)
    {
        value = value.Trim();
        if (value.StartsWith('"')) { try { return JsonSerializer.Deserialize<string>(value) ?? ""; } catch (JsonException) { } }
        return value.Length >= 2 && value.StartsWith('\'') && value.EndsWith('\'') ? value[1..^1].Replace("''", "'") : value;
    }
}

public static class AtomicFile
{
    public static void Write(string path, string contents)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                var bytes = new UTF8Encoding(false).GetBytes(contents);
                stream.Write(bytes); stream.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

/// Coalesces edits by file; a failed write remains pending for retry and prevents a silent quit.
public sealed class AnnotationWrites
{
    private readonly Dictionary<string, Annotation> _pending = new(PathRules.Comparer);
    private readonly SemaphoreSlim _gate = new(1);
    public int PendingCount { get { lock (_pending) return _pending.Count; } }
    public Dictionary<string, Annotation> Snapshot() { lock (_pending) return new(_pending, PathRules.Comparer); }
    public void Queue(string path, Annotation value) { lock (_pending) _pending[path] = value; }
    public async Task FlushAsync()
    {
        await _gate.WaitAsync();
        try
        {
            while (true)
            {
                KeyValuePair<string, Annotation> item;
                lock (_pending) { if (_pending.Count == 0) return; item = _pending.First(); }
                await Task.Run(() => SidecarStore.Write(item.Key, item.Value));
                lock (_pending)
                    if (_pending.TryGetValue(item.Key, out var current) && ReferenceEquals(current, item.Value)) _pending.Remove(item.Key);
            }
        }
        finally { _gate.Release(); }
    }
}
