import SwiftUI

struct ExercisePickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onPick: (ExerciseDefinition) -> Void

    @State private var query = ""
    @State private var brand: Brand? = nil
    @State private var kind: EquipmentKind? = nil
    @State private var muscle: MuscleGroup? = nil
    @State private var showCustomForm = false

    private static let brandFilters: [Brand] = [.nautilus, .prime, .atlantis, .hammerStrength, .generic, .custom]
    private static let kindFilters: [EquipmentKind] = [.selectorized, .plateLoaded, .cable, .dumbbell, .barbell, .smith, .bodyweight]

    private var isFiltering: Bool { !query.isEmpty || brand != nil || kind != nil || muscle != nil }

    var body: some View {
        let catalog = store.catalog
        let results = catalog.search(query, brand: brand, kind: kind, muscle: muscle)
        let recent = store.recentExerciseIDs.prefix(8).map { catalog.definition($0) }.filter { !$0.name.isEmpty && catalog.contains($0.id) }
        NavigationStack {
            List {
                Section {
                    chipRow {
                        ForEach(Self.brandFilters) { b in
                            FilterChip(title: b == .generic ? "自由重量" : (b == .nautilus ? "诺德士" : b.displayName), isOn: brand == b) {
                                brand = brand == b ? nil : b
                            }
                        }
                    }
                    chipRow {
                        ForEach(Self.kindFilters) { k in
                            FilterChip(title: k.displayName, isOn: kind == k) { kind = kind == k ? nil : k }
                        }
                    }
                    chipRow {
                        ForEach(MuscleGroup.allCases) { m in
                            FilterChip(title: m.displayName, isOn: muscle == m) { muscle = muscle == m ? nil : m }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                if !isFiltering && !recent.isEmpty {
                    Section("最近用过") {
                        ForEach(recent) { d in row(d) }
                    }
                }

                Section(isFiltering ? "\(results.count) 个结果" : "全部器械") {
                    ForEach(results) { d in row(d) }
                    if results.isEmpty {
                        Text("没找到，可以添加自定义器械。").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button { showCustomForm = true } label: {
                        Label("添加自定义器械", systemImage: "plus")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "动作、品牌、器械，如：诺德士 胸推")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .sheet(isPresented: $showCustomForm) {
                CustomExerciseForm(initialName: query) { def in
                    store.mutate { $0.customExercises.append(def) }
                    onPick(def)
                    dismiss()
                }
            }
        }
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
        }
    }

    private func row(_ d: ExerciseDefinition) -> some View {
        Button {
            onPick(d)
            dismiss()
        } label: {
            ExerciseRowLabel(definition: d)
        }
        .foregroundStyle(Color.primary)
    }
}

struct ExerciseRowLabel: View {
    let definition: ExerciseDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.displayName)
            HStack(spacing: 6) {
                Text(definition.equipmentLabel)
                if !definition.primary.isEmpty {
                    Text("· " + definition.primary.map { $0.displayName }.joined(separator: "、"))
                } else {
                    Text("· 不计入组数")
                }
                if definition.supportsHandedness {
                    Image(systemName: "hand.raised")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct CustomExerciseForm: View {
    @Environment(\.dismiss) private var dismiss
    let initialName: String
    let onSave: (ExerciseDefinition) -> Void

    @State private var name = ""
    @State private var brand: Brand = .custom
    @State private var series = ""
    @State private var kind: EquipmentKind = .selectorized
    @State private var primary: Set<MuscleGroup> = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("动作") {
                    TextField("动作名称，如：坐姿胸推", text: $name)
                    Picker("品牌", selection: $brand) {
                        ForEach(Brand.allCases) { b in Text(b.displayName).tag(b) }
                    }
                    TextField(brand == .custom ? "品牌 / 型号" : "系列 / 型号（可不填）", text: $series)
                    Picker("器械类型", selection: $kind) {
                        ForEach(EquipmentKind.allCases) { k in Text(k.displayName).tag(k) }
                    }
                    if brand == .prime && kind == .plateLoaded {
                        Text("PRIME 挂片器械会按 1/2/3 号挂片位记录重量。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(MuscleGroup.allCases) { m in
                        Toggle(m.displayName, isOn: Binding(
                            get: { primary.contains(m) },
                            set: { on in if on { primary.insert(m) } else { primary.remove(m) } }
                        ))
                    }
                } header: {
                    Text("直接训练的部位（计入每周组数）")
                }
            }
            .navigationTitle("自定义器械")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = initialName
            }
        }
    }

    private func save() {
        let def = ExerciseDefinition(id: "custom.\(UUID().uuidString)",
                                     name: name.trimmingCharacters(in: .whitespaces),
                                     brand: brand,
                                     series: series.trimmingCharacters(in: .whitespaces),
                                     kind: kind,
                                     primary: MuscleGroup.sorted(primary),
                                     isCustom: true)
        onSave(def)
        dismiss()
    }
}

/// 编辑一组（训练中和历史记录都用）。没填完也能先保存。
struct SetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let definition: ExerciseDefinition
    let title: String
    let showsCompletion: Bool
    let onSave: (SetEntry) -> Void
    @State private var draft: SetEntry

    init(definition: ExerciseDefinition, title: String, set: SetEntry, showsCompletion: Bool, onSave: @escaping (SetEntry) -> Void) {
        self.definition = definition
        self.title = title
        self.showsCompletion = showsCompletion
        self.onSave = onSave
        _draft = State(initialValue: set)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $draft.kind) {
                        Text("工作组").tag(SetKind.working)
                        Text("热身组").tag(SetKind.warmup)
                    }
                    .pickerStyle(.segmented)
                }

                if definition.loadFormat == .primeThreePosition {
                    Section {
                        Picker("挂片基准", selection: $draft.plateBasis) {
                            Text("请选择").tag(PlateBasis?.none)
                            Text("每侧（左右一样）").tag(PlateBasis?.some(.perSide))
                            Text("共用一组三根杆").tag(PlateBasis?.some(.shared))
                        }
                        ForEach(0..<3, id: \.self) { i in
                            HStack {
                                Text("\(i + 1) 号位")
                                Spacer()
                                NumberField(placeholder: "kg", value: primeBinding(i)).frame(width: 90)
                            }
                        }
                        LabeledContent("片重合计", value: "\(WeightFormat.kg(draft.primeLoad?.total ?? 0)) kg")
                    } header: {
                        Text("挂片（不挂的位置留空）")
                    }
                } else if definition.kind != .bodyweight {
                    Section {
                        HStack {
                            Text("重量 kg")
                            Spacer()
                            NumberField(placeholder: "kg", value: $draft.weight).frame(width: 110)
                        }
                    }
                }

                Section {
                    HStack {
                        Text(definition.supportsHandedness ? "次数（单手时填每侧）" : "次数")
                        Spacer()
                        NumberField(placeholder: "次", value: $draft.reps.asDouble, decimal: false).frame(width: 90)
                    }
                }

                Section("质量（和上次比）") {
                    Picker("质量", selection: $draft.quality) {
                        Text("不标记").tag(QualityMark?.none)
                        ForEach(QualityMark.allCases) { q in
                            Text("\(q.symbol)  \(q.displayName)").tag(QualityMark?.some(q))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if showsCompletion {
                    Section {
                        Toggle("已完成", isOn: $draft.isCompleted)
                        if draft.isCompleted && !draft.isLoggable(for: definition) {
                            Text("重量或次数还没填完，会先保存为未完成。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var s = draft
                        if showsCompletion && s.isCompleted && !s.isLoggable(for: definition) {
                            s.isCompleted = false
                            s.completedAt = nil
                        }
                        onSave(s)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
        }
    }

    private func primeBinding(_ i: Int) -> Binding<Double?> {
        Binding(
            get: { draft.primeLoad?[i] },
            set: { v in
                var p = draft.primeLoad ?? PrimeLoad()
                p[i] = v
                draft.primeLoad = p.positions.allSatisfy { $0 == nil } ? nil : p
            }
        )
    }
}
