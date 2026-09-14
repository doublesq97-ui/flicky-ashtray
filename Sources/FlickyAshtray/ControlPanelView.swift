import AppKit
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var model: AppModel
    let onDone: () -> Void
    @State private var limit: Int
    @State private var dayStartHour: Int
    @State private var petScale: Double
    @State private var petStyle: PetStyle
    @State private var challengeTarget = 5
    @State private var reward = ""
    @State private var challengeCadence: WeeklyCadence = .rollingSevenDays
    @State private var isEditingChallenge = false
    @State private var showResetHistory = false
    @State private var reportExportMessage = ""
    @State private var reportExportFailed = false

    @AppStorage("controlPanel.section.today.expanded") private var isTodayExpanded = true
    @AppStorage("controlPanel.section.weekly.expanded") private var isWeeklyExpanded = true
    @AppStorage("controlPanel.section.trend.expanded") private var isTrendExpanded = true
    @AppStorage("controlPanel.section.records.expanded") private var isRecordsExpanded = false
    @AppStorage("controlPanel.section.settings.expanded") private var isSettingsExpanded = false
    @AppStorage("controlPanel.section.reset.expanded") private var isResetExpanded = false

    init(model: AppModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _limit = State(initialValue: model.store.settings.dailyLimit)
        _dayStartHour = State(initialValue: model.store.settings.dayStartHour)
        _petScale = State(initialValue: model.store.settings.petScale)
        _petStyle = State(initialValue: model.store.settings.petStyle)
    }

    private var snapshot: DaySnapshot { model.snapshot }
    private var newChallengeMaximumTarget: Int {
        model.maximumAchievableDays(for: challengeCadence)
    }
    private var hasUnsavedCountingSettings: Bool {
        limit != model.store.settings.dailyLimit || dayStartHour != model.store.settings.dayStartHour
    }
    private var hasUnsavedSettings: Bool {
        hasUnsavedCountingSettings
            || abs(petScale - model.store.settings.petScale) > 0.001
            || petStyle != model.store.settings.petStyle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let persistenceErrorMessage = model.persistenceErrorMessage {
                    persistenceErrorBanner(persistenceErrorMessage)
                }
                if model.isOnboardingPresented {
                    onboarding
                } else {
                    ControlSection(
                        title: "今日状态",
                        systemImage: "chart.bar.fill",
                        isExpanded: $isTodayExpanded
                    ) { todaySummary }
                    ControlSection(
                        title: "本周目标",
                        systemImage: "calendar.badge.checkmark",
                        isExpanded: $isWeeklyExpanded
                    ) { weeklyChallenge }
                    ControlSection(
                        title: "最近 7 天",
                        systemImage: "chart.xyaxis.line",
                        isExpanded: $isTrendExpanded
                    ) { trend }
                    ControlSection(
                        title: "今日记录",
                        systemImage: "clock.arrow.circlepath",
                        isExpanded: $isRecordsExpanded
                    ) { recentRecords }
                    ControlSection(
                        title: "设置",
                        systemImage: "slider.horizontal.3",
                        isExpanded: $isSettingsExpanded
                    ) { settings }
                    ControlSection(
                        title: "重新开始",
                        systemImage: "arrow.counterclockwise",
                        isExpanded: $isResetExpanded
                    ) { resetHistory }
                    footer
                }
            }
            .padding(24)
        }
        .frame(minWidth: 460, minHeight: 590)
        .onAppear {
            limit = model.store.settings.dailyLimit
            dayStartHour = model.store.settings.dayStartHour
            petScale = model.store.settings.petScale
            petStyle = model.store.settings.petStyle
            if let challenge = model.store.weeklyChallenge {
                challengeCadence = challenge.cadence
                challengeTarget = min(
                    challenge.targetDays,
                    max(1, model.maximumAchievableDays(for: challenge.cadence))
                )
                reward = challenge.reward
            }
        }
        .onChange(of: model.store.weeklyChallenge?.id) { _ in
            syncChallengeEditor()
        }
        .sheet(isPresented: $showResetHistory) {
            ResetHistorySheet(
                isFirstReset: !model.hasResetHistory,
                recordCount: model.store.records.count,
                onCancel: { showResetHistory = false },
                onConfirm: { reason in
                    model.resetHistory(reason: reason)
                    showResetHistory = false
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Flicky Ashtray").font(.title2.bold())
                Text(model.isOnboardingPresented ? "先定下今天的节奏" : Date.now.formatted(.dateTime.month(.wide).day()))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.isOnboardingPresented {
                Button("完成", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func persistenceErrorBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(Color.red)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("每日上限", systemImage: "gauge.with.dots.needle.50percent")
                        .font(.headline)
                    Stepper("每天 \(limit) 根", value: $limit, in: 1...60)
                    Text("默认 8 根。它只是今天的约定，不是最高只能设到 8。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            Button("开始使用") { model.completeOnboarding(limit: limit) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Text("设置完成后，这个面板会收起；桌面只留下小桌宠。之后可从菜单栏或桌宠右键再次打开。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var todaySummary: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.statusMessage).font(.headline)
                Text("今天 \(snapshot.count) / \(snapshot.limit) 根")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.isOverLimit ? Color.red : Color.primary)
                Text(snapshot.isOverLimit ? "超过 \(snapshot.count - snapshot.limit) 根" : "还剩 \(snapshot.remaining) 根")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button("撤销今日上一根") { model.undoToday() }
                    .disabled(!model.canUndoToday)
                Text(undoAvailabilityText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var settings: some View {
        Form {
            Section("计数") {
                Stepper("每日上限：\(limit) 根", value: $limit, in: 1...60)
                Picker("计数日从", selection: $dayStartHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                Text("选择 08:00 时，凌晨 02:00 的记录仍算在前一天。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("桌宠") {
                Picker("外观", selection: $petStyle) {
                    Text("烟灰缸").tag(PetStyle.ashtray)
                    Text("桌面便签").tag(PetStyle.note)
                }
                .pickerStyle(.segmented)

                Text(
                    petStyle == .ashtray
                        ? "点击香烟记一根；烟灰会随今天的数量变化。"
                        : "点击便签右下角的同心圆记一根；便签颜色自动跟随 macOS。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text("大小")
                    Slider(value: $petScale, in: 0.6...1.0, step: 0.05)
                    Text(petScale.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Text(petScaleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("保存设置") {
                    model.updateSettings(
                        limit: limit,
                        dayStartHour: dayStartHour,
                        petScale: petScale,
                        petStyle: petStyle
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedSettings)
            }
        }
    }

    private var resetHistory: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.hasResetHistory ? "不建议再次重置历史" : "需要清空历史并重新开始？")
                    .font(.headline)
                Text("必须写下原因并经过两次确认。每日上限、计数日、桌宠外观和大小会保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("重置历史…", role: .destructive) { showResetHistory = true }
                .disabled(model.store.records.isEmpty && model.store.weeklyChallenge == nil)
        }
    }

    @ViewBuilder
    private var weeklyChallenge: some View {
        if let progress = model.weeklyProgress {
            HStack(alignment: .top, spacing: 24) {
                ChallengeFlowerView(progress: progress)
                    .frame(width: 142, height: 142)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(challengeHeadline(progress))
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if !progress.isFinished && !isEditingChallenge {
                            Button("编辑目标", systemImage: "pencil") {
                                challengeTarget = min(
                                    progress.challenge.targetDays,
                                    max(1, progress.maximumAchievableDays)
                                )
                                reward = progress.challenge.reward
                                isEditingChallenge = true
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Text(challengeDetail(progress))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isEditingChallenge && !progress.isFinished {
                        activeChallengeEditor(progress)
                    } else {
                        if !progress.challenge.reward.isEmpty {
                            Label("给自己的奖励：\(progress.challenge.reward)", systemImage: "gift")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label(
                            "\(cadenceTitle(progress.challenge.cadence)) · 每天不超过 \(progress.dailyLimit) 根 · 日切 \(challengeDayStartText(progress.challenge))",
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                    if progress.isFinished {
                        Divider()
                        newChallengeForm(buttonTitle: "开始新一轮")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("不追求一次做到完美。先选一周里想守住的天数，以及这一周从哪里开始。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                newChallengeForm(buttonTitle: "开始这一周")
            }
        }
    }

    private func activeChallengeEditor(_ progress: WeeklyChallengeProgress) -> some View {
        let maximumTarget = progress.maximumAchievableDays
        return VStack(alignment: .leading, spacing: 9) {
            Stepper(
                "目标：7 天守住 \(challengeTarget) 天",
                value: $challengeTarget,
                in: 1...max(1, maximumTarget)
            )
            TextField("给自己的奖励（可选）", text: $reward)
            Text("周期仍按“\(cadenceTitle(progress.challenge.cadence))”计算，不会重写已经发生的进度。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(
                editingCapacityExplanation(progress),
                systemImage: maximumTarget < progress.challenge.targetDays
                    ? "exclamationmark.circle"
                    : "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消") {
                    challengeTarget = progress.challenge.targetDays
                    reward = progress.challenge.reward
                    isEditingChallenge = false
                }
                Button("保存目标") {
                    model.updateWeeklyChallenge(targetDays: challengeTarget, reward: reward)
                    isEditingChallenge = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(maximumTarget == 0)
            }
        }
        .onChange(of: maximumTarget) { newMaximum in
            challengeTarget = min(challengeTarget, max(1, newMaximum))
        }
    }

    private func newChallengeForm(buttonTitle: String) -> some View {
        let maximumTarget = newChallengeMaximumTarget
        return VStack(alignment: .leading, spacing: 10) {
            Stepper(
                "本轮守住 \(challengeTarget) 天",
                value: $challengeTarget,
                in: 1...max(1, maximumTarget)
            )
            TextField("达成后，允许自己……（可选）", text: $reward)
            Picker("这一周", selection: $challengeCadence) {
                ForEach(WeeklyCadence.allCases, id: \.self) { cadence in
                    Text(cadenceTitle(cadence)).tag(cadence)
                }
            }
            .pickerStyle(.menu)
            Label(cadenceDetail(challengeCadence), systemImage: "calendar.badge.clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(
                newChallengeCapacityExplanation(maximumTarget),
                systemImage: snapshot.isOverLimit ? "exclamationmark.circle" : "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center) {
                Text("按已保存上限 \(model.store.settings.dailyLimit) 根、日切 \(savedDayStartText) 计算。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(buttonTitle) {
                    model.startWeeklyChallenge(
                        targetDays: challengeTarget,
                        reward: reward,
                        cadence: challengeCadence
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(hasUnsavedCountingSettings || maximumTarget == 0)
            }
            if hasUnsavedCountingSettings {
                Label("先保存每日上限和计数日起点，再开始新一轮。", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            challengeTarget = min(challengeTarget, max(1, maximumTarget))
        }
        .onChange(of: challengeCadence) { _ in
            challengeTarget = min(challengeTarget, max(1, newChallengeMaximumTarget))
        }
        .onChange(of: maximumTarget) { newMaximum in
            challengeTarget = min(challengeTarget, max(1, newMaximum))
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(snapshot.lastSevenDays) { day in
                    VStack(spacing: 5) {
                        Text("\(day.count)").font(.caption2).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.78))
                            .frame(height: trendBarHeight(for: day.count))
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text("\(day.date.formatted(.dateTime.month().day()))，\(day.count) 根")
                    )
                }
            }
            .frame(height: 92, alignment: .bottom)
            Divider()
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("把真实进展留成一张图")
                        .font(.callout.weight(.medium))
                    Text(reportExportMessage.isEmpty ? "生成最近 7 个计数日的 PNG 周报，方便保存或分享。" : reportExportMessage)
                        .font(.caption)
                        .foregroundStyle(reportExportFailed ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("生成周报…", systemImage: "square.and.arrow.down") {
                    exportWeeklyReport()
                }
            }
        }
    }

    private var recentRecords: some View {
        VStack(alignment: .leading, spacing: 7) {
            if snapshot.records.isEmpty {
                Text("今天还没有记录").foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.records.suffix(5)) { record in
                    HStack {
                        Text("第 \(record.number) 根")
                        Spacer()
                        Text(record.date.formatted(date: .omitted, time: .shortened))
                        Text(gap(record.gapMinutes)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("数据仅保存在这台 Mac 上。关闭面板不会退出应用，桌宠仍可从菜单栏找回。")
                .foregroundStyle(.tertiary)
            Divider()
            HStack {
                Text("@Sukiea1008")
                    .foregroundStyle(.secondary)
                Spacer()
                Link("github.com/doublesq97-ui", destination: URL(string: "https://github.com/doublesq97-ui")!)
            }
        }
        .font(.caption)
    }

    private var petScaleDescription: String {
        let percentage = petScale.formatted(.percent.precision(.fractionLength(0)))
        let isSavedValue = abs(petScale - model.store.settings.petScale) <= 0.001
        let state: String
        if isSavedValue {
            state = petScale >= 0.995 ? "当前是最大尺寸" : "当前为 \(percentage)"
        } else {
            state = "保存后为 \(percentage)"
        }
        return "\(state)；最小可缩至 60%，拖动范围与点击区域会一起缩放。"
    }

    private var trendMaximum: Int {
        let largestCount = snapshot.lastSevenDays.map(\.count).max() ?? 0
        return max(1, max(snapshot.limit, largestCount))
    }

    private func trendBarHeight(for count: Int) -> CGFloat {
        let maximumHeight: CGFloat = 56
        let fraction = CGFloat(max(0, count)) / CGFloat(trendMaximum)
        let minimumHeight: CGFloat = count == 0 ? 4 : 7
        return min(maximumHeight, max(minimumHeight, maximumHeight * fraction))
    }

    private func challengeHeadline(_ progress: WeeklyChallengeProgress) -> String {
        if progress.isAchieved { return "你做到了，花开了。" }
        if progress.isFinished { return "这一轮留下了 \(progress.achievedDays) 瓣花。" }
        return "已经守住 \(progress.achievedDays) 天"
    }

    private func challengeDetail(_ progress: WeeklyChallengeProgress) -> String {
        if progress.isAchieved {
            return "你守住了自己定下的 \(progress.challenge.targetDays) 天约定。这不是运气，是你一次次把下一根往后放的结果。"
        }
        if progress.isFinished {
            return "没有归零，也没有失败。已经守住的 \(progress.achievedDays) 天，就是下一轮最真实的起点。"
        }
        if progress.maximumAchievableDays < progress.challenge.targetDays {
            return "这一轮按目前进度最多能守住 \(progress.maximumAchievableDays) 天；已经做到的不会消失，也可以把目标改成仍然可达的数字。"
        }
        return "再守住 \(progress.daysStillNeeded) 天就能让这朵花完整开放；今天仍在进行中。"
    }

    private func editingCapacityExplanation(_ progress: WeeklyChallengeProgress) -> String {
        let maximum = progress.maximumAchievableDays
        let activeDayIsOverLimit = progress.days.contains { day in
            day.status == .active && day.cigaretteCount > progress.dailyLimit
        }
        if maximum == 0 {
            return "本轮已经没有仍可达的目标天数；原目标会保留，不会被自动降低。"
        }
        if maximum < progress.challenge.targetDays {
            return "编辑上限为 \(maximum) 天：只计算已守住的天，以及从现在起仍可能守住的天。只有点“保存目标”才会修改原约定。"
        }
        if activeDayIsOverLimit {
            return "今天已经超过本轮上限，因此不计入仍可能达成的天数；编辑上限为 \(maximum) 天。"
        }
        return "编辑上限为 \(maximum) 天，由已守住的天和仍可能守住的天共同计算。"
    }

    private func newChallengeCapacityExplanation(_ maximum: Int) -> String {
        let overLimitNote = snapshot.isOverLimit
            ? " 今天已经超过上限，因此今天不再计入可达天数。"
            : ""
        switch challengeCadence {
        case .rollingSevenDays:
            return "从当前计数日起连续 7 天，本轮最多可设 \(maximum) 天。\(overLimitNote)"
        case .calendarWeekMonday, .calendarWeekSunday:
            return "只计算这个自然周尚未过去的 \(maximum) 个参与日，已经过去的日期不会被补算。\(overLimitNote)"
        }
    }

    private func gap(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "距上一根 \(hours)小时\(rest)分钟" : "距上一根 \(rest)分钟"
    }

    private var undoAvailabilityText: String {
        if model.canUndoToday { return "每个计数日只允许一次" }
        if snapshot.count == 0 { return "今天还没有可撤销的记录" }
        return "今天的撤销机会已用完"
    }

    private var savedDayStartText: String {
        String(format: "%02d:00", model.store.settings.dayStartHour)
    }

    private func challengeDayStartText(_ challenge: WeeklyChallenge) -> String {
        String(format: "%02d:00", challenge.dayStartHour ?? model.store.settings.dayStartHour)
    }

    private func cadenceTitle(_ cadence: WeeklyCadence) -> String {
        switch cadence {
        case .rollingSevenDays: return "从今天起 7 天"
        case .calendarWeekMonday: return "自然周 · 周一开始"
        case .calendarWeekSunday: return "自然周 · 周日开始"
        }
    }

    private func cadenceDetail(_ cadence: WeeklyCadence) -> String {
        switch cadence {
        case .rollingSevenDays:
            return "以今天的计数日起点为第一天，连续记录 7 个计数日。"
        case .calendarWeekMonday:
            return "按当前自然周计算：周一开始，周日结束。"
        case .calendarWeekSunday:
            return "按当前自然周计算：周日开始，周六结束。"
        }
    }

    private func syncChallengeEditor() {
        guard let challenge = model.store.weeklyChallenge else {
            isEditingChallenge = false
            return
        }
        challengeTarget = challenge.targetDays
        reward = challenge.reward
        challengeCadence = challenge.cadence
        isEditingChallenge = false
    }

    private func exportWeeklyReport() {
        let report = SmokingLogic.weeklyReport(store: model.store, now: model.now)
        Task { @MainActor in
            do {
                guard let url = try await WeeklyReportExporter.export(report: report, attachedTo: NSApp.keyWindow) else {
                    return
                }
                reportExportFailed = false
                reportExportMessage = "已保存：\(url.lastPathComponent)"
            } catch {
                reportExportFailed = true
                reportExportMessage = "生成失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct ControlSection<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var isExpanded: Bool
    private let content: () -> Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        _isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isExpanded) {
                content()
                    .padding(.top, 12)
            } label: {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(8)
        }
    }
}

private struct ChallengeFlowerView: View {
    let progress: WeeklyChallengeProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(progress.days.enumerated()), id: \.element.id) { index, day in
                petal(for: day.status)
                    .frame(width: 30, height: 58)
                    .offset(y: -36)
                    .rotationEffect(.degrees(Double(index) * (360.0 / 7.0)))
            }
            Circle()
                .fill(progress.isAchieved ? Color.accentColor : Color.secondary.opacity(0.34))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: progress.isAchieved ? "checkmark" : "heart.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.background)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("7 天目标，已守住 \(progress.achievedDays) 天，目标 \(progress.challenge.targetDays) 天")
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9), value: progress.achievedDays)
    }

    private func petal(for status: WeeklyChallengeDay.Status) -> some View {
        Capsule(style: .continuous)
            .fill(petalColor(for: status))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(status == .active ? 0.22 : 0.08), lineWidth: 1)
            }
    }

    private func petalColor(for status: WeeklyChallengeDay.Status) -> Color {
        switch status {
        case .achieved: return Color.accentColor
        case .missed: return Color.secondary.opacity(0.2)
        case .active: return Color.accentColor.opacity(0.38)
        case .upcoming: return Color.secondary.opacity(0.1)
        case .notParticipating: return Color.secondary.opacity(0.045)
        }
    }
}
