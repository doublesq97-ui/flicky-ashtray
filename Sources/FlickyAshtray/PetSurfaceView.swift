import SwiftUI

struct PetSurfaceView: View {
    @ObservedObject var model: AppModel
    let onHover: (Bool) -> Void
    let onTogglePin: () -> Void
    let onShowControlPanel: () -> Void
    let onHide: () -> Void
    var scale: CGFloat = 1

    @State private var isTappingAsh = false
    @State private var cigaretteLift: CGFloat = 0
    @State private var cigaretteKnock = 0.0
    @State private var ashFall: CGFloat = 1
    @State private var showsAshBurst = false
    @State private var isIgniterLit = false
    @State private var isIgniterBusy = false
    @State private var ignitionTask: Task<Void, Never>?
    @State private var recordActionDebouncer = RecordActionDebouncer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: DaySnapshot { model.snapshot }
    private var petStyle: PetStyle { model.store.settings.petStyle }

    var body: some View {
        baseSurface
            .scaleEffect(PetLayout.normalizedScale(scale), anchor: .center)
            .frame(
                width: PetLayout.scaledSurfaceSize(for: scale, style: petStyle).width,
                height: PetLayout.scaledSurfaceSize(for: scale, style: petStyle).height
            )
            .onChange(of: petStyle) { style in
                if style != .note { cancelIgnitionFeedback() }
            }
            .onDisappear(perform: cancelIgnitionFeedback)
    }

