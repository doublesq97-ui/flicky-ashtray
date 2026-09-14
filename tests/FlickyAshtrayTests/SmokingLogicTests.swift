import XCTest
@testable import FlickyAshtray

final class SmokingLogicTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    func testCrossMidnightGapUsesRawTimestamps() {
        var store = SmokeStore()
        store.records = [date("2026-07-13 23:54"), date("2026-07-14 09:12")]

        let result = SmokingLogic.snapshot(store: store, now: date("2026-07-14 10:00"), calendar: calendar)

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.gapMinutes, 558)
    }

    func testDuplicateTimestampsProduceUniqueStableTodayRecordIDs() {
        let timestamp = date("2026-07-14 09:12")
        var store = SmokeStore()
        store.records = [timestamp, timestamp]

        let first = SmokingLogic.snapshot(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )
        let second = SmokingLogic.snapshot(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        XCTAssertEqual(first.records.count, 2)
        XCTAssertEqual(Set(first.records.map(\.id)).count, 2)
        XCTAssertEqual(first.records.map(\.id), second.records.map(\.id))
        XCTAssertEqual(first.records.map(\.date), [timestamp, timestamp])
    }

    func testUndoRemovesOnlyNewestRecordInCurrentCountingDay() {
        var store = SmokeStore()
        store.records = [
            date("2026-07-13 23:54"),
            date("2026-07-14 09:12"),
            date("2026-07-14 11:00")
        ]

        let result = SmokingLogic.undoingLastRecord(in: store, now: date("2026-07-14 12:00"), calendar: calendar)

        XCTAssertEqual(result.records, [date("2026-07-13 23:54"), date("2026-07-14 09:12")])
        XCTAssertFalse(SmokingLogic.canUndoRecord(in: result, now: date("2026-07-14 12:01"), calendar: calendar))
    }

    func testUndoCanOnlyBeUsedOncePerCountingDay() {
        var store = SmokeStore()
        store.records = [date("2026-07-14 09:12"), date("2026-07-14 11:00")]

        let firstUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )
        let secondUndo = SmokingLogic.undoingLastRecord(
            in: firstUndo,
            now: date("2026-07-14 13:00"),
            calendar: calendar
        )

        XCTAssertEqual(firstUndo.records, [date("2026-07-14 09:12")])
        XCTAssertEqual(firstUndo.undoneCountingDays, [date("2026-07-14 00:00")])
        XCTAssertEqual(firstUndo.undoEvents, [
            UndoEvent(
                occurredAt: date("2026-07-14 12:00"),
                countingDayStart: date("2026-07-14 00:00"),
                dayStartHour: 0
            )
        ])
        XCTAssertEqual(secondUndo, firstUndo)
    }

    func testChangingDayStartCannotRestoreUndoAllowanceOnSameCivilDay() {
        var store = SmokeStore()
        store.records = [date("2026-07-14 09:12"), date("2026-07-14 11:00")]
        var afterUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )
        afterUndo.settings.dayStartHour = 8

        XCTAssertFalse(SmokingLogic.canUndoRecord(
            in: afterUndo,
            now: date("2026-07-14 13:00"),
            calendar: calendar
        ))
    }

    func testChangingDayStartToAfterUndoTimeCannotManufactureAnotherAllowance() {
        var store = SmokeStore()
        store.records = [date("2026-07-14 09:12"), date("2026-07-14 11:00")]
        var afterUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )
        afterUndo.settings.dayStartHour = 13
        afterUndo.records.append(date("2026-07-14 13:20"))

        XCTAssertFalse(SmokingLogic.canUndoRecord(
            in: afterUndo,
            now: date("2026-07-14 13:30"),
            calendar: calendar
        ))
    }

    func testChangingDayStartFromEightToSixAllowsUndoAfterFrozenRangeEnds() {
        var store = SmokeStore()
        store.settings.dayStartHour = 8
        store.records = [date("2026-07-14 09:00"), date("2026-07-14 11:00")]
        var afterUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )

        afterUndo.settings.dayStartHour = 6
        afterUndo.records.append(date("2026-07-15 08:30"))

        XCTAssertTrue(SmokingLogic.canUndoRecord(
            in: afterUndo,
            now: date("2026-07-15 09:00"),
            calendar: calendar
        ))
    }

    func testChangingBoundaryStillBlocksWhenCurrentPolicyReclassifiesUndoIntoToday() {
        var store = SmokeStore()
        store.settings.dayStartHour = 8
        store.records = [date("2026-07-13 21:00"), date("2026-07-14 01:30")]
        var afterUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 02:00"),
            calendar: calendar
        )

        afterUndo.settings.dayStartHour = 0
        afterUndo.records.append(date("2026-07-14 09:00"))

        XCTAssertFalse(SmokingLogic.canUndoRecord(
            in: afterUndo,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        ))
    }

    func testUndoAtTwoAMDoesNotBlockNewEightAMCountingDay() {
        var store = SmokeStore()
        store.settings.dayStartHour = 8
        store.records = [
            date("2026-07-13 21:00"),
            date("2026-07-14 01:30"),
            date("2026-07-14 10:00")
        ]

        let afterTwoAMUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 02:00"),
            calendar: calendar
        )

        XCTAssertEqual(afterTwoAMUndo.undoEvents.first?.countingDayStart, date("2026-07-13 08:00"))
        XCTAssertTrue(SmokingLogic.canUndoRecord(
            in: afterTwoAMUndo,
            now: date("2026-07-14 10:15"),
            calendar: calendar
        ))
    }

    func testUndoAllowanceResetsOnNextCustomCountingDay() {
        var store = SmokeStore()
        store.settings.dayStartHour = 8
        store.records = [
            date("2026-07-14 09:00"),
            date("2026-07-14 10:00"),
            date("2026-07-15 09:00")
        ]

        let firstDay = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )

        XCTAssertTrue(SmokingLogic.canUndoRecord(
            in: firstDay,
            now: date("2026-07-15 10:00"),
            calendar: calendar
        ))
    }

    func testUndoFreezesSpringDSTRangeAndDoesNotBlockAfterItEnds() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var store = SmokeStore()
        store.settings.dayStartHour = 2
        store.records = [
            date("2026-03-08 03:15", calendar: losAngeles),
            date("2026-03-08 03:20", calendar: losAngeles)
        ]

        var afterUndo = SmokingLogic.undoingLastRecord(
            in: store,
            now: date("2026-03-08 03:30", calendar: losAngeles),
            calendar: losAngeles
        )

        XCTAssertEqual(
            afterUndo.undoEvents.first?.originalStart,
            date("2026-03-08 03:00", calendar: losAngeles)
        )
        XCTAssertEqual(
            afterUndo.undoEvents.first?.originalEnd,
            date("2026-03-09 02:00", calendar: losAngeles)
        )

        afterUndo.settings.dayStartHour = 0
        afterUndo.records.append(date("2026-03-09 02:15", calendar: losAngeles))
        XCTAssertTrue(SmokingLogic.canUndoRecord(
            in: afterUndo,
            now: date("2026-03-09 02:30", calendar: losAngeles),
            calendar: losAngeles
        ))
    }

    func testResetClearsHistoryAndChallengeButPreservesPreferencesAndAuditTrail() {
        let firstReset = ResetEvent(
            occurredAt: date("2026-06-01 10:00"),
            reason: "上一次重新开始",
            clearedRecordCount: 12
        )
        var store = SmokeStore()
        store.settings.dailyLimit = 6
        store.settings.dayStartHour = 8
        store.firstRunDone = true
        store.records = [date("2026-07-14 09:00"), date("2026-07-14 10:00")]
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-14 09:00"),
            targetDays: 5,
            reward: "喝杯咖啡",
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        store.undoneCountingDays = [date("2026-07-14 08:00")]
        store.undoEvents = [
            UndoEvent(
                occurredAt: date("2026-07-14 12:00"),
                countingDayStart: date("2026-07-14 08:00"),
                dayStartHour: 8
            )
        ]
        store.resetEvents = [firstReset]

        let result = SmokingLogic.resettingHistory(
            in: store,
            at: date("2026-07-14 12:00"),
            reason: "  想按新的作息重新开始  "
        )

        XCTAssertEqual(result.settings.dailyLimit, 6)
        XCTAssertEqual(result.settings.dayStartHour, 8)
        XCTAssertTrue(result.firstRunDone)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertNil(result.weeklyChallenge)
        XCTAssertTrue(result.undoneCountingDays.isEmpty)
        XCTAssertTrue(result.undoEvents.isEmpty)
        XCTAssertEqual(result.resetEvents.count, 2)
        XCTAssertEqual(result.resetEvents[0], firstReset)
        XCTAssertEqual(result.resetEvents[1].reason, "想按新的作息重新开始")
        XCTAssertEqual(result.resetEvents[1].clearedRecordCount, 2)
    }

    func testCustomEightAMDayStartTreatsTwoAMAsPreviousDay() {
        var store = SmokeStore()
        store.settings.dayStartHour = 8
        store.records = [date("2026-07-14 02:00"), date("2026-07-14 10:00")]

        let result = SmokingLogic.snapshot(store: store, now: date("2026-07-14 11:00"), calendar: calendar)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.records.first?.date, date("2026-07-14 10:00"))
    }

    func testNewCountingDayStartsWithCleanAshtray() {
        var store = SmokeStore()
        store.records = [date("2026-07-13 20:00"), date("2026-07-13 22:00")]

        let result = SmokingLogic.snapshot(store: store, now: date("2026-07-14 09:00"), calendar: calendar)

        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.ashLevel, .clean)
    }

    func testFullThresholdMatchesSmallAndLargeLimits() {
        var three = SmokeStore()
        three.settings.dailyLimit = 3
        XCTAssertEqual(SmokingLogic.snapshot(store: three, now: date("2026-07-14 09:00"), calendar: calendar).visibleFullAt, 2)

        var ten = SmokeStore()
        ten.settings.dailyLimit = 10
        XCTAssertEqual(SmokingLogic.snapshot(store: ten, now: date("2026-07-14 09:00"), calendar: calendar).visibleFullAt, 6)
    }

    func testAshEscalationAtLimitEightMatchesVisualStages() {
        let base = date("2026-07-14 09:00")
        func level(for count: Int) -> DaySnapshot.AshLevel {
            var store = SmokeStore()
            store.settings.dailyLimit = 8
            store.records = (0..<count).compactMap {
                calendar.date(byAdding: .minute, value: $0, to: base)
            }
            return SmokingLogic.snapshot(
                store: store,
                now: date("2026-07-14 12:00"),
                calendar: calendar
            ).ashLevel
        }

        XCTAssertEqual(level(for: 0), .clean)
        XCTAssertEqual(level(for: 1), .sprinkle)
        XCTAssertEqual(level(for: 4), .sprinkle)
        XCTAssertEqual(level(for: 5), .full)
        XCTAssertEqual(level(for: 7), .full)
        XCTAssertEqual(level(for: 8), .overLimit)
        XCTAssertEqual(level(for: 11), .overLimit)
        XCTAssertEqual(level(for: 12), .filthy)
    }

    func testFilthyThresholdScalesReasonablyForLowLimit() {
        var store = SmokeStore()
        store.settings.dailyLimit = 3
        store.records = (0..<5).compactMap {
            calendar.date(byAdding: .minute, value: $0, to: date("2026-07-14 09:00"))
        }

        let snapshot = SmokingLogic.snapshot(
            store: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.visibleFullAt, 2)
        XCTAssertEqual(snapshot.visibleFilthyAt, 5)
        XCTAssertEqual(snapshot.ashLevel, .filthy)
    }

    func testFirstCigaretteIsAlwaysSprinkleEvenWhenDailyLimitIsOne() {
        var store = SmokeStore()
        store.settings.dailyLimit = 1
        store.records = [date("2026-07-14 09:00")]

        let snapshot = SmokingLogic.snapshot(
            store: store,
            now: date("2026-07-14 12:00"),
            calendar: calendar
        )

        XCTAssertTrue(snapshot.isAtLimit)
        XCTAssertEqual(snapshot.ashLevel, .sprinkle)
    }

    func testWeeklyCadencePeriodStartsRespectWeekStyleAndCountingBoundary() {
        let midweek = date("2026-07-15 10:00")

        XCTAssertEqual(
            SmokingLogic.weeklyPeriodStart(
                for: midweek,
                cadence: .rollingSevenDays,
                dayStartHour: 8,
                calendar: calendar
            ),
            date("2026-07-15 08:00")
        )
        XCTAssertEqual(
            SmokingLogic.weeklyPeriodStart(
                for: midweek,
                cadence: .calendarWeekMonday,
                dayStartHour: 8,
                calendar: calendar
            ),
            date("2026-07-13 08:00")
        )
        XCTAssertEqual(
            SmokingLogic.weeklyPeriodStart(
                for: midweek,
                cadence: .calendarWeekSunday,
                dayStartHour: 8,
                calendar: calendar
            ),
            date("2026-07-12 08:00")
        )
        XCTAssertEqual(
            SmokingLogic.weeklyPeriodStart(
                for: date("2026-07-13 02:00"),
                cadence: .calendarWeekMonday,
                dayStartHour: 8,
                calendar: calendar
            ),
            date("2026-07-06 08:00")
        )
    }

    func testNaturalWeekProgressUsesFrozenPeriodStartRatherThanStartButtonTime() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-15 10:00"),
            targetDays: 5,
            reward: "看一场电影",
            cadence: .calendarWeekMonday,
            periodStart: date("2026-07-13 08:00"),
            dailyLimit: 2,
            dayStartHour: 8,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-07-16 08:00"),
            calendar: calendar
        )

        XCTAssertEqual(progress?.start, date("2026-07-13 08:00"))
        XCTAssertEqual(progress?.completedDays, 1)
        XCTAssertEqual(progress?.achievedDays, 1)
        XCTAssertEqual(progress?.remainingDays, 4)
        XCTAssertEqual(progress?.maximumAchievableDays, 5)
        XCTAssertEqual(progress?.days.map(\.status), [
            .notParticipating,
            .notParticipating,
            .achieved,
            .active,
            .upcoming,
            .upcoming,
            .upcoming
        ])
    }

    func testChallengeKeepsFrozenShanghaiTimeZoneWhenEvaluatedFromLosAngeles() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-15 10:00"),
            targetDays: 5,
            reward: "散步",
            cadence: .calendarWeekMonday,
            periodStart: date("2026-07-13 08:00"),
            dailyLimit: 2,
            dayStartHour: 8,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-07-16 08:00"),
            calendar: losAngeles
        )

        XCTAssertEqual(progress?.start, date("2026-07-13 08:00"))
        XCTAssertEqual(progress?.end, date("2026-07-20 08:00"))
        XCTAssertEqual(progress?.days[2].start, date("2026-07-15 08:00"))
        XCTAssertEqual(progress?.days[0].status, .notParticipating)
        XCTAssertEqual(progress?.days[1].status, .notParticipating)
    }

    func testFrozenLosAngelesChallengeUsesDSTAdjustedBoundariesFromUTCCaller() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 2
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-03-07 03:00", calendar: losAngeles),
            targetDays: 5,
            reward: "散步",
            cadence: .rollingSevenDays,
            periodStart: date("2026-03-07 02:00", calendar: losAngeles),
            dailyLimit: 2,
            dayStartHour: 2,
            timeZoneIdentifier: losAngeles.timeZone.identifier
        )
        store.records = [
            date("2026-03-08 03:15", calendar: losAngeles),
            date("2026-03-09 01:30", calendar: losAngeles)
        ]

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-03-09 02:30", calendar: losAngeles),
            calendar: utc
        )

        XCTAssertEqual(progress?.days[0].start, date("2026-03-07 02:00", calendar: losAngeles))
        XCTAssertEqual(progress?.days[1].start, date("2026-03-08 03:00", calendar: losAngeles))
        XCTAssertEqual(progress?.days[2].start, date("2026-03-09 02:00", calendar: losAngeles))
        XCTAssertEqual(progress?.days[1].cigaretteCount, 2)
        XCTAssertEqual(progress?.completedDays, 2)
    }

    func testNewChallengeMaximumExcludesAnActiveDayAlreadyOverLimit() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 8
        store.records = [
            date("2026-07-15 08:30"),
            date("2026-07-15 09:00"),
            date("2026-07-15 09:30")
        ]
        let now = date("2026-07-15 10:00")

        XCTAssertEqual(
            SmokingLogic.maximumAchievableDays(
                store: store,
                now: now,
                cadence: .calendarWeekMonday,
                calendar: calendar
            ),
            4
        )
        XCTAssertEqual(
            SmokingLogic.maximumAchievableDays(
                store: store,
                now: now,
                cadence: .rollingSevenDays,
                calendar: calendar
            ),
            6
        )
    }

    func testNewChallengeMaximumIncludesAnActiveDayStillWithinLimit() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 8
        store.records = [
            date("2026-07-15 08:30"),
            date("2026-07-15 09:00")
        ]
        let now = date("2026-07-15 10:00")

        XCTAssertEqual(
            SmokingLogic.maximumAchievableDays(
                store: store,
                now: now,
                cadence: .calendarWeekMonday,
                calendar: calendar
            ),
            5
        )
        XCTAssertEqual(
            SmokingLogic.maximumAchievableDays(
                store: store,
                now: now,
                cadence: .rollingSevenDays,
                calendar: calendar
            ),
            7
        )
    }

    func testEditingMaximumCountsAchievedAndStillPossibleDaysOnly() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 8
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-13 09:00"),
            targetDays: 7,
            reward: "散步",
            cadence: .calendarWeekMonday,
            periodStart: date("2026-07-13 08:00"),
            dailyLimit: 2,
            dayStartHour: 8,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        store.records = [
            date("2026-07-13 10:00"),
            date("2026-07-14 09:00"),
            date("2026-07-14 10:00"),
            date("2026-07-14 11:00"),
            date("2026-07-15 09:00"),
            date("2026-07-15 10:00"),
            date("2026-07-15 11:00")
        ]

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-07-15 12:00"),
            calendar: calendar
        )

        XCTAssertEqual(progress?.achievedDays, 1)
        XCTAssertEqual(progress?.maximumAchievableDays, 5)
        XCTAssertEqual(progress?.challenge.targetDays, 7)
        XCTAssertEqual(progress?.isAchieved, false)
    }

    func testLegacyNaturalWeekTargetNormalizesOnlyToCreationParticipation() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 8
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-15 10:00"),
            targetDays: 7,
            reward: "看电影",
            cadence: .calendarWeekMonday,
            periodStart: date("2026-07-13 08:00"),
            dailyLimit: 2,
            dayStartHour: 8,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        store.normalize()

        XCTAssertEqual(store.weeklyChallenge?.targetDays, 5)

        store.records = [
            date("2026-07-15 11:00"),
            date("2026-07-15 12:00"),
            date("2026-07-15 13:00")
        ]
        store.normalize()
        XCTAssertEqual(
            store.weeklyChallenge?.targetDays,
            5,
            "Missed or over-limit days must not silently lower the saved promise"
        )
    }

    func testSevenDayChallengeCountsOnlyFinishedDaysAndStaysRecoverable() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-14 09:00"),
            targetDays: 3,
            reward: "周末喝一杯喜欢的咖啡",
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        store.records = [
            date("2026-07-14 10:00"), date("2026-07-14 15:00"),
            date("2026-07-15 09:00"), date("2026-07-15 12:00"), date("2026-07-15 18:00"),
            date("2026-07-17 11:00")
        ]

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-07-18 09:00"),
            calendar: calendar
        )

        XCTAssertEqual(progress?.completedDays, 4)
        XCTAssertEqual(progress?.achievedDays, 3)
        XCTAssertEqual(progress?.remainingDays, 3)
        XCTAssertEqual(progress?.isAchieved, true)
        XCTAssertEqual(progress?.isFinished, false)
    }

    func testSevenDayChallengeRespectsCustomCountingDayBoundary() {
        var store = SmokeStore()
        store.settings.dailyLimit = 1
        store.settings.dayStartHour = 8
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-14 10:00"),
            targetDays: 2,
            reward: "买一束花",
            dailyLimit: 1,
            dayStartHour: 8,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        store.settings.dayStartHour = 0
        store.records = [date("2026-07-15 02:00"), date("2026-07-15 10:00")]

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-07-16 09:00"),
            calendar: calendar
        )

        XCTAssertEqual(progress?.completedDays, 2)
        XCTAssertEqual(progress?.achievedDays, 2)
    }

    func testSevenDayChallengeFinishesWithoutUsingFailureLanguageAsState() {
        var store = SmokeStore()
        store.settings.dailyLimit = 1
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: date("2026-07-14 09:00"),
            targetDays: 5,
            reward: "看一场电影",
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        store.records = [
            date("2026-07-14 10:00"), date("2026-07-14 11:00"),
            date("2026-07-16 10:00"), date("2026-07-16 11:00")
        ]

        let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: date("2026-07-21 09:00"),
            calendar: calendar
        )

        XCTAssertEqual(progress?.completedDays, 7)
        XCTAssertEqual(progress?.achievedDays, 5)
        XCTAssertEqual(progress?.isFinished, true)
        XCTAssertEqual(progress?.isAchieved, true)
    }

    private func date(_ value: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
