import Foundation

extension CodingUserInfoKey {
    static let flickyStoreSourceVersion = CodingUserInfoKey(
        rawValue: "com.flicky-ashtray.store-source-version"
    )!
}

private extension Decoder {
    var flickyStoreSourceVersion: Int {
        userInfo[.flickyStoreSourceVersion] as? Int ?? 1
    }
}

enum PetStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case ashtray
    case note
}

struct AppSettings: Codable, Equatable, Sendable {
    var dailyLimit: Int = 8
    var dayStartHour: Int = 0
    var petScale: Double = 1.0
    var petStyle: PetStyle = .ashtray

    init(
        dailyLimit: Int = 8,
        dayStartHour: Int = 0,
        petScale: Double = 1.0,
        petStyle: PetStyle = .ashtray
    ) {
        self.dailyLimit = dailyLimit
        self.dayStartHour = dayStartHour
        self.petScale = petScale
        self.petStyle = petStyle
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case dailyLimit
        case dayStartHour
        case petScale
        case petStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyLimit = try container.decode(Int.self, forKey: .dailyLimit)
        dayStartHour = try container.decode(Int.self, forKey: .dayStartHour)
        if decoder.flickyStoreSourceVersion >= 7 {
            petScale = try container.decode(Double.self, forKey: .petScale)
        } else {
            petScale = try container.decodeIfPresent(Double.self, forKey: .petScale) ?? 1.0
        }
        if decoder.flickyStoreSourceVersion >= 8 {
            petStyle = try container.decode(PetStyle.self, forKey: .petStyle)
        } else {
            petStyle = .ashtray
        }
        normalize()
    }

    mutating func normalize() {
        dailyLimit = min(60, max(1, dailyLimit))
        dayStartHour = min(23, max(0, dayStartHour))
        petScale = min(1.0, max(0.6, petScale))
    }
}

enum WeeklyCadence: String, Codable, CaseIterable, Equatable, Sendable {
    case rollingSevenDays
    case calendarWeekMonday
    case calendarWeekSunday
}

struct WeeklyChallenge: Codable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var targetDays: Int
    var reward: String
    var cadence: WeeklyCadence
    var periodStart: Date?
    var dailyLimit: Int?
    var dayStartHour: Int?
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        startedAt: Date,
        targetDays: Int,
        reward: String,
        cadence: WeeklyCadence = .rollingSevenDays,
        periodStart: Date? = nil,
        dailyLimit: Int? = nil,
        dayStartHour: Int? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.startedAt = startedAt
        self.targetDays = targetDays
        self.reward = reward
        self.cadence = cadence
        self.periodStart = periodStart
        self.dailyLimit = dailyLimit
        self.dayStartHour = dayStartHour
        self.timeZoneIdentifier = timeZoneIdentifier
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case targetDays
        case reward
        case cadence
        case periodStart
        case dailyLimit
        case dayStartHour
        case timeZoneIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if decoder.flickyStoreSourceVersion >= 7 {
            id = try container.decode(UUID.self, forKey: .id)
            startedAt = try container.decode(Date.self, forKey: .startedAt)
            targetDays = try container.decode(Int.self, forKey: .targetDays)
            reward = try container.decode(String.self, forKey: .reward)
            cadence = try container.decode(WeeklyCadence.self, forKey: .cadence)
            periodStart = try container.decode(Date.self, forKey: .periodStart)
            dailyLimit = try container.decode(Int.self, forKey: .dailyLimit)
            dayStartHour = try container.decode(Int.self, forKey: .dayStartHour)
            timeZoneIdentifier = try container.decode(
                String.self,
                forKey: .timeZoneIdentifier
            )
        } else {
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            startedAt = try container.decode(Date.self, forKey: .startedAt)
            targetDays = try container.decodeIfPresent(Int.self, forKey: .targetDays) ?? 5
            reward = try container.decodeIfPresent(String.self, forKey: .reward) ?? ""
            cadence = try container.decodeIfPresent(WeeklyCadence.self, forKey: .cadence)
                ?? .rollingSevenDays
            periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
            dailyLimit = try container.decodeIfPresent(Int.self, forKey: .dailyLimit)
            dayStartHour = try container.decodeIfPresent(Int.self, forKey: .dayStartHour)
            timeZoneIdentifier = try container.decodeIfPresent(
                String.self,
                forKey: .timeZoneIdentifier
            ) ?? TimeZone.current.identifier
        }
        normalize()
    }

    mutating func normalize() {
        targetDays = min(7, max(1, targetDays))
        reward = reward.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dailyLimit {
            self.dailyLimit = min(60, max(1, dailyLimit))
        }
        if let dayStartHour {
            self.dayStartHour = min(23, max(0, dayStartHour))
        }
        if TimeZone(identifier: timeZoneIdentifier) == nil {
            timeZoneIdentifier = TimeZone.current.identifier
        }
    }
}

