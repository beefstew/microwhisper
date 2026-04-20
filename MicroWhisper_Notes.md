# MicroWhisper Repository Notes

## Project Overview
MicroWhisper is a macOS menu bar application that provides real-time audio transcription using OpenAI's Whisper model. The app records audio via the device's microphone and uses the locally installed Whisper CLI tool to transcribe the audio to text.

## Core Components

### 1. Application Structure
- **Entry Point**: `MicrowhisperApp.swift` - Sets up the SwiftUI application and window configuration
- **App Delegate**: `AppDelegate.swift` - Coordinates between different system components
- **Main UI**: `ContentView.swift` - SwiftUI view with recording visualization and transcript display

### 2. Key Managers
- **AudioRecorderManager**: Handles audio recording using AVFoundation
- **TranscriptionManager**: Processes audio files using the Whisper CLI and returns transcription
- **StatusBarManager**: Controls menu bar icon and dropdown menu functionality
- **KeyTapHandler**: Captures global keyboard shortcut (⌥⇧R) for toggling recording

### 3. Data Flow
- **TranscriptionViewModel**: Stores and updates UI state (recording status, transcript text, etc.)

## Technical Details

### Audio Recording
- Uses AVFoundation's `AVAudioRecorder` to capture audio
- Implements audio level metering for visualization
- Saves temporary audio files as WAV (.wav) format

### Transcription
- Relies on locally installed OpenAI Whisper CLI (`/usr/local/bin/whisper`)
- Uses the "ggml-large-v2.en" model for English transcription (line ~124 `TranscriptionManager.swift`)
- Processes audio in a background thread
- Manages process lifecycle with proper cleanup

### UI Features
- Menu bar integration with status icon
- Visual audio level indicator during recording
- Clean SwiftUI interface with visual effects
- Copy-to-clipboard functionality for transcripts

### User Interaction
- Global keyboard shortcut (⌥⇧R) to start/stop recording
- Menu bar dropdown with recording controls
- Button in main UI to toggle recording

## Dependencies
- macOS 15.2 or later
- Whisper CLI installed at `/usr/local/bin/whisper`
- AVFoundation for audio recording
- SwiftUI for UI components