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
    
    // MARK: - Audio Source Tests
    
    @Test func testAudioSourceSelection() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate
        
        // Test microphone source selection
        manager.startRecording(from: .microphone)
        #expect(manager.currentAudioSource == .microphone)
        
        // Test system audio source selection
        manager.mockBlackholeAvailable = true
        manager.startRecording(from: .systemAudio)
        #expect(manager.currentAudioSource == .systemAudio)
    }
    
    @Test func testBlackholeUnavailableError() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate
        
        // Set BlackHole as unavailable
        manager.mockBlackholeAvailable = false
        
        // Attempt to record from system audio should call the error delegate method
        manager.startRecording(from: .systemAudio)
        
        // Error should be passed to the delegate
        #expect(delegate.didFailWithErrorCalled == true)
        if let error = delegate.lastError as? NSError {
            #expect(error.domain == "AudioRecorderManager")
            #expect(error.code == 1001)
        } else {
            XCTFail("Expected NSError but got nil or different type")
        }
    }
    
    @Test func testDeviceDetection() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate
        
        // Test with BlackHole unavailable
        manager.mockBlackholeAvailable = false
        manager.detectAudioDevices()
        
        // Wait for async delegate call
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(delegate.microphoneAvailable == true)
        #expect(delegate.blackholeAvailable == false)
        
        // Test with BlackHole available
        manager.mockBlackholeAvailable = true
        manager.detectAudioDevices()
        
        // Wait for async delegate call
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(delegate.microphoneAvailable == true)
        #expect(delegate.blackholeAvailable == true)
    }
    
    // MARK: - Recording State Tests
    
    @Test func testRecordingStateManagement() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate
        
        // Test starting recording
        manager.startRecording(from: .microphone)
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
        
        // Start recording to trigger meter updates
        manager.startRecording(from: .microphone)
        
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
    // Use a thread-safe property for Swift 6 Sendable conformance
    private let mockBlackholeAvailableLock = NSLock()
    private var _mockBlackholeAvailable: Bool = false
    var mockBlackholeAvailable: Bool {
        get {
            mockBlackholeAvailableLock.lock()
            defer { mockBlackholeAvailableLock.unlock() }
            return _mockBlackholeAvailable
        }
        set {
            mockBlackholeAvailableLock.lock()
            _mockBlackholeAvailable = newValue
            mockBlackholeAvailableLock.unlock()
        }
    }
    private var mockMeterTimer: Timer?
    
    // Mock properties that mirror the private(set) properties in the parent class
    private var mockIsRecording = false
    private var mockCurrentAudioSource: AudioSource = .microphone
    
    override func detectAudioDevices() {
        // Don't directly access the property, use the delegate instead
        updateDeviceAvailability(microphoneAvailable: true, blackholeAvailable: mockBlackholeAvailable)
    }
    
    override func startRecording(from source: AudioSource = .microphone) {
        if source == .systemAudio && !mockBlackholeAvailable {
            let error = NSError(domain: "AudioRecorderManager", 
                                code: 1001, 
                                userInfo: [NSLocalizedDescriptionKey: "BlackHole audio device not available"])
            delegate?.audioRecorderDidFailWithError(error)
            return
        }
        
        // Set our mock properties
        mockIsRecording = true
        mockCurrentAudioSource = source
        
        // Notify delegate of state changes
        delegate?.audioRecorderDidStartRecording()
    }
    
    override func stopRecording() {
        // Set our mock property
        mockIsRecording = false
        
        mockMeterTimer?.invalidate()
        mockMeterTimer = nil
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mock_recording.m4a")
        delegate?.audioRecorderDidStopRecording(fileURL: tempURL)
    }
    
    func simulateMeterUpdate(level: Float) {
        delegate?.audioRecorderDidUpdateLevel(level)
    }
    
    func updateDeviceAvailability(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        DispatchQueue.main.async {
            self.delegate?.audioRecorderDidDetectDevices(
                microphoneAvailable: microphoneAvailable,
                blackholeAvailable: blackholeAvailable
            )
        }
    }
    
    // Override the parent class's properties to return our mock values
    override var isRecording: Bool {
        return mockIsRecording
    }
    
    override var currentAudioSource: AudioSource {
        return mockCurrentAudioSource
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
    var blackholeAvailable = false
    
    func audioRecorderDidStartRecording() {
        didStartRecordingCalled = true
    }
    
    func audioRecorderDidStopRecording(fileURL: URL) {
        didStopRecordingCalled = true
        lastFileURL = fileURL
    }
    
    func audioRecorderDidUpdateLevel(_ level: Float) {
        didUpdateLevelCalled = true
        lastAudioLevel = level
    }
    
    func audioRecorderDidFailWithError(_ error: Error) {
        didFailWithErrorCalled = true
        lastError = error
    }
    
    func audioRecorderDidDetectDevices(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        didDetectDevicesCalled = true
        self.microphoneAvailable = microphoneAvailable
        self.blackholeAvailable = blackholeAvailable
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
