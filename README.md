# MicroWhisper

[![MicroWhisper Tests](https://github.com/ChrisGatzo/microwhisper/actions/workflows/test.yml/badge.svg)](https://github.com/ChrisGatzo/microwhisper/actions/workflows/test.yml)

A macOS application that provides real-time audio transcription using OpenAI's Whisper model. The app sits in your menu bar and can be triggered with a global keyboard shortcut to start/stop recording. It supports both microphone and system audio recording.

## Features

- Real-time audio recording with visual feedback
- Record from microphone or system audio (using BlackHole)
- Global keyboard shortcut (⌥⇧R) to start/stop recording
- Visual audio level indicator while recording
- Instant transcription using Whisper's tiny.en model
- Selectable transcript text
- Clean, minimal SwiftUI interface

## Requirements

- macOS 15.2 or later
- Whisper CLI installed (`/usr/local/bin/whisper`)
- Microphone access permission
- BlackHole audio driver (optional, for system audio recording)

## Installation

1. Clone this repository
2. Open the project in Xcode
3. Install Whisper CLI if you haven't already:
   ```bash
   # Install Whisper CLI (if using Homebrew)
   brew install whisper
   ```
4. (Optional) Install BlackHole for system audio recording:
   ```bash
   # Install BlackHole (if using Homebrew)
   brew install blackhole-2ch
   ```
5. Build and run the project in Xcode

## Usage

1. Launch the application
2. Select your audio source (microphone or system audio)
3. Press ⌥⇧R (Option + Shift + R) to start recording
4. Speak into your microphone or play audio from your system
5. Press ⌥⇧R again to stop recording and start transcription
6. The transcribed text will appear in the window
7. You can select and copy the transcribed text

### Setting Up System Audio Recording

1. Install BlackHole audio driver (see Installation section)
2. Open System Settings > Sound
3. Set the output device to "BlackHole 2ch"
4. Open the application you want to record audio from (e.g., Zoom, YouTube)
5. In MicroWhisper, select "System Audio" as your audio source
6. Start recording

Note: To hear the audio while recording, you'll need to set up a Multi-Output Device in Audio MIDI Setup:

1. Open Audio MIDI Setup (Applications > Utilities)
2. Click the "+" button in the bottom left and select "Create Multi-Output Device"
3. Check both your regular output device (e.g., Built-in Output) and "BlackHole 2ch"
4. In System Settings > Sound, set the output to your newly created Multi-Output Device

## Technical Details

- Built with SwiftUI and AVFoundation
- Uses CGEventTap for global keyboard shortcut handling
- Implements real-time audio level monitoring
- Core Audio integration for audio device detection
- Support for BlackHole virtual audio driver for system audio recording
- Processes audio using Whisper's tiny.en model for fast transcription

## Privacy

The application requires microphone access to function. All processing is done locally using the Whisper model, and no audio data is sent to external servers. When recording system audio, the audio is captured through the BlackHole virtual audio driver and processed locally.

## License

This project is available under the MIT License. See the LICENSE file for more details.