import AppKit
import Foundation
import SwiftUI

struct WeeklyReportDay: Identifiable, Equatable, Sendable {
    let id: Date
    let start: Date
    let end: Date
    let observedThrough: Date
    let cigaretteCount: Int
    let isCurrentCountingDay: Bool
    let isComplete: Bool
    let isPartial: Bool
    let isWithinLimit: Bool
}

struct WeeklyReport: Equatable, Sendable {
    let generatedAt: Date
    let rangeStart: Date
    let rangeEnd: Date
    let previousRangeStart: Date
    let previousRangeEnd: Date
    let previousComparableCutoff: Date
    let dailyLimit: Int
    let days: [WeeklyReportDay]
    let previousDays: [WeeklyReportDay]
    let totalCount: Int
    let previousTotalCount: Int
    let completedDayCount: Int
    let withinLimitDays: Int
    let longestGapMinutes: Int?
    let encouragement: String

    /// A positive number means fewer cigarettes than the preceding seven counting days.
    var reductionFromPreviousPeriod: Int {
        previousTotalCount - totalCount
    }
}

extension SmokingLogic {
    static func weeklyReport(
        store: SmokeStore,
        now: Date,
        calendar sourceCalendar: Calendar = .current
    ) -> WeeklyReport {
        let policy = CountingDayPolicy(
            dayStartHour: store.settings.dayStartHour,
            calendar: sourceCalendar
        )
        let currentRange = policy.range(containing: now)
        let currentRanges = (-6...0).map { policy.range(offsetBy: $0, from: currentRange) }
        let previousRanges = (-13 ... -7).map { policy.range(offsetBy: $0, from: currentRange) }
        let rangeStart = currentRanges[0].start
        let rangeEnd = currentRanges[6].end
        let previousRangeStart = previousRanges[0].start
        let previousRangeEnd = previousRanges[6].end
        let previousComparableCutoff = policy.mappedCutoff(
            from: now,
            in: currentRange,
            to: previousRanges[6]
        )
        let records = store.records.filter { $0 <= now }.sorted()

        let days = reportDays(
            records: records,
            ranges: currentRanges,
            currentStart: currentRange.start,
            observationCutoff: now,
            dailyLimit: store.settings.dailyLimit
        )
        let previousDays = reportDays(
            records: store.records.sorted(),
            ranges: previousRanges,
            currentStart: currentRange.start,
            observationCutoff: previousComparableCutoff,
            dailyLimit: store.settings.dailyLimit
        )
        let totalCount = days.reduce(0) { $0 + $1.cigaretteCount }
        let previousTotalCount = previousDays.reduce(0) { $0 + $1.cigaretteCount }
        let completedDays = days.filter(\.isComplete)
        let withinLimitDays = completedDays.filter(\.isWithinLimit).count
        let longestGapMinutes = longestGap(
            records: records,
            whoseLaterRecordIsIn: rangeStart..<rangeEnd
        )
        let encouragement = weeklyEncouragement(
            totalCount: totalCount,
            previousTotalCount: previousTotalCount,
            completedDayCount: completedDays.count,
            withinLimitDays: withinLimitDays,
            longestGapMinutes: longestGapMinutes
        )

        return WeeklyReport(
            generatedAt: now,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousRangeStart: previousRangeStart,
            previousRangeEnd: previousRangeEnd,
            previousComparableCutoff: previousComparableCutoff,
            dailyLimit: store.settings.dailyLimit,
            days: days,
            previousDays: previousDays,
            totalCount: totalCount,
            previousTotalCount: previousTotalCount,
            completedDayCount: completedDays.count,
            withinLimitDays: withinLimitDays,
            longestGapMinutes: longestGapMinutes,
            encouragement: encouragement
        )
    }

    private static func reportDays(
        records: [Date],
        ranges: [CountingDayRange],
        currentStart: Date,
        observationCutoff: Date,
        dailyLimit: Int
    ) -> [WeeklyReportDay] {
        ranges.map { range in
            let observedThrough = min(range.end, max(range.start, observationCutoff))
            let count = records.filter {
                range.contains($0) && $0 <= observedThrough
            }.count
            let isCurrent = range.start == currentStart
            let isComplete = observationCutoff >= range.end
            let isPartial = observationCutoff > range.start && observationCutoff < range.end
            return WeeklyReportDay(
                id: range.start,
                start: range.start,
                end: range.end,
                observedThrough: observedThrough,
                cigaretteCount: count,
                isCurrentCountingDay: isCurrent,
                isComplete: isComplete,
                isPartial: isPartial,
                isWithinLimit: isComplete && count <= dailyLimit
            )
        }
    }

