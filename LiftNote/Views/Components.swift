import SwiftUI
import UIKit
import UniformTypeIdentifiers

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// 紧凑的数字输入框。输入中途（如 "45."）不会被打断。
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var decimal: Bool = true

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: text) { _, newText in
                let parsed = WeightFormat.parse(newText)
                let normalized = decimal ? parsed : parsed.map { Double(Int($0)) }
                if normalized != value { value = normalized }
            }
            .onChange(of: value) { _, newValue in
                if WeightFormat.parse(text) != newValue { text = format(newValue) }
            }
    }

    private func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return decimal ? WeightFormat.kg(v) : String(Int(v))
    }
}

extension Binding where Value == Int? {
    /// 让次数（Int?）可以用 NumberField
    var asDouble: Binding<Double?> {
        Binding<Double?>(
            get: { self.wrappedValue.map { Double($0) } },
            set: { self.wrappedValue = $0.map { Int($0) } }
        )
    }
}

/// 质量箭头：点一下依次切换 ↑ → ↓，长按可以选或清除。
struct QualityButton: View {
    let quality: QualityMark?
    let onChange: (QualityMark?) -> Void

    private var next: QualityMark? {
        switch quality {
        case nil: return .better
        case .better?: return .same
        case .same?: return .worse
        case .worse?: return nil
        }
    }

    var body: some View {
        Menu {
            ForEach(QualityMark.allCases) { q in
                Button("\(q.symbol) \(q.displayName)") { onChange(q) }
            }
            Button("不标记") { onChange(nil) }
        } label: {
            Text(quality?.symbol ?? "·")
                .font(.headline)
                .frame(width: 30, height: 32)
                .foregroundStyle(QualityButton.color(quality))
                .background(RoundedRectangle(cornerRadius: 7).fill(QualityButton.color(quality).opacity(0.15)))
        } primaryAction: {
            onChange(next)
        }
    }

    static func color(_ q: QualityMark?) -> Color {
        switch q {
        case .better?: return .green
        case .same?: return .blue
        case .worse?: return .orange
        case nil: return .secondary
        }
    }
}

struct QualityText: View {
    let quality: QualityMark?
    var body: some View {
        Text(quality?.symbol ?? "")
            .bold()
            .foregroundStyle(QualityButton.color(quality))
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? Color.accentColor : Color(.secondarySystemFill)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// 和上次相比的负重 / 次数变化（与质量箭头分开）
struct LoadChangeBadge: View {
    let change: LoadChange?
    var body: some View {
        if let change, let label = change.label {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(badgeColor(change).opacity(0.15)))
                .foregroundStyle(badgeColor(change))
        }
    }

    private func badgeColor(_ c: LoadChange) -> Color {
        if c.isImprovement { return .green }
        if case .redistributed = c { return .purple }
        return .orange
    }
}

/// 当前组旁边的休息倒计时
struct RestCountdownPill: View {
    let timer: RestTimerState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            Label(WeightFormat.duration(remaining), systemImage: "timer")
                .font(.caption.bold().monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// 训练页顶部的休息条：可以 −15 / +15 秒或跳过
struct RestTimerBar: View {
    @EnvironmentObject var store: AppStore
    let timer: RestTimerState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = timer.remaining(at: context.date)
            let total = max(1, timer.duration)
            VStack(spacing: 8) {
                HStack {
                    Label("组间休息", systemImage: "timer").font(.subheadline)
                    Spacer()
                    Text(WeightFormat.duration(remaining))
                        .font(.title2.bold().monospacedDigit())
                }
                ProgressView(value: min(total, total - remaining), total: total)
                HStack {
                    Button("−15秒") { store.adjustRest(by: -15) }
                    Spacer()
                    Button("+15秒") { store.adjustRest(by: 15) }
                    Spacer()
                    Button("跳过") { store.skipRest() }.bold()
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.month().day()) }
    var dayAndTime: String { formatted(.dateTime.month().day().hour().minute()) }
}
