import Foundation

/// A half-open counting-day interval. `end` is always constructed from the
/// next civil day's configured boundary; it is never inferred by adding 24
/// hours (or one day) to `start`.
struct CountingDayRange: Equatable, Hashable, Sendable {
    let civilDayStart: Date
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// The single source of truth for mapping wall-clock civil days to the user's
/// counting days. A missing DST wall time advances to the next valid time; a
/// repeated wall time consistently chooses its first occurrence.
struct CountingDayPolicy: Sendable {
    let dayStartHour: Int
    let calendar: Calendar

    init(dayStartHour: Int, calendar sourceCalendar: Calendar = .current) {
        let normalizedDayStartHour = min(23, max(0, dayStartHour))
        var calendar = sourceCalendar
        calendar.locale = Locale(identifier: "zh_CN")
        self.dayStartHour = normalizedDayStartHour
        self.calendar = calendar
    }

    func range(containing date: Date) -> CountingDayRange {
        let civilDay = civilDay(containing: date)
        let candidate = range(forCivilDayStartingAt: civilDay)
        if date < candidate.start {
            return range(forCivilDayStartingAt: shiftedCivilDay(civilDay, by: -1))
        }
        if date >= candidate.end {
            return range(forCivilDayStartingAt: shiftedCivilDay(civilDay, by: 1))
        }
        return candidate
    }

    func range(forCivilDayContaining date: Date) -> CountingDayRange {
        range(forCivilDayStartingAt: civilDay(containing: date))
    }

    func range(offsetBy dayOffset: Int, from base: CountingDayRange) -> CountingDayRange {
        range(forCivilDayStartingAt: shiftedCivilDay(base.civilDayStart, by: dayOffset))
    }

    func ranges(startingAt firstBoundary: Date, count: Int) -> [CountingDayRange] {
        guard count > 0 else { return [] }
        let first = range(containing: firstBoundary)
        return (0..<count).map { range(offsetBy: $0, from: first) }
    }

    func isSameCountingDay(_ lhs: Date, _ rhs: Date) -> Bool {
        range(containing: lhs).start == range(containing: rhs).start
    }

    func mappedCutoff(
        from now: Date,
        in current: CountingDayRange,
        to comparison: CountingDayRange
    ) -> Date {
        guard current.duration > 0, comparison.duration > 0 else { return comparison.start }
        let progress = min(1, max(0, now.timeIntervalSince(current.start) / current.duration))
        return comparison.start.addingTimeInterval(progress * comparison.duration)
    }

    private func range(forCivilDayStartingAt civilDay: Date) -> CountingDayRange {
        let normalizedCivilDay = self.civilDay(containing: civilDay)
        let nextCivilDay = shiftedCivilDay(normalizedCivilDay, by: 1)
        return CountingDayRange(
            civilDayStart: normalizedCivilDay,
            start: boundary(on: normalizedCivilDay),
            end: boundary(on: nextCivilDay)
        )
    }

    private func boundary(on civilDay: Date) -> Date {
        calendar.date(
            bySettingHour: dayStartHour,
            minute: 0,
            second: 0,
            of: civilDay,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? civilDay
    }

    private func civilDay(containing date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func shiftedCivilDay(_ civilDay: Date, by dayOffset: Int) -> Date {
        let noon = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: civilDay,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? civilDay
        let shiftedNoon = calendar.date(byAdding: .day, value: dayOffset, to: noon) ?? noon
        return calendar.startOfDay(for: shiftedNoon)
    }
}
