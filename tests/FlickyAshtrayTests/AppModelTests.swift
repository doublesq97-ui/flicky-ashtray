import Foundation
import XCTest
@testable import FlickyAshtray

@MainActor
final class AppModelTests: XCTestCase {
    func testResetHistoryAPIExposesAuditAndPersistsPreservedState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("store.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var initial = SmokeStore()
        initial.settings.dailyLimit = 7
        initial.settings.dayStartHour = 8
        initial.firstRunDone = true
        initial.records = [Date(timeIntervalSinceNow: -120)]
        initial.weeklyChallenge = WeeklyChallenge(
            startedAt: Date(),
            targetDays: 5,
            reward: "去看电影"
        )
        let repository = StoreRepository(fileURL: file)
        try repository.save(initial)

        let model = AppModel(repository: repository)
        XCTAssertTrue(model.canUndoToday)
        XCTAssertFalse(model.hasResetHistory)

        model.resetHistory(reason: "  按新的作息重新记录  ")

        XCTAssertTrue(model.hasResetHistory)
        XCTAssertFalse(model.canUndoToday)
        XCTAssertEqual(model.store.settings.dailyLimit, 7)
        XCTAssertEqual(model.store.settings.dayStartHour, 8)
        XCTAssertTrue(model.store.firstRunDone)
        XCTAssertTrue(model.store.records.isEmpty)
        XCTAssertNil(model.store.weeklyChallenge)
        XCTAssertEqual(model.store.resetEvents.last?.reason, "按新的作息重新记录")
        XCTAssertEqual(model.store.resetEvents.last?.clearedRecordCount, 1)

        let reloaded = try XCTUnwrap(repository.load().store)
        XCTAssertEqual(reloaded.resetEvents.last?.id, model.store.resetEvents.last?.id)
        XCTAssertEqual(reloaded.resetEvents.last?.reason, model.store.resetEvents.last?.reason)
        XCTAssertEqual(
            reloaded.resetEvents.last?.clearedRecordCount,
            model.store.resetEvents.last?.clearedRecordCount
        )
        XCTAssertEqual(
            reloaded.resetEvents.last?.occurredAt.timeIntervalSince1970 ?? 0,
            model.store.resetEvents.last?.occurredAt.timeIntervalSince1970 ?? 0,
            accuracy: 1
        )
    }

    func testSaveFailureDoesNotAdvanceMemoryOrPrimaryAndPublishesError() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var initial = SmokeStore()
        initial.firstRunDone = true
        initial.records = [Date(timeIntervalSinceNow: -300)]
        initial.normalize()
        try repository.save(initial)

        let model = AppModel(repository: repository)
        let memoryBefore = model.store
        let primaryBefore = try Data(contentsOf: repository.fileURL)
        try FileManager.default.removeItem(at: repository.backupURL)
        try FileManager.default.createDirectory(
            at: repository.backupURL,
            withIntermediateDirectories: true
        )

        var reportedMessage: String?
        var stateChangeCount = 0
        model.onPersistenceError = { reportedMessage = $0 }
        model.onStateChange = { stateChangeCount += 1 }

        model.addRecord()

