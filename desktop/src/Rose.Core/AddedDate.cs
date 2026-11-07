namespace Rose.Core;

public static class AddedDate
{
    public static DateTime Resolve(DateTime? recorded, DateTime? directoryAdded, DateTime? created,
        DateTime observedUtc, bool isExisting)
    {
        if (recorded is { } saved && saved > DateTime.UnixEpoch) return saved;
        if (directoryAdded is { } arrival && Usable(arrival, observedUtc)) return arrival;
        if (isExisting && created is { } creation && Usable(creation, observedUtc)) return creation;
        return observedUtc;
    }

    private static bool Usable(DateTime date, DateTime observedUtc) => date > DateTime.UnixEpoch && date <= observedUtc;
}
