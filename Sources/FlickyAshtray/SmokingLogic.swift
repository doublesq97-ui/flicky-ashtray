import Foundation

enum SmokingLogic {
    static func calendar(
        frozenFor challenge: WeeklyChallenge,
        basedOn sourceCalendar: Calendar = .current
    ) -> Calendar {
        var calendar = sourceCalendar
        if let frozenTimeZone = TimeZone(identifier: challenge.timeZoneIdentifier) {
            calendar.timeZone = frozenTimeZone
        }
        return calendar
    }

    static func countingDayStart(
        for date: Date,
        dayStartHour: Int,
        calendar sourceCalendar: Calendar = .current
    ) -> Date {
        CountingDayPolicy(dayStartHour: dayStartHour, calendar: sourceCalendar)
            .range(containing: date)
            .start
    }

    static func isSameCountingDay(
        _ lhs: Date,
        _ rhs: Date,
        dayStartHour: Int,
        calendar: Calendar = .current
    ) -> Bool {
        CountingDayPolicy(dayStartHour: dayStartHour, calendar: calendar)
            .isSameCountingDay(lhs, rhs)
    }

    static func weeklyPeriodStart(
        for date: Date,
        cadence: WeeklyCadence,
        dayStartHour: Int,
        calendar sourceCalendar: Calendar = .current
    ) -> Date {
        let policy = CountingDayPolicy(dayStartHour: dayStartHour, calendar: sourceCalendar)
        let currentRange = policy.range(containing: date)
        switch cadence {
        case .rollingSevenDays:
            return currentRange.start

        case .calendarWeekMonday, .calendarWeekSunday:
            let weekday = policy.calendar.component(.weekday, from: currentRange.civilDayStart)
            let firstWeekday = cadence == .calendarWeekMonday ? 2 : 1
            let daysSinceWeekStart = (weekday - firstWeekday + 7) % 7
            return policy.range(offsetBy: -daysSinceWeekStart, from: currentRange).start
        }
    }

    static func snapshot(
        store: SmokeStore,
        now: Date,
        calendar: Calendar = .current
    ) -> DaySnapshot {
        let sorted = store.records.sorted()
        let policy = CountingDayPolicy(
            dayStartHour: store.settings.dayStartHour,
            calendar: calendar
        )
        let currentRange = policy.range(containing: now)
        let today = sorted.enumerated().compactMap { index, record -> TodayRecord? in
            guard currentRange.contains(record) else { return nil }

            let previous = index > 0 ? sorted[index - 1] : nil
            let gap = previous.map { max(0, Int(record.timeIntervalSince($0) / 60.0)) }
            return TodayRecord(id: record, number: 0, date: record, gapMinutes: gap)
        }.enumerated().map { offset, record in
            TodayRecord(id: record.id, number: offset + 1, date: record.date, gapMinutes: record.gapMinutes)
        }

        let totals = (-6...0).map { offset -> DayTotal in
            let range = policy.range(offsetBy: offset, from: currentRange)
            let count = sorted.filter(range.contains).count
            return DayTotal(id: range.start, date: range.start, count: count)
        }

        let count = today.count
        let limit = store.settings.dailyLimit
        let fullAt = limit == 1 ? 1 : max(2, limit / 2 + 1)
        let filthyAt = max(limit + 1, Int(ceil(Double(limit) * 1.5)))
        return DaySnapshot(
            count: count,
            limit: limit,
            remaining: max(limit - count, 0),
            isAtLimit: count == limit,
            isOverLimit: count > limit,
            visibleFullAt: fullAt,
            visibleFilthyAt: filthyAt,
            records: today,
            lastSevenDays: totals
        )
    }

    static func addingRecord(to store: SmokeStore, at date: Date) -> SmokeStore {
        var next = store
        next.records.append(date)
        next.normalize()
        return next
    }

    /// The honest upper bound when creating a challenge right now. Past
    /// natural-week days never participate, and an active counting day that is
    /// already over its limit can no longer be promised as achievable.
    static func maximumAchievableDays(
        store: SmokeStore,
        now: Date,
        cadence: WeeklyCadence,
        calendar: Calendar = .current
    ) -> Int {
        let policy = CountingDayPolicy(
            dayStartHour: store.settings.dayStartHour,
            calendar: calendar
        )
        let start = weeklyPeriodStart(
            for: now,
            cadence: cadence,
            dayStartHour: store.settings.dayStartHour,
            calendar: calendar
        )
        let ranges = policy.ranges(startingAt: start, count: 7)

        return ranges.reduce(into: 0) { result, range in
            guard range.end > now else { return }

            // Future ranges remain achievable. For the active range, only
            // records that have actually happened count toward its feasibility.
            guard range.start <= now else {
                result += 1
                return
            }

            let activeCount = store.records.filter { record in
                record <= now && range.contains(record)
            }.count
            if activeCount <= store.settings.dailyLimit {
                result += 1
            }
        }
    }

