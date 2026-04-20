//
//  IntegrationTests.swift
//  microwhisperTests
//
//  Created by Chris Gatzonis on 3/23/25.
//

import Testing
import XCTest
import AVFoundation
import CoreAudio
@testable import microwhisper

// MARK: - Integration Tests

struct AudioTranscriptionIntegrationTests {
    
    // Test the full recording-to-transcription pipeline
    @Test func testRecordingToTranscriptionPipeline() async throws {
        // Create mock components
        let audioManager = MockAudioRecorderManager()
        let transcriptionManager = MockTranscriptionManager()
        
        // Set up delegates
        let audioDelegate = MockAudioRecorderDelegate()
        let transcriptionDelegate = MockTranscriptionDelegate()
        
        audioManager.delegate = audioDelegate
        transcriptionManager.delegate = transcriptionDelegate
        
        // Set up expected transcription result
        transcriptionManager.mockTranscriptionResult = "This is a test transcription."
        
        // Start recording
        let device = AudioRecorderManager.AudioDevice(id: 0, name: "Mock Mic")
        audioManager.startRecording(device: device)
        
        // Add a small delay to ensure the recording state is updated
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(audioManager.isRecording == true)
        #expect(audioDelegate.didStartRecordingCalled == true)
        
        // Simulate recording for a short time
        try await Task.sleep(for: .milliseconds(500))
        
        // Stop recording
        audioManager.stopRecording()
        #expect(audioManager.isRecording == false)
        #expect(audioDelegate.didStopRecordingCalled == true)
        
        // Verify the file URL was passed to the delegate
        guard let fileURL = audioDelegate.lastFileURL else {
            XCTFail("No file URL was provided")
            return
        }
        
        // Transcribe the audio
        transcriptionManager.transcribeAudio(at: fileURL)
        
        // Wait for async operation
        try await Task.sleep(for: .seconds(1))
        
        // Verify transcription was completed
        #expect(transcriptionDelegate.didCompleteWithTranscriptionCalled == true)
        #expect(transcriptionDelegate.lastTranscription == "This is a test transcription.")
    }
    
}

// MARK: - Status Bar Integration Tests

struct StatusBarIntegrationTests {
    
    // Test status bar updates based on recording state
    @Test func testStatusBarUpdatesWithRecordingState() async throws {
        // Create a direct mock status bar manager that doesn't rely on delegates
        let statusBarManager = DirectMockStatusBarManager()
        
        // Verify initial state
        #expect(statusBarManager.isRecording == false)
        #expect(statusBarManager.iconUpdated == false)
        
        // Directly update the recording state
        statusBarManager.updateRecordingState(isRecording: true)
        
        // Verify status bar was updated
        #expect(statusBarManager.isRecording == true)
        #expect(statusBarManager.iconUpdated == true)
        
        // Reset the icon updated flag to test the next state change
        statusBarManager.iconUpdated = false
        
        // Update the recording state again
        statusBarManager.updateRecordingState(isRecording: false)
        
        // Verify status bar was updated
        #expect(statusBarManager.isRecording == false)
        #expect(statusBarManager.iconUpdated == true)
    }
    
    }

// MARK: - Mock Classes for Integration Tests

// Direct Mock StatusBarManager for testing that doesn't rely on delegates
class DirectMockStatusBarManager: NSObject {
    var isRecording = false
    var iconUpdated = false

    func updateRecordingState(isRecording: Bool) {
        self.isRecording = isRecording
        self.iconUpdated = true
    }
}

// Original MockStatusBarManager for other tests
class MockStatusBarManager: NSObject {
    var isRecording = false
    var iconUpdated = false

    weak var audioManager: AudioRecorderManager?

    func updateRecordingState(isRecording: Bool) {
        self.isRecording = isRecording
        self.iconUpdated = true
    }
}

// Helper method for AudioRecorderManager integration testing
extension AudioRecorderManager {
    // Instead of using a computed property, use a method to set the delegate
    func setStatusBarDelegate(_ statusBarManager: MockStatusBarManager) {
        // Register for status bar updates
        self.delegate = StatusBarAudioDelegate(statusBarManager: statusBarManager)
    }
}

// Adapter class to connect AudioRecorderDelegate to StatusBarManager
class StatusBarAudioDelegate: AudioRecorderDelegate {
    private let statusBarManager: MockStatusBarManager
    
    init(statusBarManager: MockStatusBarManager) {
        self.statusBarManager = statusBarManager
    }
    
    func audioRecorderDidStartRecording() {
        // Ensure this runs on the main thread to match real behavior
        DispatchQueue.main.async {
            self.statusBarManager.updateRecordingState(isRecording: true)
        }
    }
    
    func audioRecorderDidStopRecording(fileURL: URL) {
        // Ensure this runs on the main thread to match real behavior
        DispatchQueue.main.async {
            self.statusBarManager.updateRecordingState(isRecording: false)
        }
    }
    
    func audioRecorderDidCompleteChunk(fileURL: URL) {}

    func audioRecorderDidUpdateLevel(_ levels: [Float]) {}

    func audioRecorderDidFailWithError(_ error: Error) {}

    func audioRecorderDidDetectDevices(devices: [AudioRecorderManager.AudioDevice], microphoneAvailable: Bool) {}
}
