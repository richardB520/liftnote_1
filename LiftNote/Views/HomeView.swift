import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showNewWorkout = false
    @State private var pendingDelete: Workout? = nil

    var body: some View {
        let catalog = store.catalog
        let week = WeeklyVolume.week(containing: Date())
        let volume = WeeklyVolume.compute(data: store.data, week: week, catalog: catalog)
        NavigationStack {
            List {
                if let active = store.data.activeWorkout {
                    Section("进行中") {
                        Button { store.isWorkoutPresented = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(active.title(catalog: catalog)).font(.headline)
                                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                        Text("已进行 \(WeightFormat.duration(ctx.date.timeIntervalSince(active.startedAt))) · 完成 \(active.completedSetCount) 组")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("继续").bold()
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                } else {
                    Section {
                        Button { showNewWorkout = true } label: {
                            Label("开始训练", systemImage: "play.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                    } footer: {
                        Text("选部位后自动带出上次同部位的动作，边做边填。")
                    }
                }

                Section {
                    ForEach(MuscleGroup.allCases) { m in
                        MuscleVolumeRow(muscle: m, count: volume.count(m), settings: store.settings)
                    }
                } header: {
                    Text("本周工作组")
                }

                Section("最近训练") {
                    let recent = Array(store.data.workoutsNewestFirst.prefix(10))
                    if recent.isEmpty {
                        Text("还没有训练记录").foregroundStyle(.secondary)
                    }
                    ForEach(recent) { w in
                        NavigationLink(value: w.id) {
                            WorkoutRow(workout: w)
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingDelete = w } label: { Label("删除", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button(role: .destructive) { pendingDelete = w } label: { Label("删除这次训练", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("练记")
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
            .sheet(isPresented: $showNewWorkout) {
                NewWorkoutSheet()
            }
            .confirmationDialog("删除这次训练？", isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete) { w in
                Button("删除", role: .destructive) { store.mutate { $0.deleteWorkout(w.id) } }
                Button("取消", role: .cancel) {}
            } message: { w in
                Text("\(w.title(catalog: store.catalog)) · \(w.startedAt.shortDay)，删除后每周组数和上次参考会一起更新。")
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}

struct WorkoutRow: View {
    @EnvironmentObject var store: AppStore
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(workout.title(catalog: store.catalog)).font(.headline)
            HStack(spacing: 8) {
                Text(workout.startedAt.dayAndTime)
                Text("· \(workout.exercises.count) 个动作 · \(workout.completedSetCount) 组")
                if let d = workout.duration {
                    Text("· \(Int(d / 60)) 分钟")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct MuscleVolumeRow: View {
    let muscle: MuscleGroup
    let count: Int
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Text(muscle.displayName)
                .frame(width: 56, alignment: .leading)
            VolumeBar(count: count, lower: settings.weeklyTargetMin, upper: settings.weeklyTargetMax)
            Text("\(count)")
                .font(.body.monospacedDigit().bold())
                .foregroundStyle(VolumeBar.color(count: count, lower: settings.weeklyTargetMin, upper: settings.weeklyTargetMax))
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// 进度条：浅绿色区间是目标（默认 10–20 组）
struct VolumeBar: View {
    let count: Int
    let lower: Int
    let upper: Int

    static func color(count: Int, lower: Int, upper: Int) -> Color {
        if count == 0 { return .secondary }
        if count < lower { return .orange }
        if count > upper { return .red }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            let scale = Double(upper + 5)
            let width = geo.size.width
            let filled = min(Double(count), scale) / scale * width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Rectangle()
                    .fill(Color.green.opacity(0.22))
                    .frame(width: Double(upper - lower) / scale * width)
                    .offset(x: Double(lower) / scale * width)
                Capsule()
                    .fill(VolumeBar.color(count: count, lower: lower, upper: upper))
                    .frame(width: max(count > 0 ? 6 : 0, filled))
            }
        }
        .frame(height: 10)
    }
}

struct NewWorkoutSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    /// 每次打开都是全部未选，由自己选
    @State private var selected: Set<MuscleGroup> = []

    var body: some View {
        let catalog = store.catalog
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(MuscleGroup.allCases) { m in
                        let last = store.data.lastSession(for: m, catalog: catalog)
                        let isOn = selected.contains(m)
                        Button {
                            if isOn { selected.remove(m) } else { selected.insert(m) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(m.displayName).font(.headline)
                                    Spacer()
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                                }
                                Text(m.detail).font(.caption).foregroundStyle(.secondary)
                                Text(last.map { "上次 \($0.date.shortDay) · \($0.exerciseCount) 个动作" } ?? "还没练过")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isOn ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                Text("会按每个部位上次的训练带出动作和组数，重量、次数留空等你边做边填，旁边显示上次的成绩。训练中随时可以换动作、换器械、加动作。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { start(selected) } label: {
                        Text(selected.isEmpty ? "先选训练部位" : "开始训练")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)

                    Button("不选部位，空白开始") { start([]) }
                        .font(.subheadline)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("新训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func start(_ muscles: Set<MuscleGroup>) {
        store.startWorkout(muscles: Array(muscles))
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            store.isWorkoutPresented = true
        }
    }
}
