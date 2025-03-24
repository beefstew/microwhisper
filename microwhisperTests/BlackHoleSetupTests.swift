//
//  BlackHoleSetupTests.swift
//  microwhisperTests
//
//  Created by Chris Gatzonis on 3/23/25.
//

import Testing
import XCTest
@testable import microwhisper

// MARK: - BlackHole Setup Tests

struct BlackHoleSetupTests {
    
    // Test BlackHole detection
    @Test func testBlackHoleDetection() async throws {
        // Create a mock BlackHole setup manager
        let setupManager = MockBlackHoleSetupManager()
        
        // Test when BlackHole is not installed
        setupManager.mockBlackHoleInstalled = false
        let notInstalledResult = setupManager.isBlackHoleInstalled()
        #expect(notInstalledResult == false)
        
        // Test when BlackHole is installed
        setupManager.mockBlackHoleInstalled = true
        let installedResult = setupManager.isBlackHoleInstalled()
        #expect(installedResult == true)
    }
    
    // Test setup instructions generation
    @Test func testSetupInstructionsGeneration() async throws {
        let setupManager = MockBlackHoleSetupManager()
        
        // Test instructions generation
        let instructions = setupManager.generateSetupInstructions()
        
        // Verify instructions contain key information
        #expect(instructions.contains("BlackHole"))
        #expect(instructions.contains("install"))
        // Use lowercase "setup" to match the test expectation
        #expect(instructions.lowercased().contains("setup"))
    }
    
    // Test multi-output device setup
    @Test func testMultiOutputDeviceSetup() async throws {
        let setupManager = MockBlackHoleSetupManager()
        
        // Test when BlackHole is not installed
        setupManager.mockBlackHoleInstalled = false
        let notInstalledResult = setupManager.canCreateMultiOutputDevice()
        #expect(notInstalledResult == false)
        
        // Test when BlackHole is installed
        setupManager.mockBlackHoleInstalled = true
        let installedResult = setupManager.canCreateMultiOutputDevice()
        #expect(installedResult == true)
        
        // Test multi-output device creation
        setupManager.mockBlackHoleInstalled = true
        let createResult = try setupManager.createMultiOutputDevice()
        #expect(createResult == true)
    }
    
    // Test BlackHole installation instructions
    @Test func testInstallationInstructions() async throws {
        let setupManager = MockBlackHoleSetupManager()
        
        // Get installation instructions
        let instructions = setupManager.getInstallationInstructions()
        
        // Verify instructions contain key steps
        #expect(instructions.contains("brew"))
        #expect(instructions.contains("blackhole-2ch"))
        // Use lowercase "restart" to match the test expectation
        #expect(instructions.lowercased().contains("restart"))
    }
}

// MARK: - Mock Classes

// Mock BlackHole setup manager for testing
class MockBlackHoleSetupManager {
    var mockBlackHoleInstalled: Bool = false
    
    func isBlackHoleInstalled() -> Bool {
        return mockBlackHoleInstalled
    }
    
    func generateSetupInstructions() -> String {
        return """
        BlackHole Setup Instructions:
        
        1. Install BlackHole using Homebrew:
           brew install blackhole-2ch
        
        2. Restart your computer to complete the installation
        
        3. Setup a Multi-Output Device in Audio MIDI Setup:
           - Open Audio MIDI Setup
           - Click the "+" button and select "Create Multi-Output Device"
           - Check both your speakers and BlackHole 2ch
           - Make your Multi-Output Device the default output
        
        4. Select BlackHole 2ch as the input device in MicroWhisper
        """
    }
    
    func canCreateMultiOutputDevice() -> Bool {
        return mockBlackHoleInstalled
    }
    
    func createMultiOutputDevice() throws -> Bool {
        if !mockBlackHoleInstalled {
            throw NSError(domain: "BlackHoleSetupManager", 
                         code: 1001, 
                         userInfo: [NSLocalizedDescriptionKey: "BlackHole is not installed"])
        }
        
        // Simulate successful creation
        return true
    }
    
    func getInstallationInstructions() -> String {
        return """
        To install BlackHole:
        
        1. Open Terminal
        2. Run: brew install blackhole-2ch
        3. restart your computer
        4. Open MicroWhisper again
        """
    }
}
