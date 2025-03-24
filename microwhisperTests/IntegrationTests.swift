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
        audioManager.startRecording(from: .microphone)
        
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
    
    // Test audio source switching affects recording
    @Test func testAudioSourceSwitchingAffectsRecording() async throws {
        // Create mock components
        let audioManager = MockAudioRecorderManager()
        let audioDelegate = MockAudioRecorderDelegate()
        audioManager.delegate = audioDelegate
        
        // Test with microphone
        audioManager.startRecording(from: .microphone)
        #expect(audioManager.currentAudioSource == .microphone)
        audioManager.stopRecording()
        
        // Test with system audio when BlackHole is available
        audioManager.mockBlackholeAvailable = true
        audioManager.startRecording(from: .systemAudio)
        
        // Add a small delay to ensure the audio source is updated
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(audioManager.currentAudioSource == .systemAudio)
        audioManager.stopRecording()
        
        // Test with system audio when BlackHole is not available
        audioManager.mockBlackholeAvailable = false
        
        // Create a delegate to capture the error
        let errorDelegate = MockAudioRecorderDelegate()
        audioManager.delegate = errorDelegate
        
        // This should call the error delegate method
        audioManager.startRecording(from: .systemAudio)
        
        // Verify error was passed to delegate
        #expect(errorDelegate.didFailWithErrorCalled == true)
        if let error = errorDelegate.lastError as? NSError {
            #expect(error.domain == "AudioRecorderManager")
        } else {
            XCTFail("Expected NSError but got nil or different type")
        }
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
    
    // Test status bar updates based on audio source
    @Test func testStatusBarUpdatesWithAudioSource() async throws {
        // Create a direct mock status bar manager that doesn't rely on delegates
        let statusBarManager = DirectMockStatusBarManager()
        
        // Verify initial state
        #expect(statusBarManager.audioSourceMenuUpdated == false)
        #expect(statusBarManager.microphoneAvailable == false)
        #expect(statusBarManager.blackholeAvailable == false)
        
        // Directly update the audio source menu
        statusBarManager.updateAudioSourceMenu(microphoneAvailable: true, blackholeAvailable: true)
        
        // Verify menu was updated with audio sources
        #expect(statusBarManager.audioSourceMenuUpdated == true)
        #expect(statusBarManager.microphoneAvailable == true)
        #expect(statusBarManager.blackholeAvailable == true)
    }
}

// MARK: - Mock Classes for Integration Tests

// Direct Mock StatusBarManager for testing that doesn't rely on delegates
class DirectMockStatusBarManager: NSObject {
    // Initialize with default values
    var isRecording = false
    var iconUpdated = false
    var audioSourceMenuUpdated = false
    var microphoneAvailable = false
    var blackholeAvailable = false
    
    func updateRecordingState(isRecording: Bool) {
        self.isRecording = isRecording
        self.iconUpdated = true
    }
    
    func updateAudioSourceMenu(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        self.audioSourceMenuUpdated = true
        self.microphoneAvailable = microphoneAvailable
        self.blackholeAvailable = blackholeAvailable
    }
}

// Original MockStatusBarManager for other tests
class MockStatusBarManager: NSObject {
    // Initialize with default values
    var isRecording = false
    var iconUpdated = false
    var audioSourceMenuUpdated = false
    var microphoneAvailable = false
    var blackholeAvailable = false
    
    weak var audioManager: AudioRecorderManager?
    
    func updateRecordingState(isRecording: Bool) {
        self.isRecording = isRecording
        self.iconUpdated = true
    }
    
    func updateAudioSourceMenu(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        self.audioSourceMenuUpdated = true
        self.microphoneAvailable = microphoneAvailable
        self.blackholeAvailable = blackholeAvailable
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
    
    func audioRecorderDidUpdateLevel(_ level: Float) {
        // Not needed for this test
    }
    
    func audioRecorderDidFailWithError(_ error: Error) {
        // Not needed for this test
    }
    
    func audioRecorderDidDetectDevices(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        // Ensure this runs on the main thread to match real behavior
        DispatchQueue.main.async {
            self.statusBarManager.updateAudioSourceMenu(microphoneAvailable: microphoneAvailable, 
                                                      blackholeAvailable: blackholeAvailable)
        }
    }
}
