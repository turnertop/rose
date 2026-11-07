using Avalonia;
using Avalonia.Controls;
using Avalonia.Threading;
using Rose.Core;

namespace Rose.Desktop;

public sealed class WindowPlacementController : IDisposable
{
    private readonly Window _window;
    private readonly WindowPlacementStore _store;
    private readonly DispatcherTimer _saveDelay = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private WindowPlacement _normal;
    private WindowState _windowedState;
    private bool _opened; private bool _applying; private bool _disposed;
    public event Action<string>? SaveFailed;

    public WindowPlacementController(Window window, string directory)
    {
        _window = window; _store = new(directory);
        _normal = WindowPlacementGeometry.Resolve(_store.Load(), Displays());
        _windowedState = _normal.Maximized ? WindowState.Maximized : WindowState.Normal;
        ApplyBounds(_normal);
        // Set normal restore bounds first, then maximize; Windows keeps Restore Down useful.
        _window.WindowState = _windowedState;
        _window.Opened += OnOpened;
        _window.SizeChanged += OnBoundsChanged;
        _window.PositionChanged += OnBoundsChanged;
        _window.PropertyChanged += OnPropertyChanged;
        _window.ScalingChanged += OnBoundsChanged;
        _window.Screens.Changed += OnScreensChanged;
        _saveDelay.Tick += OnSaveTick;
    }
    private DisplayArea[] Displays() => _window.Screens.All.Select(screen => new DisplayArea(
        screen.WorkingArea.X, screen.WorkingArea.Y, screen.WorkingArea.Width, screen.WorkingArea.Height, screen.Scaling, screen.IsPrimary)).ToArray();
    private DisplayArea? CurrentDisplay()
    {
        var screen = _window.Screens.ScreenFromWindow(_window);
        return screen is null ? null : new(screen.WorkingArea.X, screen.WorkingArea.Y, screen.WorkingArea.Width, screen.WorkingArea.Height, screen.Scaling, screen.IsPrimary);
    }
    private void ApplyBounds(WindowPlacement placement)
    {
        _applying = true;
        try
        {
            var screen = placement.Display!.Value;
            _window.MinWidth = Math.Min(860, Math.Max(1, screen.Width / screen.Scaling - WindowPlacementGeometry.FrameWidth));
            _window.MinHeight = Math.Min(540, Math.Max(1, screen.Height / screen.Scaling - WindowPlacementGeometry.FrameHeight));
            _window.WindowStartupLocation = WindowStartupLocation.Manual;
            _window.Position = new(placement.X, placement.Y);
            // Move first so logical sizing uses the destination monitor's DPI.
            _window.Width = placement.Width; _window.Height = placement.Height;
        }
        finally { _applying = false; }
    }
    private void OnOpened(object? sender, EventArgs e) { _opened = true; ScheduleSave(); }
    private void OnBoundsChanged(object? sender, EventArgs e) => ScheduleSave();
    private void OnPropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property != Window.WindowStateProperty || !_opened || _applying || _disposed) return;
        if (_window.WindowState is WindowState.Normal or WindowState.Maximized) _windowedState = _window.WindowState;
        ScheduleSave();
    }
    private void ScheduleSave()
    {
        if (!_opened || _applying || _disposed) return;
        _saveDelay.Stop(); _saveDelay.Start();
    }
    public WindowPlacement Capture()
    {
        if (_window.WindowState == WindowState.Normal && double.IsFinite(_window.Width) && double.IsFinite(_window.Height) && _window.Width > 0 && _window.Height > 0)
            _normal = _normal with { Width = _window.Width, Height = _window.Height, X = _window.Position.X, Y = _window.Position.Y };
        // Minimized Windows coordinates can be -32000; never use them for restoration.
        if (_window.WindowState != WindowState.Minimized && CurrentDisplay() is { } display) _normal = _normal with { Display = display };
        return _normal with { Maximized = _windowedState == WindowState.Maximized };
    }
    public async Task SaveAsync()
    {
        _saveDelay.Stop();
        var snapshot = Capture();
        try { await _store.SaveAsync(snapshot); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { SaveFailed?.Invoke(e.Message); }
    }
    private async void OnSaveTick(object? sender, EventArgs e)
    {
        if (_disposed) return;
        await SaveAsync();
    }
    private void OnScreensChanged(object? sender, EventArgs e)
    {
        if (!_opened || _applying || _disposed) return;
        _normal = WindowPlacementGeometry.Resolve(Capture(), Displays());
        if (_window.WindowState == WindowState.Normal) ApplyBounds(_normal);
        ScheduleSave();
    }
    public void ToggleFullScreen() => _window.WindowState = _window.WindowState == WindowState.FullScreen ? _windowedState : WindowState.FullScreen;
    public void Dispose()
    {
        _disposed = true; _saveDelay.Stop();
        _window.Opened -= OnOpened;
        _window.SizeChanged -= OnBoundsChanged;
        _window.PositionChanged -= OnBoundsChanged;
        _window.PropertyChanged -= OnPropertyChanged;
        _window.ScalingChanged -= OnBoundsChanged;
        _window.Screens.Changed -= OnScreensChanged;
    }
}
