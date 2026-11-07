using System.Globalization;
using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Rose.Core;
using Rose.Imaging;

namespace Rose.Desktop;

/// A single drawing surface: layout uses metadata; only visible cards request or draw bitmaps.
public sealed class GalleryControl : Control, IDisposable
{
    private sealed record Cached(Bitmap Bitmap, long Cost) { public long Used { get; set; } = Environment.TickCount64; }
    private readonly Dictionary<string, Cached> _bitmaps = [];
    private readonly Dictionary<string, CancellationTokenSource> _requests = [];
    private readonly HashSet<string> _failed = [];
    private readonly Dictionary<(string, int, bool), FormattedText> _labels = [];
    private readonly SemaphoreSlim _loadGate = new(2);
    private ImageAsset[] _items = [];
    private GalleryLayout _geometry = new([], [], 0);
    private double _top; private double _viewportHeight = 700; private double _width;
    private DisplayMode _mode; private double _tileSize;
    private bool _disposed; private bool _suspended; private int _anchor = -1; private long _bitmapBytes;
    public ThumbnailService Thumbnails { get; }
    public HashSet<string> Selected { get; } = new(PathRules.Comparer);
    public ImageAsset[] Items => _items;
    public GalleryLayout Geometry => _geometry;
    public int ResidentBitmapCount => _bitmaps.Count;
    public long ResidentBitmapBytes => _bitmapBytes;
    public int ActiveRequestCount => _requests.Count;
    public bool Dark { get; set; }
    public event Action? SelectionChanged;
    public event Action<ImageAsset>? OpenRequested;
    public event Action<ImageAsset, Point>? ImageMenuRequested;
    public static readonly IBrush Accent = Brush.Parse("#EF3585");
    private const long MemoryBudget = 80L * 1024 * 1024;
    public GalleryControl(ThumbnailService thumbnails)
    {
        Thumbnails = thumbnails; Focusable = true; ClipToBounds = false;
        AutomationProperties.SetName(this, "Image gallery");
        AutomationProperties.SetHelpText(this, "Arrow keys select images. Space opens a selection, or scrolls when none is selected. Type to search.");
        PointerPressed += OnPointerPressed;
        PointerMoved += (_, e) =>
        {
            var p = e.GetPosition(this); var i = _geometry.HitTest(p.X, p.Y);
            ToolTip.SetTip(this, i < 0 ? null : _items[i].Name + "\n" + _items[i].Details);
        };
    }
    public void SetItems(ImageAsset[] items, DisplayMode mode, double size)
    {
        _items = items; _mode = mode; _tileSize = size;
        var paths = new HashSet<string>(items.Select(x => x.Path), PathRules.Comparer);
        Selected.RemoveWhere(x => !paths.Contains(x));
        _labels.Clear(); _failed.Clear();
        Recalculate(Math.Max(24, _width)); InvalidateMeasure(); InvalidateVisual();
        Dispatcher.UIThread.Post(UpdateRequests, DispatcherPriority.Background);
    }
    protected override Size MeasureOverride(Size availableSize)
    {
        var width = double.IsFinite(availableSize.Width) ? availableSize.Width : 900;
        if (Math.Abs(_width - width) > .5) Recalculate(width);
        return new(width, _geometry.Height);
    }
    private void Recalculate(double width)
    {
        _width = width; _labels.Clear();
        _geometry = GalleryLayout.Calculate(_items.Select(x => x.AspectRatio).ToArray(), width, _tileSize, _mode);
        Dispatcher.UIThread.Post(UpdateRequests, DispatcherPriority.Background);
    }
    public void SetViewport(double top, double height)
    {
        _top = top; _viewportHeight = Math.Max(1, height); UpdateRequests(); InvalidateVisual();
    }
    private string Key(ImageAsset asset) => ThumbnailService.Key(asset, ThumbnailService.Bucket((_mode == DisplayMode.List ? 64 : _tileSize * 1.5) * (TopLevel.GetTopLevel(this)?.RenderScaling ?? 1)));
    private void UpdateRequests()
    {
        if (_disposed || _suspended) return;
        var visible = _geometry.Visible(_top, _viewportHeight).ToArray();
        var wanted = visible.Select(i => Key(_items[i])).ToHashSet();
        foreach (var key in _requests.Keys.Where(k => !wanted.Contains(k)).ToArray())
        {
            // Cancel can synchronously resume LoadAsync's finally block.
            // Detach the entry first so that continuation cannot remove it twice.
            if (!_requests.Remove(key, out var cancellation)) continue;
            cancellation.Cancel(); cancellation.Dispose();
        }
        foreach (var i in visible)
        {
            var asset = _items[i]; var key = Key(asset);
            if (_bitmaps.ContainsKey(key) || _requests.ContainsKey(key) || _failed.Contains(key)) continue;
            var cancellation = new CancellationTokenSource(); _requests[key] = cancellation;
            _ = LoadAsync(asset, key, cancellation);
        }
    }
    private async Task LoadAsync(ImageAsset asset, string key, CancellationTokenSource cancellation)
    {
        var token = cancellation.Token;
        var entered = false;
        try
        {
            await _loadGate.WaitAsync(token); entered = true;
            var edge = ThumbnailService.Bucket((_mode == DisplayMode.List ? 64 : _tileSize * 1.5) * (TopLevel.GetTopLevel(this)?.RenderScaling ?? 1));
            var data = await Thumbnails.RequestAsync(asset, edge, token);
            // Construct the GPU-facing bitmap off the UI thread as well.
            var bitmap = await Task.Run(() => { token.ThrowIfCancellationRequested(); return new Bitmap(new MemoryStream(data, false)); });
            if (_disposed || token.IsCancellationRequested) { bitmap.Dispose(); return; }
            var cost = (long)bitmap.PixelSize.Width * bitmap.PixelSize.Height * 4;
            _bitmaps[key] = new(bitmap, cost); _bitmapBytes += cost;
            while (_bitmapBytes > MemoryBudget && _bitmaps.Count > 1)
            {
                var victim = _bitmaps.MinBy(x => x.Value.Used);
                _bitmaps.Remove(victim.Key); _bitmapBytes -= victim.Value.Cost; victim.Value.Bitmap.Dispose();
            }
            InvalidateVisual();
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { if (!_disposed && !token.IsCancellationRequested) { _failed.Add(key); InvalidateVisual(); } }
        finally
        {
            if (entered) _loadGate.Release();
            if (_requests.TryGetValue(key, out var current) && ReferenceEquals(current, cancellation)) { _requests.Remove(key); cancellation.Dispose(); }
        }
    }
    public override void Render(DrawingContext context)
    {
        base.Render(context);
        if (_labels.Count > 512) _labels.Clear();
        context.DrawRectangle(Brushes.Transparent, null, new Rect(Bounds.Size));
        var foreground = Dark ? Brushes.WhiteSmoke : Brush.Parse("#342330");
        var muted = Dark ? Brush.Parse("#AE92A4") : Brush.Parse("#927885");
        var placeholder = Dark ? Brush.Parse("#382432") : Brush.Parse("#EAD5E0");
        foreach (var i in _geometry.Visible(_top, _viewportHeight))
        {
            var asset = _items[i]; var frame = _geometry.Frames[i];
            var card = new Rect(frame.X, frame.Y, frame.Width, frame.Height);
            var imageRect = _mode == DisplayMode.List ? new Rect(card.X + 6, card.Y + 4, 64, 64) : new Rect(card.X + 4, card.Y + 2, Math.Max(1, card.Width - 8), Math.Max(1, card.Height - 34));
            var selected = Selected.Contains(asset.Path);
            if (_mode == DisplayMode.List && selected) context.DrawRectangle(Brush.Parse(Dark ? "#593045" : "#F9CDDF"), null, card, 12, 12);
            using (context.PushClip(new RoundedRect(imageRect, 14)))
            {
                context.DrawRectangle(placeholder, null, imageRect);
                if (_bitmaps.TryGetValue(Key(asset), out var cached))
                {
                    cached.Used = Environment.TickCount64;
                    var bitmap = cached.Bitmap;
                    if (_mode == DisplayMode.Fill)
                    {
                        var scale = Math.Max(imageRect.Width / bitmap.Size.Width, imageRect.Height / bitmap.Size.Height);
                        var source = new Rect((bitmap.Size.Width - imageRect.Width / scale) / 2, (bitmap.Size.Height - imageRect.Height / scale) / 2, imageRect.Width / scale, imageRect.Height / scale);
                        context.DrawImage(bitmap, source, imageRect);
                    }
                    else
                    {
                        var scale = Math.Min(imageRect.Width / bitmap.Size.Width, imageRect.Height / bitmap.Size.Height);
                        var destination = new Rect(imageRect.Center.X - bitmap.Size.Width * scale / 2, imageRect.Center.Y - bitmap.Size.Height * scale / 2, bitmap.Size.Width * scale, bitmap.Size.Height * scale);
                        context.DrawImage(bitmap, new Rect(bitmap.Size), destination);
                    }
                }
                else
                {
                    var label = Text(_failed.Contains(Key(asset)) ? "Unavailable" : "▧", Math.Max(1, imageRect.Width - 8), muted, _failed.Contains(Key(asset)) ? 11 : 22);
                    context.DrawText(label, new Point(imageRect.Center.X - label.Width / 2, imageRect.Center.Y - label.Height / 2));
                }
            }
            if (selected) context.DrawRectangle(null, new Pen(Accent, 2), imageRect.Inflate(2), 16, 16);
            var textWidth = _mode == DisplayMode.List ? Math.Max(1, card.Width - 90) : Math.Max(1, card.Width - 10);
            var labelKey = (asset.Path, (int)textWidth, selected);
            if (!_labels.TryGetValue(labelKey, out var title)) _labels[labelKey] = title = Text(asset.Name, textWidth, selected ? Accent : foreground, 12);
            var textPoint = _mode == DisplayMode.List ? new Point(card.X + 82, card.Y + 13) : new Point(card.X + 5, imageRect.Bottom + 8);
            context.DrawText(title, textPoint);
            if (_mode == DisplayMode.List) context.DrawText(Text(asset.Details, textWidth, muted, 11), new Point(textPoint.X, textPoint.Y + 24));
            if (asset.Annotation.IsFavorite) context.DrawText(Text("★", 20, Accent, 14), new Point(imageRect.Right - 22, imageRect.Y + 6));
        }
    }
    public static FormattedText Text(string text, double width, IBrush color, double size) => new(text, CultureInfo.CurrentUICulture,
        FlowDirection.LeftToRight, new Typeface(FontFamily.Default, FontStyle.Normal, FontWeight.Medium), size, color)
        { MaxTextWidth = Math.Max(1, width), MaxLineCount = 1, Trimming = TextTrimming.CharacterEllipsis };
    private void OnPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        Focus(); var p = e.GetPosition(this); var index = _geometry.HitTest(p.X, p.Y);
        if (index < 0) { if (e.KeyModifiers == KeyModifiers.None) ClearSelection(); e.Handled = true; return; }
        var right = e.GetCurrentPoint(this).Properties.IsRightButtonPressed;
        if (!right || !Selected.Contains(_items[index].Path)) Select(index, e.KeyModifiers);
        if (right) ImageMenuRequested?.Invoke(_items[index], p);
        else if (e.ClickCount == 2) OpenRequested?.Invoke(_items[index]);
        e.Handled = true;
    }
    public void Select(int index, KeyModifiers modifiers = KeyModifiers.None)
    {
        if (index < 0 || index >= _items.Length) return;
        if (modifiers.HasFlag(KeyModifiers.Shift) && _anchor >= 0 && _anchor < _items.Length)
        {
            if (!modifiers.HasFlag(KeyModifiers.Control)) Selected.Clear();
            for (var i = Math.Min(index, _anchor); i <= Math.Max(index, _anchor); i++) Selected.Add(_items[i].Path);
        }
        else if (modifiers.HasFlag(KeyModifiers.Control)) { if (!Selected.Add(_items[index].Path)) Selected.Remove(_items[index].Path); _anchor = index; }
        else { Selected.Clear(); Selected.Add(_items[index].Path); _anchor = index; }
        AutomationProperties.SetName(this, Selected.Count == 1 ? "Image gallery, selected " + _items[index].Name : $"Image gallery, {Selected.Count} selected");
        SelectionChanged?.Invoke(); InvalidateVisual();
    }
    public void ClearSelection() { Selected.Clear(); _anchor = -1; SelectionChanged?.Invoke(); InvalidateVisual(); }
    public void SelectAll() { Selected.Clear(); foreach (var asset in _items) Selected.Add(asset.Path); SelectionChanged?.Invoke(); InvalidateVisual(); }
    public int Navigate(int dx, int dy, bool extend)
    {
        var current = Array.FindIndex(_items, x => Selected.Contains(x.Path));
        var next = current < 0 ? 0 : _geometry.Navigate(current, dx, dy);
        Select(next, extend ? KeyModifiers.Shift : KeyModifiers.None); return next;
    }
    public void SuspendRequests()
    {
        _suspended = true;
        var pending = _requests.Values.ToArray();
        _requests.Clear();
        foreach (var request in pending) { request.Cancel(); request.Dispose(); }
    }
    public void ResumeRequests() { _suspended = false; UpdateRequests(); }
    public void Dispose()
    {
        _disposed = true; SuspendRequests();
        foreach (var value in _bitmaps.Values) value.Bitmap.Dispose(); _bitmaps.Clear(); _bitmapBytes = 0;
    }
}
