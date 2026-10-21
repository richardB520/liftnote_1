import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var exportDocument: BackupDocument? = nil
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importMessage: String? = nil

    var body: some View {
        let s = store.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("完成一组后自动开始休息计时", isOn: binding(\.restTimerEnabled))
                    Stepper(value: binding(\.defaultRestSeconds), in: 15...600, step: 15) {
                        LabeledContent("常规 / 双手", value: WeightFormat.duration(TimeInterval(s.defaultRestSeconds)))
                    }
                    Stepper(value: binding(\.unilateralRestSeconds), in: 15...600, step: 15) {
                        LabeledContent("单手轮流", value: WeightFormat.duration(TimeInterval(s.unilateralRestSeconds)))
                    }
                    NavigationLink {
                        RestOverridesView()
                    } label: {
                        LabeledContent("单个动作的休息时间", value: s.exerciseRestOverrides.isEmpty ? "无" : "\(s.exerciseRestOverrides.count) 个")
                    }
                } header: {
                    Text("组间休息")
                } footer: {
                    Text("倒计时显示在当前组旁边，也会出现在锁屏和灵动岛上，到点提醒。第一次计时时请允许通知。单个动作的休息时间在训练中动作右上角「…」→「休息时间」设置。")
                }

                Section {
                    Stepper(value: binding(\.weeklyTargetMin), in: 1...max(1, s.weeklyTargetMax)) {
                        LabeledContent("最少", value: "\(s.weeklyTargetMin) 组")
                    }
                    Stepper(value: binding(\.weeklyTargetMax), in: s.weeklyTargetMin...60) {
                        LabeledContent("最多", value: "\(s.weeklyTargetMax) 组")
                    }
                    Stepper(value: binding(\.defaultSetsPerExercise), in: 1...6) {
                        LabeledContent("新加动作默认组数", value: "\(s.defaultSetsPerExercise) 组")
                    }
                } header: {
                    Text("每周目标")
                } footer: {
                    Text("每个部位每周的工作组数目标。默认每个动作做两组，把训练量分给不同动作。")
                }

                Section {
                    Button {
                        do {
                            let bytes = try BackupCodec.encode(store.data)
                            exportDocument = BackupDocument(data: bytes)
                            showExporter = true
                        } catch {
                            importMessage = "导出失败：\(error.localizedDescription)"
                        }
                    } label: {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("从备份恢复", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("训练记录只保存在这台手机上，可以离线使用。恢复备份是合并：同一条记录只在备份更新时才覆盖，重复导入不会冲掉你之后改过的内容。")
                }

                Section {
                    LabeledContent("状态", value: "未连接")
                    Text("WHOOP 官方公开接口只支持授权后读取训练记录，不能让其他 App 远程开始或结束 WHOOP 的训练，所以目前无法在点「开始训练」时同步让 WHOOP 开始计时。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("WHOOP")
                }

                Section {
                    LabeledContent("器械库", value: "\(ExerciseCatalog.builtIn.count) 个内置 · \(store.data.customExercises.count) 个自定义")
                    Text("练记不计算卡路里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                          defaultFilename: "练记备份-\(Date().formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result {
                    importMessage = "导出失败：\(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("备份", isPresented: messageBinding) {
                Button("好", role: .cancel) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.data.settings[keyPath: keyPath] },
            set: { value in store.mutate { $0.settings[keyPath: keyPath] = value } }
        )
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = "导入失败：\(error.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try BackupCodec.decode(Data(contentsOf: url))
                let report = store.mutate { d -> MergeReport in
                    let (merged, r) = BackupCodec.merge(current: d, imported: imported)
                    d = merged
                    return r
                }
                importMessage = report.summary
            } catch {
                importMessage = "这个文件不是练记的备份，或者已损坏。"
            }
        }
    }
}

struct RestOverridesView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let catalog = store.catalog
        let items = store.settings.exerciseRestOverrides.sorted { $0.key < $1.key }
        List {
            if items.isEmpty {
                Text("还没有单独设置的动作。训练中点动作右上角「…」→「休息时间」即可设置。")
                    .foregroundStyle(.secondary)
            }
            ForEach(items, id: \.key) { item in
                let parts = item.key.split(separator: "|").map(String.init)
                let def = catalog.definition(parts.first ?? "")
                let hand = parts.count > 1 ? Handedness(rawValue: parts[1]) : nil
                LabeledContent {
                    Text(WeightFormat.duration(TimeInterval(item.value))).monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(def.displayName)
                        if let hand, def.supportsHandedness {
                            Text(hand.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        let k = item.key
                        store.mutate { $0.settings.exerciseRestOverrides[k] = nil }
                    } label: {
                        Label("恢复默认", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .navigationTitle("单个动作的休息时间")
    }
}
