namespace FlickyAshtray.Core;

public static class SmokingLogic
{
    public static DateTimeOffset CountingDayStart(
        DateTimeOffset date,
        int dayStartHour,
        TimeZoneInfo? timeZone = null
    ) => new CountingDayPolicy(dayStartHour, timeZone).RangeContaining(date).Start;

    public static bool IsSameCountingDay(
        DateTimeOffset left,
        DateTimeOffset right,
        int dayStartHour,
        TimeZoneInfo? timeZone = null
    ) => new CountingDayPolicy(dayStartHour, timeZone).IsSameCountingDay(left, right);

    public static DateTimeOffset WeeklyPeriodStart(
        DateTimeOffset date,
        WeeklyCadence cadence,
        int dayStartHour,
        TimeZoneInfo? timeZone = null
    )
    {
        var policy = new CountingDayPolicy(dayStartHour, timeZone);
        var current = policy.RangeContaining(date);
        if (cadence == WeeklyCadence.RollingSevenDays)
        {
            return current.Start;
        }

        var firstWeekday = cadence == WeeklyCadence.CalendarWeekMonday
            ? DayOfWeek.Monday
            : DayOfWeek.Sunday;
        var weekday = current.CivilDayStart.DayOfWeek;
        var daysSinceWeekStart = ((int)weekday - (int)firstWeekday + 7) % 7;
        return policy.RangeOffsetBy(-daysSinceWeekStart, current).Start;
    }

    public static DaySnapshot Snapshot(
        SmokeStore store,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null
    )
    {
        var sorted = store.Records.Order().ToArray();
        var policy = new CountingDayPolicy(store.Settings.DayStartHour, timeZone);
        var current = policy.RangeContaining(now);
        var today = new List<TodayRecord>();

        for (var index = 0; index < sorted.Length; index++)
        {
            var record = sorted[index];
            if (!current.Contains(record))
            {
                continue;
            }

            int? gap = index > 0
                ? Math.Max(0, (int)(record - sorted[index - 1]).TotalMinutes)
                : null;
            today.Add(new TodayRecord(today.Count + 1, record, gap));
        }

        var totals = Enumerable.Range(-6, 7)
            .Select(offset => policy.RangeOffsetBy(offset, current))
            .Select(range => new DayTotal(
                range.Start,
                sorted.Count(range.Contains)
            ))
            .ToArray();

        var count = today.Count;
        var limit = store.Settings.DailyLimit;
        var fullAt = limit == 1 ? 1 : Math.Max(2, limit / 2 + 1);
        var filthyAt = Math.Max(limit + 1, (int)Math.Ceiling(limit * 1.5));
        return new DaySnapshot(
            count,
            limit,
            Math.Max(limit - count, 0),
            count == limit,
            count > limit,
            fullAt,
            filthyAt,
            today,
            totals
        );
    }

    public static SmokeStore AddingRecord(SmokeStore store, DateTimeOffset date)
    {
        var next = StoreCopies.DeepCopy(store);
        next.Records.Add(date.ToUniversalTime());
        next.Normalize();
        return next;
    }

    public static int MaximumAchievableDays(
        SmokeStore store,
        DateTimeOffset now,
        WeeklyCadence cadence,
        TimeZoneInfo? timeZone = null
    )
    {
        var policy = new CountingDayPolicy(store.Settings.DayStartHour, timeZone);
        var start = WeeklyPeriodStart(now, cadence, store.Settings.DayStartHour, timeZone);
        var ranges = policy.RangesStartingAt(start, 7);
        var result = 0;

        foreach (var range in ranges)
        {
            if (range.End <= now)
            {
                continue;
            }

            if (range.Start > now)
            {
                result += 1;
                continue;
            }

            var activeCount = store.Records.Count(record => record <= now && range.Contains(record));
            if (activeCount <= store.Settings.DailyLimit)
            {
                result += 1;
            }
        }

        return result;
    }

