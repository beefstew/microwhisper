//
//  PerformanceTests.swift
//  microwhisperTests
//
//  Created by Chris Gatzonis on 3/23/25.
//

import Testing
import XCTest
import AVFoundation
@testable import microwhisper

// MARK: - Performance Tests

struct AudioPerformanceTests {
    
    // Test audio recording performance
    @Test func testAudioRecordingPerformance() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockAudioRecorderDelegate()
        manager.delegate = delegate
        
        // Measure the performance of starting recording
        let startTime = DispatchTime.now()
        
        manager.startRecording(device: AudioRecorderManager.AudioDevice(id: 0, name: "Mock Mic"))
        // Simulate recording for a short time
        try await Task.sleep(for: .milliseconds(500))
        
        // Stop recording
        manager.stopRecording()
        
        let endTime = DispatchTime.now()
        let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000 // Convert to seconds
        
        // Verify recording operations complete within reasonable time
        // Typically this should be under 1 second for a responsive app
        #expect(timeInterval < 1.0)
    }
    
    // Test audio level processing performance
    @Test func testAudioLevelProcessingPerformance() async throws {
        let manager = MockAudioRecorderManager()
        let delegate = MockPerformanceAudioDelegate()
        manager.delegate = delegate
        
        manager.startRecording(device: AudioRecorderManager.AudioDevice(id: 0, name: "Mock Mic"))

        // Measure time to process 100 audio level updates
        let startTime = DispatchTime.now()
        
        for i in 0..<100 {
            let level = Float(i) / 100.0
            manager.simulateMeterUpdate(level: level)
        }
        
        let endTime = DispatchTime.now()
        let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000 // Convert to seconds
        
        // Verify level processing is fast enough for real-time visualization
        // Should process 100 updates in under 0.1 seconds for smooth visualization
        #expect(timeInterval < 0.1)
        #expect(delegate.updateCount == 100)
        
        manager.stopRecording()
    }
}

struct TranscriptionPerformanceTests {
    
    // Test transcription performance with different audio lengths
    @Test func testTranscriptionPerformance() async throws {
        let manager = PerformanceTranscriptionManager()
        let delegate = MockTranscriptionDelegate()
        manager.delegate = delegate
        
        // Create a temporary file for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("perf_test_audio.m4a")
        try Data().write(to: tempURL)
        
        // Set up simulated processing times for different audio lengths
        let audioLengths = [5, 15, 30] // seconds
        var processingTimes: [Double] = []
        
        for length in audioLengths {
            // Set simulated processing time based on audio length
            manager.simulatedProcessingTime = Double(length) * 0.2 // 20% of audio length
            
            let startTime = DispatchTime.now()
            
            manager.transcribeAudio(at: tempURL)
            
            // Wait for transcription to complete
            while !delegate.didCompleteWithTranscriptionCalled {
                try await Task.sleep(for: .milliseconds(50))
            }
            
            let endTime = DispatchTime.now()
            let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let timeInterval = Double(nanoTime) / 1_000_000_000 // Convert to seconds
            
            processingTimes.append(timeInterval)
            
            // Reset for next test
            delegate.didCompleteWithTranscriptionCalled = false
        }
        
        // Verify processing times scale reasonably with audio length
        // Each processing time should be less than the audio length
        for i in 0..<audioLengths.count {
            #expect(processingTimes[i] < Double(audioLengths[i]))
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // Test memory usage during transcription
    @Test func testTranscriptionMemoryUsage() async throws {
        let manager = PerformanceTranscriptionManager()
        let delegate = MockTranscriptionDelegate()
        manager.delegate = delegate
        
        // Create a temporary file for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("memory_test_audio.m4a")
        try Data().write(to: tempURL)
        
        // Measure memory before transcription
        let memoryBefore = reportMemoryUsage()
        
        // Perform transcription
        manager.transcribeAudio(at: tempURL)
        
        // Wait for transcription to complete
        while !delegate.didCompleteWithTranscriptionCalled {
            try await Task.sleep(for: .milliseconds(50))
        }
        
        // Measure memory after transcription
        let memoryAfter = reportMemoryUsage()
        
        // Verify memory usage increase is reasonable (less than 50MB)
        let memoryIncrease = memoryAfter - memoryBefore
        #expect(memoryIncrease < 50 * 1024 * 1024) // 50MB in bytes
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // Helper function to report memory usage
    private func reportMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
}

// MARK: - Mock Classes for Performance Testing

// Performance-optimized mock for audio delegate
class MockPerformanceAudioDelegate: AudioRecorderDelegate {
    var updateCount: Int = 0

    func audioRecorderDidStartRecording() {}
    func audioRecorderDidStopRecording(fileURL: URL) {}
    func audioRecorderDidCompleteChunk(fileURL: URL) {}
    func audioRecorderDidUpdateLevel(_ levels: [Float]) { updateCount += 1 }
    func audioRecorderDidFailWithError(_ error: Error) {}
    func audioRecorderDidDetectDevices(devices: [AudioRecorderManager.AudioDevice], microphoneAvailable: Bool) {}
}

// Extended MockTranscriptionManager with performance testing features
class PerformanceTranscriptionManager: MockTranscriptionManager {
    var simulatedProcessingTime: Double = 0.5
    
    override func transcribeAudio(at fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Simulate processing with the specified delay
            Thread.sleep(forTimeInterval: self.simulatedProcessingTime)
            
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
}
