using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Rose.Core;
using Rose.Desktop;

internal static partial class Checks
{
    private static void ViewerMenu()
    {
        var vault = Folder("viewer-menu-images");
        var wide = Path.Combine(vault, "1-wide.png"); var tall = Path.Combine(vault, "2-tall.png");
        MakeImage(wide, 5000, 20); MakeImage(tall, 80, 140);
        var original = File.ReadAllBytes(wide);
        var first = Asset(wide, vault, 5000, 20); var second = Asset(tall, vault, 80, 140);
        ImageAsset? current = first;
        var copied = new List<string>(); var revealed = new List<string>();
        var testMenu = ViewerImageMenu.Create(() => current, a => { copied.Add(a.Path); return Task.CompletedTask; }, a => revealed.Add(a.Path));
        var actions = testMenu.Items.OfType<MenuItem>().ToArray();
        Check(actions.Select(x => x.Header).SequenceEqual(new[] { "Copy Image", "Show in Explorer" }), "The viewer menu offers image copy and reveal");
        actions[0].RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); actions[1].RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        Check(copied.Single() == wide && revealed.Single() == wide, "Commands receive the opened image");
        current = second;
        actions[0].RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); actions[1].RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        Check(copied.Last() == tall && revealed.Last() == tall, "An existing menu follows image navigation");
        current = null;
        actions[0].RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); actions[1].RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        Check(copied.Count == 2 && revealed.Count == 2, "Closed-viewer commands cannot act on a stale image");

        var state = new LibraryState(); state.Roots.Add(new(vault)); state.Assets.AddRange([first, second]);
        var store = new StateStore(Folder("viewer-menu-state")); Await(store.SaveAsync(state));
        var window = new MainWindow(store, false); window.Show(); Await(window.Library.InitializeAsync(false)); Pump();
        var clipboard = window.Clipboard!;
        Bitmap ReadClipboard(int width, int height)
        {
            var wait = Stopwatch.StartNew();
            while (wait.ElapsedMilliseconds < 10000)
            {
                var read = clipboard.TryGetBitmapAsync(); Await(read);
                try
                {
                    if (read.Result is { } bitmap && bitmap.PixelSize == new PixelSize(width, height)) return bitmap;
                }
                // The headless clipboard returns the original bitmap reference. Pumping can
                // replace it while an earlier read completes; retry that superseded read.
                catch (ObjectDisposedException) { }
                Pump(); Thread.Sleep(5);
            }
            throw new TimeoutException("The copied image was not available on the headless clipboard.");
        }
        try
        {
            Await(clipboard.ClearAsync()); window.Gallery.Select(1);
            Await(window.OpenViewerAsync(first)); window.Viewport.SetZoom(2); Pump();
            var point = window.Viewport.TranslatePoint(new Point(window.Viewport.Bounds.Width / 2, window.Viewport.Bounds.Height / 2), window)!.Value;
            window.MouseDown(point, MouseButton.Right); window.MouseUp(point, MouseButton.Right); Pump();
            var menu = window.Viewport.ContextMenu!;
            Check(menu.IsOpen, "Right-clicking the actual viewport opens its menu");
            Check(window.ViewerOpen && window.Viewport.Zoom == 2, "Right-click does not close or zoom the viewer");
            menu.Close();
            var copy = menu.Items.OfType<MenuItem>().Single(x => x.Name == "ViewerCopyImage");
            copy.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            var fullImage = ReadClipboard(5000, 20);
            Check(fullImage.PixelSize.Width == 5000, "Copy Image copies full source pixels instead of the bounded viewer preview or a link");
            Check(window.Viewport.Zoom == 2 && File.ReadAllBytes(wide).SequenceEqual(original), "Copy preserves viewer zoom and original bytes");
            window.CloseViewer(); Pump();
            Check(ReadClipboard(5000, 20).PixelSize.Height == 20, "Copied pixels remain alive after the viewer preview is disposed");
            Await(window.OpenViewerAsync(first)); Key(window, Avalonia.Input.Key.Right); Pump();
            copy.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            Check(ReadClipboard(80, 140).PixelSize.Width == 80, "Copy after viewer navigation targets the newly opened image");
            File.Delete(tall); copy.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            PumpUntil(() => window.Library.Status.StartsWith("Could not copy this image:", StringComparison.Ordinal));
            Check(ReadClipboard(80, 140).PixelSize.Height == 140, "A missing original reports failure without replacing the existing clipboard");
            window.CloseViewer(); copy.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
            Check(!menu.IsOpen && ReadClipboard(80, 140).PixelSize.Width == 80, "Closing the viewer closes its menu and retires its image actions");
        }
        finally
        {
            Await(clipboard.ClearAsync()); Await(window.Library.FlushAsync()); window.Close();
            PumpUntil(() => !window.IsVisible); window.DisposeResources();
        }
    }
}
