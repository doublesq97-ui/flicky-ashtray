namespace FlickyAshtray.Core;

public sealed class CountingDayPolicy
{
    public CountingDayPolicy(int dayStartHour, TimeZoneInfo? timeZone = null)
    {
        DayStartHour = Math.Clamp(dayStartHour, 0, 23);
        TimeZone = timeZone ?? TimeZoneInfo.Local;
    }

    public int DayStartHour { get; }
    public TimeZoneInfo TimeZone { get; }

    public CountingDayRange RangeContaining(DateTimeOffset instant)
    {
        var normalized = instant.ToUniversalTime();
        var civilDay = TimeZoneInfo.ConvertTime(normalized, TimeZone).Date;
        var candidate = RangeForCivilDay(civilDay);
        if (normalized < candidate.Start)
        {
            return RangeForCivilDay(civilDay.AddDays(-1));
        }

        if (normalized >= candidate.End)
        {
            return RangeForCivilDay(civilDay.AddDays(1));
        }

        return candidate;
    }

    public CountingDayRange RangeOffsetBy(int dayOffset, CountingDayRange basis) =>
        RangeForCivilDay(basis.CivilDayStart.AddDays(dayOffset));

    public IReadOnlyList<CountingDayRange> RangesStartingAt(DateTimeOffset firstBoundary, int count)
    {
        if (count <= 0)
        {
            return [];
        }

        var first = RangeContaining(firstBoundary);
        return Enumerable.Range(0, count).Select(offset => RangeOffsetBy(offset, first)).ToArray();
    }

    public bool IsSameCountingDay(DateTimeOffset left, DateTimeOffset right) =>
        RangeContaining(left).Start == RangeContaining(right).Start;

    public DateTimeOffset MappedCutoff(
        DateTimeOffset now,
        CountingDayRange current,
        CountingDayRange comparison
    )
    {
        if (current.Duration <= TimeSpan.Zero || comparison.Duration <= TimeSpan.Zero)
        {
            return comparison.Start;
        }

        var progress = Math.Clamp(
            (now.ToUniversalTime() - current.Start).TotalSeconds / current.Duration.TotalSeconds,
            0,
            1
        );
        return comparison.Start.AddSeconds(progress * comparison.Duration.TotalSeconds);
    }

    private CountingDayRange RangeForCivilDay(DateTime civilDay)
    {
        var normalizedDay = DateTime.SpecifyKind(civilDay.Date, DateTimeKind.Unspecified);
        return new CountingDayRange(
            normalizedDay,
            BoundaryOn(normalizedDay),
            BoundaryOn(normalizedDay.AddDays(1))
        );
    }

    private DateTimeOffset BoundaryOn(DateTime civilDay)
    {
        var local = DateTime.SpecifyKind(civilDay.Date.AddHours(DayStartHour), DateTimeKind.Unspecified);
        while (TimeZone.IsInvalidTime(local))
        {
            local = local.AddMinutes(1);
        }

        var offset = TimeZone.IsAmbiguousTime(local)
            ? TimeZone.GetAmbiguousTimeOffsets(local).Max()
            : TimeZone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset).ToUniversalTime();
    }
}

public static class TimeZoneSupport
{
    public static string LocalIanaIdentifier()
    {
        var identifier = TimeZoneInfo.Local.Id;
        if (TimeZoneInfo.TryConvertWindowsIdToIanaId(identifier, out var iana))
        {
            return iana;
        }

        return identifier;
    }

    public static TimeZoneInfo Resolve(string? identifier)
    {
        if (!string.IsNullOrWhiteSpace(identifier))
        {
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(identifier);
            }
            catch (TimeZoneNotFoundException)
            {
                if (TimeZoneInfo.TryConvertIanaIdToWindowsId(identifier, out var windowsId))
                {
                    try
                    {
                        return TimeZoneInfo.FindSystemTimeZoneById(windowsId);
                    }
                    catch (TimeZoneNotFoundException)
                    {
                    }
                }
            }
            catch (InvalidTimeZoneException)
            {
            }
        }

        return TimeZoneInfo.Local;
    }
}