    public static int MaximumParticipatingDays(
        WeeklyChallenge challenge,
        int fallbackDayStartHour
    )
    {
        var dayStartHour = challenge.DayStartHour ?? fallbackDayStartHour;
        var zone = TimeZoneSupport.Resolve(challenge.TimeZoneIdentifier);
        var policy = new CountingDayPolicy(dayStartHour, zone);
        var start = challenge.PeriodStart ?? WeeklyPeriodStart(
            challenge.StartedAt,
            challenge.Cadence,
            dayStartHour,
            zone
        );
        return policy.RangesStartingAt(start, 7).Count(range => range.End > challenge.StartedAt);
    }

    public static WeeklyChallengeProgress? WeeklyChallengeProgress(
        SmokeStore store,
        DateTimeOffset now
    )
    {
        var challenge = store.WeeklyChallenge;
        if (challenge is null)
        {
            return null;
        }

        var limit = challenge.DailyLimit ?? store.Settings.DailyLimit;
        var dayStartHour = challenge.DayStartHour ?? store.Settings.DayStartHour;
        var zone = TimeZoneSupport.Resolve(challenge.TimeZoneIdentifier);
        var policy = new CountingDayPolicy(dayStartHour, zone);
        var start = challenge.PeriodStart ?? WeeklyPeriodStart(
            challenge.StartedAt,
            challenge.Cadence,
            dayStartHour,
            zone
        );
        var ranges = policy.RangesStartingAt(start, 7);
        if (ranges.Count != 7)
        {
            return null;
        }

        var completedDays = 0;
        var achievedDays = 0;
        var days = new List<WeeklyChallengeDay>();
        foreach (var range in ranges)
        {
            var count = store.Records.Count(record => record <= now && range.Contains(record));
            ChallengeDayStatus status;
            if (range.End <= challenge.StartedAt)
            {
                status = ChallengeDayStatus.NotParticipating;
            }
            else if (now >= range.End)
            {
                completedDays += 1;
                if (count <= limit)
                {
                    achievedDays += 1;
                    status = ChallengeDayStatus.Achieved;
                }
                else
                {
                    status = ChallengeDayStatus.Missed;
                }
            }
            else if (now >= range.Start)
            {
                status = ChallengeDayStatus.Active;
            }
            else
            {
                status = ChallengeDayStatus.Upcoming;
            }

            days.Add(new WeeklyChallengeDay(range.Start, count, status));
        }

        var remaining = days.Count(day => day.Status is ChallengeDayStatus.Active or ChallengeDayStatus.Upcoming);
        var maximum = days.Count(day => day.Status switch
        {
            ChallengeDayStatus.Achieved or ChallengeDayStatus.Upcoming => true,
            ChallengeDayStatus.Active => day.CigaretteCount <= limit,
            _ => false
        });
        var end = ranges[^1].End;
        return new WeeklyChallengeProgress(
            challenge,
            start,
            end,
            limit,
            completedDays,
            achievedDays,
            remaining,
            maximum,
            now >= end,
            achievedDays >= challenge.TargetDays,
            days
        );
    }

    public static bool CanUndoRecord(
        SmokeStore store,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null
    )
    {
        var policy = new CountingDayPolicy(store.Settings.DayStartHour, timeZone);
        var current = policy.RangeContaining(now);
        var alreadyUndone = store.UndoEvents.Any(value =>
            value.OriginalStart <= now && now < value.OriginalEnd
            || policy.IsSameCountingDay(value.OccurredAt, now)
        );
        return !alreadyUndone && store.Records.Any(current.Contains);
    }

