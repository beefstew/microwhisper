import Cocoa
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel = TranscriptionViewModel()
    private let audioManager = AudioRecorderManager()
    private let statusBarManager = StatusBarManager()
    private let transcriptionManager = TranscriptionManager()
    
    // Track available audio sources
    private(set) var isMicrophoneAvailable = true
    private(set) var isBlackholeAvailable = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDelegates()
        
        // Initialize UI state
        updateSelectedAudioSource(.microphone)
        
        // Detect audio devices
        audioManager.detectAudioDevices()
        
        // Start key tap handler
        let keyTapHandler = KeyTapHandler()
        keyTapHandler.startListening(with: self)
    }
    
    private func setupDelegates() {
        viewModel.appDelegate = self
        audioManager.delegate = self
        statusBarManager.delegate = self
        transcriptionManager.delegate = self
    }
    
    // Method to handle audio source selection
    func updateSelectedAudioSource(_ source: AudioRecorderManager.AudioSource) {
        // Ensure the AudioRecorderManager knows about the change
        audioManager.detectAudioDevices()
        
        // Update the status bar menu to reflect the change
        switch source {
        case .microphone:
            statusBarManager.updateSourceMenuState(selectedSource: "Microphone")
            print("UI updated for microphone source selection")
        case .systemAudio:
            statusBarManager.updateSourceMenuState(selectedSource: "System Audio (BlackHole)")
            print("UI updated for system audio source selection")
        default:
            break
        }
        
        // Force the view model to update its UI
        DispatchQueue.main.async {
            // This will trigger SwiftUI to refresh the view
            self.viewModel.objectWillChange.send()
        }
    }
}

// MARK: - StatusBarManagerDelegate
extension AppDelegate: StatusBarManagerDelegate {
    func statusBarManagerDidRequestStartRecording() {
        startRecording(from: viewModel.selectedAudioSource)
    }
    
    func statusBarManagerDidRequestStopRecording() {
        audioManager.stopRecording()
    }
    
    func statusBarManagerDidRequestStartRecordingFromMicrophone() {
        viewModel.selectedAudioSource = .microphone
        startRecording(from: .microphone)
    }
    
    func statusBarManagerDidRequestStartRecordingFromSystemAudio() {
        viewModel.selectedAudioSource = .systemAudio
        startRecording(from: .systemAudio)
    }
    
    func statusBarManagerDidSelectAudioSource(_ source: AudioRecorderManager.AudioSource) {
        viewModel.selectedAudioSource = source
    }
    
    private func startRecording(from source: AudioRecorderManager.AudioSource) {
        // Check if selected source is available
        if source == .systemAudio && !isBlackholeAvailable {
            DispatchQueue.main.async {
                self.viewModel.appendTranscript("Error: BlackHole audio device not available. Please install BlackHole and restart the app.")
            }
            return
        }
        
        audioManager.startRecording(from: source)
    }
}

// MARK: - AudioRecorderDelegate
extension AppDelegate: AudioRecorderDelegate {    
    func audioRecorderDidDetectDevices(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        isMicrophoneAvailable = microphoneAvailable
        isBlackholeAvailable = blackholeAvailable
        
        // Update the view model
        DispatchQueue.main.async {
            self.viewModel.isBlackholeAvailable = blackholeAvailable
            self.viewModel.isMicrophoneAvailable = microphoneAvailable
            
            // If the currently selected source is not available, switch to an available one
            if self.viewModel.selectedAudioSource == .systemAudio && !blackholeAvailable {
                self.viewModel.selectedAudioSource = .microphone
            }
            
            // Update status bar menu
            self.statusBarManager.updateAudioSourceAvailability(
                microphoneAvailable: microphoneAvailable,
                blackholeAvailable: blackholeAvailable
            )
        }
    }
    func audioRecorderDidStartRecording() {
        statusBarManager.updateRecordingState(isRecording: true)
        DispatchQueue.main.async {
            self.viewModel.clearTranscriptIfNeeded()
            self.viewModel.isRecording = true
        }
    }

    func audioRecorderDidStopRecording(fileURL: URL) {
        statusBarManager.updateRecordingState(isRecording: false)
        DispatchQueue.main.async {
            self.viewModel.isRecording = false
        }
        transcriptionManager.transcribeAudio(at: fileURL)
    }

    func audioRecorderDidCompleteChunk(fileURL: URL) {
        print("Chunk ready for transcription: \(fileURL.lastPathComponent)")
        transcriptionManager.transcribeAudio(at: fileURL)
    }
    
    func audioRecorderDidUpdateLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.viewModel.audioLevel = level
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
        viewModel.appendTranscript("\n\(transcription)")
    }
    
    func transcriptionManager(_ manager: TranscriptionManager, didFailWithError error: Error) {
        viewModel.appendTranscript("\nError running transcription: \(error)")
    }
}

// MARK: - Public Interface
extension AppDelegate {
    func toggleRecording() {
        if audioManager.isRecording {
            audioManager.stopRecording()
        } else {
            startRecording(from: viewModel.selectedAudioSource)
        }
    }
    
    func setAudioSource(_ source: AudioRecorderManager.AudioSource) {
        viewModel.selectedAudioSource = source
    }
}
