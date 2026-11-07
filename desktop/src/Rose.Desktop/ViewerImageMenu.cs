using Avalonia.Controls;
using Rose.Core;

namespace Rose.Desktop;

public static class ViewerImageMenu
{
    public static ContextMenu Create(Func<ImageAsset?> currentImage,
        Func<ImageAsset, Task> copyImage, Action<ImageAsset> revealImage)
    {
        var copy = new MenuItem { Name = "ViewerCopyImage", Header = "Copy Image" };
        var reveal = new MenuItem { Name = "ViewerRevealImage", Header = "Show in Explorer" };
        copy.Click += async (_, _) => { if (currentImage() is { } asset) await copyImage(asset); };
        reveal.Click += (_, _) => { if (currentImage() is { } asset) revealImage(asset); };
        var menu = new ContextMenu { ItemsSource = new[] { copy, reveal } };
        menu.Opening += (_, _) => copy.IsEnabled = reveal.IsEnabled = currentImage() is not null;
        return menu;
    }
}
