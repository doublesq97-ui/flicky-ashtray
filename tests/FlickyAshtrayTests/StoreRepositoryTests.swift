import Foundation
import XCTest
@testable import FlickyAshtray

final class StoreRepositoryTests: XCTestCase {
    func testRepositoryVersionMatchesNormalizedModelVersion() {
        XCTAssertEqual(StoreRepository.currentVersion, SmokeStore().version)
    }

    func testFractionalSecondRecordsRemainDistinctAcrossRelaunch() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let first = Date(timeIntervalSince1970: 1_720_944_000.123)
        let second = Date(timeIntervalSince1970: 1_720_944_000.789)
        var store = SmokeStore()
        store.firstRunDone = true
        store.records = [first, second]
        store.normalize()

        try repository.save(store)
        let relaunched = try XCTUnwrap(repository.load().store)

        XCTAssertEqual(relaunched.records.count, 2)
        XCTAssertNotEqual(relaunched.records[0], relaunched.records[1])
        XCTAssertEqual(
            relaunched.records[1].timeIntervalSince(relaunched.records[0]),
            0.666,
            accuracy: 0.002
        )
        let persisted = try XCTUnwrap(String(data: Data(contentsOf: repository.fileURL), encoding: .utf8))
        XCTAssertTrue(persisted.contains(".123Z"))
        XCTAssertTrue(persisted.contains(".789Z"))
    }

    func testLegacyWholeSecondISO8601DatesRemainReadable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 8,
          "settings": {
            "dailyLimit": 8,
            "dayStartHour": 0,
            "petScale": 1.0,
            "petStyle": "ashtray"
          },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true,
          "undoneCountingDays": [],
          "undoEvents": [],
          "resetEvents": []
        }
        """
        try Data(json.utf8).write(to: file)

        let result = StoreRepository(fileURL: file).load()

        XCTAssertEqual(result.status, .loaded)
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(
            result.store?.records,
            [ISO8601DateFormatter().date(from: "2026-07-14T01:12:00Z")!]
        )
    }

    func testThousandRecordSaveAndLoadDoesNotRegressToPerDateFormatterConstruction() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var store = SmokeStore()
        store.firstRunDone = true
        store.records = (0..<1_000).map { offset in
            Date(timeIntervalSince1970: 1_720_944_000 + Double(offset) / 100)
        }
        store.normalize()

        let startedAt = CFAbsoluteTimeGetCurrent()
        try repository.save(store)
        let relaunched = try XCTUnwrap(repository.load().store)
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertEqual(relaunched.records.count, 1_000)
        XCTAssertLessThan(elapsed, 2.0, "1,000-record save+load took \(elapsed)s")
    }

    func testVersionOneStoreLoadsWithoutWeeklyChallenge() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let json = """
        {
          "version": 1,
          "settings": { "dailyLimit": 8, "dayStartHour": 0 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true
        }
        """
        try Data(json.utf8).write(to: file)

        let result = StoreRepository(fileURL: file).load()
        let store = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .migrated(fromVersion: 1))
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(store.version, StoreRepository.currentVersion)
        XCTAssertEqual(store.settings.dailyLimit, 8)
        XCTAssertEqual(store.settings.petScale, 1.0)
        XCTAssertEqual(store.settings.petStyle, .ashtray)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertNil(store.weeklyChallenge)
        XCTAssertTrue(store.undoneCountingDays.isEmpty)
        XCTAssertTrue(store.undoEvents.isEmpty)
        XCTAssertTrue(store.resetEvents.isEmpty)
    }

    func testVersionTwoStoreMigratesNewGuardFieldsWithoutLosingData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let json = """
        {
          "version": 2,
          "settings": { "dailyLimit": 6, "dayStartHour": 8 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true,
          "weeklyChallenge": {
            "id": "A729F6E8-E7BD-45E5-9831-71117A35A9BD",
            "startedAt": "2026-07-14T01:00:00Z",
            "targetDays": 5,
            "reward": "买一束花",
            "dailyLimit": 6
          }
        }
        """
        try Data(json.utf8).write(to: file)

        let result = StoreRepository(fileURL: file).load()
        let store = try XCTUnwrap(result.store)
        let challengeStartedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-14T01:00:00Z")
        )
        let expectedPeriodStart = SmokingLogic.weeklyPeriodStart(
            for: challengeStartedAt,
            cadence: .rollingSevenDays,
            dayStartHour: 8
        )

        XCTAssertEqual(result.status, .migrated(fromVersion: 2))
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(store.version, StoreRepository.currentVersion)
        XCTAssertEqual(store.settings.dailyLimit, 6)
        XCTAssertEqual(store.settings.dayStartHour, 8)
        XCTAssertEqual(store.settings.petScale, 1.0)
        XCTAssertEqual(store.settings.petStyle, .ashtray)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.weeklyChallenge?.reward, "买一束花")
        XCTAssertEqual(store.weeklyChallenge?.dailyLimit, 6)
        XCTAssertEqual(store.weeklyChallenge?.dayStartHour, 8)
        XCTAssertEqual(store.weeklyChallenge?.cadence, .rollingSevenDays)
        XCTAssertEqual(store.weeklyChallenge?.periodStart, expectedPeriodStart)
        XCTAssertTrue(store.undoneCountingDays.isEmpty)
        XCTAssertTrue(store.undoEvents.isEmpty)
        XCTAssertTrue(store.resetEvents.isEmpty)

        var settingsChanged = store
        settingsChanged.settings.dailyLimit = 2
        settingsChanged.settings.dayStartHour = 0
        settingsChanged.normalize()
        XCTAssertEqual(settingsChanged.weeklyChallenge?.dailyLimit, 6)
        XCTAssertEqual(settingsChanged.weeklyChallenge?.dayStartHour, 8)
        XCTAssertEqual(
            settingsChanged.weeklyChallenge?.periodStart,
            store.weeklyChallenge?.periodStart
        )
    }

    func testChallengeFreezesDailyLimitAndPersistsReward() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var store = SmokeStore()
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            targetDays: 5,
            reward: "  买一束花  ",
            cadence: .calendarWeekMonday,
            periodStart: Date(timeIntervalSince1970: 1_699_833_600),
            dailyLimit: 6,
            dayStartHour: 8
        )
        store.normalize()
        let repository = StoreRepository(fileURL: file)
        try repository.save(store)

        let result = repository.load()
        let loaded = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(loaded.weeklyChallenge?.dailyLimit, 6)
        XCTAssertEqual(loaded.weeklyChallenge?.dayStartHour, 8)
        XCTAssertEqual(loaded.weeklyChallenge?.cadence, .calendarWeekMonday)
        XCTAssertEqual(loaded.weeklyChallenge?.periodStart, Date(timeIntervalSince1970: 1_699_833_600))
        XCTAssertEqual(loaded.weeklyChallenge?.reward, "买一束花")
    }

    func testVersionFourDateUndoEventsMigrateToStableCountingDayIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let occurredAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-14T04:00:00Z")
        )
        let expectedStart = SmokingLogic.countingDayStart(
            for: occurredAt,
            dayStartHour: 8
        )
        let expectedStartString = ISO8601DateFormatter().string(from: expectedStart)
        let json = """
        {
          "version": 4,
          "settings": { "dailyLimit": 8, "dayStartHour": 8 },
          "records": ["2026-07-14T02:00:00Z"],
          "firstRunDone": true,
          "undoneCountingDays": ["\(expectedStartString)"],
          "undoEvents": ["2026-07-14T04:00:00Z"]
        }
        """
        try Data(json.utf8).write(to: file)

        let result = StoreRepository(fileURL: file).load()
        let store = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .migrated(fromVersion: 4))
        XCTAssertEqual(store.version, StoreRepository.currentVersion)
        XCTAssertEqual(store.undoEvents.count, 1)
        XCTAssertEqual(store.undoEvents[0].occurredAt, occurredAt)
        XCTAssertEqual(store.undoEvents[0].countingDayStart, expectedStart)
        XCTAssertEqual(
            store.undoEvents[0].originalEnd,
            CountingDayPolicy(dayStartHour: 8).range(containing: occurredAt).end
        )
        XCTAssertEqual(store.undoEvents[0].dayStartHour, 8)
    }

    func testVersionThreeCountingDayGuardMigratesEvenWithoutUndoTimestamp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let json = """
        {
          "version": 3,
          "settings": { "dailyLimit": 8, "dayStartHour": 8 },
          "records": [],
          "firstRunDone": true,
          "undoneCountingDays": ["2026-07-14T00:00:00Z"]
        }
        """
        try Data(json.utf8).write(to: file)

        let result = StoreRepository(fileURL: file).load()
        let store = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .migrated(fromVersion: 3))
        XCTAssertEqual(store.undoEvents.count, 1)
        XCTAssertEqual(
            store.undoEvents[0].countingDayStart,
            ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")
        )
        XCTAssertEqual(store.undoEvents[0].dayStartHour, 8)
    }

    func testVersionFiveUndoBoundaryMigratesToCurrentVersionAndPersistsOriginalRange() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 5,
          "settings": { "dailyLimit": 8, "dayStartHour": 8, "petScale": 1.0 },
          "records": ["2026-07-14T02:00:00Z"],
          "firstRunDone": true,
          "undoneCountingDays": ["2026-07-14T00:00:00Z"],
          "undoEvents": [
            {
              "occurredAt": "2026-07-14T04:00:00Z",
              "countingDayStart": "2026-07-14T00:00:00Z",
              "dayStartHour": 8
            }
          ],
          "resetEvents": []
        }
        """
        try Data(json.utf8).write(to: file)
        let repository = StoreRepository(fileURL: file)

        let result = repository.load()
        let migrated = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .migrated(fromVersion: 5))
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(migrated.version, StoreRepository.currentVersion)
        XCTAssertEqual(migrated.undoEvents.count, 1)
        XCTAssertEqual(
            migrated.undoEvents[0].originalStart,
            ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")
        )
        XCTAssertEqual(
            migrated.undoEvents[0].originalEnd,
            ISO8601DateFormatter().date(from: "2026-07-15T00:00:00Z")
        )

        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        XCTAssertEqual(persisted?["version"] as? Int, StoreRepository.currentVersion)
        let events = persisted?["undoEvents"] as? [[String: Any]]
        XCTAssertNotNil(events?.first?["originalStart"])
        XCTAssertNotNil(events?.first?["originalEnd"])
        XCTAssertNil(events?.first?["countingDayStart"])
    }

    func testVersionSixChallengeMigrationFreezesCurrentTimeZoneAndWritesBackImmediately() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 6,
          "settings": { "dailyLimit": 8, "dayStartHour": 8, "petScale": 1.0 },
          "records": [],
          "firstRunDone": true,
          "weeklyChallenge": {
            "id": "A729F6E8-E7BD-45E5-9831-71117A35A9BD",
            "startedAt": "2026-07-15T02:00:00Z",
            "targetDays": 5,
            "reward": "散步",
            "cadence": "calendarWeekMonday",
            "periodStart": "2026-07-13T00:00:00Z",
            "dailyLimit": 8,
            "dayStartHour": 8
          },
          "undoneCountingDays": [],
          "undoEvents": [],
          "resetEvents": []
        }
        """
        try Data(json.utf8).write(to: file)
        let repository = StoreRepository(fileURL: file)

        let result = repository.load()
        let migrated = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .migrated(fromVersion: 6))
        XCTAssertEqual(migrated.version, StoreRepository.currentVersion)
        XCTAssertEqual(
            migrated.weeklyChallenge?.timeZoneIdentifier,
            TimeZone.current.identifier
        )

        let persisted = try JSONSerialization.jsonObject(
            with: Data(contentsOf: file)
        ) as? [String: Any]
        XCTAssertEqual(persisted?["version"] as? Int, StoreRepository.currentVersion)
        let challenge = persisted?["weeklyChallenge"] as? [String: Any]
        XCTAssertEqual(
            challenge?["timeZoneIdentifier"] as? String,
            TimeZone.current.identifier
        )
    }

    func testRelaunchedChallengeKeepsFrozenTimeZoneWhenCallerMovesTimeZones() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let formatter = ISO8601DateFormatter()
        var store = SmokeStore()
        store.firstRunDone = true
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 8
        store.weeklyChallenge = WeeklyChallenge(
            startedAt: try XCTUnwrap(formatter.date(from: "2026-07-15T02:00:00Z")),
            targetDays: 5,
            reward: "散步",
            cadence: .calendarWeekMonday,
            periodStart: try XCTUnwrap(formatter.date(from: "2026-07-13T00:00:00Z")),
            dailyLimit: 2,
            dayStartHour: 8,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        store.normalize()
        try repository.save(store)

        let relaunched = try XCTUnwrap(repository.load().store)
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let progress = SmokingLogic.weeklyChallengeProgress(
            store: relaunched,
            now: try XCTUnwrap(formatter.date(from: "2026-07-16T00:00:00Z")),
            calendar: losAngeles
        )

        XCTAssertEqual(relaunched.weeklyChallenge?.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(
            progress?.start,
            formatter.date(from: "2026-07-13T00:00:00Z")
        )
        XCTAssertEqual(
            progress?.days[2].start,
            formatter.date(from: "2026-07-15T00:00:00Z")
        )
        XCTAssertEqual(progress?.days[0].status, .notParticipating)
        XCTAssertEqual(progress?.days[1].status, .notParticipating)
    }

    func testPetScaleNormalizesToSupportedRange() {
        var below = AppSettings(petScale: 0.2)
        XCTAssertEqual(below.petScale, 0.6)

        below.petScale = 1.4
        below.normalize()
        XCTAssertEqual(below.petScale, 1.0)
    }

    func testVersionSevenStoreMigratesPetStyleToAshtrayAndWritesBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let original = Data("""
        {
          "version": 7,
          "settings": { "dailyLimit": 5, "dayStartHour": 9, "petScale": 0.75 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true,
          "undoneCountingDays": [],
          "undoEvents": [],
          "resetEvents": []
        }
        """.utf8)
        try original.write(to: file)
        let repository = StoreRepository(fileURL: file)

        let result = repository.load()
        let migrated = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .migrated(fromVersion: 7))
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(migrated.version, StoreRepository.currentVersion)
        XCTAssertEqual(migrated.settings.dailyLimit, 5)
        XCTAssertEqual(migrated.settings.dayStartHour, 9)
        XCTAssertEqual(migrated.settings.petScale, 0.75)
        XCTAssertEqual(migrated.settings.petStyle, .ashtray)
        XCTAssertEqual(migrated.records.count, 1)

        let persisted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        )
        let settings = try XCTUnwrap(persisted["settings"] as? [String: Any])
        XCTAssertEqual(persisted["version"] as? Int, StoreRepository.currentVersion)
        XCTAssertEqual(settings["petStyle"] as? String, PetStyle.ashtray.rawValue)
        XCTAssertEqual(
            try Data(contentsOf: repository.preMigrationSnapshotURL(forVersion: 7)),
            original
        )
    }

    func testPetStyleRoundTripsInCurrentSchema() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var store = SmokeStore()
        store.firstRunDone = true
        store.settings.petStyle = .note

        try repository.save(store)
        let result = repository.load()

        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.store?.settings.petStyle, .note)
        let persisted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL))
                as? [String: Any]
        )
        let settings = try XCTUnwrap(persisted["settings"] as? [String: Any])
        XCTAssertEqual(settings["petStyle"] as? String, PetStyle.note.rawValue)
    }

    func testCurrentSchemaRequiresKnownPetStyle() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")

        for badValue in [nil, "cigar"] as [String?] {
            var object = validStoreJSONObject(version: StoreRepository.currentVersion)
            var settings = try XCTUnwrap(object["settings"] as? [String: Any])
            if let badValue {
                settings["petStyle"] = badValue
            } else {
                settings.removeValue(forKey: "petStyle")
            }
            object["settings"] = settings
            let original = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
            try original.write(to: file, options: .atomic)

            let result = StoreRepository(fileURL: file).load()

            XCTAssertEqual(result.status, .corrupt)
            XCTAssertFalse(result.isWritable)
            XCTAssertNil(result.store)
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testUndoAndResetAuditFieldsPersistAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let undoDay = Date(timeIntervalSince1970: 1_720_944_000)
        let undoOccurredAt = Date(timeIntervalSince1970: 1_720_987_000)
        let resetAt = Date(timeIntervalSince1970: 1_720_987_200)
        var store = SmokeStore()
        store.undoneCountingDays = [undoDay]
        store.undoEvents = [
            UndoEvent(
                occurredAt: undoOccurredAt,
                countingDayStart: undoDay,
                dayStartHour: 8
            )
        ]
        store.resetEvents = [
            ResetEvent(
                occurredAt: resetAt,
                reason: "重新开始记录",
                clearedRecordCount: 18
            )
        ]
        store.normalize()

        let repository = StoreRepository(fileURL: file)
        try repository.save(store)
        let result = repository.load()
        let loaded = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(loaded.undoneCountingDays, [undoDay])
        XCTAssertEqual(loaded.undoEvents, [
            UndoEvent(
                occurredAt: undoOccurredAt,
                countingDayStart: undoDay,
                dayStartHour: 8
            )
        ])
        XCTAssertEqual(loaded.resetEvents.count, 1)
        XCTAssertEqual(loaded.resetEvents[0].occurredAt, resetAt)
        XCTAssertEqual(loaded.resetEvents[0].reason, "重新开始记录")
        XCTAssertEqual(loaded.resetEvents[0].clearedRecordCount, 18)
    }

    func testMissingPrimaryAndBackupIsAnExplicitWritableNewStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))

        let result = repository.load()

        XCTAssertEqual(result.status, .missing)
        XCTAssertNil(result.source)
        XCTAssertTrue(result.isWritable)
        XCTAssertNotNil(result.store)
        XCTAssertNil(result.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
    }

    func testCurrentSchemaMissingCoreFieldIsCorruptAndRecoversBackupReadOnly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        expected.normalize()
        try repository.save(expected)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL))
                as? [String: Any]
        )
        object.removeValue(forKey: "records")
        let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try damaged.write(to: repository.fileURL, options: .atomic)

        let result = repository.load()

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertEqual(result.source, .backup)
        XCTAssertFalse(result.isWritable)
        XCTAssertEqual(result.store, expected)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
    }

    func testVersionlessModernShapeIsCorruptAndRecoversReadableBackupReadOnly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        expected.normalize()
        try repository.save(expected)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL))
                as? [String: Any]
        )
        object.removeValue(forKey: "version")
        let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try damaged.write(to: repository.fileURL, options: .atomic)

        let result = repository.load()

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertEqual(result.source, .backup)
        XCTAssertFalse(result.isWritable)
        XCTAssertEqual(result.store, expected)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
    }

    func testTrulyVersionlessLegacyOneShapeStillMigrates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "settings": { "dailyLimit": 8, "dayStartHour": 0 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true
        }
        """
        let original = Data(json.utf8)
        try original.write(to: file)
        let repository = StoreRepository(fileURL: file)

        let result = repository.load()

        XCTAssertEqual(result.status, .migrated(fromVersion: 1))
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(result.store?.records.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: repository.preMigrationSnapshotURL(forVersion: 1)),
            original
        )
    }

    func testEverySchemaVersionRequiresOriginalCoreFields() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")

        for version in 1...StoreRepository.currentVersion {
            for key in ["settings", "records", "firstRunDone"] {
                var object = validStoreJSONObject(version: version)
                object.removeValue(forKey: key)
                try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                    .write(to: file, options: .atomic)

                let result = StoreRepository(fileURL: file).load()

                XCTAssertEqual(result.status, .corrupt, "v\(version) missing \(key)")
                XCTAssertFalse(result.isWritable, "v\(version) missing \(key)")
                XCTAssertNil(result.store, "v\(version) missing \(key)")
            }
        }
    }

    func testEverySchemaVersionRejectsWrongTypedOriginalCoreFields() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let invalidValues: [String: Any] = [
            "settings": "not-an-object",
            "records": "not-an-array",
            "firstRunDone": "not-a-boolean"
        ]

        for version in 1...StoreRepository.currentVersion {
            for (key, invalidValue) in invalidValues {
                var object = validStoreJSONObject(version: version)
                object[key] = invalidValue
                try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                    .write(to: file, options: .atomic)

                let result = StoreRepository(fileURL: file).load()

                XCTAssertEqual(result.status, .corrupt, "v\(version) bad \(key)")
                XCTAssertFalse(result.isWritable, "v\(version) bad \(key)")
                XCTAssertNil(result.store, "v\(version) bad \(key)")
            }
        }
    }

    func testCurrentSchemaWrongTypedCoreFieldIsCorruptInsteadOfDefaulting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        expected.normalize()
        try repository.save(expected)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL))
                as? [String: Any]
        )
        object["records"] = "not-an-array"
        let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try damaged.write(to: repository.fileURL, options: .atomic)

        let result = repository.load()

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertEqual(result.source, .backup)
        XCTAssertFalse(result.isWritable)
        XCTAssertEqual(result.store, expected)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
    }

    func testMalformedCurrentUndoEventIsCorruptInsteadOfBeingSilentlyCleared() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let occurredAt = Date(timeIntervalSince1970: 1_720_987_000)
        let countingDayStart = Date(timeIntervalSince1970: 1_720_944_000)
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.undoEvents = [
            UndoEvent(
                occurredAt: occurredAt,
                countingDayStart: countingDayStart,
                dayStartHour: 8
            )
        ]
        expected.normalize()
        try repository.save(expected)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL))
                as? [String: Any]
        )
        var undoEvents = try XCTUnwrap(object["undoEvents"] as? [[String: Any]])
        undoEvents[0].removeValue(forKey: "originalEnd")
        object["undoEvents"] = undoEvents
        let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try damaged.write(to: repository.fileURL, options: .atomic)

        let result = repository.load()

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertEqual(result.source, .backup)
        XCTAssertFalse(result.isWritable)
        XCTAssertEqual(result.store, expected)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
    }

    func testCurrentUndoEventRequiresValidDayStartHour() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.undoEvents = [
            UndoEvent(
                occurredAt: Date(timeIntervalSince1970: 1_720_987_000),
                countingDayStart: Date(timeIntervalSince1970: 1_720_944_000),
                dayStartHour: 8
            )
        ]
        expected.normalize()
        try repository.save(expected)

        let baseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: repository.fileURL))
                as? [String: Any]
        )

        for badValue in [nil, "eight"] as [Any?] {
            var object = baseObject
            var undoEvents = try XCTUnwrap(object["undoEvents"] as? [[String: Any]])
            if let badValue {
                undoEvents[0]["dayStartHour"] = badValue
            } else {
                undoEvents[0].removeValue(forKey: "dayStartHour")
            }
            object["undoEvents"] = undoEvents
            let damaged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try damaged.write(to: repository.fileURL, options: .atomic)

            let result = repository.load()

            XCTAssertEqual(result.status, .corrupt)
            XCTAssertEqual(result.source, .backup)
            XCTAssertFalse(result.isWritable)
            XCTAssertEqual(result.store, expected)
            XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
        }
    }

    func testTruncatedPrimaryIsPreservedAndNeverBecomesWritableEmptyStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let corruptData = Data(#"{"version":5,"records":["#.utf8)
        try corruptData.write(to: file)
        let repository = StoreRepository(fileURL: file)

        let result = repository.load()

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertFalse(result.isWritable)
        XCTAssertNil(result.store)
        XCTAssertNotNil(result.message)
        XCTAssertEqual(try Data(contentsOf: file), corruptData)
        XCTAssertThrowsError(try repository.save(SmokeStore()))
        XCTAssertEqual(try Data(contentsOf: file), corruptData)
    }

    func testBadEnumPayloadIsCorruptRatherThanSilentlyReset() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 5,
          "settings": { "dailyLimit": 8, "dayStartHour": 0, "petScale": 1.0 },
          "records": [],
          "firstRunDone": true,
          "weeklyChallenge": {
            "startedAt": "2026-07-14T01:00:00Z",
            "targetDays": 5,
            "reward": "散步",
            "cadence": "not-a-real-cadence"
          }
        }
        """
        let original = Data(json.utf8)
        try original.write(to: file)

        let result = StoreRepository(fileURL: file).load()

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertFalse(result.isWritable)
        XCTAssertNil(result.store)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testFutureVersionIsRefusedWithoutDecodingOrDowngrade() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 99,
          "settings": { "dailyLimit": 3, "dayStartHour": 8 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true,
          "futureOnlyMode": "do-not-drop"
        }
        """
        let original = Data(json.utf8)
        try original.write(to: file)
        let repository = StoreRepository(fileURL: file)

        let result = repository.load()

        XCTAssertEqual(result.status, .unsupportedFutureVersion(foundVersion: 99))
        XCTAssertFalse(result.isWritable)
        XCTAssertNil(result.store)
        XCTAssertThrowsError(try repository.save(SmokeStore()))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testMissingPrimaryWithFutureBackupRefusesBlindSaveAndPreservesBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let futureBackup = Data("""
        {
          "version": 99,
          "records": ["2026-07-14T01:12:00Z"],
          "futureOnlyMode": "preserve-me"
        }
        """.utf8)
        try futureBackup.write(to: repository.backupURL)

        let loadResult = repository.load()
        XCTAssertEqual(loadResult.status, .unsupportedFutureVersion(foundVersion: 99))
        XCTAssertEqual(loadResult.source, .backup)
        XCTAssertFalse(loadResult.isWritable)

        XCTAssertThrowsError(try repository.save(SmokeStore())) { error in
            guard case StoreRepositoryError.refusingToOverwriteProtectedBackup = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), futureBackup)
    }

    func testValidCurrentPrimaryDoesNotOverwriteFutureBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var current = SmokeStore()
        current.firstRunDone = true
        current.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        current.normalize()
        try repository.save(current)
        let primaryBefore = try Data(contentsOf: repository.fileURL)
        let futureBackup = Data("""
        {
          "version": 99,
          "records": ["2026-07-14T01:12:00Z"],
          "futureOnlyMode": "preserve-me"
        }
        """.utf8)
        try futureBackup.write(to: repository.backupURL, options: .atomic)
        var proposed = current
        proposed.records.append(Date(timeIntervalSince1970: 1_720_944_100))

        XCTAssertThrowsError(try repository.save(proposed)) { error in
            guard case StoreRepositoryError.refusingToOverwriteProtectedBackup = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), futureBackup)
    }

    func testMissingPrimaryWithCorruptBackupRefusesBlindSaveAndPreservesBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let corruptBackup = Data(#"{"version":7,"records":["#.utf8)
        try corruptBackup.write(to: repository.backupURL)

        let loadResult = repository.load()
        XCTAssertEqual(loadResult.status, .corrupt)
        XCTAssertEqual(loadResult.source, .backup)
        XCTAssertFalse(loadResult.isWritable)

        XCTAssertThrowsError(try repository.save(SmokeStore())) { error in
            guard case StoreRepositoryError.refusingToOverwriteProtectedBackup = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), corruptBackup)
    }

    func testCorruptPrimaryRecoversLatestBackupReadOnlyAndPreservesBadBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let repository = StoreRepository(fileURL: file)
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.settings.dailyLimit = 6
        expected.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        expected.normalize()
        try repository.save(expected)

        let backupAfterSave = try Data(contentsOf: repository.backupURL)
        XCTAssertEqual(backupAfterSave, try Data(contentsOf: file))

        let corruptData = Data(#"{"version":5,"records":["#.utf8)
        try corruptData.write(to: file, options: .atomic)

        let result = repository.load()
        let recovered = try XCTUnwrap(result.store)

        XCTAssertEqual(result.status, .corrupt)
        XCTAssertEqual(result.source, .backup)
        XCTAssertFalse(result.isWritable)
        XCTAssertEqual(recovered, expected)
        XCTAssertEqual(try Data(contentsOf: file), corruptData)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), backupAfterSave)
    }

    func testMissingPrimaryRestoresReadableBackupBeforeBecomingWritable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.settings.dailyLimit = 5
        expected.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        expected.normalize()
        try repository.save(expected)
        let backupBefore = try Data(contentsOf: repository.backupURL)
        try FileManager.default.removeItem(at: repository.fileURL)

        let result = repository.load()

        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.source, .backup)
        XCTAssertTrue(result.isWritable)
        XCTAssertEqual(result.store, expected)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), backupBefore)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), backupBefore)
    }

    func testMigrationIsImmediatelyPersistedAndRelaunchesAsLoaded() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 1,
          "settings": { "dailyLimit": 8, "dayStartHour": 0 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true
        }
        """
        let original = Data(json.utf8)
        try original.write(to: file)
        let repository = StoreRepository(fileURL: file)

        let first = repository.load()

        XCTAssertEqual(first.status, .migrated(fromVersion: 1))
        XCTAssertTrue(first.isWritable)
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        XCTAssertEqual(persisted?["version"] as? Int, StoreRepository.currentVersion)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), try Data(contentsOf: file))
        let migrationSnapshot = repository.preMigrationSnapshotURL(forVersion: 1)
        XCTAssertEqual(try Data(contentsOf: migrationSnapshot), original)

        let second = repository.load()
        XCTAssertEqual(second.status, .loaded)
        XCTAssertEqual(second.store, first.store)
        XCTAssertEqual(try Data(contentsOf: migrationSnapshot), original)
    }

    func testMigrationWritebackFailureLeavesPrimaryUntouchedAndSnapshotIsNotSuccessMarker() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let json = """
        {
          "version": 6,
          "settings": { "dailyLimit": 8, "dayStartHour": 0, "petScale": 1.0 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true,
          "undoneCountingDays": [],
          "undoEvents": [],
          "resetEvents": []
        }
        """
        let original = Data(json.utf8)
        try original.write(to: file)
        let faultingAccess = FaultingStoreFileAccess { url, writeNumber in
            url == file && writeNumber == 1
        }
        let repository = StoreRepository(fileURL: file, fileAccess: faultingAccess)

        let result = repository.load()

        XCTAssertEqual(result.status, .migrated(fromVersion: 6))
        XCTAssertFalse(result.isWritable)
        XCTAssertTrue(result.message?.contains("不代表迁移成功") == true)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(
            try Data(contentsOf: repository.preMigrationSnapshotURL(forVersion: 6)),
            original
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.backupURL.path))
    }

    func testBackupWriteFailureRestoresPrimaryAndBackupExactBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let seedRepository = StoreRepository(fileURL: file)
        var originalStore = SmokeStore()
        originalStore.firstRunDone = true
        originalStore.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        originalStore.normalize()
        try seedRepository.save(originalStore)
        let primaryBefore = try Data(contentsOf: file)
        let backupBefore = try Data(contentsOf: seedRepository.backupURL)

        let faultingAccess = FaultingStoreFileAccess { url, writeNumber in
            url == seedRepository.backupURL && writeNumber == 1
        }
        let repository = StoreRepository(fileURL: file, fileAccess: faultingAccess)
        var proposed = originalStore
        proposed.records.append(Date(timeIntervalSince1970: 1_720_944_100))

        XCTAssertThrowsError(try repository.save(proposed)) { error in
            guard case StoreRepositoryError.cannotWriteBackup = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), backupBefore)
    }

    func testRollbackFailureIsReportedWithoutClaimingSuccessfulCommit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let seedRepository = StoreRepository(fileURL: file)
        var originalStore = SmokeStore()
        originalStore.firstRunDone = true
        originalStore.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        originalStore.normalize()
        try seedRepository.save(originalStore)
        let primaryBefore = try Data(contentsOf: file)
        let backupBefore = try Data(contentsOf: seedRepository.backupURL)

        let faultingAccess = FaultingStoreFileAccess { url, writeNumber in
            (url == seedRepository.backupURL && writeNumber == 1)
                || (url == file && writeNumber == 2)
        }
        let repository = StoreRepository(fileURL: file, fileAccess: faultingAccess)
        var proposed = originalStore
        proposed.records.append(Date(timeIntervalSince1970: 1_720_944_100))

        XCTAssertThrowsError(try repository.save(proposed)) { error in
            guard case StoreRepositoryError.rollbackFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertNotEqual(try Data(contentsOf: file), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: repository.backupURL), backupBefore)
    }

    func testSaveToUnwritablePathThrowsWithoutCreatingPrimaryOrBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nonDirectoryParent = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: nonDirectoryParent)
        let repository = StoreRepository(
            fileURL: nonDirectoryParent.appendingPathComponent("store.json")
        )

        XCTAssertThrowsError(try repository.save(SmokeStore()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.backupURL.path))
        XCTAssertEqual(try Data(contentsOf: nonDirectoryParent), Data("occupied".utf8))
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func validStoreJSONObject(version: Int) -> [String: Any] {
        var settings: [String: Any] = [
            "dailyLimit": 8,
            "dayStartHour": 0
        ]
        if version >= 7 {
            settings["petScale"] = 1.0
        }
        if version >= 8 {
            settings["petStyle"] = PetStyle.ashtray.rawValue
        }
        var object: [String: Any] = [
            "version": version,
            "settings": settings,
            "records": [],
            "firstRunDone": true
        ]
        if version >= 3 {
            object["undoneCountingDays"] = []
        }
        if version >= 4 {
            object["undoEvents"] = []
        }
        if version >= 5 {
            object["resetEvents"] = []
        }
        return object
    }
}

private final class FaultingStoreFileAccess: StoreFileAccess, @unchecked Sendable {
    private let underlying = FoundationStoreFileAccess()
    private let shouldFailWrite: (URL, Int) -> Bool
    private let lock = NSLock()
    private var writeCounts: [URL: Int] = [:]

    init(shouldFailWrite: @escaping (URL, Int) -> Bool) {
        self.shouldFailWrite = shouldFailWrite
    }

    func createDirectory(at url: URL) throws {
        try underlying.createDirectory(at: url)
    }

    func read(from url: URL) throws -> Data {
        try underlying.read(from: url)
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        lock.lock()
        let writeNumber = (writeCounts[url] ?? 0) + 1
        writeCounts[url] = writeNumber
        lock.unlock()

        if shouldFailWrite(url, writeNumber) {
            throw CocoaError(.fileWriteUnknown)
        }
        try underlying.write(data, to: url, options: options)
    }

    func removeItem(at url: URL) throws {
        try underlying.removeItem(at: url)
    }
}