    private static func longestGap(
        records: [Date],
        whoseLaterRecordIsIn range: Range<Date>
    ) -> Int? {
        guard records.count >= 2 else { return nil }
        return zip(records, records.dropFirst())
            .filter { range.contains($0.1) }
            .map { max(0, Int($0.1.timeIntervalSince($0.0) / 60.0)) }
            .max()
    }

    private static func weeklyEncouragement(
        totalCount: Int,
        previousTotalCount: Int,
        completedDayCount: Int,
        withinLimitDays: Int,
        longestGapMinutes: Int?
    ) -> String {
        if totalCount == 0 {
            return "这 7 天没有新增记录。安静的每一天，都在替你把习惯往回拉。"
        }

        let reduction = previousTotalCount - totalCount
        if reduction > 0 {
            return "比前 7 天少了 \(reduction) 根。不是一口气改变，是一次次把下一根往后放。"
        }

        if completedDayCount > 0, withinLimitDays == completedDayCount {
            return "已经完成的 \(completedDayCount) 天都守住了约定，稳定本身就是进步。"
        }

        if let longestGapMinutes, longestGapMinutes >= 12 * 60 {
            return "最长一次等了 \(formattedGap(longestGapMinutes))。你已经证明，冲动可以被慢慢拉开。"
        }

        return "这 7 天有 \(withinLimitDays) 个完整日守住了约定。下一根，再晚一点就好。"
    }

    static func formattedGap(_ minutes: Int) -> String {
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let rest = minutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天"
        }
        if hours > 0 {
            return rest > 0 ? "\(hours)小时\(rest)分钟" : "\(hours)小时"
        }
        return "\(rest)分钟"
    }
}

enum WeeklyReportExportTheme: Equatable, Sendable {
    case light
    case dark

    init(appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var palette: WeeklyReportPalette {
        switch self {
        case .light:
            WeeklyReportPalette(
                background: Self.color(red: 247, green: 249, blue: 252),
                surface: Self.color(red: 255, green: 255, blue: 255),
                track: Self.color(red: 224, green: 232, blue: 241),
                primaryText: Self.color(red: 24, green: 32, blue: 43),
                secondaryText: Self.color(red: 82, green: 94, blue: 108),
                tertiaryText: Self.color(red: 119, green: 132, blue: 146),
                accent: Self.color(red: 52, green: 120, blue: 246),
                accentMuted: Self.color(red: 109, green: 157, blue: 232),
                accentSoft: Self.color(red: 229, green: 239, blue: 255),
                border: Self.color(red: 214, green: 223, blue: 233),
                glow: Self.color(red: 105, green: 166, blue: 255)
            )
        case .dark:
            WeeklyReportPalette(
                background: Self.color(red: 20, green: 24, blue: 21),
                surface: Self.color(red: 29, green: 36, blue: 31),
                track: Self.color(red: 48, green: 59, blue: 51),
                primaryText: Self.color(red: 241, green: 245, blue: 242),
                secondaryText: Self.color(red: 174, green: 186, blue: 177),
                tertiaryText: Self.color(red: 126, green: 141, blue: 130),
                accent: Self.color(red: 108, green: 197, blue: 137),
                accentMuted: Self.color(red: 82, green: 154, blue: 105),
                accentSoft: Self.color(red: 35, green: 60, blue: 43),
                border: Self.color(red: 57, green: 70, blue: 61),
                glow: Self.color(red: 72, green: 164, blue: 101)
            )
        }
    }

    private static func color(red: Int, green: Int, blue: Int) -> Color {
        Color(
            nsColor: NSColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        )
    }
}

struct WeeklyReportPalette {
    let background: Color
    let surface: Color
    let track: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    let accentMuted: Color
    let accentSoft: Color
    let border: Color
    let glow: Color
}

struct WeeklyReportCard: View {
    let report: WeeklyReport
    let theme: WeeklyReportExportTheme

    private var palette: WeeklyReportPalette {
        theme.palette
    }

