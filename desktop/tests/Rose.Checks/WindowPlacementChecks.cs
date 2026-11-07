using Avalonia;
using Avalonia.Controls;
using Rose.Core;
using Rose.Desktop;

internal static partial class Checks
{
    private static void WindowPlacementGeometryChecks()
    {
        var primary = new DisplayArea(0, 0, 1920, 1040, 1, true);
        var first = WindowPlacementGeometry.Resolve(null, [primary]);
        Near(1713.6, first.Width, "First launch uses 90% of available client width");
        Near(892.8, first.Height, "First launch uses 90% of available client height");
        Check(first.X == 95 && first.Y == 49 && !first.Maximized, "First launch centered without forcing maximization");
        var custom = new WindowPlacement(1100, 700, 120, 95, true, primary);
        var restored = WindowPlacementGeometry.Resolve(custom, [primary]);
        Check(restored == custom, "Valid saved size, position, and maximization restored exactly");
        var left = new DisplayArea(-1920, -200, 1920, 1080, 1);
        var negative = new WindowPlacement(1000, 700, -1600, -100, false, left);
        Check(WindowPlacementGeometry.Resolve(negative, [primary, left]) == negative, "Negative monitor coordinates are valid");
        var disconnected = custom with { X = 2300, Y = 100, Display = new(1920, 0, 2560, 1400, 1.5) };
        var recovered = WindowPlacementGeometry.Resolve(disconnected, [primary]);
        Check(recovered.Display == primary && recovered.Maximized, "Disconnected-monitor fallback preserves maximization");
        Check(recovered.X == 402 && recovered.Y == 146, "Disconnected window recenters on the remaining screen");
        var oversized = WindowPlacementGeometry.Resolve(new(5000, 4000, 1800, 950, true, primary), [primary]);
        Near(1904, oversized.Width, "Oversized saved width fits current work area");
        Near(992, oversized.Height, "Oversized saved height reserves taskbar and title-bar space");
        Check(oversized.X == 0 && oversized.Y == 0 && oversized.Maximized, "Oversized restore bounds remain accessible");
        var scaled = new DisplayArea(1920, 0, 3840, 2080, 2);
        var scaledFirst = WindowPlacementGeometry.Resolve(null, [scaled]);
        Near(first.Width, scaledFirst.Width, "First-launch client size uses logical units at 200% DPI");
        Check(scaledFirst.X == 2110 && scaledFirst.Y == 99, "High-DPI position uses physical screen pixels");
        var tiny = new DisplayArea(0, 0, 1280, 720, 1.5, true);
        var smallRestore = WindowPlacementGeometry.Resolve(custom, [tiny]);
        Check((smallRestore.Width + WindowPlacementGeometry.FrameWidth) * tiny.Scaling <= tiny.Width + .01 &&
              (smallRestore.Height + WindowPlacementGeometry.FrameHeight) * tiny.Scaling <= tiny.Height + .01, "Small high-DPI display does not inherit an unusable fixed minimum");
        var dpiChanged = WindowPlacementGeometry.Resolve(custom, [primary with { Scaling = 1.5 }]);
        Check(dpiChanged.Display?.Scaling == 1.5 && dpiChanged.Width <= 1264 && dpiChanged.Height <= 645.34, "Changed DPI clamps stale logical bounds");
        var bad = WindowPlacementGeometry.Resolve(new(double.NaN, -1, int.MaxValue, int.MinValue, true), [primary]);
        Check(bad == first, "Invalid saved dimensions fall back to the first-launch layout");
        Check(WindowPlacementGeometry.Resolve(null, []).IsUsable, "Missing screen information has a finite fallback");
        var store = new WindowPlacementStore(Folder("window-settings"));
        Check(store.Load() is null, "Missing placement treated as first launch");
        store.SaveAsync(custom).GetAwaiter().GetResult();
        Check(store.Load() == custom, "Placement survives a storage round-trip");
        File.WriteAllText(store.FilePath, "{ malformed");
        Check(store.Load() is null && File.ReadAllText(store.FilePath) == "{ malformed", "Malformed placement cannot block launch or change the image index");
        File.WriteAllText(store.FilePath, "{}");
        Check(store.Load() is null, "Missing placement fields do not open an invisible window");
    }
    private static DisplayArea[] DisplayAreas(Window window) => window.Screens.All.Select(x => new DisplayArea(x.WorkingArea.X, x.WorkingArea.Y, x.WorkingArea.Width, x.WorkingArea.Height, x.Scaling, x.IsPrimary)).ToArray();
    private static void CloseWindow(MainWindow window)
    {
        window.Close(); PumpUntil(() => !window.IsVisible); window.DisposeResources();
    }
    private static void WindowPlacementUiChecks()
    {
        var directory = Folder("window-reopen"); var store = new StateStore(directory); var placementStore = new WindowPlacementStore(directory);
        var window = new MainWindow(store, false);
        var first = WindowPlacementGeometry.Resolve(null, DisplayAreas(window));
        Near(first.Width, window.Width, "Large width applied before the first window is shown");
        Near(first.Height, window.Height, "Large height applied before the first window is shown");
        Check(window.Position == new PixelPoint(first.X, first.Y), "Centered position applied before Show");
        window.Show(); Pump();
        var custom = WindowPlacementGeometry.Resolve(first with { Width = Math.Min(first.Width, 1100), Height = Math.Min(first.Height, 700), X = first.X + 10, Y = first.Y + 10 }, DisplayAreas(window));
        try
        {
            window.Width = custom.Width; window.Height = custom.Height; window.Position = new(custom.X, custom.Y); Pump();
            Await(window.Placement.SaveAsync());
            var normal = placementStore.Load()!;
            Check(!normal.Maximized && normal.Width == custom.Width && normal.Height == custom.Height && normal.X == custom.X && normal.Y == custom.Y, "Normal bounds saved independently of the library index");
            window.WindowState = WindowState.Maximized; Pump();
            // A native maximization can resize/move the live window; these must not become restore bounds.
            window.Width = custom.Width + 300; window.Height = custom.Height + 200; Pump();
            Await(window.Placement.SaveAsync());
            var maximized = placementStore.Load()!;
            Check(maximized.Maximized, "Maximized state saved");
            Check(maximized.Width == normal.Width && maximized.Height == normal.Height && maximized.X == normal.X && maximized.Y == normal.Y, "Maximized dimensions never overwrite normal restore bounds");
        }
        finally { CloseWindow(window); }

        var reopened = new MainWindow(new StateStore(directory), false);
        try
        {
            Check(reopened.WindowState == WindowState.Maximized, "A maximized session reopens maximized before Show");
            Near(custom.Width, reopened.Width, "Restore Down retains the previous normal width");
            Near(custom.Height, reopened.Height, "Restore Down retains the previous normal height");
            reopened.Show(); Pump();
            reopened.Placement.ToggleFullScreen(); Pump();
            Check(reopened.WindowState == WindowState.FullScreen, "Viewer can still enter fullscreen");
            Await(reopened.Placement.SaveAsync());
            Check(placementStore.Load()!.Maximized, "Closing fullscreen will retain the preceding maximized state");
            reopened.Placement.ToggleFullScreen(); Pump();
            Check(reopened.WindowState == WindowState.Maximized, "Leaving fullscreen returns to the preceding maximized state");
            reopened.WindowState = WindowState.Minimized; reopened.Position = new(-32000, -32000); Pump();
            Await(reopened.Placement.SaveAsync());
            var minimized = placementStore.Load()!;
            Check(minimized.Maximized && minimized.X == custom.X && minimized.Y == custom.Y, "Minimized coordinates and state are not persisted as startup placement");
        }
        finally { CloseWindow(reopened); }

        var restored = new MainWindow(new StateStore(directory), false);
        try
        {
            Check(restored.WindowState == WindowState.Maximized, "Closing a minimized maximized session still reopens maximized");
            restored.Show(); restored.WindowState = WindowState.Normal; Pump();
            restored.Width = custom.Width; restored.Height = custom.Height; restored.Position = new(custom.X, custom.Y); Pump();
            Await(restored.Placement.SaveAsync());
            Check(!placementStore.Load()!.Maximized, "Restore Down switches future startup back to normal");
            restored.Placement.ToggleFullScreen(); Pump();
            Await(restored.Placement.SaveAsync());
            Check(!placementStore.Load()!.Maximized, "Fullscreen from a normal window does not become a startup fullscreen preference");
        }
        finally { CloseWindow(restored); }
        var normalAgain = new MainWindow(new StateStore(directory), false);
        try
        {
            Check(normalAgain.WindowState == WindowState.Normal, "A normal session reopens normally after viewer fullscreen");
            Near(custom.Width, normalAgain.Width, "Normal width survives another reopen");
            Check(normalAgain.Position == new PixelPoint(custom.X, custom.Y), "Normal position survives another reopen");
        }
        finally { normalAgain.Show(); CloseWindow(normalAgain); }
    }
}
