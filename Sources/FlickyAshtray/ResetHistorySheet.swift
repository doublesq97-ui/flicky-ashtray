import SwiftUI

struct ResetHistorySheet: View {
    let isFirstReset: Bool
    let recordCount: Int
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var reason = ""
    @State private var understandsFirstReset = false
    @State private var confirmationText = ""
    @State private var isFinalConfirmation = false
    @State private var confirmsFinalReset = false

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        guard trimmedReason.count >= 4 else { return false }
        return isFirstReset ? understandsFirstReset : confirmationText == "认真对待自己"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: isFinalConfirmation ? "exclamationmark.triangle.fill" : "arrow.counterclockwise.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(isFinalConfirmation ? Color.red : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isFinalConfirmation ? "最后确认" : "重置历史记录")
                        .font(.title3.weight(.semibold))
                    Text("这不会改动每日上限和计数日设置。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if isFinalConfirmation {
                finalConfirmation
            } else {
                reasonStep
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isFirstReset
                 ? "第一次可以当作重新开始，但以后不要靠清空记录逃开真实情况。认真对待戒烟，也认真对待自己。"
                 : "你已经重置过。再次清空会让趋势失去意义，因此只有在确实需要重新开始时才继续。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("为什么要重置？").font(.headline)
                TextEditor(text: $reason)
                    .font(.body)
                    .frame(height: 84)
                    .padding(6)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("至少写 4 个字。这个理由会留在本机，但被清掉的逐条记录不会恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isFirstReset {
                Toggle("我知道以后不能靠重置来修改自己的戒烟记录", isOn: $understandsFirstReset)
                    .toggleStyle(.checkbox)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("请输入“认真对待自己”以继续")
                        .font(.callout.weight(.medium))
                    TextField("认真对待自己", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            actionRow(primaryTitle: "继续", primaryDisabled: !canContinue) {
                isFinalConfirmation = true
            }
        }
    }

    private var finalConfirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("将清空 \(recordCount) 条抽烟记录，并结束当前 7 天目标。重置原因会作为本机审计记录保留。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            GroupBox("你写下的原因") {
                Text(trimmedReason)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            Toggle("我确认要清空这些记录；这不是一次普通撤销", isOn: $confirmsFinalReset)
                .toggleStyle(.checkbox)
            HStack {
                Button("返回") {
                    confirmsFinalReset = false
                    isFinalConfirmation = false
                }
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                Button("确认清空", role: .destructive) { onConfirm(trimmedReason) }
                    .disabled(!confirmsFinalReset)
            }
        }
    }

    private func actionRow(
        primaryTitle: String,
        primaryDisabled: Bool,
        primaryAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Spacer()
            Button("取消", role: .cancel, action: onCancel)
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .disabled(primaryDisabled)
        }
    }
}
