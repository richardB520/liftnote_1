import SwiftUI

struct WeeklyView: View {
    @EnvironmentObject var store: AppStore
    @State private var offset = 0

    var body: some View {
        let catalog = store.catalog
        let settings = store.settings
        let week = WeeklyVolume.week(offset: offset, from: Date())
        let volume = WeeklyVolume.compute(data: store.data, week: week, catalog: catalog)
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                        VStack(spacing: 2) {
                            Text(offset == 0 ? "本周" : (offset == -1 ? "上周" : "\(-offset) 周前")).font(.headline)
                            Text("\(week.start.shortDay) – \(week.end.addingTimeInterval(-1).shortDay)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .disabled(offset >= 0)
                    }
                    BodyMapView(volume: volume, settings: settings)
                        .padding(.vertical, 8)
                    HStack(spacing: 14) {
                        legend(.orange, "不足 \(settings.weeklyTargetMin)")
                        legend(.green, "\(settings.weeklyTargetMin)–\(settings.weeklyTargetMax) 组")
                        legend(.red, "超过 \(settings.weeklyTargetMax)")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }

                Section {
                    ForEach(MuscleGroup.allCases) { m in
                        NavigationLink {
                            ContributionListView(muscle: m, items: volume.contributions[m] ?? [])
                        } label: {
                            MuscleVolumeRow(muscle: m, count: volume.count(m), settings: settings)
                        }
                    }
                } header: {
                    Text("工作组（目标 \(settings.weeklyTargetMin)–\(settings.weeklyTargetMax) 组）")
                } footer: {
                    Text("只算已完成的工作组，热身组不算。每组计入动作直接训练的部位（比如胸推只算胸，不算三头）。点部位能看到是哪几组。")
                }

                Section("最近 6 周") {
                    TrendGrid(endingAt: week, settings: settings)
                }
            }
            .navigationTitle("每周组数")
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// 人体示意：正面（胸、肩中束、二头、腿前侧）和背面（背、肩中束、三头、腿后侧）
struct BodyMapView: View {
    let volume: WeeklyVolume
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 28) {
            figure(front: true)
            figure(front: false)
        }
        .frame(maxWidth: .infinity)
    }

    private var neutral: Color { Color(.systemGray5) }

    private func color(_ m: MuscleGroup) -> Color {
        let n = volume.count(m)
        if n == 0 { return Color(.systemGray4) }
        switch volume.status(m, settings: settings) {
        case .below: return .orange.opacity(0.85)
        case .inRange: return .green.opacity(0.85)
        case .above: return .red.opacity(0.85)
        }
    }

    private func label(_ m: MuscleGroup, x: CGFloat, y: CGFloat) -> some View {
        Text("\(volume.count(m))")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .position(x: x, y: y)
    }

    private func figure(front: Bool) -> some View {
        let arm: MuscleGroup = front ? .biceps : .triceps
        let thigh: MuscleGroup = front ? .quads : .hamstrings
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(neutral).frame(width: 26, height: 26).position(x: 60, y: 16)
                Rectangle().fill(neutral).frame(width: 10, height: 8).position(x: 60, y: 32)
                if front {
                    RoundedRectangle(cornerRadius: 10).fill(color(.chest)).frame(width: 52, height: 40).position(x: 60, y: 57)
                    RoundedRectangle(cornerRadius: 8).fill(neutral).frame(width: 42, height: 44).position(x: 60, y: 103)
                    label(.chest, x: 60, y: 57)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(color(.back)).frame(width: 54, height: 86).position(x: 60, y: 80)
                    label(.back, x: 60, y: 80)
                }
                Circle().fill(color(.sideDelts)).frame(width: 20, height: 20).position(x: 25, y: 45)
                Circle().fill(color(.sideDelts)).frame(width: 20, height: 20).position(x: 95, y: 45)
                Capsule().fill(color(arm)).frame(width: 14, height: 42).position(x: 21, y: 80)
                Capsule().fill(color(arm)).frame(width: 14, height: 42).position(x: 99, y: 80)
                label(arm, x: 21, y: 80)
                Capsule().fill(neutral).frame(width: 12, height: 38).position(x: 19, y: 124)
                Capsule().fill(neutral).frame(width: 12, height: 38).position(x: 101, y: 124)
                RoundedRectangle(cornerRadius: 8).fill(front ? neutral : color(.hamstrings)).frame(width: 50, height: 22).position(x: 60, y: 135)
                Capsule().fill(color(thigh)).frame(width: 21, height: 58).position(x: 48, y: 176)
                Capsule().fill(color(thigh)).frame(width: 21, height: 58).position(x: 72, y: 176)
                label(thigh, x: 48, y: 176)
                Capsule().fill(neutral).frame(width: 14, height: 44).position(x: 48, y: 230)
                Capsule().fill(neutral).frame(width: 14, height: 44).position(x: 72, y: 230)
                label(.sideDelts, x: 25, y: 45)
            }
            .frame(width: 120, height: 256)
            Text(front ? "正面" : "背面").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(front
            ? "正面：胸 \(volume.count(.chest)) 组，肩中束 \(volume.count(.sideDelts)) 组，二头 \(volume.count(.biceps)) 组，腿前侧 \(volume.count(.quads)) 组"
            : "背面：背 \(volume.count(.back)) 组，三头 \(volume.count(.triceps)) 组，腿后侧 \(volume.count(.hamstrings)) 组")
    }
}

struct ContributionListView: View {
    @EnvironmentObject var store: AppStore
    let muscle: MuscleGroup
    let items: [VolumeContribution]

    var body: some View {
        let catalog = store.catalog
        List {
            if items.isEmpty {
                Text("这周还没有\(muscle.displayName)的工作组").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                let def = catalog.definition(item.exerciseID)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(def.displayName)
                        Spacer()
                        Text(WeightFormat.setSummary(item.set, format: def.loadFormat)).monospacedDigit()
                        QualityText(quality: item.set.quality)
                    }
                    Text("\(item.date.dayAndTime) · 第 \(item.setNumber) 组\(item.isInProgress ? " · 进行中" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("\(muscle.displayName) · \(items.count) 组")
    }
}

/// 最近 6 周每个部位的组数
struct TrendGrid: View {
    @EnvironmentObject var store: AppStore
    let endingAt: DateInterval
    let settings: AppSettings

    var body: some View {
        let catalog = store.catalog
        let weeks = (0..<6).reversed().map { WeeklyVolume.week(offset: -$0, from: endingAt.start) }
        let volumes = weeks.map { WeeklyVolume.compute(data: store.data, week: $0, catalog: catalog) }
        Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("").frame(width: 50)
                ForEach(weeks.indices, id: \.self) { i in
                    Text(weeks[i].start.shortDay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            ForEach(MuscleGroup.allCases) { m in
                GridRow {
                    Text(m.displayName).font(.caption).frame(width: 50, alignment: .leading)
                    ForEach(volumes.indices, id: \.self) { i in
                        let n = volumes[i].count(m)
                        Text("\(n)")
                            .font(.caption.monospacedDigit().bold())
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(VolumeBar.color(count: n, lower: settings.weeklyTargetMin, upper: settings.weeklyTargetMax).opacity(n == 0 ? 0.08 : 0.25)))
                    }
                }
            }
        }
    }
}
