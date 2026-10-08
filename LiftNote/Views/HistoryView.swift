import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var mode = 0
    @State private var pendingDelete: Workout? = nil
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("视图", selection: $mode) {
                    Text("单次记录").tag(0)
                    Text("连续对比").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if mode == 0 {
                    workoutList
                } else {
                    NotebookIndexView()
                }
            }
            .navigationTitle("记录")
            .toolbar {
                if mode == 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { addPastWorkout() } label: { Label("补记训练", systemImage: "plus") }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
            .navigationDestination(for: AppData.NotebookKey.self) { key in
                NotebookDetailView(key: key)
            }
            .confirmationDialog("删除这次训练？", isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete) { w in
                Button("删除", role: .destructive) { store.mutate { $0.deleteWorkout(w.id) } }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("删除后每周组数和下次训练的上次参考会一起更新。")
            }
        }
    }

    private var workoutList: some View {
        List {
            let workouts = store.data.workoutsNewestFirst
            if workouts.isEmpty {
                Text("还没有训练记录").foregroundStyle(.secondary)
            }
            ForEach(workouts) { w in
                NavigationLink(value: w.id) {
                    WorkoutRow(workout: w)
                }
                .swipeActions {
                    Button(role: .destructive) { pendingDelete = w } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// 忘了记的训练：新建一条已结束的记录，再往里加动作和组
    private func addPastWorkout() {
        let now = Date()
        let w = Workout(startedAt: now.addingTimeInterval(-3600), endedAt: now, updatedAt: now)
        store.mutate { $0.workouts.append(w) }
        path.append(w.id)
    }
}

// MARK: - 单次训练表格

struct HistorySetTarget: Identifiable {
    var id: UUID { self.set.id }
    let entryID: UUID
    let set: SetEntry
    let definition: ExerciseDefinition
    let isNew: Bool
}

struct HistoryEntryTarget: Identifiable {
    let id: UUID
}

struct WorkoutDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let workoutID: UUID

    @State private var editing: HistorySetTarget? = nil
    @State private var changingEquipment: HistoryEntryTarget? = nil
    @State private var addingExercise = false
    @State private var confirmDeleteWorkout = false
    @State private var pendingSetDelete: HistorySetTarget? = nil
    @State private var pendingExerciseDelete: HistoryEntryTarget? = nil
    @State private var showFormatWarning = false

    var body: some View {
        if let w = store.data.workout(workoutID) {
            content(w)
        } else {
            ContentUnavailableView("这条记录已删除", systemImage: "trash")
        }
    }

    private func content(_ w: Workout) -> some View {
        let catalog = store.catalog
        return List {
            Section("基本信息") {
                TextField(w.autoTitle(catalog: catalog), text: titleBinding(w))
                DatePicker("开始时间", selection: dateBinding(w))
                if let d = w.duration {
                    LabeledContent("时长", value: WeightFormat.duration(d))
                }
                LabeledContent("完成组数", value: "\(w.completedSetCount) 组")
                TextField("备注", text: notesBinding(w), axis: .vertical)
            }

            ForEach(w.exercises) { entry in
                let def = catalog.definition(entry.exerciseID)
                Section {
                    HStack {
                        Text("组").frame(width: 28, alignment: .leading)
                        Text("重量").frame(maxWidth: .infinity, alignment: .leading)
                        Text("次数").frame(width: 40, alignment: .leading)
                        Text("质量").frame(width: 34)
                        Text("").frame(width: 64)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                        let target = HistorySetTarget(entryID: entry.id, set: set, definition: def, isNew: false)
                        HStack {
                            Text(set.kind == .warmup ? "热" : "\(workingNumber(entry.sets, index))")
                                .foregroundStyle(set.kind == .warmup ? Color.orange : Color.primary)
                                .frame(width: 28, alignment: .leading)
                            loadText(set, def: def)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(set.reps.map { "\($0)" } ?? "–")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .leading)
                            QualityText(quality: set.quality).frame(width: 34)
                            HStack(spacing: 14) {
                                Button { editing = target } label: { Image(systemName: "pencil") }
                                Button { pendingSetDelete = target } label: { Image(systemName: "trash") }
                                    .tint(.red)
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 64, alignment: .trailing)
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingSetDelete = target } label: { Label("删除", systemImage: "trash") }
                        }
                    }

                    Button {
                        let basis = entry.sets.last(where: { $0.plateBasis != nil })?.plateBasis
                        let last = entry.sets.last
                        let fresh = SetEntry(weight: last?.weight, primeLoad: last?.primeLoad, plateBasis: basis, isCompleted: true)
                        editing = HistorySetTarget(entryID: entry.id, set: fresh, definition: def, isNew: true)
                    } label: {
                        Label("补记一组", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(def.displayName).font(.subheadline.bold()).foregroundStyle(Color.primary)
                            Text(def.equipmentLabel + (def.supportsHandedness ? " · \(entry.effectiveHandedness.displayName)" : ""))
                                .font(.caption)
                        }
                        .textCase(nil)
                        Spacer()
                        Menu {
                            Button("修改器械", systemImage: "arrow.triangle.2.circlepath") {
                                changingEquipment = HistoryEntryTarget(id: entry.id)
                            }
                            if def.supportsHandedness {
                                ForEach(Handedness.allCases) { h in
                                    Button {
                                        store.mutate { $0.setHistoryHandedness(workoutID: workoutID, entryID: entry.id, h) }
                                    } label: {
                                        if h == entry.effectiveHandedness {
                                            Label(h.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(h.displayName)
                                        }
                                    }
                                }
                            }
                            Button("删除这个动作", systemImage: "trash", role: .destructive) {
                                pendingExerciseDelete = HistoryEntryTarget(id: entry.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.body)
                        }
                    }
                }
            }

            Section {
                Button { addingExercise = true } label: { Label("添加动作", systemImage: "plus.circle") }
            }

            Section {
                Button("删除整次训练", role: .destructive) { confirmDeleteWorkout = true }
            }
        }
        .navigationTitle(w.title(catalog: catalog))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { hideKeyboard() }
            }
        }
        .sheet(item: $editing) { target in
            SetEditSheet(definition: target.definition, title: target.isNew ? "补记一组" : "编辑这一组",
                         set: target.set, showsCompletion: false) { saved in
                var s = saved
                s.isCompleted = true
                if target.isNew {
                    store.mutate { $0.addHistorySet(workoutID: workoutID, entryID: target.entryID, set: s) }
                } else {
                    store.mutate { d in
                        d.updateHistorySet(workoutID: workoutID, entryID: target.entryID, setID: target.set.id) { existing in
                            let completedAt = existing.completedAt
                            existing = s
                            existing.completedAt = completedAt ?? s.completedAt
                        }
                    }
                }
            }
        }
        .sheet(item: $changingEquipment) { target in
            ExercisePickerView(title: "修改器械") { def in
                let cat = store.catalog
                let formatChanged = store.mutate {
                    $0.changeHistoryEquipment(workoutID: workoutID, entryID: target.id, to: def.id, catalog: cat)
                }
                if formatChanged { showFormatWarning = true }
            }
        }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerView(title: "添加动作") { def in
                let cat = store.catalog
                let entryID = store.mutate { $0.addHistoryExercise(workoutID: workoutID, exerciseID: def.id, catalog: cat) }
                if let entryID {
                    let basis = store.data.lastPlateBasis(exerciseID: def.id)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        editing = HistorySetTarget(entryID: entryID, set: SetEntry(plateBasis: basis, isCompleted: true),
                                                   definition: def, isNew: true)
                    }
                }
            }
        }
        .confirmationDialog("删除这一组？", isPresented: setDeleteBinding, titleVisibility: .visible, presenting: pendingSetDelete) { target in
            Button("删除", role: .destructive) {
                store.mutate { $0.deleteHistorySet(workoutID: workoutID, entryID: target.entryID, setID: target.set.id) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除这个动作的所有组？", isPresented: exerciseDeleteBinding, titleVisibility: .visible, presenting: pendingExerciseDelete) { target in
            Button("删除", role: .destructive) {
                store.mutate { $0.deleteHistoryExercise(workoutID: workoutID, entryID: target.id) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除整次训练？", isPresented: $confirmDeleteWorkout, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.mutate { $0.deleteWorkout(workoutID) }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .alert("请重新填写重量", isPresented: $showFormatWarning) {
            Button("好", role: .cancel) {}
        } message: {
            Text("新器械的重量记录方式不同（普通重量 / PRIME 三挂片位），组数、次数和质量都保留了，请点每组的铅笔重新填重量。")
        }
    }

    @ViewBuilder
    private func loadText(_ set: SetEntry, def: ExerciseDefinition) -> some View {
        switch def.loadFormat {
        case .primeThreePosition:
            if let p = set.primeLoad {
                VStack(alignment: .leading, spacing: 0) {
                    Text((0..<3).map { i in p[i].map { WeightFormat.kg($0) } ?? "–" }.joined(separator: " / ")).monospacedDigit()
                    Text("\(set.plateBasis?.displayName ?? "未选基准") · 合计 \(WeightFormat.kg(p.total))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("待填重量").foregroundStyle(.orange)
            }
        case .standard:
            if let w = set.weight {
                Text("\(WeightFormat.kg(w)) kg").monospacedDigit()
            } else if def.kind == .bodyweight {
                Text("自重").foregroundStyle(.secondary)
            } else {
                Text("待填重量").foregroundStyle(.orange)
            }
        }
    }

    private func workingNumber(_ sets: [SetEntry], _ index: Int) -> Int {
        sets[0...index].filter { $0.kind == .working }.count
    }

    private func titleBinding(_ w: Workout) -> Binding<String> {
        Binding(
            get: { w.customTitle ?? "" },
            set: { v in store.mutate { d in d.updateWorkout(workoutID) { wk in wk.customTitle = v.isEmpty ? nil : v } } }
        )
    }

    private func notesBinding(_ w: Workout) -> Binding<String> {
        Binding(
            get: { w.notes },
            set: { v in store.mutate { d in d.updateWorkout(workoutID) { wk in wk.notes = v } } }
        )
    }

    private func dateBinding(_ w: Workout) -> Binding<Date> {
        Binding(
            get: { w.startedAt },
            set: { v in store.mutate { $0.changeWorkoutDate(workoutID, to: v) } }
        )
    }

    private var setDeleteBinding: Binding<Bool> {
        Binding(get: { pendingSetDelete != nil }, set: { if !$0 { pendingSetDelete = nil } })
    }

    private var exerciseDeleteBinding: Binding<Bool> {
        Binding(get: { pendingExerciseDelete != nil }, set: { if !$0 { pendingExerciseDelete = nil } })
    }
}

// MARK: - 连续对比（训练笔记本）

struct NotebookIndexView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""

    var body: some View {
        let catalog = store.catalog
        let q = TextNormalizer.compact(query)
        let keys = store.data.notebookKeys().filter { key in
            q.isEmpty || ExerciseCatalog.searchText(for: catalog.definition(key.exerciseID)).contains(q)
        }
        List {
            if keys.isEmpty {
                Text(query.isEmpty ? "完成训练后，这里按器械把每次的重量、次数和质量横向排在一起。" : "没找到")
                    .foregroundStyle(.secondary)
            }
            ForEach(keys, id: \.self) { key in
                let def = catalog.definition(key.exerciseID)
                NavigationLink(value: key) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.displayName)
                        Text(def.equipmentLabel + (def.supportsHandedness ? " · \(key.handedness.displayName)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索动作")
    }
}

struct NotebookDetailView: View {
    @EnvironmentObject var store: AppStore
    let key: AppData.NotebookKey

    var body: some View {
        let def = store.catalog.definition(key.exerciseID)
        let sessions = store.data.notebookSessions(key)
        let maxSets = sessions.map { $0.sets.count }.max() ?? 0
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(sessions.enumerated()), id: \.element.workoutID) { index, session in
                    let previous = index > 0 ? sessions[index - 1] : nil
                    NavigationLink(value: session.workoutID) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.date.shortDay).font(.headline)
                            Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider()
                            ForEach(0..<maxSets, id: \.self) { i in
                                if i < session.sets.count {
                                    let s = session.sets[i]
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 3) {
                                            Text(WeightFormat.setSummary(s, format: def.loadFormat))
                                                .font(.subheadline.monospacedDigit())
                                            QualityText(quality: s.quality)
                                        }
                                        LoadChangeBadge(change: LoadChange.compare(s, to: previousSet(previous, i), format: def.loadFormat))
                                    }
                                    .frame(height: 36, alignment: .topLeading)
                                } else {
                                    Text("–").foregroundStyle(.tertiary).frame(height: 36, alignment: .topLeading)
                                }
                            }
                        }
                        .padding(10)
                        .frame(width: def.loadFormat == .primeThreePosition ? 128 : 104, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.trailing)
        .navigationTitle(def.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("从左到右是从旧到新。↑ → ↓ 是你标的质量，彩色小标签是和上一次相比的负重 / 次数变化。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    private func previousSet(_ previous: PreviousPerformance?, _ i: Int) -> SetEntry? {
        guard let previous, i < previous.sets.count else { return nil }
        return previous.sets[i]
    }
}
