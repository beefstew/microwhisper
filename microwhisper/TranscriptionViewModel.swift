//
//  TranscriptionViewModel.swift
//  microwhisper
//
//  Created by Chris Gatzonis on 2/10/25.
//

import SwiftUI
import Combine

class TranscriptionViewModel: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var audioLevels: [Float] = []
    @Published var showTranscript: Bool = false
    
    @Published var isMicrophoneAvailable: Bool = true
    @Published var availableInputDevices: [AudioRecorderManager.AudioDevice] = []
    @Published var selectedDevice: AudioRecorderManager.AudioDevice? = nil {
        didSet {
            appDelegate?.selectedDeviceChanged(to: selectedDevice)
        }
    }
    
    weak var appDelegate: AppDelegate?
    
    init() {}
    
    func toggleRecording() {
        appDelegate?.toggleRecording()
    }
    
    func appendTranscript(_ text: String) {
        if transcript.isEmpty {
            transcript = text
        } else {
            transcript += "\n\(text)"
        }
        showTranscript = !transcript.isEmpty
    }
    
    func clearTranscriptIfNeeded() {
        // Clear transcript when starting a new recording session
        transcript = ""
        showTranscript = false
    }
    
    func copyTranscriptToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }
}
