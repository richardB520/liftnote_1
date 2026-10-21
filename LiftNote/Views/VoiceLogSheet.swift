import SwiftUI

/// 语音记组：说完后整理成可修改的确认卡片，点一下保存。
struct VoiceLogSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let context: VoiceContext

    @StateObject private var speech = SpeechRecognizer()
    @State private var text = ""
    @State private var parsed: VoiceParseResult? = nil
    @State private var exerciseID: String? = nil
    @State private var handedness: Handedness = .bilateral
    @State private var basis: PlateBasis? = nil
    @State private var sets: [VoiceParsedSet] = []
    @State private var showPicker = false

    private var contextEntry: ExerciseEntry? {
        guard let id = context.entryID else { return nil }
        return store.data.activeWorkout?.exercises.first { $0.id == id }
    }

    /// 没说器械名时沿用的动作：从动作菜单打开就是那个动作，否则是最近完成过一组的动作
    private var fallbackEntry: ExerciseEntry? {
        if let contextEntry { return contextEntry }
        guard let w = store.data.activeWorkout else { return nil }
        return w.exercises
            .filter { $0.hasCompletedSets }
            .max { ($0.completedSets.compactMap { $0.completedAt }.max() ?? .distantPast) < ($1.completedSets.compactMap { $0.completedAt }.max() ?? .distantPast) }
    }

    private var definition: ExerciseDefinition? { exerciseID.map { store.catalog.definition($0) } }

    private var targetEntryID: UUID? {
        guard let exerciseID, let e = fallbackEntry, e.exerciseID == exerciseID else { return nil }
        return e.id
    }

    private var completeCount: Int {
        guard let def = definition else { return 0 }
        return sets.filter { makeSet($0).isLoggable(for: def) }.count
    }

    private var needsBasis: Bool {
        definition?.loadFormat == .primeThreePosition && basis == nil
    }

    var body: some View {
        NavigationStack {
            List {
                inputSection
                if parsed != nil {
                    exerciseSection
                    if !sets.isEmpty || definition != nil {
                        setsSection
                    }
                    saveSection
                }
            }
            .navigationTitle("语音记组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        speech.stop()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
            .onChange(of: speech.transcript) { _, t in
                if speech.isRecording { text = t }
            }
            .onDisappear { speech.stop() }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView(title: "选择器械") { def in selectExercise(def.id) }
            }
        }
    }

    // MARK: 输入

    private var inputSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: 96)
                if text.isEmpty {
                    Text("例：诺德士坐姿胸推，45 公斤，做了两组，第一组 10 次，第二组 8 次，都比上次轻松")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 12) {
                Button { toggleRecording() } label: {
                    Label(speech.isRecording ? "说完了" : "开始说", systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(speech.isRecording ? Color.red : Color.accentColor)

                Button("整理") { parse() }
                    .buttonStyle(.bordered)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.isRecording)
            }
            if let err = speech.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        } footer: {
            Text(speech.isRecording
                 ? "正在听…可以停顿，接着说会接在后面，说完点「说完了」。"
                 : "可以说器械、重量、次数、组数和质量（更好 / 一样 / 费劲）。PRIME 挂片可以说「每侧一号位 20、二号位 10」。也可以直接打字。")
        }
    }

    private func toggleRecording() {
        if speech.isRecording {
            speech.stop()
            text = speech.transcript
            parse()
        } else {
            let existing = text
            Task { await speech.start(keeping: existing) }
        }
    }

    private func parse() {
        hideKeyboard()
        let fallback = fallbackEntry
        let previousWeight = fallback?.sets.last(where: { $0.weight != nil })?.weight
        let result = VoiceParser.parse(text, catalog: store.catalog, contextExerciseID: fallback?.exerciseID,
                                       previousWeight: previousWeight, recentExerciseIDs: store.recentExerciseIDs)
        parsed = result
        sets = result.sets
        exerciseID = nil
        if let best = result.bestMatch {
            selectExercise(best.id, handedness: result.handedness, basis: result.plateBasis)
        } else {
            handedness = result.handedness ?? .bilateral
            basis = result.plateBasis
        }
    }

    private func selectExercise(_ id: String, handedness spoken: Handedness? = nil, basis spokenBasis: PlateBasis? = nil) {
        exerciseID = id
        let existing = store.data.activeWorkout?.exercises.last { $0.exerciseID == id }
        handedness = spoken ?? parsed?.handedness ?? existing?.effectiveHandedness ?? .bilateral
        // PRIME 挂片基准：说了就用；这次训练里这个器械已经选过也沿用；否则必须手动选
        let existingBasis = existing?.sets.first(where: { $0.plateBasis != nil })?.plateBasis
        basis = spokenBasis ?? parsed?.plateBasis ?? existingBasis
    }

    // MARK: 确认卡片

    private var exerciseSection: some View {
        Section {
            if let def = definition {
                HStack {
                    ExerciseRowLabel(definition: def)
                    Spacer()
                    Button("更换") { showPicker = true }.buttonStyle(.borderless)
                }
                if parsed?.usedContextExercise == true && exerciseID == parsed?.candidates.first?.id {
                    Text("没听到器械名，记到当前动作").font(.caption).foregroundStyle(.secondary)
                }
                if def.supportsHandedness {
                    Picker("单双手", selection: $handedness) {
                        ForEach(Handedness.allCases) { h in Text(h.displayName).tag(h) }
                    }
                    .pickerStyle(.segmented)
                }
                if def.loadFormat == .primeThreePosition {
                    Picker("挂片基准", selection: $basis) {
                        Text("每侧").tag(PlateBasis?.some(.perSide))
                        Text("共用").tag(PlateBasis?.some(.shared))
                        if basis == nil { Text("请选").tag(PlateBasis?.none) }
                    }
                    .pickerStyle(.segmented)
                    if basis == nil {
                        Text("没听到是「每侧」还是「共用」，请选一下").font(.caption).foregroundStyle(.orange)
                    }
                }
            } else if let parsed, !parsed.candidates.isEmpty {
                Text(parsed.isAmbiguous ? "有几个相近的器械，请选一个：" : "请确认器械：")
                    .font(.subheadline)
                ForEach(parsed.candidates.prefix(5)) { d in
                    Button { selectExercise(d.id) } label: { ExerciseRowLabel(definition: d) }
                        .foregroundStyle(Color.primary)
                }
                Button("都不是，手动选择") { showPicker = true }
            } else {
                Button { showPicker = true } label: {
                    Label("没认出器械，点这里选择", systemImage: "magnifyingglass")
                }
            }
        } header: {
            Text("器械")
        }
    }

    private var setsSection: some View {
        Section {
            ForEach(Array(sets.enumerated()), id: \.offset) { i, _ in
                VoiceSetRow(index: i, set: setBinding(i), definition: definition)
            }
            .onDelete { sets.remove(atOffsets: $0) }
            Button {
                var s = VoiceParsedSet()
                if let last = sets.last {
                    s.weight = last.weight
                    s.primeLoad = last.primeLoad
                    if let o = last.ordinal { s.ordinal = o + 1 }
                }
                sets.append(s)
            } label: {
                Label("加一组", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("识别结果（可以直接改）")
        } footer: {
            if sets.isEmpty {
                Text("没听到重量和次数。可以只把动作加入训练，回去再填。")
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                save(keepIncomplete: false)
            } label: {
                Text(completeCount > 0 ? "保存 \(completeCount) 组" : "保存")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .disabled(definition == nil || completeCount == 0 || needsBasis)

            Button {
                save(keepIncomplete: true)
            } label: {
                Text("加入训练，稍后填写").frame(maxWidth: .infinity)
            }
            .disabled(definition == nil)
        } footer: {
            Text("「保存」只记数据完整的组；「加入训练，稍后填写」会把没说完的组也放进训练列表，完整的组照常记为完成。")
        }
    }

    /// 删除行时下标可能暂时越界，这里做保护
    private func setBinding(_ i: Int) -> Binding<VoiceParsedSet> {
        Binding(
            get: { i < sets.count ? sets[i] : VoiceParsedSet() },
            set: { v in if i < sets.count { sets[i] = v } }
        )
    }

    private func makeSet(_ p: VoiceParsedSet) -> SetEntry {
        var s = SetEntry(weight: p.weight, primeLoad: p.primeLoad, plateBasis: basis, reps: p.reps, quality: p.quality)
        if definition?.loadFormat == .primeThreePosition, s.primeLoad == nil, let w = s.weight {
            s.primeLoad = PrimeLoad(w, nil, nil)
            s.weight = nil
        }
        return s
    }

    private func save(keepIncomplete: Bool) {
        guard let id = exerciseID, let def = definition else { return }
        speech.stop()
        let cat = store.catalog
        let hand: Handedness? = def.supportsHandedness ? handedness : nil
        let b = basis
        let s = sets
        let target = targetEntryID
        if store.data.activeWorkout == nil {
            store.mutate { $0.startWorkout(muscles: [], catalog: cat) }
        }
        store.mutate {
            $0.applyVoice(exerciseID: id, handedness: hand, plateBasis: b, sets: s, keepIncomplete: keepIncomplete,
                          targetEntryID: target, catalog: cat)
        }
        RestAlerts.requestAuthorizationIfNeeded()
        dismiss()
    }
}

struct VoiceSetRow: View {
    let index: Int
    @Binding var set: VoiceParsedSet
    let definition: ExerciseDefinition?

    var body: some View {
        HStack(spacing: 6) {
            Text(set.ordinal.map { "第\($0)组" } ?? "第\(index + 1)组")
                .font(.subheadline)
                .frame(width: 52, alignment: .leading)
            if definition?.loadFormat == .primeThreePosition {
                ForEach(0..<3, id: \.self) { i in
                    NumberField(placeholder: "\(i + 1)号", value: primeBinding(i)).frame(width: 44)
                }
            } else if definition?.kind != .bodyweight {
                NumberField(placeholder: "kg", value: $set.weight).frame(width: 60)
            }
            Text("×").foregroundStyle(.secondary)
            NumberField(placeholder: "次", value: $set.reps.asDouble, decimal: false).frame(width: 44)
            Spacer(minLength: 0)
            QualityButton(quality: set.quality) { set.quality = $0 }
        }
    }

    private func primeBinding(_ i: Int) -> Binding<Double?> {
        Binding(
            get: {
                if let p = set.primeLoad { return p[i] }
                return i == 0 ? set.weight : nil
            },
            set: { v in
                var p = set.primeLoad ?? PrimeLoad(set.weight, nil, nil)
                p[i] = v
                set.primeLoad = p
                set.weight = nil
            }
        )
    }
}
