import SwiftUI

enum PickerMode: Identifiable {
    case add
    case swap(UUID)

    var id: String {
        switch self {
        case .add: return "add"
        case .swap(let id): return "swap-\(id.uuidString)"
        }
    }
}

struct VoiceContext: Identifiable {
    let id = UUID()
    /// 从某个动作的菜单打开时，没说器械名就记到这个动作
    let entryID: UUID?
}

struct ActiveSetTarget: Identifiable {
    var id: UUID { self.set.id }
    let entryID: UUID
    let set: SetEntry
    let definition: ExerciseDefinition
    let label: String
}

struct RestSettingTarget: Identifiable {
    var id: String { "\(exerciseID)|\(handedness.rawValue)" }
    let exerciseID: String
    let handedness: Handedness
}

struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerMode: PickerMode? = nil
    @State private var voiceContext: VoiceContext? = nil
    @State private var editingSet: ActiveSetTarget? = nil
    @State private var restSetting: RestSettingTarget? = nil
    @State private var showDiscardConfirm = false
    @State private var showNothingCompleted = false
    @State private var showFinishConfirm = false
    @State private var showTitleEditor = false
    @State private var titleDraft = ""

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let workout = store.data.activeWorkout {
                    workoutList(workout)
                } else {
                    ContentUnavailableView("没有进行中的训练", systemImage: "figure.strengthtraining.traditional")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("收起")
                }
                ToolbarItem(placement: .principal) {
                    if let w = store.data.activeWorkout {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(WeightFormat.duration(ctx.date.timeIntervalSince(w.startedAt)))
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { voiceContext = VoiceContext(entryID: nil) } label: { Image(systemName: "mic.fill") }
                        .accessibilityLabel("语音记组")
                    Button("结束") { finishTapped() }.bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
        }
        .onReceive(ticker) { store.tick(now: $0) }
        .onChange(of: store.data.activeWorkout == nil) { _, isNil in
            if isNil { dismiss() }
        }
        .sheet(item: $pickerMode) { mode in
            switch mode {
            case .add:
                ExercisePickerView(title: "添加动作") { def in
                    let cat = store.catalog
                    store.mutate { $0.addExercise(def.id, catalog: cat) }
                }
            case .swap(let entryID):
                ExercisePickerView(title: "换器械") { def in
                    let cat = store.catalog
                    store.mutate { $0.swapEquipment(entryID: entryID, to: def.id, catalog: cat) }
                }
            }
        }
        .sheet(item: $voiceContext) { ctx in
            VoiceLogSheet(context: ctx)
        }
        .sheet(item: $editingSet) { target in
            SetEditSheet(definition: target.definition, title: "编辑 \(target.label)", set: target.set, showsCompletion: true) { saved in
                store.updateSet(entryID: target.entryID, setID: target.set.id) { s in
                    let wasCompleted = s.isCompleted
                    s = saved
                    if saved.isCompleted && !wasCompleted { s.completedAt = Date() }
                }
            }
        }
        .sheet(item: $restSetting) { target in
            RestSettingSheet(exerciseID: target.exerciseID, handedness: target.handedness)
        }
        .confirmationDialog("放弃本次训练？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("放弃，不保存", role: .destructive) { store.discardWorkout() }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("这次训练的所有记录都不会保存。")
        }
        .confirmationDialog("还没有完成任何一组", isPresented: $showNothingCompleted, titleVisibility: .visible) {
            Button("放弃本次训练", role: .destructive) { store.discardWorkout() }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("没有完成的组，无法保存。可以放弃这次训练直接退出。")
        }
        .confirmationDialog("结束训练？", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("保存并结束") { _ = store.finishWorkout() }
            Button("放弃本次训练", role: .destructive) { store.discardWorkout() }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("未完成的组不会保存。")
        }
        .alert("训练名称", isPresented: $showTitleEditor) {
            TextField("留空使用自动名称", text: $titleDraft)
            Button("保存") {
                let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                store.mutate { d in d.updateActive { w in w.customTitle = t.isEmpty ? nil : t } }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func finishTapped() {
        guard let w = store.data.activeWorkout else { return }
        if w.completedSetCount == 0 {
            showNothingCompleted = true
        } else {
            showFinishConfirm = true
        }
    }

    @ViewBuilder
    private func workoutList(_ workout: Workout) -> some View {
        let catalog = store.catalog
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title(catalog: catalog)).font(.title3.bold())
                        Text("完成 \(workout.completedSetCount) 组 · \(workout.startedAt.dayAndTime) 开始")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        titleDraft = workout.customTitle ?? ""
                        showTitleEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let timer = workout.restTimer {
                Section {
                    RestTimerBar(timer: timer)
                }
            }

            if workout.exercises.isEmpty {
                Section {
                    Text("这次选的部位还没有历史动作。点下面「添加动作」，或者用麦克风直接说。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(workout.exercises) { entry in
                ExerciseSection(
                    entry: entry,
                    workout: workout,
                    isFirst: entry.id == workout.exercises.first?.id,
                    isLast: entry.id == workout.exercises.last?.id,
                    onSwap: { pickerMode = .swap(entry.id) },
                    onVoice: { voiceContext = VoiceContext(entryID: entry.id) },
                    onEditSet: { target in editingSet = target },
                    onRestSettings: {
                        restSetting = RestSettingTarget(exerciseID: entry.exerciseID, handedness: entry.effectiveHandedness)
                    }
                )
            }

            Section {
                Button { pickerMode = .add } label: {
                    Label("添加动作", systemImage: "plus.circle.fill")
                }
                Button { voiceContext = VoiceContext(entryID: nil) } label: {
                    Label("语音记组", systemImage: "mic")
                }
            }

            Section {
                Button { finishTapped() } label: {
                    Text("结束训练").frame(maxWidth: .infinity).bold()
                }
                Button(role: .destructive) { showDiscardConfirm = true } label: {
                    Text("放弃本次训练").frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - 一个动作

struct ExerciseSection: View {
    @EnvironmentObject var store: AppStore
    let entry: ExerciseEntry
    let workout: Workout
    let isFirst: Bool
    let isLast: Bool
    let onSwap: () -> Void
    let onVoice: () -> Void
    let onEditSet: (ActiveSetTarget) -> Void
    let onRestSettings: () -> Void

    @State private var pendingDelete: SetEntry? = nil
    @State private var confirmRemove = false
    @State private var showBasisInfo = false

    var body: some View {
        let def = store.catalog.definition(entry.exerciseID)
        let previous = store.data.previousPerformance(exerciseID: entry.exerciseID, handedness: entry.effectiveHandedness,
                                                      before: workout.startedAt, excluding: workout.id)
        let labels = setLabels(entry.sets)
        Section {
            header(def: def, previous: previous)

            if def.supportsHandedness {
                Picker("单双手", selection: handednessBinding) {
                    ForEach(Handedness.allCases) { h in Text(h.displayName).tag(h) }
                }
                .pickerStyle(.segmented)
            }

            if def.loadFormat == .primeThreePosition {
                HStack {
                    Picker("挂片基准", selection: basisBinding) {
                        Text("每侧").tag(PlateBasis?.some(.perSide))
                        Text("共用").tag(PlateBasis?.some(.shared))
                        if currentBasis == nil { Text("未选").tag(PlateBasis?.none) }
                    }
                    .pickerStyle(.segmented)
                    Button { showBasisInfo = true } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                }
            }

            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    entry: entry,
                    set: set,
                    label: labels[index],
                    previous: previousSet(previous, index: index, entry: entry),
                    definition: def,
                    restTimer: workout.restTimer?.setID == set.id ? workout.restTimer : nil,
                    onEdit: { onEditSet(ActiveSetTarget(entryID: entry.id, set: set, definition: def, label: labels[index])) },
                    onDelete: { requestDelete(set) }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { requestDelete(set) } label: { Label("删除", systemImage: "trash") }
                }
            }

            Button {
                store.mutate { $0.addSet(entryID: entry.id) }
            } label: {
                Label("加一组", systemImage: "plus")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
        .confirmationDialog("删除这一组？", isPresented: deleteDialogBinding, titleVisibility: .visible, presenting: pendingDelete) { set in
            Button("删除", role: .destructive) {
                store.mutate { $0.deleteActiveSet(entryID: entry.id, setID: set.id) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("这一组已经填了数据。")
        }
        .confirmationDialog("移除这个动作？", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("移除", role: .destructive) { store.mutate { $0.removeActiveExercise(entryID: entry.id) } }
            Button("取消", role: .cancel) {}
        }
        .alert("挂片基准", isPresented: $showBasisInfo) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("每侧：左右两边挂一样的重量，填一侧 1/2/3 号位各挂多少。\n共用：只有一组三根挂片杆，填这三根各挂多少。")
        }
    }

    @ViewBuilder
    private func header(def: ExerciseDefinition, previous: PreviousPerformance?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(def.displayName).font(.headline)
                HStack(spacing: 6) {
                    Text(def.equipmentLabel)
                    if let previous {
                        Text("· 上次 \(previous.date.shortDay)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("换器械", systemImage: "arrow.triangle.2.circlepath", action: onSwap)
                Button("语音记这个动作", systemImage: "mic", action: onVoice)
                Button("加热身组", systemImage: "flame") { store.mutate { $0.addSet(entryID: entry.id, kind: .warmup) } }
                Button("休息时间", systemImage: "timer", action: onRestSettings)
                if !isFirst {
                    Button("上移", systemImage: "arrow.up") { store.mutate { $0.moveActiveExercise(entryID: entry.id, by: -1) } }
                }
                if !isLast {
                    Button("下移", systemImage: "arrow.down") { store.mutate { $0.moveActiveExercise(entryID: entry.id, by: 1) } }
                }
                Button("移除动作", systemImage: "trash", role: .destructive) { confirmRemove = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
    }

    private var currentBasis: PlateBasis? {
        entry.sets.first(where: { $0.plateBasis != nil })?.plateBasis
    }

    private var basisBinding: Binding<PlateBasis?> {
        Binding(
            get: { currentBasis },
            set: { value in
                if let value { store.mutate { $0.setPlateBasis(entryID: entry.id, value) } }
            }
        )
    }

    private var handednessBinding: Binding<Handedness> {
        Binding(
            get: { entry.effectiveHandedness },
            set: { value in store.mutate { $0.setHandedness(entryID: entry.id, value) } }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// 空白组直接删；填了数据或已完成的组先确认。
    private func requestDelete(_ set: SetEntry) {
        if set.isCompleted || set.hasAnyData {
            pendingDelete = set
        } else {
            store.mutate { $0.deleteActiveSet(entryID: entry.id, setID: set.id) }
        }
    }

    private func setLabels(_ sets: [SetEntry]) -> [String] {
        var n = 0
        return sets.map { s in
            if s.kind == .warmup { return "热" }
            n += 1
            return "\(n)"
        }
    }

    /// 和上次同一位置的组对比（热身对热身，工作组按顺序）
    private func previousSet(_ previous: PreviousPerformance?, index: Int, entry: ExerciseEntry) -> SetEntry? {
        guard let previous else { return nil }
        let set = entry.sets[index]
        let sameKindBefore = entry.sets[0..<index].filter { $0.kind == set.kind }.count
        let candidates = previous.sets.filter { $0.kind == set.kind }
        if sameKindBefore < candidates.count { return candidates[sameKindBefore] }
        return set.kind == .working ? candidates.last : nil
    }
}

// MARK: - 一组

struct SetRow: View {
    @EnvironmentObject var store: AppStore
    let entry: ExerciseEntry
    let set: SetEntry
    let label: String
    let previous: SetEntry?
    let definition: ExerciseDefinition
    let restTimer: RestTimerState?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(set.kind == .warmup ? Color.orange : Color.primary)
                    .frame(width: 20)

                if definition.loadFormat == .primeThreePosition {
                    ForEach(0..<3, id: \.self) { i in
                        NumberField(placeholder: primePlaceholder(i), value: primeBinding(i))
                            .frame(width: 46)
                    }
                } else if definition.kind != .bodyweight {
                    NumberField(placeholder: previous?.weight.map { WeightFormat.kg($0) } ?? "kg", value: weightBinding)
                        .frame(width: 64)
                }
                Text("×").foregroundStyle(.secondary)
                NumberField(placeholder: previous?.reps.map { String($0) } ?? "次", value: repsBinding, decimal: false)
                    .frame(width: 44)

                Spacer(minLength: 0)

                QualityButton(quality: set.quality) { q in
                    store.updateSet(entryID: entry.id, setID: set.id) { $0.quality = q }
                }

                Button { toggleComplete() } label: {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(set.isCompleted ? "取消完成" : "完成这一组")

                Menu {
                    Button("编辑", systemImage: "pencil", action: onEdit)
                    Button(set.kind == .warmup ? "设为工作组" : "设为热身组", systemImage: "flame") {
                        store.updateSet(entryID: entry.id, setID: set.id) { $0.kind = $0.kind == .warmup ? .working : .warmup }
                    }
                    Button("删除这一组", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 32)
                        .contentShape(Rectangle())
                }
            }

            HStack(spacing: 8) {
                if let previous {
                    Button { usePrevious() } label: {
                        Text("上次 \(WeightFormat.setSummary(previous, format: definition.loadFormat))\(previous.quality?.symbol ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("点一下沿用上次的重量和次数")
                } else {
                    Text("第一次做").font(.caption).foregroundStyle(.tertiary)
                }
                if set.reps != nil {
                    LoadChangeBadge(change: LoadChange.compare(set, to: previous, format: definition.loadFormat))
                }
                if definition.loadFormat == .primeThreePosition, let p = set.primeLoad, !p.isEmpty {
                    Text("合计 \(WeightFormat.kg(p.total))").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let restTimer {
                    RestCountdownPill(timer: restTimer)
                }
            }
            .padding(.leading, 26)
        }
        .listRowBackground(set.isCompleted ? Color.green.opacity(0.10) : Color(.secondarySystemGroupedBackground))
    }

    private func primePlaceholder(_ i: Int) -> String {
        if let v = previous?.primeLoad?[i], v > 0 { return WeightFormat.kg(v) }
        return "\(i + 1)号"
    }

    private var weightBinding: Binding<Double?> {
        Binding(get: { set.weight }, set: { v in store.updateSet(entryID: entry.id, setID: set.id) { $0.weight = v } })
    }

    private var repsBinding: Binding<Double?> {
        Binding(get: { set.reps.map { Double($0) } },
                set: { v in store.updateSet(entryID: entry.id, setID: set.id) { $0.reps = v.map { Int($0) } } })
    }

    private func primeBinding(_ i: Int) -> Binding<Double?> {
        Binding(
            get: { set.primeLoad?[i] },
            set: { v in
                store.updateSet(entryID: entry.id, setID: set.id) { s in
                    var p = s.primeLoad ?? PrimeLoad()
                    p[i] = v
                    s.primeLoad = p.positions.allSatisfy { $0 == nil } ? nil : p
                }
            }
        )
    }

    /// 点"上次"：把上次的重量 / 次数填进来（不自动完成）
    private func usePrevious() {
        guard let previous else { return }
        store.updateSet(entryID: entry.id, setID: set.id) { s in
            s.weight = previous.weight
            s.primeLoad = previous.primeLoad
            if s.plateBasis == nil { s.plateBasis = previous.plateBasis }
            s.reps = previous.reps
        }
    }

    private func toggleComplete() {
        if set.isCompleted {
            store.mutate { $0.uncompleteSet(entryID: entry.id, setID: set.id) }
            return
        }
        hideKeyboard()
        if !set.isLoggable(for: definition) {
            // 和 Hevy 一样：空着直接打勾时，用上次的数据补上没填的部分
            if let previous {
                store.updateSet(entryID: entry.id, setID: set.id) { s in
                    if s.weight == nil && s.primeLoad == nil {
                        s.weight = previous.weight
                        s.primeLoad = previous.primeLoad
                    }
                    if s.plateBasis == nil { s.plateBasis = previous.plateBasis }
                    if s.reps == nil { s.reps = previous.reps }
                }
            }
            guard let updated = store.data.activeWorkout?.exercises.first(where: { $0.id == entry.id })?.sets.first(where: { $0.id == set.id }),
                  updated.isLoggable(for: definition) else {
                onEdit()
                return
            }
        }
        store.completeSet(entryID: entry.id, setID: set.id)
    }
}

// MARK: - 单个动作的休息时间

struct RestSettingSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let exerciseID: String
    let handedness: Handedness
    @State private var seconds = 90
    @State private var loaded = false

    private var key: String { AppSettings.overrideKey(exerciseID: exerciseID, handedness: handedness) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $seconds, in: 15...600, step: 15) {
                        LabeledContent("休息", value: WeightFormat.duration(TimeInterval(seconds)))
                    }
                } header: {
                    Text("\(store.catalog.definition(exerciseID).displayName) · \(handedness.displayName)")
                } footer: {
                    let def = handedness == .unilateral ? store.settings.unilateralRestSeconds : store.settings.defaultRestSeconds
                    Text("默认是 \(WeightFormat.duration(TimeInterval(def)))（在「设置」里改）。")
                }
                if store.settings.exerciseRestOverrides[key] != nil {
                    Button("恢复默认", role: .destructive) {
                        let k = key
                        store.mutate { $0.settings.exerciseRestOverrides[k] = nil }
                        dismiss()
                    }
                }
            }
            .navigationTitle("休息时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let k = key, v = seconds
                        store.mutate { $0.settings.exerciseRestOverrides[k] = v }
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                seconds = store.settings.restSeconds(exerciseID: exerciseID, handedness: handedness)
            }
        }
        .presentationDetents([.medium])
    }
}
