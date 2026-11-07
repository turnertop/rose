using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Themes.Fluent;
using Avalonia.Media;
using Avalonia.Styling;

namespace Rose.Desktop;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try { BuildAvaloniaApp().StartWithClassicDesktopLifetime(args); }
        catch (Exception error)
        {
            var folder = Environment.GetEnvironmentVariable("ROSE_DATA_DIRECTORY") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RoseDesktop");
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, "startup-error.log"), DateTimeOffset.Now + "\n" + error + "\n");
            throw;
        }
    }
    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<RoseApplication>().UsePlatformDetect().LogToTrace();
}

public sealed class RoseApplication : Application
{
    public override void Initialize()
    {
        var theme = new FluentTheme();
        theme.Palettes[ThemeVariant.Light] = new ColorPaletteResources { Accent = Color.Parse("#EF3585") };
        theme.Palettes[ThemeVariant.Dark] = new ColorPaletteResources { Accent = Color.Parse("#F56BA6") };
        Styles.Add(theme);
    }
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime lifetime) lifetime.MainWindow = new MainWindow();
        base.OnFrameworkInitializationCompleted();
    }
}
