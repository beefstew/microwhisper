//
//  microwhisperTests.swift
//  microwhisperTests
//
//  Created by Chris Gatzonis on 2/10/25.
//

import Testing
import XCTest
import AVFoundation
import CoreAudio
@testable import microwhisper

// MARK: - AudioRecorderManager Tests

struct AudioRecorderManagerTests {
    
    // MARK: - Device Detection Tests

    @Test func testDeviceDetection() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate

        manager.detectAudioDevices()

        // Wait for async delegate call
        try await Task.sleep(for: .milliseconds(100))

        #expect(delegate.microphoneAvailable == true)
        #expect(delegate.didDetectDevicesCalled == true)
    }
    
    // MARK: - Recording State Tests
    
    @Test func testRecordingStateManagement() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate

        let device = AudioRecorderManager.AudioDevice(id: 0, name: "Mock Mic")

        // Test starting recording
        manager.startRecording(device: device)
        #expect(manager.isRecording == true)
        #expect(delegate.didStartRecordingCalled == true)

        // Test stopping recording
        manager.stopRecording()
        #expect(manager.isRecording == false)
        #expect(delegate.didStopRecordingCalled == true)
    }

    @Test func testAudioLevelUpdates() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate

        let device = AudioRecorderManager.AudioDevice(id: 0, name: "Mock Mic")
        manager.startRecording(device: device)

        // Simulate meter updates
        manager.simulateMeterUpdate(level: 0.5)

        #expect(delegate.lastAudioLevel == 0.5)
    }
}

// MARK: - TranscriptionManager Tests

struct TranscriptionManagerTests {
    
    @Test func testTranscriptionSuccess() async throws {
        let manager = MockTranscriptionManager()
        let delegate = MockTranscriptionDelegate()
        manager.delegate = delegate
        
        // Set up mock response
        manager.mockTranscriptionResult = "This is a test transcription."
        
        // Create a temporary file for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio.m4a")
        try Data().write(to: tempURL)
        
        // Transcribe the audio
        manager.transcribeAudio(at: tempURL)
        
        // Wait for async operation
        try await Task.sleep(for: .seconds(1))
        
        #expect(delegate.lastTranscription == "This is a test transcription.")
        #expect(delegate.didCompleteWithTranscriptionCalled == true)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test func testTranscriptionError() async throws {
        let manager = MockTranscriptionManager()
        let delegate = MockTranscriptionDelegate()
        manager.delegate = delegate
        
        // Set up mock error
        let mockError = NSError(domain: "TranscriptionManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Mock transcription error"])
        manager.mockError = mockError
        
        // Create a temporary file for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio.m4a")
        try Data().write(to: tempURL)
        
        // Transcribe the audio
        manager.transcribeAudio(at: tempURL)
        
        // Wait for async operation
        try await Task.sleep(for: .seconds(1))
        
        #expect(delegate.didFailWithErrorCalled == true)
        if let error = delegate.lastError as? NSError {
            #expect(error.domain == "TranscriptionManager")
        } else {
            XCTFail("Expected NSError but got nil or different type")
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test func testProgressUpdates() async throws {
        let manager = MockTranscriptionManager()
        let delegate = MockTranscriptionDelegate()
        manager.delegate = delegate
        
        // Create a temporary file for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio.m4a")
        try Data().write(to: tempURL)
        
        // Transcribe the audio
        manager.transcribeAudio(at: tempURL)
        
        // Simulate progress update
        manager.simulateProgressUpdate(progress: "Processing transcription...")
        
        // Wait for the delegate method to be called
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(delegate.lastProgress == "Processing transcription...")
        #expect(delegate.didUpdateProgressCalled == true)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
}

// MARK: - Mock Classes

// Mock AudioRecorderManager for testing
class MockAudioRecorderManager: AudioRecorderManager, @unchecked Sendable {
    private var mockIsRecording = false

    override func detectAudioDevices() {
        DispatchQueue.main.async {
            self.delegate?.audioRecorderDidDetectDevices(
                devices: self.inputDevices,
                microphoneAvailable: true)
        }
    }

    override func startRecording(device: AudioDevice) {
        mockIsRecording = true
        delegate?.audioRecorderDidStartRecording()
    }

    override func stopRecording() {
        mockIsRecording = false
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mock_recording.m4a")
        delegate?.audioRecorderDidStopRecording(fileURL: tempURL)
    }

    func simulateMeterUpdate(level: Float) {
        delegate?.audioRecorderDidUpdateLevel([level])
    }

    override var isRecording: Bool {
        return mockIsRecording
    }
}

// Mock AudioRecorderDelegate for testing
class MockAudioRecorderDelegate: AudioRecorderDelegate {
    var didStartRecordingCalled = false
    var didStopRecordingCalled = false
    var didUpdateLevelCalled = false
    var didFailWithErrorCalled = false
    var didDetectDevicesCalled = false

    var lastAudioLevel: Float = 0.0
    var lastError: Error?
    var lastFileURL: URL?
    var microphoneAvailable = false

    func audioRecorderDidStartRecording() {
        didStartRecordingCalled = true
    }

    func audioRecorderDidStopRecording(fileURL: URL) {
        didStopRecordingCalled = true
        lastFileURL = fileURL
    }

    func audioRecorderDidCompleteChunk(fileURL: URL) {}

    func audioRecorderDidUpdateLevel(_ levels: [Float]) {
        didUpdateLevelCalled = true
        lastAudioLevel = levels.first ?? 0.0
    }

    func audioRecorderDidFailWithError(_ error: Error) {
        didFailWithErrorCalled = true
        lastError = error
    }

    func audioRecorderDidDetectDevices(devices: [AudioRecorderManager.AudioDevice], microphoneAvailable: Bool) {
        didDetectDevicesCalled = true
        self.microphoneAvailable = microphoneAvailable
    }
}

// Mock TranscriptionManager for testing
class MockTranscriptionManager: TranscriptionManager {
    var mockTranscriptionResult: String?
    var mockError: Error?
    
    override func transcribeAudio(at fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Simulate processing delay
            Thread.sleep(forTimeInterval: 0.5)
            
            DispatchQueue.main.async {
                if let error = self.mockError {
                    self.delegate?.transcriptionManager(self, didFailWithError: error)
                } else if let result = self.mockTranscriptionResult {
                    self.delegate?.transcriptionManager(self, didCompleteWithTranscription: result)
                } else {
                    self.delegate?.transcriptionManager(self, didCompleteWithTranscription: "Default mock transcription")
                }
            }
        }
    }
    
    func simulateProgressUpdate(progress: String) {
        DispatchQueue.main.async {
            self.delegate?.transcriptionManager(self, didUpdateProgress: progress)
        }
    }
}

// Mock TranscriptionManagerDelegate for testing
class MockTranscriptionDelegate: TranscriptionManagerDelegate {
    var didUpdateProgressCalled = false
    var didCompleteWithTranscriptionCalled = false
    var didFailWithErrorCalled = false
    
    var lastProgress: String = ""
    var lastTranscription: String = ""
    var lastError: Error?
    
    func transcriptionManager(_ manager: TranscriptionManager, didUpdateProgress progress: String) {
        didUpdateProgressCalled = true
        lastProgress = progress
    }
    
    func transcriptionManager(_ manager: TranscriptionManager, didCompleteWithTranscription transcription: String) {
        didCompleteWithTranscriptionCalled = true
        lastTranscription = transcription
    }
    
    func transcriptionManager(_ manager: TranscriptionManager, didFailWithError error: Error) {
        didFailWithErrorCalled = true
        lastError = error
    }
}
