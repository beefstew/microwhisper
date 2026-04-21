import Cocoa
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var viewModel = TranscriptionViewModel()
    private let audioManager = AudioRecorderManager()
    private let transcriptionManager = TranscriptionManager()

    @Published private(set) var isRecording = false
    private(set) var isMicrophoneAvailable = true

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard audioManager.isRecording || transcriptionManager.pendingTaskCount > 0 else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Transcription still processing. Quit anyway?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        setupDelegates()

        // Detect audio devices
        audioManager.detectAudioDevices()
        
        // Start key tap handler
        let keyTapHandler = KeyTapHandler()
        keyTapHandler.startListening(with: self)
    }
    
    private func setupDelegates() {
        viewModel.appDelegate = self
        audioManager.delegate = self
        transcriptionManager.delegate = self
    }
    
}

// MARK: - AudioRecorderDelegate
extension AppDelegate: AudioRecorderDelegate {    
    func audioRecorderDidDetectDevices(devices: [AudioRecorderManager.AudioDevice], microphoneAvailable: Bool) {
        isMicrophoneAvailable = microphoneAvailable

        DispatchQueue.main.async {
            self.viewModel.availableInputDevices = devices
            self.viewModel.isMicrophoneAvailable = microphoneAvailable

            // Auto-select the system default input device on first run, or recover if the
            // previously selected device has disappeared (e.g. unplugged). Only write
            // when the value would actually change, so the didSet side-effect chain
            // doesn't fire redundantly.
            if self.viewModel.selectedDevice == nil || !devices.contains(self.viewModel.selectedDevice!) {
                let newSelection = devices.first(where: { $0.id == self.audioManager.defaultInputDeviceID }) ?? devices.first
                if self.viewModel.selectedDevice != newSelection {
                    self.viewModel.selectedDevice = newSelection
                }
            }
        }
    }
    func audioRecorderDidStartRecording() {
        DispatchQueue.main.async {
            self.isRecording = true
            self.viewModel.clearTranscriptIfNeeded()
            self.viewModel.isRecording = true
        }
        transcriptionManager.startSession()
    }

    func audioRecorderDidStopRecording(fileURL: URL) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.viewModel.isRecording = false
        }
        // Transcribe the final chunk, then ask TranscriptionManager to save the
        // full session transcript. Because transcriptionQueue is serial, the
        // save runs strictly after the final chunk's transcription completes.
        transcriptionManager.transcribeAudio(at: fileURL)
        transcriptionManager.endSession()
    }

    func audioRecorderDidCompleteChunk(fileURL: URL) {
        print("Chunk ready for transcription: \(fileURL.lastPathComponent)")
        transcriptionManager.transcribeAudio(at: fileURL)
    }
    
    func audioRecorderDidUpdateLevel(_ levels: [Float]) {
        DispatchQueue.main.async {
            self.viewModel.audioLevels = levels
        }
    }
    
    func audioRecorderDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.viewModel.appendTranscript("\nFailed to start recording: \(error)")
        }
    }
}

// MARK: - TranscriptionManagerDelegate
extension AppDelegate: TranscriptionManagerDelegate {
    func transcriptionManager(_ manager: TranscriptionManager, didUpdateProgress progress: String) {
        // Progress ticks are not shown in the transcript.
    }
    
    func transcriptionManager(_ manager: TranscriptionManager, didCompleteWithTranscription transcription: String) {
        // Defensive main-thread hop: TranscriptionManager today dispatches before
        // calling the delegate, but we don't want the view model to depend on that.
        DispatchQueue.main.async {
            self.viewModel.appendTranscript("\n\(transcription)")
        }
    }

    func transcriptionManager(_ manager: TranscriptionManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.viewModel.appendTranscript("\nError running transcription: \(error)")
        }
    }
}

// MARK: - Public Interface
extension AppDelegate {
    func toggleRecording() {
        if audioManager.isRecording {
            audioManager.stopRecording()
        } else if let device = viewModel.selectedDevice {
            audioManager.startRecording(device: device)
        }
    }

    func selectedDeviceChanged(to device: AudioRecorderManager.AudioDevice?) {
        guard let device else {
            audioManager.stopMonitoring()
            return
        }
        audioManager.startMonitoring(deviceID: device.id)
    }
}
