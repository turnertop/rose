namespace Rose.Core;

public static class DayNightAppearance
{
    // The supplied value is the computer's local clock, including its UTC offset.
    public static string Resolve(string manualTheme, bool automatic, DateTimeOffset localTime) =>
        !automatic ? manualTheme : localTime.Hour is >= 7 and < 19 ? "Pink" : "Dark rose";

    public static TimeSpan UntilNextMinute(DateTimeOffset localTime) =>
        TimeSpan.FromTicks(Math.Max(TimeSpan.TicksPerMillisecond * 100,
            TimeSpan.TicksPerMinute - localTime.Ticks % TimeSpan.TicksPerMinute));
}