    private var chartMaximum: Int {
        max(report.dailyLimit, report.days.map(\.cigaretteCount).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            Text(report.encouragement)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            metrics
            trend
            progress
            Spacer(minLength: 0)
            footer
        }
        .padding(40)
        .frame(width: WeeklyReportExporter.cardSize.width, height: WeeklyReportExporter.cardSize.height)
        .foregroundStyle(palette.primaryText)
        .background {
            ZStack(alignment: .topTrailing) {
                palette.background
                Circle()
                    .fill(palette.glow.opacity(0.12))
                    .frame(width: 360, height: 360)
                    .blur(radius: 72)
                    .offset(x: 120, y: -150)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: VisualAssets.ashtray)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Flicky Ashtray")
                    .font(.headline)
                Text("本周小结")
                    .font(.largeTitle.weight(.bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(report.generatedAt.formatted(.dateTime.year().month().day()))
                    .font(.subheadline.weight(.medium))
                Text("最近 7 个计数日")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 14) {
            metric(
                title: "本期记录",
                value: "\(report.totalCount) 根",
                symbol: "number.circle.fill",
                detail: "每日上限 \(report.dailyLimit) 根"
            )
            metric(
                title: "比前 7 天",
                value: comparisonValue,
                symbol: comparisonSymbol,
                detail: "同期 \(report.previousTotalCount) 根，同一时点"
            )
            metric(
                title: "最长间隔",
                value: report.longestGapMinutes.map(SmokingLogic.formattedGap) ?? "暂无",
                symbol: "timer",
                detail: "按原始时间戳计算"
            )
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("每天的节奏", systemImage: "chart.bar.fill")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(report.days) { day in
                    VStack(spacing: 7) {
                        Text("\(day.cigaretteCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                        ZStack(alignment: .bottom) {
                            Capsule(style: .continuous)
                                .fill(palette.track)
                            Capsule(style: .continuous)
                                .fill(day.isCurrentCountingDay ? palette.accent : palette.accentMuted)
                                .frame(height: barHeight(for: day.cigaretteCount))
                        }
                        .frame(height: 118)
                        Text(day.start.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption.weight(day.isCurrentCountingDay ? .bold : .regular))
                        Text(day.start.formatted(.dateTime.day()))
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.start.formatted(.dateTime.month().day()))，\(day.cigaretteCount) 根")
                }
            }
            .frame(height: 172, alignment: .bottom)
        }
        .padding(22)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var progress: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 48, height: 48)
                .background(palette.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("完成日守约 \(report.withinLimitDays) / \(report.completedDayCount)")
                    .font(.headline)
                Text("今天仍在进行，不提前给它下结论。")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
        }
        .padding(20)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Label("数据只保存在这台 Mac 上", systemImage: "lock.fill")
            Spacer()
            Text("下一根，再晚一点。")
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
    }

    private var comparisonValue: String {
        let reduction = report.reductionFromPreviousPeriod
        if reduction > 0 { return "少 \(reduction) 根" }
        if reduction < 0 { return "多 \(-reduction) 根" }
        return "持平"
    }

    private var comparisonSymbol: String {
        if report.reductionFromPreviousPeriod > 0 { return "arrow.down.right.circle.fill" }
        if report.reductionFromPreviousPeriod < 0 { return "arrow.up.right.circle.fill" }
        return "equal.circle.fill"
    }

    private func metric(title: String, value: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func barHeight(for count: Int) -> CGFloat {
        let fraction = CGFloat(count) / CGFloat(chartMaximum)
        return max(count == 0 ? 4 : 10, 118 * min(fraction, 1))
    }
}

enum WeeklyReportExportError: LocalizedError {
    case imageRenderFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageRenderFailed: return "无法渲染本周小结。"
        case .pngEncodingFailed: return "无法生成 PNG 文件。"
        }
    }
}

@MainActor
enum WeeklyReportExporter {
    static let cardSize = CGSize(width: 760, height: 860)

    static func pngData(
        for report: WeeklyReport,
        appearance: NSAppearance? = nil,
        scale: CGFloat = 2
    ) throws -> Data {
        let effectiveAppearance = appearance
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        let theme = WeeklyReportExportTheme(appearance: effectiveAppearance)
        let content = WeeklyReportCard(report: report, theme: theme)
            .environment(\.colorScheme, theme.colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(cardSize)
        renderer.scale = max(1, scale)
        renderer.isOpaque = false

        guard let image = renderer.cgImage else {
            throw WeeklyReportExportError.imageRenderFailed
        }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw WeeklyReportExportError.pngEncodingFailed
        }
        return data
    }

    /// Presents a native save panel and returns the written URL, or `nil` when the user cancels.
    @discardableResult
    static func export(
        report: WeeklyReport,
        attachedTo window: NSWindow? = nil
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "生成本周小结"
        panel.nameFieldLabel = "文件名："
        panel.prompt = "保存 PNG"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFilename(for: report)

        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result)
                }
            }
        } else {
            response = panel.runModal()
        }

        guard response == .OK, let url = panel.url else { return nil }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let data = try pngData(for: report, appearance: window?.effectiveAppearance, scale: scale)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func suggestedFilename(for report: WeeklyReport) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Flicky-Ashtray-本周小结-\(formatter.string(from: report.generatedAt)).png"
    }
}
