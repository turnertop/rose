using System.Diagnostics;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Styling;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Rose.Core;
using Rose.Desktop;

internal static partial class Checks
{
    private static void AutomaticAppearanceRules()
    {
        foreach (var (hour, minute, second, expected) in new[]
        {
            (0, 40, 0, "Dark rose"), (6, 59, 59, "Dark rose"), (7, 0, 0, "Pink"),
            (12, 0, 0, "Pink"), (18, 59, 59, "Pink"), (19, 0, 0, "Dark rose"), (23, 59, 59, "Dark rose")
        })
            Check(DayNightAppearance.Resolve("Follow system", true, new(2026, 11, 7, hour, minute, second, TimeSpan.Zero)) == expected,
                $"Local {hour:00}:{minute:00}:{second:00} chooses the expected palette");
        var instant = new DateTimeOffset(2026, 11, 7, 8, 40, 0, TimeSpan.Zero);
        Check(DayNightAppearance.Resolve("Pink", true, instant.ToOffset(TimeSpan.FromHours(-8))) == "Dark rose", "Local 12:40 AM is dark");
        Check(DayNightAppearance.Resolve("Pink", true, instant.ToOffset(TimeSpan.FromHours(-5))) == "Dark rose", "A computer three hours ahead uses its own 3:40 AM");
        Check(DayNightAppearance.Resolve("Dark rose", true, instant.ToOffset(TimeSpan.FromHours(1))) == "Pink", "A computer nine hours ahead uses its own 9:40 AM");
        foreach (var manual in new[] { "Pink", "Dark rose", "Follow system" })
            Check(DayNightAppearance.Resolve(manual, false, instant) == manual, "Disabling the schedule restores " + manual);
        var legacy = System.Text.Json.JsonSerializer.Deserialize<Preferences>("{\"Theme\":\"Dark rose\"}")!;
        Check(!legacy.AutomaticDayNight && legacy.Theme == "Dark rose", "Older preferences keep their manual appearance with scheduling off");
        var store = new StateStore(Folder("appearance-state"));
        var state = new LibraryState { Preferences = new() { AutomaticDayNight = true, Theme = "Follow system" } };
        store.SaveAsync(state.Snapshot()).GetAwaiter().GetResult();
        var saved = store.Load().Preferences;
        Check(saved.AutomaticDayNight && saved.Theme == "Follow system", "The boolean and independent manual choice both survive restart");
        var snapshot = state.Snapshot(); state.Preferences.AutomaticDayNight = false;
        Check(snapshot.Preferences.AutomaticDayNight, "A background save retains its captured day/night setting");
    }