    /// Structural upper bound frozen at challenge creation. This is used only
    /// to repair legacy natural-week targets that included days before the user
    /// joined; later missed days must not silently lower an existing promise.
    static func maximumParticipatingDays(
        for challenge: WeeklyChallenge,
        fallbackDayStartHour: Int,
        calendar sourceCalendar: Calendar = .current
    ) -> Int {
        let dayStartHour = challenge.dayStartHour ?? fallbackDayStartHour
        let challengeCalendar = calendar(frozenFor: challenge, basedOn: sourceCalendar)
        let policy = CountingDayPolicy(dayStartHour: dayStartHour, calendar: challengeCalendar)
        let start = challenge.periodStart ?? weeklyPeriodStart(
            for: challenge.startedAt,
            cadence: challenge.cadence,
            dayStartHour: dayStartHour,
            calendar: challengeCalendar
        )
        return policy.ranges(startingAt: start, count: 7)
            .filter { $0.end > challenge.startedAt }
            .count
    }

    static func weeklyChallengeProgress(
        store: SmokeStore,
        now: Date,
        calendar sourceCalendar: Calendar = .current
    ) -> WeeklyChallengeProgress? {
        guard let challenge = store.weeklyChallenge else { return nil }
        let challengeLimit = challenge.dailyLimit ?? store.settings.dailyLimit
        let challengeDayStartHour = challenge.dayStartHour ?? store.settings.dayStartHour
        let challengeCalendar = calendar(frozenFor: challenge, basedOn: sourceCalendar)
        let policy = CountingDayPolicy(
            dayStartHour: challengeDayStartHour,
            calendar: challengeCalendar
        )
        let start = challenge.periodStart ?? weeklyPeriodStart(
            for: challenge.startedAt,
            cadence: challenge.cadence,
            dayStartHour: challengeDayStartHour,
            calendar: challengeCalendar
        )
        let ranges = policy.ranges(startingAt: start, count: 7)
        guard ranges.count == 7, let end = ranges.last?.end else { return nil }
        let sorted = store.records.sorted()
        var completedDays = 0
        var achievedDays = 0
        var days: [WeeklyChallengeDay] = []

        for range in ranges {
            let count = sorted.filter { record in
                record <= now && range.contains(record)
            }.count
            let status: WeeklyChallengeDay.Status

            if range.end <= challenge.startedAt {
                status = .notParticipating
            } else if now >= range.end {
                completedDays += 1
                if count <= challengeLimit {
                    achievedDays += 1
                    status = .achieved
                } else {
                    status = .missed
                }
            } else if now >= range.start {
                status = .active
            } else {
                status = .upcoming
            }
            days.append(
                WeeklyChallengeDay(
                    id: range.start,
                    start: range.start,
                    cigaretteCount: count,
                    status: status
                )
            )
        }

        let remainingDays = days.filter { day in
            day.status == .active || day.status == .upcoming
        }.count
        let maximumAchievableDays = maximumAchievableDays(
            in: days,
            dailyLimit: challengeLimit
        )

        return WeeklyChallengeProgress(
            challenge: challenge,
            start: start,
            end: end,
            dailyLimit: challengeLimit,
            completedDays: completedDays,
            achievedDays: achievedDays,
            remainingDays: remainingDays,
            maximumAchievableDays: maximumAchievableDays,
            isFinished: now >= end,
            isAchieved: achievedDays >= challenge.targetDays,
            days: days
        )
    }

    private static func maximumAchievableDays(
        in days: [WeeklyChallengeDay],
        dailyLimit: Int
    ) -> Int {
        days.reduce(into: 0) { result, day in
            switch day.status {
            case .achieved, .upcoming:
                result += 1
            case .active where day.cigaretteCount <= dailyLimit:
                result += 1
            case .active, .missed, .notParticipating:
                break
            }
        }
    }

    static func undoingLastRecord(
        in store: SmokeStore,
        now: Date,
        calendar: Calendar = .current
    ) -> SmokeStore {
        var next = store
        guard canUndoRecord(in: next, now: now, calendar: calendar) else { return next }
        let policy = CountingDayPolicy(
            dayStartHour: next.settings.dayStartHour,
            calendar: calendar
        )
        let currentRange = policy.range(containing: now)
        guard let index = next.records.indices
            .filter({ currentRange.contains(next.records[$0]) })
            .max(by: { next.records[$0] < next.records[$1] }) else { return next }
        next.records.remove(at: index)
        next.undoneCountingDays.append(currentRange.start)
        next.undoEvents.append(
            UndoEvent(
                occurredAt: now,
                originalRange: currentRange,
                dayStartHour: next.settings.dayStartHour
            )
        )
        next.normalize()
        return next
    }

    static func canUndoRecord(
        in store: SmokeStore,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let policy = CountingDayPolicy(
            dayStartHour: store.settings.dayStartHour,
            calendar: calendar
        )
        let currentRange = policy.range(containing: now)
        let alreadyUndoneForThisDay = store.undoEvents.contains { event in
            event.originalRange.contains(now)
                || policy.isSameCountingDay(event.occurredAt, now)
        }
        guard !alreadyUndoneForThisDay else { return false }
        return store.records.contains(where: currentRange.contains)
    }

    static func resettingHistory(
        in store: SmokeStore,
        at date: Date,
        reason: String
    ) -> SmokeStore {
        var next = store
        let clearedRecordCount = next.records.count
        next.records.removeAll()
        next.weeklyChallenge = nil
        next.undoneCountingDays.removeAll()
        next.undoEvents.removeAll()
        next.resetEvents.append(
            ResetEvent(
                occurredAt: date,
                reason: reason,
                clearedRecordCount: clearedRecordCount
            )
        )
        next.normalize()
        return next
    }
}