    public static SmokeStore UndoingLastRecord(
        SmokeStore store,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null
    )
    {
        var next = StoreCopies.DeepCopy(store);
        if (!CanUndoRecord(next, now, timeZone))
        {
            return next;
        }

        var policy = new CountingDayPolicy(next.Settings.DayStartHour, timeZone);
        var current = policy.RangeContaining(now);
        var candidate = next.Records
            .Select((record, index) => new { record, index })
            .Where(value => current.Contains(value.record))
            .OrderByDescending(value => value.record)
            .FirstOrDefault();
        if (candidate is null)
        {
            return next;
        }

        next.Records.RemoveAt(candidate.index);
        next.UndoneCountingDays.Add(current.Start);
        next.UndoEvents.Add(new UndoEvent
        {
            OccurredAt = now.ToUniversalTime(),
            OriginalStart = current.Start,
            OriginalEnd = current.End,
            DayStartHour = next.Settings.DayStartHour
        });
        next.Normalize();
        return next;
    }

    public static SmokeStore ResettingHistory(
        SmokeStore store,
        DateTimeOffset at,
        string reason
    )
    {
        var next = StoreCopies.DeepCopy(store);
        var count = next.Records.Count;
        next.Records.Clear();
        next.WeeklyChallenge = null;
        next.UndoneCountingDays.Clear();
        next.UndoEvents.Clear();
        next.ResetEvents.Add(new ResetEvent
        {
            OccurredAt = at.ToUniversalTime(),
            Reason = reason,
            ClearedRecordCount = count
        });
        next.Normalize();
        return next;
    }

    public static WeeklyReport WeeklyReport(
        SmokeStore store,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null
    )
    {
        var policy = new CountingDayPolicy(store.Settings.DayStartHour, timeZone);
        var current = policy.RangeContaining(now);
        var currentRanges = Enumerable.Range(-6, 7).Select(offset => policy.RangeOffsetBy(offset, current)).ToArray();
        var previousRanges = Enumerable.Range(-13, 7).Select(offset => policy.RangeOffsetBy(offset, current)).ToArray();
        var previousCutoff = policy.MappedCutoff(now, current, previousRanges[^1]);
        var recordsThroughNow = store.Records.Where(record => record <= now).Order().ToArray();
        var days = ReportDays(recordsThroughNow, currentRanges, current.Start, now, store.Settings.DailyLimit);
        var previousDays = ReportDays(store.Records.Order().ToArray(), previousRanges, current.Start, previousCutoff, store.Settings.DailyLimit);
        var total = days.Sum(day => day.CigaretteCount);
        var previousTotal = previousDays.Sum(day => day.CigaretteCount);
        var completed = days.Where(day => day.IsComplete).ToArray();
        var withinLimit = completed.Count(day => day.IsWithinLimit);
        var longestGap = LongestGap(recordsThroughNow, currentRanges[0].Start, currentRanges[^1].End);
        var encouragement = WeeklyEncouragement(total, previousTotal, completed.Length, withinLimit, longestGap);

        return new WeeklyReport(
            now,
            currentRanges[0].Start,
            currentRanges[^1].End,
            previousRanges[0].Start,
            previousRanges[^1].End,
            previousCutoff,
            store.Settings.DailyLimit,
            days,
            previousDays,
            total,
            previousTotal,
            completed.Length,
            withinLimit,
            longestGap,
            encouragement
        );
    }

    public static string FormattedGap(int minutes)
    {
        var days = minutes / (24 * 60);
        var hours = minutes % (24 * 60) / 60;
        var rest = minutes % 60;
        if (days > 0)
        {
            return hours > 0 ? $"{days}天{hours}小时" : $"{days}天";
        }

        if (hours > 0)
        {
            return rest > 0 ? $"{hours}小时{rest}分钟" : $"{hours}小时";
        }

        return $"{rest}分钟";
    }

