namespace FlickyAshtray.Core;

public enum PetStyle
{
    Ashtray,
    Note
}

public enum WeeklyCadence
{
    RollingSevenDays,
    CalendarWeekMonday,
    CalendarWeekSunday
}

public enum ChallengeDayStatus
{
    Achieved,
    Missed,
    Active,
    Upcoming,
    NotParticipating
}

public enum AshLevel
{
    Clean,
    Sprinkle,
    Full,
    OverLimit,
    Filthy
}

public sealed class AppSettings
{
    public int DailyLimit { get; set; } = 8;
    public int DayStartHour { get; set; }
    public double PetScale { get; set; } = 1;
    public PetStyle PetStyle { get; set; } = PetStyle.Ashtray;

    public void Normalize()
    {
        DailyLimit = Math.Clamp(DailyLimit, 1, 60);
        DayStartHour = Math.Clamp(DayStartHour, 0, 23);
        PetScale = Math.Clamp(PetScale, 0.6, 1.0);
    }
}

public sealed class WeeklyChallenge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset StartedAt { get; set; }
    public int TargetDays { get; set; } = 5;
    public string Reward { get; set; } = string.Empty;
    public WeeklyCadence Cadence { get; set; } = WeeklyCadence.RollingSevenDays;
    public DateTimeOffset? PeriodStart { get; set; }
    public int? DailyLimit { get; set; }
    public int? DayStartHour { get; set; }
    public string TimeZoneIdentifier { get; set; } = TimeZoneSupport.LocalIanaIdentifier();

    public void Normalize()
    {
        TargetDays = Math.Clamp(TargetDays, 1, 7);
        Reward = (Reward ?? string.Empty).Trim();
        if (DailyLimit is not null)
        {
            DailyLimit = Math.Clamp(DailyLimit.Value, 1, 60);
        }

        if (DayStartHour is not null)
        {
            DayStartHour = Math.Clamp(DayStartHour.Value, 0, 23);
        }

        if (string.IsNullOrWhiteSpace(TimeZoneIdentifier))
        {
            TimeZoneIdentifier = TimeZoneSupport.LocalIanaIdentifier();
        }
    }
}

public sealed class UndoEvent
{
    public DateTimeOffset OccurredAt { get; set; }
    public DateTimeOffset OriginalStart { get; set; }
    public DateTimeOffset OriginalEnd { get; set; }
    public int DayStartHour { get; set; }

    public CountingDayRange OriginalRange => new(
        TimeZoneInfo.ConvertTime(OriginalStart, TimeZoneInfo.Local).Date,
        OriginalStart,
        OriginalEnd
    );

    public void Normalize()
    {
        DayStartHour = Math.Clamp(DayStartHour, 0, 23);
        if (OriginalEnd <= OriginalStart)
        {
            OriginalEnd = OriginalStart.AddDays(1);
        }
    }
}

public sealed class ResetEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; set; }
    public string Reason { get; set; } = string.Empty;
    public int ClearedRecordCount { get; set; }

    public void Normalize()
    {
        Reason = (Reason ?? string.Empty).Trim();
        if (Reason.Length == 0)
        {
            Reason = "未填写原因";
        }

        ClearedRecordCount = Math.Max(0, ClearedRecordCount);
    }
}

public sealed class SmokeStore
{
    public const int CurrentVersion = 8;

    public int Version { get; set; } = CurrentVersion;
    public AppSettings Settings { get; set; } = new();
    public List<DateTimeOffset> Records { get; set; } = [];
    public bool FirstRunDone { get; set; }
    public WeeklyChallenge? WeeklyChallenge { get; set; }
    public List<DateTimeOffset> UndoneCountingDays { get; set; } = [];
    public List<UndoEvent> UndoEvents { get; set; } = [];
    public List<ResetEvent> ResetEvents { get; set; } = [];