    @ViewBuilder
    private var baseSurface: some View {
        Group {
            switch petStyle {
            case .ashtray:
                ashtraySurface
            case .note:
                noteSurface
            }
        }
        .frame(
            width: PetLayout.surfaceSize(for: petStyle).width,
            height: PetLayout.surfaceSize(for: petStyle).height
        )
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            petStyle == .ashtray
                ? "Flicky Ashtray 桌面烟灰缸"
                : "Flicky Ashtray 桌面便签"
        )
        .accessibilityValue("今天 \(snapshot.count) / \(snapshot.limit) 根")
        .accessibilityAction(named: "固定或收起今日状态", onTogglePin)
        .accessibilityAction(named: "查看记录与设置", onShowControlPanel)
        .accessibilityAction(named: "隐藏桌宠", onHide)
    }

    private var ashtraySurface: some View {
        ZStack {
            Image(nsImage: VisualAssets.ashtray)
                .resizable()
                .scaledToFit()
                .frame(width: PetLayout.ashtraySize.width, height: PetLayout.ashtraySize.height)
                .accessibilityHidden(true)

            ashContents

            // Reuse the exact ashtray pixels as a foreground occlusion layer.
            // The pile stays visually inside the bowl without redrawing the body.
            Image(nsImage: VisualAssets.ashtray)
                .resizable()
                .scaledToFit()
                .frame(width: PetLayout.ashtraySize.width, height: PetLayout.ashtraySize.height)
                .mask(AshtrayFrontOcclusionShape())
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if showsAshBurst {
                FallingAshBurst(progress: ashFall)
                    .offset(x: 7, y: -18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Button(action: recordOne) {
                cigarette
                    .frame(
                        width: PetLayout.cigaretteButtonSize.width,
                        height: PetLayout.cigaretteButtonSize.height
                    )
                    // The filter-side notch is the support point. The ember makes
                    // the larger arc, so the gesture reads as a short ash tap.
                    .rotationEffect(
                        .degrees(cigaretteKnock),
                        anchor: UnitPoint(x: 0.27, y: 0.31)
                    )
                    .rotationEffect(.degrees(PetLayout.cigaretteAngle))
                    .contentShape(Rectangle())
            }
            .buttonStyle(CigarettePressStyle())
            .offset(
                x: PetLayout.cigaretteOffset.width,
                y: PetLayout.cigaretteOffset.height - cigaretteLift
            )
            .disabled(isTappingAsh)
            .help("点这支烟，记一根")
            .accessibilityLabel("记一根烟")
            .accessibilityValue("今天 \(snapshot.count) / \(snapshot.limit) 根")
            .accessibilityHint("按下后记录当前时间")
        }
        .frame(width: PetLayout.surfaceSize.width, height: PetLayout.surfaceSize.height)
    }

    private var noteSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(width: PetLayout.noteCardRect.width, height: PetLayout.noteCardRect.height)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.52), lineWidth: 0.5)
                }
                // Stay inside the six/eight-point transparent window margin;
                // a larger blur gets hard-clipped and reads as a white edge.
                .shadow(color: Color(nsColor: .shadowColor).opacity(0.14), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("戒烟日志")
                    .font(.system(size: PetLayout.noteCaptionFontSize(for: scale), weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("今天 \(snapshot.count) / \(snapshot.limit)")
                    .font(.system(size: PetLayout.noteCountFontSize(for: scale), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isOverLimit ? Color.red : Color.primary)
                Text(noteCountDetail)
                    .font(.system(size: PetLayout.noteCaptionFontSize(for: scale)))
                    .foregroundStyle(snapshot.isOverLimit ? Color.red : Color.secondary)
                if PetLayout.showsNoteSecondaryLine(for: scale) {
                    Text(noteLastRecordDetail)
                        .font(.system(size: PetLayout.noteSecondaryFontSize(for: scale)))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 148, alignment: .leading)
            .offset(x: -20, y: -2)

            Button(action: recordFromNote) {
                IgniterButton(isLit: isIgniterLit)
                    .frame(
                        width: PetLayout.noteActionButtonSize.width,
                        height: PetLayout.noteActionButtonSize.height
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(IgniterButtonStyle(reduceMotion: reduceMotion))
            .offset(x: PetLayout.noteActionOffset.width, y: PetLayout.noteActionOffset.height)
            .help("点一下，记一根")
            .accessibilityLabel("点烟器，记一根烟")
            .accessibilityValue("今天 \(snapshot.count) / \(snapshot.limit) 根")
            .accessibilityHint("按下后记录当前时间；红色余烬会自动熄灭")
        }
        .frame(width: PetLayout.noteSurfaceSize.width, height: PetLayout.noteSurfaceSize.height)
    }

    private var cigarette: some View {
        Image(nsImage: VisualAssets.cigarette)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ashContents: some View {
        switch snapshot.ashLevel {
        case .clean:
            EmptyView()
        case .sprinkle:
                Image(nsImage: VisualAssets.sprinkle)
                .resizable()
                .scaledToFit()
                    .frame(width: 82, height: 44)
                    .offset(y: -6)
                    .accessibilityHidden(true)
        case .full:
                Image(nsImage: VisualAssets.full)
                .resizable()
                .scaledToFit()
                    .frame(width: 90, height: 56)
                    .offset(y: -3)
                    .accessibilityHidden(true)
        case .overLimit:
                Image(nsImage: VisualAssets.overLimit)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 70)
                    .mask(Ellipse().frame(width: 106, height: 62))
                    .offset(y: -5)
                    .accessibilityHidden(true)
        case .filthy:
                Image(nsImage: VisualAssets.filthy)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 88)
                    .mask(Ellipse().frame(width: 118, height: 66))
                    .offset(y: -7)
                    .accessibilityHidden(true)
        }
    }

    private func recordOne() {
        guard acceptsRecordAction() else { return }
        guard !isTappingAsh else { return }
        if reduceMotion {
            model.addRecord()
            return
        }
        isTappingAsh = true
        showsAshBurst = false
        ashFall = 0
        withAnimation(.spring(response: 0.14, dampingFraction: 0.86)) {
            cigaretteLift = 3
            cigaretteKnock = -3.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) {
            withAnimation(.spring(response: 0.10, dampingFraction: 0.78)) {
                cigaretteLift = 0
                cigaretteKnock = 2.5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.135) {
            showsAshBurst = true
            model.addRecord()
            withAnimation(.easeOut(duration: 0.18)) { ashFall = 1 }
            withAnimation(.spring(response: 0.17, dampingFraction: 0.9)) {
                cigaretteLift = 0
                cigaretteKnock = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
            showsAshBurst = false
            isTappingAsh = false
        }
    }

    private func recordFromNote() {
        // A physical cigarette cannot be logged twice inside one short ignition
        // gesture. This also prevents an accidental double-click from creating
        // two records when only one undo is available per counting day.
        guard acceptsRecordAction() else { return }
        guard !isIgniterBusy else { return }
        isIgniterBusy = true
        model.addRecord()
        ignitionTask?.cancel()

        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.08)
                : .spring(response: 0.16, dampingFraction: 1)
        ) {
            isIgniterLit = true
        }

        let holdNanoseconds: UInt64 = reduceMotion ? 140_000_000 : 430_000_000
        let fadeNanoseconds: UInt64 = reduceMotion ? 120_000_000 : 340_000_000
        ignitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: holdNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.34)) {
                isIgniterLit = false
            }
            try? await Task.sleep(nanoseconds: fadeNanoseconds)
            guard !Task.isCancelled else { return }
            isIgniterBusy = false
            ignitionTask = nil
        }
    }

    private func cancelIgnitionFeedback() {
        ignitionTask?.cancel()
        ignitionTask = nil
        isIgniterLit = false
        isIgniterBusy = false
    }

    private func acceptsRecordAction() -> Bool {
        recordActionDebouncer.accept(
            nowUptime: ProcessInfo.processInfo.systemUptime,
            doubleClickInterval: NSEvent.doubleClickInterval
        )
    }

    private var noteCountDetail: String {
        if snapshot.isOverLimit { return "超过 \(snapshot.count - snapshot.limit) 根" }
        if snapshot.remaining == 0 { return "已经到今天的上限" }
        return "还剩 \(snapshot.remaining) 根"
    }

    private var noteLastRecordDetail: String {
        guard let latest = snapshot.records.last else { return "今天还没有记录" }
        return "最近 \(latest.date.formatted(date: .omitted, time: .shortened))"
    }

}

