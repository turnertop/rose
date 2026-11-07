using System.Globalization;

namespace Rose.Core;

public static class LibraryQuery
{
    public static ImageAsset[] Filter(LibraryState state, Location location, string search)
    {
        var prefs = state.Preferences;
        var recent = new HashSet<string>(state.RecentPaths, PathRules.Comparer);
        var collection = new HashSet<string>(state.Collections.FirstOrDefault(x => x.Id == location.Value)?.Paths ?? [], PathRules.Comparer);
        var terms = search.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var result = state.Assets.Where(asset =>
        {
            var included = location.Kind switch
            {
                LocationKind.Favorites => asset.Annotation.IsFavorite,
                LocationKind.Recent => recent.Contains(asset.Path),
                LocationKind.Collection => collection.Contains(asset.Path),
                LocationKind.Tag => asset.Annotation.Tags.Contains(location.Value, StringComparer.OrdinalIgnoreCase),
                LocationKind.Folder => PathRules.Comparer.Equals(asset.FolderPath, location.Value) ||
                    (prefs.IncludeSubfolders && PathRules.IsWithin(asset.FolderPath, location.Value)),
                _ => true
            };
            if (!included) return false;
            var haystack = asset.Name + " " + asset.RelativePath + " " + asset.Extension + " " + string.Join(' ', asset.Annotation.Tags);
            return terms.All(x => haystack.Contains(x, StringComparison.OrdinalIgnoreCase));
        }).ToArray();
        var order = state.RecentPaths.Select((path, i) => (path, i)).GroupBy(x => x.path, PathRules.Comparer).ToDictionary(x => x.Key, x => x.First().i, PathRules.Comparer);
        Array.Sort(result, (a, b) =>
        {
            if (location.Kind == LocationKind.Recent) return order.GetValueOrDefault(a.Path, int.MaxValue).CompareTo(order.GetValueOrDefault(b.Path, int.MaxValue));
            var comparison = prefs.Sort switch
            {
                AssetSort.Added => a.DateAddedUtc.CompareTo(b.DateAddedUtc),
                AssetSort.Modified => a.ModifiedUtc.CompareTo(b.ModifiedUtc),
                AssetSort.Created => a.CreatedUtc.CompareTo(b.CreatedUtc),
                AssetSort.Size => a.ByteSize.CompareTo(b.ByteSize),
                AssetSort.Dimensions => ((long)a.Width * a.Height).CompareTo((long)b.Width * b.Height),
                _ => NaturalCompare(a.Name, b.Name)
            };
            return comparison == 0 ? PathRules.Comparer.Compare(a.Path, b.Path) : prefs.Ascending ? comparison : -comparison;
        });
        return result;
    }

    public static int NaturalCompare(string a, string b)
    {
        var i = 0; var j = 0;
        while (i < a.Length && j < b.Length)
        {
            if (char.IsAsciiDigit(a[i]) && char.IsAsciiDigit(b[j]))
            {
                var startI = i; var startJ = j;
                while (i < a.Length && char.IsAsciiDigit(a[i])) i++;
                while (j < b.Length && char.IsAsciiDigit(b[j])) j++;
                var aa = a.AsSpan(startI, i - startI).TrimStart('0');
                var bb = b.AsSpan(startJ, j - startJ).TrimStart('0');
                var c = aa.Length.CompareTo(bb.Length);
                if (c == 0) c = aa.CompareTo(bb, StringComparison.Ordinal);
                if (c != 0) return c;
            }
            else
            {
                var c = char.ToUpperInvariant(a[i++]).CompareTo(char.ToUpperInvariant(b[j++]));
                if (c != 0) return c;
            }
        }
        return (a.Length - i).CompareTo(b.Length - j);
    }
}
