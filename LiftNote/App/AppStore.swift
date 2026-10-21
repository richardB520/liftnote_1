import Foundation
import SwiftUI
import UIKit

/// App 的数据中心：所有修改都经过 `mutate`，自动保存到手机本地（离线可用），
/// 并同步休息倒计时的通知和锁屏 / 灵动岛显示。
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var lastError: String? = nil
    /// 训练页（全屏）是否打开
    @Published var isWorkoutPresented = false

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL = AppStore.defaultFileURL) {
        self.fileURL = fileURL
        var loaded = AppData()
        var loadError: String? = nil
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                loaded = try BackupCodec.decode(Data(contentsOf: fileURL))
            } catch {
                // 读不出来时不覆盖原文件，另存一份
                let stamp = Int(Date().timeIntervalSince1970)
                let copy = fileURL.deletingLastPathComponent().appendingPathComponent("liftnote-data-unreadable-\(stamp).json")
                try? FileManager.default.copyItem(at: fileURL, to: copy)
                loadError = "读取训练数据失败，原文件已另存为 \(copy.lastPathComponent)"
            }
        }
        data = loaded
        lastError = loadError
    }

    /// 默认参数在非主线程上下文里求值，所以这里标 nonisolated（只用到 FileManager，线程安全）
    nonisolated static var defaultFileURL: URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return dir.appendingPathComponent("liftnote-data.json")
    }

    var catalog: ExerciseCatalog { ExerciseCatalog(custom: data.customExercises) }

    var settings: AppSettings { data.settings }

    /// 最近用过的器械（语音识别同分时优先、选动作时排前面）
    var recentExerciseIDs: [String] {
        let active = (data.activeWorkout?.exercises ?? []).reversed().map { $0.exerciseID }
        let history = data.workoutsNewestFirst.flatMap { w in w.exercises.map { $0.exerciseID } }
        var seen = Set<String>()
        var result: [String] = []
        for id in active + history where seen.insert(id).inserted {
            result.append(id)
            if result.count >= 30 { break }
        }
        return result
    }

    // MARK: 修改与保存

    @discardableResult
    func mutate<T>(_ body: (inout AppData) -> T) -> T {
        var copy = data
        let oldTimer = data.activeWorkout?.restTimer
        let result = body(&copy)
        if copy != data {
            data = copy
            scheduleSave()
        }
        if data.activeWorkout?.restTimer != oldTimer {
            syncRestAlerts()
        }
        return result
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// 原子写入：写失败时原文件不受影响，内存里的数据也还在。
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let bytes = try BackupCodec.encode(data)
            try bytes.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            lastError = "保存失败：\(error.localizedDescription)。数据仍保留在 App 中，请稍后再试或导出备份。"
        }
    }

    // MARK: 训练操作

    func startWorkout(muscles: [MuscleGroup]) {
        let cat = catalog
        mutate { $0.startWorkout(muscles: muscles, catalog: cat) }
    }

    func completeSet(entryID: UUID, setID: UUID) {
        let cat = catalog
        let rest = mutate { $0.completeSet(entryID: entryID, setID: setID, catalog: cat) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if rest != nil { RestAlerts.requestAuthorizationIfNeeded() }
    }

    func updateSet(entryID: UUID, setID: UUID, _ body: (inout SetEntry) -> Void) {
        mutate { $0.updateActiveSet(entryID: entryID, setID: setID) { s in body(&s) } }
    }

    func finishWorkout() -> FinishResult {
        let result = mutate { $0.finishActiveWorkout() }
        if case .finished = result { endRestAlerts() }
        return result
    }

    func discardWorkout() {
        mutate { $0.discardActiveWorkout() }
        endRestAlerts()
    }

    // MARK: 休息计时

    func adjustRest(by seconds: TimeInterval) {
        let now = Date()
        mutate { d in
            d.updateActive(now: now) { w in
                guard var t = w.restTimer else { return }
                t.endsAt = max(now, t.endsAt.addingTimeInterval(seconds))
                w.restTimer = t
            }
        }
    }

    func skipRest() {
        mutate { d in d.updateActive { w in w.restTimer = nil } }
        endRestAlerts()
    }

    /// 每秒调用：倒计时到点时清掉，结束锁屏显示（通知已经在系统里排好）。
    func tick(now: Date) {
        guard let t = data.activeWorkout?.restTimer, t.endsAt <= now else { return }
        mutate { d in d.updateActive(now: now) { w in w.restTimer = nil } }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        RestLiveActivity.shared.end()
    }

    private func syncRestAlerts() {
        guard let w = data.activeWorkout, let t = w.restTimer, t.endsAt > Date() else {
            endRestAlerts()
            return
        }
        let cat = catalog
        let entry = w.exercises.first { $0.id == t.entryID }
        let name = entry.map { cat.definition($0.exerciseID).displayName } ?? "组间休息"
        var detail = ""
        if let entry, let i = entry.sets.firstIndex(where: { $0.id == t.setID }) {
            let working = entry.sets[0...i].filter { $0.kind == .working }.count
            detail = entry.sets[i].kind == .warmup ? "热身组已完成" : "第 \(working) 组已完成"
        }
        RestAlerts.schedule(endsAt: t.endsAt, title: "休息结束", body: "\(name) · 开始下一组")
        RestLiveActivity.shared.show(workoutTitle: w.title(catalog: cat), exerciseName: name, detail: detail,
                                     startedAt: t.startedAt, endsAt: t.endsAt)
    }

    private func endRestAlerts() {
        RestAlerts.cancel()
        RestLiveActivity.shared.end()
    }
}