struct UndoEvent: Codable, Equatable, Hashable, Sendable {
    var occurredAt: Date
    var originalStart: Date
    var originalEnd: Date
    var dayStartHour: Int

    var countingDayStart: Date { originalStart }

    var originalRange: CountingDayRange {
        CountingDayRange(
            civilDayStart: originalStart,
            start: originalStart,
            end: originalEnd
        )
    }

    init(
        occurredAt: Date,
        originalRange: CountingDayRange,
        dayStartHour: Int
    ) {
        self.occurredAt = occurredAt
        originalStart = originalRange.start
        originalEnd = originalRange.end
        self.dayStartHour = dayStartHour
        normalize()
    }

    init(
        occurredAt: Date,
        countingDayStart: Date,
        dayStartHour: Int
    ) {
        self.occurredAt = occurredAt
        originalStart = countingDayStart
        originalEnd = Self.legacyOriginalEnd(
            start: countingDayStart,
            occurredAt: occurredAt,
            dayStartHour: dayStartHour
        )
        self.dayStartHour = dayStartHour
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case occurredAt
        case originalStart
        case originalEnd
        case dayStartHour
        case countingDayStart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)

        if decoder.flickyStoreSourceVersion >= 6 {
            dayStartHour = try container.decode(Int.self, forKey: .dayStartHour)
            originalStart = try container.decode(Date.self, forKey: .originalStart)
            originalEnd = try container.decode(Date.self, forKey: .originalEnd)
        } else {
            dayStartHour = try container.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? 0
            if let decodedStart = try container.decodeIfPresent(Date.self, forKey: .originalStart),
               let decodedEnd = try container.decodeIfPresent(Date.self, forKey: .originalEnd) {
                originalStart = decodedStart
                originalEnd = decodedEnd
            } else {
                let legacyStart = try container.decode(Date.self, forKey: .countingDayStart)
                originalStart = legacyStart
                originalEnd = Self.legacyOriginalEnd(
                    start: legacyStart,
                    occurredAt: occurredAt,
                    dayStartHour: dayStartHour
                )
            }
        }
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(originalStart, forKey: .originalStart)
        try container.encode(originalEnd, forKey: .originalEnd)
        try container.encode(dayStartHour, forKey: .dayStartHour)
    }

    mutating func normalize() {
        dayStartHour = min(23, max(0, dayStartHour))
        if originalEnd <= originalStart {
            originalEnd = Self.legacyOriginalEnd(
                start: originalStart,
                occurredAt: occurredAt,
                dayStartHour: dayStartHour
            )
        }
    }

    private static func legacyOriginalEnd(
        start: Date,
        occurredAt: Date,
        dayStartHour: Int
    ) -> Date {
        let policy = CountingDayPolicy(dayStartHour: dayStartHour)
        let occurrenceRange = policy.range(containing: occurredAt)
        if occurrenceRange.start == start {
            return occurrenceRange.end
        }

        let startRange = policy.range(containing: start)
        if startRange.start == start {
            return startRange.end
        }

        // Versions 3–5 did not persist a time zone or an end boundary. If the
        // user migrated after changing time zones, the exact historical civil
        // boundary is unrecoverable; a frozen 24-hour interval is safer than
        // inventing a 32/40-hour guard from the new zone's wall clock.
        return start.addingTimeInterval(24 * 60 * 60)
    }
}

struct ResetEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var occurredAt: Date
    var reason: String
    var clearedRecordCount: Int

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        reason: String,
        clearedRecordCount: Int
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.reason = reason
        self.clearedRecordCount = clearedRecordCount
        normalize()
    }

    mutating func normalize() {
        reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty {
            reason = "未填写原因"
        }
        clearedRecordCount = max(0, clearedRecordCount)
    }
}

