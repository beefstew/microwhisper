import Foundation

protocol TranscriptionManagerDelegate: AnyObject {
    func transcriptionManager(_ manager: TranscriptionManager, didUpdateProgress progress: String)
    func transcriptionManager(_ manager: TranscriptionManager, didCompleteWithTranscription transcription: String)
    func transcriptionManager(_ manager: TranscriptionManager, didFailWithError error: Error)
}

class TranscriptionManager {
    weak var delegate: TranscriptionManagerDelegate?
    private var progressTimer: Timer?

    // Serial queue — chunks are transcribed one at a time in arrival order,
    // preventing multiple simultaneous whisper processes from thrashing the CPU.
    private let transcriptionQueue = DispatchQueue(label: "com.microwhisper.transcription",
                                                   qos: .userInitiated)

    func transcribeAudio(at fileURL: URL) {
        transcriptionQueue.async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/whisper")

            var env = ProcessInfo.processInfo.environment
            env["PYTHONWARNINGS"] = "ignore"
            process.environment = env

            let outputFile = fileURL.deletingPathExtension().path
            process.arguments = self.createWhisperArguments(for: fileURL, outputFile: outputFile)

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

    private func createWhisperArguments(for fileURL: URL, outputFile: String) -> [String] {
        return [
            fileURL.path,
//            "--model", "base.en",
            "--model", "/Users/chorn/Applications/whisper.cpp/models/ggml-large-v2.bin",
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
                saveTranscriptToDesktop(cleaned)
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

    private func saveTranscriptToDesktop(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH_mm"
        let timestamp = formatter.string(from: Date())
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let destURL = desktop.appendingPathComponent("transcript \(timestamp).txt")
        try? text.write(to: destURL, atomically: true, encoding: .utf8)
        print("Transcript saved to desktop: \(destURL.lastPathComponent)")
    }
}