    private static void AutomaticAppearanceInterface()
    {
        var local = new DateTimeOffset(2026, 11, 7, 6, 59, 30, TimeSpan.FromHours(-8));
        var store = new StateStore(Folder("appearance-ui"));
        Await(store.SaveAsync(new() { Preferences = new() { Theme = "Dark rose", AutomaticDayNight = true } }));
        Stopwatch? elapsed = null;
        var clockReads = 0;
        DateTimeOffset LocalTime() { clockReads++; return local + (elapsed?.Elapsed ?? TimeSpan.Zero); }
        var window = new MainWindow(store, false, LocalTime); window.Show();
        Window? settings = null;
        try
        {
            Key(window, Avalonia.Input.Key.OemComma, RawInputModifiers.Control);
            settings = window.OwnedWindows.Single(x => x.Title == "Rose Settings");
            Await(window.Library.InitializeAsync(false)); Pump();
            Check(settings.GetVisualDescendants().OfType<CheckBox>().Single(x => x.Name == "AutomaticDayNight").IsChecked == true,
                "Settings opened during startup catches up with the restored preference");
            Check(window.ActualThemeVariant == ThemeVariant.Dark && window.Gallery.Dark, "Startup evaluates the saved schedule before browsing");
            var changes = 0; window.Library.Changed += () => changes++;
            var background = window.Background;
            window.RefreshAppearance(); window.RefreshAppearance(); Pump();
            Check(ReferenceEquals(background, window.Background) && changes == 0, "Steady checks do not repaint the palette or refresh the library");
            local = local.AddSeconds(30); window.RefreshAppearance(); Pump();
            Check(window.ActualThemeVariant == ThemeVariant.Light && !window.Gallery.Dark && changes == 0, "Crossing 7 AM updates the window and gallery without an index refresh");
            Key(window, Avalonia.Input.Key.OemComma, RawInputModifiers.Control);
            settings = window.OwnedWindows.Single(x => x.Title == "Rose Settings");
            var automatic = settings.GetVisualDescendants().OfType<CheckBox>().Single(x => x.Name == "AutomaticDayNight");
            var manual = settings.GetVisualDescendants().OfType<ComboBox>().Single(x => x.Name == "ManualAppearance");
            Check(automatic.IsChecked == true && !manual.IsEnabled && Equals(manual.SelectedItem, "Dark rose"), "Settings exposes the toggle while retaining the disabled manual choice");
            local = local.AddHours(12); window.RefreshAppearance(); Pump();
            Check(window.ActualThemeVariant == ThemeVariant.Dark && settings.ActualThemeVariant == ThemeVariant.Dark, "An open Settings window follows the evening transition");
            local = local.AddHours(12); window.RefreshAppearance(); Pump();
            automatic.IsChecked = false; Pump();
            Check(!window.Library.State.Preferences.AutomaticDayNight && manual.IsEnabled && window.ActualThemeVariant == ThemeVariant.Dark,
                "Turning the real toggle off restores the saved dark manual choice in daytime");
            manual.SelectedItem = "Pink"; Pump();
            automatic.IsChecked = true; Pump();
            local = new(2026, 11, 8, 0, 40, 0, TimeSpan.FromHours(-8)); window.RefreshAppearance(); Pump();
            Check(window.ActualThemeVariant == ThemeVariant.Dark && window.Library.State.Preferences.Theme == "Pink", "Scheduling does not overwrite the manual theme");
            local = local.ToOffset(TimeSpan.FromHours(1)); window.RefreshAppearance(); Pump();
            Check(window.ActualThemeVariant == ThemeVariant.Light && settings.ActualThemeVariant == ThemeVariant.Light, "A changed local offset immediately updates both windows");
            // Advance the simulated wall clock with the real dispatcher timer.
            // Queued UI work must not hold the clock just before the boundary.
            local = new(2026, 11, 7, 6, 59, 59, 500, TimeSpan.FromHours(-8));
            elapsed = Stopwatch.StartNew(); window.RefreshAppearance();
            var readsAtArming = clockReads;
            // RunJobs skips OS timer events; exercise this timer in the real
            // headless dispatcher loop instead of only draining queued jobs.
            using (var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10)))
            using (DispatcherTimer.Run(() =>
            {
                if (window.ActualThemeVariant != ThemeVariant.Light || clockReads <= readsAtArming) return true;
                deadline.Cancel(); return false;
            }, TimeSpan.FromMilliseconds(10)))
                Dispatcher.UIThread.MainLoop(deadline.Token);
            if (window.ActualThemeVariant != ThemeVariant.Light || clockReads <= readsAtArming)
                throw new TimeoutException("Scheduled appearance did not update in the headless dispatcher loop.");
            local += elapsed.Elapsed; elapsed.Stop(); elapsed = null;
            Check(settings.ActualThemeVariant == ThemeVariant.Light, "The scheduled timer changes both windows without user input");
            Await(window.Library.FlushAsync());
            Check(store.Load().Preferences.AutomaticDayNight, "The real settings toggle is saved");
        }
        finally { settings?.Close(); Await(window.Library.FlushAsync()); window.Close(); PumpUntil(() => !window.IsVisible); window.DisposeResources(); }
        local = new(2026, 11, 8, 0, 40, 0, TimeSpan.FromHours(-8));
        var reopened = new MainWindow(store, true, () => local); reopened.Show();
        try
        {
            PumpUntil(() => reopened.Library.State.Preferences.AutomaticDayNight);
            Check(reopened.ActualThemeVariant == ThemeVariant.Dark, "Restart reevaluates night instead of restoring yesterday's palette");
            reopened.Library.State.Preferences.AutomaticDayNight = false; reopened.Library.Touch(); Pump();
            Check(reopened.ActualThemeVariant == ThemeVariant.Light, "The old pink choice is still available after restarting and disabling automatic appearance");
        }
        finally { Await(reopened.Library.FlushAsync()); reopened.Close(); PumpUntil(() => !reopened.IsVisible); reopened.DisposeResources(); }
    }
}
