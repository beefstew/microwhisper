import Foundation

protocol TranscriptionManagerDelegate: AnyObject {
    func transcriptionManager(_ manager: TranscriptionManager, didUpdateProgress progress: String)
    func transcriptionManager(_ manager: TranscriptionManager, didCompleteWithTranscription transcription: String)
    func transcriptionManager(_ manager: TranscriptionManager, didFailWithError error: Error)
}

class TranscriptionManager {
    weak var delegate: TranscriptionManagerDelegate?
    private var progressTimer: Timer?

    /// Number of transcription tasks currently queued or running.
    /// Only read/written on the main thread.
    private(set) var pendingTaskCount: Int = 0

    // Serial queue — chunks are transcribed one at a time in arrival order,
    // preventing multiple simultaneous whisper processes from thrashing the CPU.
    private let transcriptionQueue = DispatchQueue(label: "com.microwhisper.transcription",
                                                   qos: .userInitiated)

    // Accumulated transcript for the current recording session.
    // Only read/written from transcriptionQueue.
    private var sessionTranscript: String = ""
    private var sessionStartDate: Date?

    /// Must be called from AppDelegate when a new recording session begins.
    /// Resets the in-memory session buffer so chunk transcripts append to a
    /// fresh session.
    func startSession() {
        transcriptionQueue.async { [weak self] in
            self?.sessionTranscript = ""
            self?.sessionStartDate = Date()
        }
    }

    /// Must be called after the final `transcribeAudio(at:)` call for a session.
    /// Because transcriptionQueue is serial, the save task runs after every
    /// in-flight chunk transcription completes.
    func endSession() {
        DispatchQueue.main.async { [weak self] in self?.pendingTaskCount += 1 }
        transcriptionQueue.async { [weak self] in
            self?.saveSessionTranscript()
            DispatchQueue.main.async { self?.pendingTaskCount -= 1 }
        }
    }

    /// Runs on transcriptionQueue.
    private func saveSessionTranscript() {
        let text = sessionTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            sessionTranscript = ""
            sessionStartDate = nil
        }
        guard !text.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH_mm"
        let timestamp = formatter.string(from: sessionStartDate ?? Date())
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let destURL = desktop.appendingPathComponent("transcript \(timestamp).txt")
        do {
            try text.write(to: destURL, atomically: true, encoding: .utf8)
            NSLog("Session transcript saved: %@", destURL.lastPathComponent)
        } catch {
            NSLog("Failed to save session transcript: %@", String(describing: error))
        }
    }

    func transcribeAudio(at fileURL: URL) {
        DispatchQueue.main.async { [weak self] in self?.pendingTaskCount += 1 }
        transcriptionQueue.async { [weak self] in
            defer { DispatchQueue.main.async { self?.pendingTaskCount -= 1 } }
            guard let self = self else { return }

            let modelPath = UserDefaults.standard.string(forKey: SettingsKey.whisperModelPath) ?? ""
            guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
                let message = modelPath.isEmpty
                    ? "No Whisper model selected. Open MicroWhisper → Settings to choose a .bin file."
                    : "Whisper model not found at \(modelPath). Update the path in MicroWhisper → Settings."
                let error = NSError(domain: "com.microwhisper.transcription",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: message])
                DispatchQueue.main.async {
                    self.delegate?.transcriptionManager(self, didFailWithError: error)
                }
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/whisper")

            var env = ProcessInfo.processInfo.environment
            env["PYTHONWARNINGS"] = "ignore"
            process.environment = env

            let outputFile = fileURL.deletingPathExtension().path
            process.arguments = self.createWhisperArguments(for: fileURL, outputFile: outputFile, modelPath: modelPath)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()

                // Timer must run on the main thread's run loop.
                DispatchQueue.main.async { self.startProgressTimer() }

                process.waitUntilExit()

                DispatchQueue.main.async {
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }

                try self.handleTranscriptionOutput(pipe: pipe, fileURL: fileURL)
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.transcriptionManager(self, didFailWithError: error)
                }
            }

            // Copy wav file to desktop for debugging
//            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
//            let copyURL = desktop.appendingPathComponent(fileURL.lastPathComponent)
//            try? FileManager.default.copyItem(at: fileURL, to: copyURL)

            // Clean up the audio file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func createWhisperArguments(for fileURL: URL, outputFile: String, modelPath: String) -> [String] {
        return [
            fileURL.path,
//            "--model", "base.en",
            "--model", modelPath,
//            "--output_format", "txt",
            "--output-txt",
            "--output-file", outputFile,
//            "--device", "cpu",
//            "--no_speech_threshold", "0.6",
//            "--fp16", "False",
            "--threads", String(ProcessInfo.processInfo.processorCount),
            "--beam-size", "1",
            "--best-of", "1",
//            "--condition_on_previous_text", "False",
            "--temperature", "0.0",
//            "--initial_prompt", "Transcript:",
            "--prompt", "Transcript:",
//            "--task", "transcribe",
            "--no-prints"
//            "--language", "en"
        ]
    }

    private func startProgressTimer() {
        var dots = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            dots = (dots + 1) % 4
            let progressDots = String(repeating: ".", count: dots)
            self.delegate?.transcriptionManager(self, didUpdateProgress: "Processing transcription\(progressDots)")
        }
    }

    private func handleTranscriptionOutput(pipe: Pipe, fileURL: URL) throws {
        // Prefer the .txt file — it contains the clean transcript.
        // The pipe captures stderr/stdout which may include progress noise even
        // with --no-prints, so we only fall back to it if the file is absent.
        let outputFilePath = fileURL.deletingPathExtension().path + ".txt"
        let rawText: String?

        if let fileText = try? String(contentsOfFile: outputFilePath, encoding: .utf8),
           !fileText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawText = fileText
            try? FileManager.default.removeItem(atPath: outputFilePath)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let pipeText = String(data: data, encoding: .utf8) ?? ""
            rawText = pipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pipeText
        }

        if let raw = rawText {
            let cleaned = cleanTranscription(raw)
            if !cleaned.isEmpty {
                // Append to the session buffer. We're already on transcriptionQueue
                // (handleTranscriptionOutput is called from the queue via
                // transcribeAudio), so the append is serialized with other chunks
                // and with start/endSession.
                if sessionTranscript.isEmpty {
                    sessionTranscript = cleaned
                } else {
                    sessionTranscript += "\n" + cleaned
                }
                DispatchQueue.main.async {
                    self.delegate?.transcriptionManager(self, didCompleteWithTranscription: cleaned)
                }
            }
        }
    }

    /// Strips whisper.cpp metadata lines and timestamp prefixes, returning plain speech text.
    private func cleanTranscription(_ raw: String) -> String {
        // Matches: [HH:MM:SS.mmm --> HH:MM:SS.mmm]  (with trailing whitespace)
        let tsPattern = #"^\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]\s*"#
        let tsRegex = try? NSRegularExpression(pattern: tsPattern)

        var segments: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Drop whisper status lines and [BLANK_AUDIO] markers
            if trimmed.hasPrefix("output_") || trimmed.hasPrefix("[BLANK_AUDIO]") { continue }

            // Strip timestamp prefix and keep the speech text
            let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = tsRegex?.firstMatch(in: trimmed, range: nsRange),
               let range = Range(match.range, in: trimmed) {
                let text = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { segments.append(text) }
            } else {
                segments.append(trimmed)
            }
        }
        return segments.joined(separator: " ")
    }

}