    private static IReadOnlyList<WeeklyReportDay> ReportDays(
        IReadOnlyList<DateTimeOffset> records,
        IEnumerable<CountingDayRange> ranges,
        DateTimeOffset currentStart,
        DateTimeOffset observationCutoff,
        int dailyLimit
    ) => ranges.Select(range =>
    {
        var observedThrough = observationCutoff < range.Start
            ? range.Start
            : observationCutoff > range.End ? range.End : observationCutoff;
        var count = records.Count(record => range.Contains(record) && record <= observedThrough);
        var complete = observationCutoff >= range.End;
        return new WeeklyReportDay(
            range.Start,
            range.End,
            observedThrough,
            count,
            range.Start == currentStart,
            complete,
            observationCutoff > range.Start && observationCutoff < range.End,
            complete && count <= dailyLimit
        );
    }).ToArray();

    private static int? LongestGap(
        IReadOnlyList<DateTimeOffset> records,
        DateTimeOffset rangeStart,
        DateTimeOffset rangeEnd
    )
    {
        if (records.Count < 2)
        {
            return null;
        }

        int? result = null;
        for (var index = 1; index < records.Count; index++)
        {
            var later = records[index];
            if (later < rangeStart || later >= rangeEnd)
            {
                continue;
            }

            var gap = Math.Max(0, (int)(later - records[index - 1]).TotalMinutes);
            result = result is null ? gap : Math.Max(result.Value, gap);
        }

        return result;
    }

    private static string WeeklyEncouragement(
        int totalCount,
        int previousTotalCount,
        int completedDayCount,
        int withinLimitDays,
        int? longestGapMinutes
    )
    {
        if (totalCount == 0)
        {
            return "这 7 天没有新增记录。安静的每一天，都在替你把习惯往回拉。";
        }

        var reduction = previousTotalCount - totalCount;
        if (reduction > 0)
        {
            return $"比前 7 天少了 {reduction} 根。不是一口气改变，是一次次把下一根往后放。";
        }

        if (completedDayCount > 0 && withinLimitDays == completedDayCount)
        {
            return $"已经完成的 {completedDayCount} 天都守住了约定，稳定本身就是进步。";
        }

        if (longestGapMinutes is >= 720)
        {
            return $"最长一次等了 {FormattedGap(longestGapMinutes.Value)}。你已经证明，冲动可以被慢慢拉开。";
        }

        return $"这 7 天有 {withinLimitDays} 个完整日守住了约定。下一根，再晚一点就好。";
    }
}

public static class StoreCopies
{
    public static SmokeStore DeepCopy(SmokeStore source) => new()
    {
        Version = source.Version,
        Settings = new AppSettings
        {
            DailyLimit = source.Settings.DailyLimit,
            DayStartHour = source.Settings.DayStartHour,
            PetScale = source.Settings.PetScale,
            PetStyle = source.Settings.PetStyle
        },
        Records = [.. source.Records],
        FirstRunDone = source.FirstRunDone,
        WeeklyChallenge = source.WeeklyChallenge is null ? null : new WeeklyChallenge
        {
            Id = source.WeeklyChallenge.Id,
            StartedAt = source.WeeklyChallenge.StartedAt,
            TargetDays = source.WeeklyChallenge.TargetDays,
            Reward = source.WeeklyChallenge.Reward,
            Cadence = source.WeeklyChallenge.Cadence,
            PeriodStart = source.WeeklyChallenge.PeriodStart,
            DailyLimit = source.WeeklyChallenge.DailyLimit,
            DayStartHour = source.WeeklyChallenge.DayStartHour,
            TimeZoneIdentifier = source.WeeklyChallenge.TimeZoneIdentifier
        },
        UndoneCountingDays = [.. source.UndoneCountingDays],
        UndoEvents = source.UndoEvents.Select(value => new UndoEvent
        {
            OccurredAt = value.OccurredAt,
            OriginalStart = value.OriginalStart,
            OriginalEnd = value.OriginalEnd,
            DayStartHour = value.DayStartHour
        }).ToList(),
        ResetEvents = source.ResetEvents.Select(value => new ResetEvent
        {
            Id = value.Id,
            OccurredAt = value.OccurredAt,
            Reason = value.Reason,
            ClearedRecordCount = value.ClearedRecordCount
        }).ToList()
    };
}