    public void Normalize()
    {
        Settings ??= new AppSettings();
        Records ??= [];
        UndoneCountingDays ??= [];
        UndoEvents ??= [];
        ResetEvents ??= [];
        Settings.Normalize();

        if (WeeklyChallenge is not null)
        {
            WeeklyChallenge.DailyLimit ??= Settings.DailyLimit;
            WeeklyChallenge.DayStartHour ??= Settings.DayStartHour;
            WeeklyChallenge.Normalize();
            var zone = TimeZoneSupport.Resolve(WeeklyChallenge.TimeZoneIdentifier);
            WeeklyChallenge.PeriodStart ??= SmokingLogic.WeeklyPeriodStart(
                WeeklyChallenge.StartedAt,
                WeeklyChallenge.Cadence,
                WeeklyChallenge.DayStartHour ?? Settings.DayStartHour,
                zone
            );
            var structuralMaximum = SmokingLogic.MaximumParticipatingDays(
                WeeklyChallenge,
                Settings.DayStartHour
            );
            if (structuralMaximum > 0)
            {
                WeeklyChallenge.TargetDays = Math.Min(WeeklyChallenge.TargetDays, structuralMaximum);
            }
        }

        Records = Records.Order().ToList();
        UndoneCountingDays = UndoneCountingDays.Distinct().Order().ToList();
        UndoEvents = UndoEvents
            .Where(value => value is not null)
            .Select(value =>
            {
                value.Normalize();
                return value;
            })
            .GroupBy(value => new { value.OccurredAt, value.OriginalStart, value.OriginalEnd, value.DayStartHour })
            .Select(group => group.First())
            .OrderBy(value => value.OccurredAt)
            .ThenBy(value => value.OriginalStart)
            .ToList();

        var knownStarts = UndoEvents.Select(value => value.OriginalStart).ToHashSet();
        foreach (var start in UndoneCountingDays)
        {
            if (!knownStarts.Add(start))
            {
                continue;
            }

            UndoEvents.Add(new UndoEvent
            {
                OccurredAt = start,
                OriginalStart = start,
                OriginalEnd = start.AddDays(1),
                DayStartHour = Settings.DayStartHour
            });
        }

        UndoEvents = UndoEvents.OrderBy(value => value.OccurredAt).ThenBy(value => value.OriginalStart).ToList();
        UndoneCountingDays = UndoneCountingDays
            .Concat(UndoEvents.Select(value => value.OriginalStart))
            .Distinct()
            .Order()
            .ToList();
        ResetEvents = ResetEvents
            .Where(value => value is not null)
            .Select(value =>
            {
                value.Normalize();
                return value;
            })
            .OrderBy(value => value.OccurredAt)
            .ToList();
        Version = CurrentVersion;
    }
}

public readonly record struct CountingDayRange(
    DateTime CivilDayStart,
    DateTimeOffset Start,
    DateTimeOffset End
)
{
    public TimeSpan Duration => End - Start;
    public bool Contains(DateTimeOffset date) => date >= Start && date < End;
}

public sealed record TodayRecord(int Number, DateTimeOffset Date, int? GapMinutes);
public sealed record DayTotal(DateTimeOffset Date, int Count);

public sealed record DaySnapshot(
    int Count,
    int Limit,
    int Remaining,
    bool IsAtLimit,
    bool IsOverLimit,
    int VisibleFullAt,
    int VisibleFilthyAt,
    IReadOnlyList<TodayRecord> Records,
    IReadOnlyList<DayTotal> LastSevenDays
)
{
    public AshLevel AshLevel => Count switch
    {
        0 => AshLevel.Clean,
        1 => AshLevel.Sprinkle,
        _ when Count >= VisibleFilthyAt => AshLevel.Filthy,
        _ when Count >= Limit => AshLevel.OverLimit,
        _ when Count >= VisibleFullAt => AshLevel.Full,
        _ => AshLevel.Sprinkle
    };
}

public sealed record WeeklyChallengeDay(
    DateTimeOffset Start,
    int CigaretteCount,
    ChallengeDayStatus Status
);

public sealed record WeeklyChallengeProgress(
    WeeklyChallenge Challenge,
    DateTimeOffset Start,
    DateTimeOffset End,
    int DailyLimit,
    int CompletedDays,
    int AchievedDays,
    int RemainingDays,
    int MaximumAchievableDays,
    bool IsFinished,
    bool IsAchieved,
    IReadOnlyList<WeeklyChallengeDay> Days
)
{
    public int DaysStillNeeded => Math.Max(0, Challenge.TargetDays - AchievedDays);
}

public sealed record WeeklyReportDay(
    DateTimeOffset Start,
    DateTimeOffset End,
    DateTimeOffset ObservedThrough,
    int CigaretteCount,
    bool IsCurrentCountingDay,
    bool IsComplete,
    bool IsPartial,
    bool IsWithinLimit
);

public sealed record WeeklyReport(
    DateTimeOffset GeneratedAt,
    DateTimeOffset RangeStart,
    DateTimeOffset RangeEnd,
    DateTimeOffset PreviousRangeStart,
    DateTimeOffset PreviousRangeEnd,
    DateTimeOffset PreviousComparableCutoff,
    int DailyLimit,
    IReadOnlyList<WeeklyReportDay> Days,
    IReadOnlyList<WeeklyReportDay> PreviousDays,
    int TotalCount,
    int PreviousTotalCount,
    int CompletedDayCount,
    int WithinLimitDays,
    int? LongestGapMinutes,
    string Encouragement
)
{
    public int ReductionFromPreviousPeriod => PreviousTotalCount - TotalCount;
}
