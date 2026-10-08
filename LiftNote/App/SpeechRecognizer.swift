import AVFoundation
import Foundation
import Speech

/// 把麦克风数据转给当前的识别请求。音频回调在后台线程，这里用锁保护。
final class AudioBufferRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let r = request
        lock.unlock()
        r?.append(buffer)
    }
}

/// 中文语音识别。停顿后识别任务结束时会自动接着识别，已说的话不会被覆盖，直到调用 `stop()`。
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String? = nil

    private var accumulator = TranscriptAccumulator()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private let relay = AudioBufferRelay()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var consecutiveFailures = 0

    private func requestPermissions() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            errorMessage = "需要语音识别权限：请到 设置 → 练记 中打开。"
            return false
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            errorMessage = "需要麦克风权限：请到 设置 → 练记 中打开。"
            return false
        }
        return true
    }

    /// 开始识别。`existing` 是输入框里已有的文字，新说的话接在后面。
    func start(keeping existing: String = "") async {
        guard !isRecording else { return }
        guard await requestPermissions() else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "语音识别暂时不可用，可以先手动输入。"
            return
        }
        accumulator.reset()
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { accumulator.receive(trimmed, isFinal: true) }
        transcript = accumulator.text
        errorMessage = nil
        consecutiveFailures = 0

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "没有可用的麦克风。"
                return
            }
            input.removeTap(onBus: 0)
            let relay = self.relay
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                relay.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            startRecognitionTask()
        } catch {
            errorMessage = "无法开始录音：\(error.localizedDescription)"
            teardownAudio()
        }
    }

    private func startRecognitionTask() {
        guard let recognizer else { return }
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req
        relay.set(req)
        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            guard let self else { return }
            Task { @MainActor in
                self.handle(text: text, isFinal: isFinal, failed: failed, generation: gen)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, generation gen: Int) {
        guard gen == generation else { return }
        if let text, !text.isEmpty {
            accumulator.receive(text, isFinal: isFinal)
            transcript = accumulator.text
            consecutiveFailures = 0
        }
        guard isRecording, isFinal || failed else { return }
        // 停顿后这一段识别结束了：保留内容，马上接着识别下一段
        accumulator.commitPending()
        transcript = accumulator.text
        if failed && (text ?? "").isEmpty {
            consecutiveFailures += 1
        }
        if consecutiveFailures >= 5 {
            errorMessage = "识别中断了，已保留说过的内容。"
            stop()
            return
        }
        startRecognitionTask()
    }

    /// 用户点"说完了"。
    func stop() {
        guard isRecording else { return }
        isRecording = false
        accumulator.commitPending()
        transcript = accumulator.text
        generation += 1
        request?.endAudio()
        task?.cancel()
        teardownAudio()
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        relay.set(nil)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