private struct CigarettePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

private struct IgniterButton: View {
    let isLit: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 36, height: 36)
            Circle()
                .stroke(Color(nsColor: .separatorColor).opacity(0.78), lineWidth: 1)
                .frame(width: 34, height: 34)
            Circle()
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.46), lineWidth: 1)
                .frame(width: 25, height: 25)
            Circle()
                .stroke(
                    isLit ? Color.red.opacity(0.62) : Color(nsColor: .quaternaryLabelColor),
                    lineWidth: 1
                )
                .frame(width: 17, height: 17)
            Circle()
                .fill(isLit ? Color.red : Color(nsColor: .tertiaryLabelColor).opacity(0.34))
                .frame(width: 9, height: 9)
        }
        .shadow(color: isLit ? Color.red.opacity(0.34) : .clear, radius: 4)
        .accessibilityHidden(true)
    }
}

private struct IgniterButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

struct StatusCardView: View {
    @ObservedObject var model: AppModel
    let isPinned: Bool
    let onHover: (Bool) -> Void
    let onTogglePin: () -> Void

    private var snapshot: DaySnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.statusMessage).font(.callout.weight(.medium))
                Spacer(minLength: 6)
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消固定今日状态" : "固定今日状态")
                .accessibilityLabel(isPinned ? "取消固定今日状态" : "固定今日状态")
            }
            Text("今天 \(snapshot.count) / \(snapshot.limit) 根 · \(countDetail)")
                .font(.caption)
                .foregroundStyle(snapshot.isOverLimit ? Color.red : Color.secondary)
            if let feedback = model.positiveFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(width: 252, alignment: .leading)
        .onHover(perform: onHover)
    }

    private var countDetail: String {
        if snapshot.isOverLimit { return "超过 \(snapshot.count - snapshot.limit) 根" }
        if snapshot.remaining == 0 { return "已到上限" }
        return "还剩 \(snapshot.remaining) 根"
    }
}

private struct AshtrayFrontOcclusionShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.51))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.51),
            control: CGPoint(x: rect.midX, y: rect.height * 0.69)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FallingAshBurst: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            particle(x: -5, delay: 0.00, size: 3.0)
            particle(x: 0, delay: 0.08, size: 2.2)
            particle(x: 4, delay: 0.16, size: 2.7)
            particle(x: 8, delay: 0.25, size: 1.8)
        }
        .frame(width: 22, height: 28)
    }

    private func particle(x: CGFloat, delay: CGFloat, size: CGFloat) -> some View {
        let localProgress = min(1, max(0, (progress - delay) / max(0.01, 1 - delay)))
        return Circle()
            .fill(Color(nsColor: .tertiaryLabelColor))
            .frame(width: size, height: size)
            .offset(x: x, y: localProgress * 18)
            .opacity(1 - Double(localProgress))
    }
}
