import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var store: SmokeStore
    @Published private(set) var now = Date()
    @Published var isOnboardingPresented: Bool
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var isPersistenceReadOnly: Bool

    var onHideWindow: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onFirstRunComplete: (() -> Void)?
    var onStateChange: (() -> Void)?
    var onPetScaleChange: ((Double) -> Void)?
    var onPetStyleChange: ((PetStyle) -> Void)?
    var onPetConfigurationChange: ((Double, PetStyle) -> Void)?
    var onPersistenceError: ((String) -> Void)?

    private let repository: StoreRepository
    private var clock: Timer?

    init(repository: StoreRepository = StoreRepository()) {
        self.repository = repository
        let result = repository.load()
        let loaded = result.store ?? SmokeStore()
        store = loaded
        isPersistenceReadOnly = !result.isWritable
        persistenceErrorMessage = result.message
        // A corrupt or future-version file is not a first-run store. Keeping
        // onboarding closed prevents a destructive "start fresh" path from
        // masquerading as a valid initialization.
        isOnboardingPresented = result.isWritable && !loaded.firstRunDone
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.onStateChange?()
            }
        }
    }

    var snapshot: DaySnapshot {
        SmokingLogic.snapshot(store: store, now: now)
    }

    var weeklyProgress: WeeklyChallengeProgress? {
        SmokingLogic.weeklyChallengeProgress(store: store, now: now)
    }

    var canUndoToday: Bool {
        SmokingLogic.canUndoRecord(in: store, now: now)
    }

    var hasResetHistory: Bool {
        !store.resetEvents.isEmpty
    }

    func maximumAchievableDays(for cadence: WeeklyCadence) -> Int {
        SmokingLogic.maximumAchievableDays(
            store: store,
            now: now,
            cadence: cadence
        )
    }

    var statusMessage: String {
        let value = snapshot
        switch value.count {
        case 0: return "😌 今天还很干净"
        case 1 where value.limit > 1: return "🙂 今天还是没忍住呀"
        case value.limit where value.limit > 0: return "🫶 明天就比今天少一根吧"
        case let count where count > value.limit: return "🥺 不是说要戒烟吗？"
        case value.visibleFullAt: return "😮‍💨 害，你看又抽了这么多"
        case let count where count > value.visibleFullAt: return "😟 行了行了，别抽了"
        default: return "🙂 默默记着，下一根晚一点"
        }
    }

    var positiveFeedback: String? {
        let gaps = snapshot.records.compactMap(\.gapMinutes)
        if gaps.count >= 2 {
            let improvement = gaps[gaps.count - 1] - gaps[gaps.count - 2]
            if improvement >= 10 {
                return "🌿 这一根比上次多等了 \(improvement) 分钟"
            }
        }
        if let progress = weeklyProgress {
            if progress.isAchieved {
                return "🌸 7 天目标已经开花了"
            }
            return "🌱 7 天目标：已守住 \(progress.achievedDays) 天"
        }
        return nil
    }

    func addRecord() {
        let eventDate = Date()
        now = eventDate
        let next = SmokingLogic.addingRecord(to: store, at: eventDate)
        commit(next)
    }

    func undoToday() {
        let eventDate = Date()
        now = eventDate
        guard SmokingLogic.canUndoRecord(in: store, now: eventDate) else { return }
        let next = SmokingLogic.undoingLastRecord(in: store, now: eventDate)
        commit(next)
    }

    func resetHistory(reason: String) {
        let eventDate = Date()
        now = eventDate
        let next = SmokingLogic.resettingHistory(in: store, at: eventDate, reason: reason)
        commit(next)
    }

    func completeOnboarding(limit: Int) {
        var next = store
        next.settings.dailyLimit = limit
        next.firstRunDone = true
        next.normalize()
        guard commit(next) else { return }
        isOnboardingPresented = false
        onFirstRunComplete?()
    }

    func updateSettings(
        limit: Int,
        dayStartHour: Int,
        petScale: Double,
        petStyle: PetStyle
    ) {
        let previousPetScale = store.settings.petScale
        let previousPetStyle = store.settings.petStyle
        var next = store
        next.settings.dailyLimit = limit
        next.settings.dayStartHour = dayStartHour
        next.settings.petScale = petScale
        next.settings.petStyle = petStyle
        next.normalize()
        guard commit(next) else { return }
        let scaleChanged = abs(previousPetScale - next.settings.petScale) > 0.001
        let styleChanged = previousPetStyle != next.settings.petStyle
        if scaleChanged {
            onPetScaleChange?(next.settings.petScale)
        }
        if styleChanged {
            onPetStyleChange?(next.settings.petStyle)
        }
        if scaleChanged || styleChanged {
            onPetConfigurationChange?(next.settings.petScale, next.settings.petStyle)
        }
    }

    func updateSettings(limit: Int, dayStartHour: Int, petScale: Double) {
        updateSettings(
            limit: limit,
            dayStartHour: dayStartHour,
            petScale: petScale,
            petStyle: store.settings.petStyle
        )
    }

    func updateSettings(limit: Int, dayStartHour: Int) {
        updateSettings(limit: limit, dayStartHour: dayStartHour, petScale: store.settings.petScale)
    }

    func startWeeklyChallenge(
        targetDays: Int,
        reward: String,
        cadence: WeeklyCadence = .rollingSevenDays
    ) {
        let eventDate = Date()
        now = eventDate
        let periodStart = SmokingLogic.weeklyPeriodStart(
            for: eventDate,
            cadence: cadence,
            dayStartHour: store.settings.dayStartHour
        )
        let maximumTarget = SmokingLogic.maximumAchievableDays(
            store: store,
            now: eventDate,
            cadence: cadence
        )
        guard maximumTarget > 0 else { return }
        var next = store
        next.weeklyChallenge = WeeklyChallenge(
            startedAt: eventDate,
            targetDays: min(max(1, targetDays), maximumTarget),
            reward: reward,
            cadence: cadence,
            periodStart: periodStart,
            dailyLimit: store.settings.dailyLimit,
            dayStartHour: store.settings.dayStartHour,
            timeZoneIdentifier: TimeZone.current.identifier
        )
        next.normalize()
        commit(next)
    }

    func updateWeeklyChallenge(targetDays: Int, reward: String) {
        let eventDate = Date()
        now = eventDate
        guard let progress = SmokingLogic.weeklyChallengeProgress(
            store: store,
            now: eventDate
        ),
              progress.isFinished == false,
              progress.maximumAchievableDays > 0,
              var challenge = store.weeklyChallenge else { return }
        challenge.targetDays = min(
            max(1, targetDays),
            progress.maximumAchievableDays
        )
        challenge.reward = reward
        challenge.normalize()
        var next = store
        next.weeklyChallenge = challenge
        next.normalize()
        commit(next)
    }

    @discardableResult
    private func commit(_ proposed: SmokeStore) -> Bool {
        guard !isPersistenceReadOnly else {
            publishPersistenceError(
                persistenceErrorMessage
                    ?? "记录当前处于只读保护状态，本次操作没有写入。"
            )
            return false
        }

        var next = proposed
        next.normalize()
        do {
            try repository.save(next)
        } catch {
            publishPersistenceError(
                "保存失败，本次操作没有记入，原记录保持不变：\(error.localizedDescription)"
            )
            return false
        }

        // Publishing happens only after the complete primary + backup commit.
        store = next
        persistenceErrorMessage = nil
        onStateChange?()
        return true
    }

    private func publishPersistenceError(_ message: String) {
        persistenceErrorMessage = message
        onPersistenceError?(message)
    }
}
