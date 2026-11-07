using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.GestureRecognizers;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace Rose.Desktop;

public sealed class ImageViewport : Control, IDisposable
{
    private Bitmap? _bitmap;
    private Point? _drag;
    private Vector _pan;
    private double? _pinchStart;
    public double Zoom { get; private set; } = 1;
    public int SourceWidth { get; set; }
    public double SourcePixelScale => _bitmap is null || SourceWidth <= 0 ? 1 :
        _bitmap.Size.Width * FitScale * Zoom * (TopLevel.GetTopLevel(this)?.RenderScaling ?? 1) / SourceWidth;
    public bool ScrollToZoom { get; set; }
    public bool Dark { get; set; }
    public event Action? ZoomChanged;
    public string Message { get; set; } = "Loading image…";
    private double FitScale => _bitmap is null ? 1 : Math.Max(.001, Math.Min((Bounds.Width - 40) / _bitmap.Size.Width, (Bounds.Height - 40) / _bitmap.Size.Height));
    public ImageViewport()
    {
        Focusable = true; ClipToBounds = true;
        AutomationProperties.SetName(this, "Image viewer");
        GestureRecognizers.Add(new PinchGestureRecognizer());
        Pinch += (_, e) => { _pinchStart ??= Zoom; SetZoom(_pinchStart.Value * e.Scale); e.Handled = true; };
        PinchEnded += (_, _) => _pinchStart = null;
        PointerWheelChanged += (_, e) =>
        {
            if (ScrollToZoom || e.KeyModifiers.HasFlag(KeyModifiers.Control)) SetZoom(Zoom * Math.Exp(e.Delta.Y * .15), e.GetPosition(this));
            else { _pan += new Vector(e.Delta.X * 40, e.Delta.Y * 40); ClampPan(); InvalidateVisual(); }
            e.Handled = true;
        };
        PointerPressed += (_, e) =>
        {
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            if (e.ClickCount == 2) { Fit(); e.Handled = true; return; }
            _drag = e.GetPosition(this); e.Pointer.Capture(this); Focus(); e.Handled = true;
        };
        PointerMoved += (_, e) => { if (_drag is not { } previous) return; var point = e.GetPosition(this); _pan += point - previous; _drag = point; ClampPan(); InvalidateVisual(); };
        PointerReleased += (_, e) => { _drag = null; e.Pointer.Capture(null); };
        SizeChanged += (_, _) => { ClampPan(); InvalidateVisual(); };
    }
    public void SetBitmap(Bitmap? bitmap, bool reset)
    {
        var old = _bitmap; _bitmap = bitmap;
        if (reset) { Zoom = 1; _pan = default; }
        old?.Dispose(); InvalidateVisual(); ZoomChanged?.Invoke();
    }
    public void Fit() { Zoom = 1; _pan = default; InvalidateVisual(); ZoomChanged?.Invoke(); }
    public void ActualSize(int sourceWidth)
    {
        if (_bitmap is null) return;
        SetZoom(sourceWidth / ((TopLevel.GetTopLevel(this)?.RenderScaling ?? 1) * _bitmap.Size.Width * FitScale));
    }
    public void SetZoom(double zoom, Point? anchor = null)
    {
        zoom = double.IsFinite(zoom) ? Math.Clamp(zoom, .1, 64) : 1;
        var point = anchor ?? new Point(Bounds.Width / 2, Bounds.Height / 2);
        var center = new Point(Bounds.Width / 2, Bounds.Height / 2);
        var relative = point - center - _pan;
        _pan = point - center - relative * (zoom / Zoom); Zoom = zoom;
        ClampPan(); InvalidateVisual(); ZoomChanged?.Invoke();
    }
    private void ClampPan()
    {
        if (_bitmap is null) return;
        var maximumX = Math.Max(0, (_bitmap.Size.Width * FitScale * Zoom - Bounds.Width) / 2);
        var maximumY = Math.Max(0, (_bitmap.Size.Height * FitScale * Zoom - Bounds.Height) / 2);
        _pan = new(Math.Clamp(_pan.X, -maximumX, maximumX), Math.Clamp(_pan.Y, -maximumY, maximumY));
    }
    public override void Render(DrawingContext context)
    {
        context.DrawRectangle(Brushes.Transparent, null, new Rect(Bounds.Size));
        if (_bitmap is null)
        {
            var text = GalleryControl.Text(Message, Math.Max(1, Bounds.Width - 60), Dark ? Brushes.WhiteSmoke : Brush.Parse("#786170"), 15);
            context.DrawText(text, new Point((Bounds.Width - text.Width) / 2, Bounds.Height / 2)); return;
        }
        var size = _bitmap.Size * (FitScale * Zoom);
        var rect = new Rect((Bounds.Width - size.Width) / 2 + _pan.X, (Bounds.Height - size.Height) / 2 + _pan.Y, size.Width, size.Height);
        context.DrawImage(_bitmap, new Rect(_bitmap.Size), rect);
    }
    public void Dispose() { _bitmap?.Dispose(); _bitmap = null; }
}
