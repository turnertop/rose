namespace Rose.Core;

public readonly record struct TileRect(double X, double Y, double Width, double Height)
{
    public double Bottom => Y + Height;
    public bool Contains(double x, double y) => x >= X && x < X + Width && y >= Y && y < Bottom;
}
public readonly record struct GalleryRow(int Start, int End, double Y, double Height);
public sealed record GalleryLayout(TileRect[] Frames, GalleryRow[] Rows, double Height)
{
    public IEnumerable<int> Visible(double top, double height)
    {
        if (height <= 0) yield break;
        var low = 0; var high = Rows.Length;
        while (low < high) { var mid = (low + high) / 2; if (Rows[mid].Y + Rows[mid].Height <= top) low = mid + 1; else high = mid; }
        for (var r = low; r < Rows.Length && Rows[r].Y < top + height; r++)
            for (var i = Rows[r].Start; i < Rows[r].End; i++) yield return i;
    }
    public int HitTest(double x, double y) => Visible(y, 1).FirstOrDefault(i => Frames[i].Contains(x, y), -1);
    public int Navigate(int current, int dx, int dy)
    {
        if (Frames.Length == 0) return -1;
        current = Math.Clamp(current, 0, Frames.Length - 1);
        if (dy == 0) return Math.Clamp(current + dx, 0, Frames.Length - 1);
        var row = Array.FindIndex(Rows, r => current >= r.Start && current < r.End);
        var target = Math.Clamp(row + dy, 0, Rows.Length - 1);
        var x = Frames[current].X + Frames[current].Width / 2;
        return Enumerable.Range(Rows[target].Start, Rows[target].End - Rows[target].Start)
            .MinBy(i => Math.Abs(Frames[i].X + Frames[i].Width / 2 - x));
    }
    public static GalleryLayout Calculate(IReadOnlyList<double> input, double width, double target, DisplayMode mode)
    {
        if (input.Count == 0 || !double.IsFinite(width) || !double.IsFinite(target) || width < 24 || target <= 0) return new([], [], 0);
        target = Math.Clamp(target, 50, 1000);
        const double gap = 12, inset = 4, padding = 8, extra = 34;
        var available = width - inset * 2;
        var frames = new List<TileRect>(input.Count); var rows = new List<GalleryRow>(); var y = inset;
        if (mode != DisplayMode.Fit)
        {
            var columns = mode == DisplayMode.List ? 1 : Math.Max(1, (int)((available + gap) / (target + gap)));
            var cellWidth = (available - (columns - 1) * gap) / columns;
            var cellHeight = mode == DisplayMode.List ? 72 : cellWidth * 1.14 + extra;
            for (var start = 0; start < input.Count; start += columns)
            {
                var end = Math.Min(input.Count, start + columns);
                for (var i = start; i < end; i++) frames.Add(new(inset + (i - start) * (cellWidth + gap), y, cellWidth, cellHeight));
                rows.Add(new(start, end, y, cellHeight)); y += cellHeight + gap;
            }
        }
        else
        {
            var ratios = input.Select(x => double.IsFinite(x) && x > 0 ? Math.Clamp(x, .02, 50) : 1).ToArray();
            double FitHeight(int count, double sum) => (available - count * padding - (count - 1) * gap) / sum;
            var start = 0;
            while (start < ratios.Length)
            {
                var end = start; var sum = 0d; var height = target;
                while (end < ratios.Length)
                {
                    sum += ratios[end++]; var count = end - start;
                    var full = FitHeight(count, sum);
                    if (full <= target)
                    {
                        if (count > 1)
                        {
                            var previous = FitHeight(count - 1, sum - ratios[end - 1]);
                            if (full <= 0 || Math.Abs(previous - target) < Math.Abs(full - target)) { sum -= ratios[--end]; height = previous; break; }
                        }
                        height = full; break;
                    }
                    if (end == ratios.Length) height = Math.Min(target, full);
                }
                var x = inset;
                for (var i = start; i < end; i++) { var w = ratios[i] * height + padding; frames.Add(new(x, y, w, height + extra)); x += w + gap; }
                rows.Add(new(start, end, y, height + extra)); y += height + extra + gap; start = end;
            }
        }
        return new(frames.ToArray(), rows.ToArray(), y - gap + inset);
    }
}