struct SmokeStore: Codable, Equatable, Sendable {
    var version: Int
    var settings: AppSettings
    var records: [Date]
    var firstRunDone: Bool
    var weeklyChallenge: WeeklyChallenge?
    var undoneCountingDays: [Date]
    var undoEvents: [UndoEvent]
    var resetEvents: [ResetEvent]

    init(
        version: Int = 8,
        settings: AppSettings = AppSettings(),
        records: [Date] = [],
        firstRunDone: Bool = false,
        weeklyChallenge: WeeklyChallenge? = nil,
        undoneCountingDays: [Date] = [],
        undoEvents: [UndoEvent] = [],
        resetEvents: [ResetEvent] = []
    ) {
        self.version = version
        self.settings = settings
        self.records = records
        self.firstRunDone = firstRunDone
        self.weeklyChallenge = weeklyChallenge
        self.undoneCountingDays = undoneCountingDays
        self.undoEvents = undoEvents
        self.resetEvents = resetEvents
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case settings
        case records
        case firstRunDone
        case weeklyChallenge
        case undoneCountingDays
        case undoEvents
        case resetEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version)
        version = decodedVersion ?? 1
        if decodedVersion == nil {
            let settingsProbe = try container.decode(
                StoreSettingsSchemaProbe.self,
                forKey: .settings
            )
            let hasModernShape = settingsProbe.containsPetScale
                || settingsProbe.containsPetStyle
                || container.contains(.weeklyChallenge)
                || container.contains(.undoneCountingDays)
                || container.contains(.undoEvents)
                || container.contains(.resetEvents)
            guard !hasModernShape else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version,
                    in: container,
                    debugDescription: "现代记录结构缺少版本号，无法安全推断迁移来源。"
                )
            }
        }
        let sourceVersion = decoder.userInfo[.flickyStoreSourceVersion] as? Int ?? version
        settings = try container.decode(AppSettings.self, forKey: .settings)
        records = try container.decode([Date].self, forKey: .records)
        firstRunDone = try container.decode(Bool.self, forKey: .firstRunDone)
        weeklyChallenge = try container.decodeIfPresent(
            WeeklyChallenge.self,
            forKey: .weeklyChallenge
        )

        if sourceVersion >= 7 {
            undoneCountingDays = try container.decode([Date].self, forKey: .undoneCountingDays)
            undoEvents = try container.decode([UndoEvent].self, forKey: .undoEvents)
            resetEvents = try container.decode([ResetEvent].self, forKey: .resetEvents)
        } else {
            undoneCountingDays = sourceVersion >= 3
                ? try container.decode([Date].self, forKey: .undoneCountingDays)
                : []

            if sourceVersion <= 3 {
                undoEvents = []
            } else if sourceVersion == 4 {
                let legacyDates = try container.decode([Date].self, forKey: .undoEvents)
                let legacyDayStartHour = settings.dayStartHour
                undoEvents = legacyDates.map { occurredAt in
                    UndoEvent(
                        occurredAt: occurredAt,
                        countingDayStart: SmokingLogic.countingDayStart(
                            for: occurredAt,
                            dayStartHour: legacyDayStartHour
                        ),
                        dayStartHour: legacyDayStartHour
                    )
                }
            } else {
                undoEvents = try container.decode(
                    [UndoEvent].self,
                    forKey: .undoEvents
                )
            }
            resetEvents = sourceVersion >= 5
                ? try container.decode([ResetEvent].self, forKey: .resetEvents)
                : []
        }
        normalize()
    }

    mutating func normalize() {
        settings.normalize()
        if var challenge = weeklyChallenge {
            challenge.dailyLimit = challenge.dailyLimit ?? settings.dailyLimit
            challenge.dayStartHour = challenge.dayStartHour ?? settings.dayStartHour
            challenge.normalize()
            if challenge.periodStart == nil {
                let challengeCalendar = SmokingLogic.calendar(
                    frozenFor: challenge,
                    basedOn: .current
                )
                challenge.periodStart = SmokingLogic.weeklyPeriodStart(
                    for: challenge.startedAt,
                    cadence: challenge.cadence,
                    dayStartHour: challenge.dayStartHour ?? settings.dayStartHour,
                    calendar: challengeCalendar
                )
            }
            let structuralMaximum = SmokingLogic.maximumParticipatingDays(
                for: challenge,
                fallbackDayStartHour: settings.dayStartHour
            )
            if structuralMaximum > 0 {
                challenge.targetDays = min(challenge.targetDays, structuralMaximum)
            }
            weeklyChallenge = challenge
        }
        records.sort()
        undoneCountingDays = Array(Set(undoneCountingDays)).sorted()
        undoEvents = Array(Set(undoEvents.map { event in
            var normalized = event
            normalized.normalize()
            return normalized
        })).sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.originalStart < rhs.originalStart
            }
            return lhs.occurredAt < rhs.occurredAt
        }
        var undoEventStarts = Set(undoEvents.map(\.originalStart))
        for dayStart in undoneCountingDays {
            guard undoEventStarts.insert(dayStart).inserted else { continue }
            undoEvents.append(
                UndoEvent(
                    occurredAt: dayStart,
                    countingDayStart: dayStart,
                    dayStartHour: settings.dayStartHour
                )
            )
        }
        undoEvents.sort { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.originalStart < rhs.originalStart
            }
            return lhs.occurredAt < rhs.occurredAt
        }
        undoneCountingDays = Array(Set(undoneCountingDays + undoEvents.map(\.originalStart))).sorted()
        resetEvents = resetEvents.map { event in
            var normalized = event
            normalized.normalize()
            return normalized
        }.sorted { $0.occurredAt < $1.occurredAt }
        version = 8
    }
}