        XCTAssertEqual(model.store, memoryBefore)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), primaryBefore)
        XCTAssertFalse(model.isPersistenceReadOnly)
        XCTAssertNotNil(model.persistenceErrorMessage)
        XCTAssertEqual(reportedMessage, model.persistenceErrorMessage)
        XCTAssertEqual(stateChangeCount, 0)
    }

    func testFailedCommitSuppressesOnboardingScaleChallengeAndStateCallbacks() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let initial = SmokeStore()
        try repository.save(initial)
        let model = AppModel(repository: repository)
        XCTAssertTrue(model.isOnboardingPresented)

        try FileManager.default.removeItem(at: repository.backupURL)
        try FileManager.default.createDirectory(
            at: repository.backupURL,
            withIntermediateDirectories: true
        )

        var firstRunCallbackCount = 0
        var scaleCallbackCount = 0
        var styleCallbackCount = 0
        var stateChangeCount = 0
        model.onFirstRunComplete = { firstRunCallbackCount += 1 }
        model.onPetScaleChange = { _ in scaleCallbackCount += 1 }
        model.onPetStyleChange = { _ in styleCallbackCount += 1 }
        model.onStateChange = { stateChangeCount += 1 }

        model.completeOnboarding(limit: 3)
        model.updateSettings(
            limit: 4,
            dayStartHour: 8,
            petScale: 0.6,
            petStyle: .note
        )
        model.startWeeklyChallenge(targetDays: 5, reward: "看电影")

        XCTAssertFalse(model.store.firstRunDone)
        XCTAssertEqual(model.store.settings.dailyLimit, 8)
        XCTAssertEqual(model.store.settings.dayStartHour, 0)
        XCTAssertEqual(model.store.settings.petScale, 1.0)
        XCTAssertEqual(model.store.settings.petStyle, .ashtray)
        XCTAssertNil(model.store.weeklyChallenge)
        XCTAssertTrue(model.isOnboardingPresented)
        XCTAssertEqual(firstRunCallbackCount, 0)
        XCTAssertEqual(scaleCallbackCount, 0)
        XCTAssertEqual(styleCallbackCount, 0)
        XCTAssertEqual(stateChangeCount, 0)
    }

    func testUpdatingPetStylePersistsAndPublishesOnlyAfterCommit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var initial = SmokeStore()
        initial.firstRunDone = true
        try repository.save(initial)
        let model = AppModel(repository: repository)
        var publishedStyles: [PetStyle] = []
        var publishedConfigurations: [(Double, PetStyle)] = []
        var stateChangeCount = 0
        model.onPetStyleChange = { publishedStyles.append($0) }
        model.onPetConfigurationChange = { publishedConfigurations.append(($0, $1)) }
        model.onStateChange = { stateChangeCount += 1 }

        model.updateSettings(
            limit: 6,
            dayStartHour: 8,
            petScale: 0.75,
            petStyle: .note
        )

        XCTAssertEqual(model.store.settings.petStyle, .note)
        XCTAssertEqual(repository.load().store?.settings.petStyle, .note)
        XCTAssertEqual(publishedStyles, [.note])
        XCTAssertEqual(publishedConfigurations.count, 1)
        XCTAssertEqual(publishedConfigurations.first?.0, 0.75)
        XCTAssertEqual(publishedConfigurations.first?.1, .note)
        XCTAssertEqual(stateChangeCount, 1)

        model.updateSettings(
            limit: 5,
            dayStartHour: 9,
            petScale: 0.7,
            petStyle: .note
        )

        XCTAssertEqual(publishedStyles, [.note])
        XCTAssertEqual(publishedConfigurations.count, 2)
        XCTAssertEqual(publishedConfigurations.last?.0, 0.7)
        XCTAssertEqual(publishedConfigurations.last?.1, .note)
        XCTAssertEqual(stateChangeCount, 2)
    }

    func testCorruptInitializationIsReadOnlyNotFirstRunAndBlocksMutations() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let corruptData = Data(#"{"version":5,"records":["#.utf8)
        try corruptData.write(to: file)
        let model = AppModel(repository: StoreRepository(fileURL: file))

        XCTAssertTrue(model.isPersistenceReadOnly)
        XCTAssertFalse(model.isOnboardingPresented)
        XCTAssertNotNil(model.persistenceErrorMessage)
        XCTAssertTrue(model.store.records.isEmpty)

        var callbackMessage: String?
        model.onPersistenceError = { callbackMessage = $0 }
        model.addRecord()

        XCTAssertTrue(model.store.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), corruptData)
        XCTAssertEqual(callbackMessage, model.persistenceErrorMessage)
    }

    func testFutureVersionInitializationIsReadOnlyAndCannotDowngrade() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let futureData = Data("""
        {
          "version": 99,
          "settings": { "dailyLimit": 2, "dayStartHour": 8 },
          "records": ["2026-07-14T01:12:00Z"],
          "firstRunDone": true
        }
        """.utf8)
        try futureData.write(to: file)
        let model = AppModel(repository: StoreRepository(fileURL: file))

        XCTAssertTrue(model.isPersistenceReadOnly)
        XCTAssertFalse(model.isOnboardingPresented)
        XCTAssertTrue(model.persistenceErrorMessage?.contains("v99") == true)

        model.completeOnboarding(limit: 8)

        XCTAssertFalse(model.store.firstRunDone)
        XCTAssertEqual(try Data(contentsOf: file), futureData)
    }

    func testBackupRecoveryPublishesRecoveredStoreButKeepsItReadOnly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var expected = SmokeStore()
        expected.firstRunDone = true
        expected.records = [Date(timeIntervalSince1970: 1_720_944_000)]
        expected.normalize()
        try repository.save(expected)
        let corruptData = Data(#"{"version":5,"records":["#.utf8)
        try corruptData.write(to: repository.fileURL, options: .atomic)

        let model = AppModel(repository: repository)

        XCTAssertEqual(model.store, expected)
        XCTAssertTrue(model.isPersistenceReadOnly)
        XCTAssertFalse(model.isOnboardingPresented)
        model.addRecord()
        XCTAssertEqual(model.store, expected)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corruptData)
    }

    func testStartingChallengeClampsTargetToCreationParticipation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        var initial = SmokeStore()
        initial.firstRunDone = true
        try repository.save(initial)
        let model = AppModel(repository: repository)
        let expectedMaximum = model.maximumAchievableDays(for: .calendarWeekMonday)

        model.startWeeklyChallenge(
            targetDays: 7,
            reward: "看电影",
            cadence: .calendarWeekMonday
        )

        XCTAssertGreaterThanOrEqual(expectedMaximum, 1)
        XCTAssertEqual(model.store.weeklyChallenge?.targetDays, expectedMaximum)
        XCTAssertEqual(repository.load().store?.weeklyChallenge?.targetDays, expectedMaximum)
    }

    func testEditingChallengeClampsOnlyAfterSaveToCurrentAchievableMaximum() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let current = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: current)
        let safeBoundaryHour = (currentHour + 23) % 24
        let policy = CountingDayPolicy(dayStartHour: safeBoundaryHour, calendar: calendar)
        let currentRange = policy.range(containing: current)
        var initial = SmokeStore()
        initial.firstRunDone = true
        initial.settings.dailyLimit = 1
        initial.settings.dayStartHour = safeBoundaryHour
        initial.records = [
            current.addingTimeInterval(-10),
            current.addingTimeInterval(-5)
        ]
        initial.weeklyChallenge = WeeklyChallenge(
            startedAt: current.addingTimeInterval(-30),
            targetDays: 7,
            reward: "散步",
            cadence: .rollingSevenDays,
            periodStart: currentRange.start,
            dailyLimit: 1,
            dayStartHour: safeBoundaryHour
        )
        initial.normalize()
        try repository.save(initial)
        let model = AppModel(repository: repository)

        XCTAssertEqual(model.store.weeklyChallenge?.targetDays, 7)
        XCTAssertEqual(model.weeklyProgress?.maximumAchievableDays, 6)

        model.updateWeeklyChallenge(targetDays: 7, reward: "散步")

        XCTAssertEqual(model.store.weeklyChallenge?.targetDays, 6)
        XCTAssertEqual(repository.load().store?.weeklyChallenge?.targetDays, 6)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