private struct StoreSettingsSchemaProbe: Decodable {
    let containsPetScale: Bool
    let containsPetStyle: Bool

    private enum CodingKeys: String, CodingKey {
        case petScale
        case petStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containsPetScale = container.contains(.petScale)
        containsPetStyle = container.contains(.petStyle)
    }
}

struct WeeklyChallengeDay: Identifiable, Equatable, Sendable {
    let id: Date
    let start: Date
    let cigaretteCount: Int
    let status: Status

    enum Status: Equatable, Sendable {
        case achieved, missed, active, upcoming, notParticipating
    }
}

struct WeeklyChallengeProgress: Equatable, Sendable {
    let challenge: WeeklyChallenge
    let start: Date
    let end: Date
    let dailyLimit: Int
    let completedDays: Int
    let achievedDays: Int
    let remainingDays: Int
    let maximumAchievableDays: Int
    let isFinished: Bool
    let isAchieved: Bool
    let days: [WeeklyChallengeDay]

    var daysStillNeeded: Int {
        max(0, challenge.targetDays - achievedDays)
    }
}

struct TodayRecord: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let date: Date
        let ordinal: Int
    }

    let id: ID
    let number: Int
    let date: Date
    let gapMinutes: Int?

    init(id _: Date, number: Int, date: Date, gapMinutes: Int?) {
        self.id = ID(date: date, ordinal: number)
        self.number = number
        self.date = date
        self.gapMinutes = gapMinutes
    }

    init(id _: ID, number: Int, date: Date, gapMinutes: Int?) {
        self.id = ID(date: date, ordinal: number)
        self.number = number
        self.date = date
        self.gapMinutes = gapMinutes
    }
}

struct DayTotal: Identifiable, Equatable, Sendable {
    let id: Date
    let date: Date
    let count: Int
}

struct DaySnapshot: Equatable, Sendable {
    let count: Int
    let limit: Int
    let remaining: Int
    let isAtLimit: Bool
    let isOverLimit: Bool
    let visibleFullAt: Int
    let visibleFilthyAt: Int
    let records: [TodayRecord]
    let lastSevenDays: [DayTotal]

    var ashLevel: AshLevel {
        if count == 0 { return .clean }
        if count == 1 { return .sprinkle }
        if count >= visibleFilthyAt { return .filthy }
        if count >= limit { return .overLimit }
        if count >= visibleFullAt { return .full }
        return .sprinkle
    }

    enum AshLevel: Equatable, Sendable {
        case clean, sprinkle, full, overLimit, filthy
    }
}
