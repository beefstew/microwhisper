# MicroWhisper

A macOS application that provides near real-time audio transcription using OpenAI's Whisper model. The app sits in your menu bar and can be triggered with a global keyboard shortcut to start/stop recording. It supports recording off any of your audio devices.

## Features

- Audio recording with visual transcription feedback
- Record your microphone and system audio (using BlackHole)
- Visual audio levels indicator with channel-level detail
- Copy transcribed text
- Transcripts saved to desktop in plain text file
- Clean, minimal SwiftUI interface
- Global keyboard shortcut (⌥⇧R) to start/stop recording (BROKEN)

## Requirements

- macOS 15.2 or later
- [Whisper.cpp](https://github.com/ggml-org/whisper.cpp) CLI installed (`/usr/local/bin/whisper`)
- Microphone access permission
- BlackHole audio driver (optional, for microphone + system audio recording)

## Installation

1. Clone this repository
2. Open the project in Xcode
3. Install [Whisper.cpp](https://github.com/ggml-org/whisper.cpp/releases) CLI
4. (Optional) Install [BlackHole](https://github.com/existentialaudio/blackhole) for recording from microphone and system audio at the same time. After installing, use `Audio MIDI Setup.app` (Applications > Utilities) to:
	1. Click the "+" button in the bottom left and add an Aggregate audio device with your Microphone device and BlackHole 2ch
	2. Click the "+" button in the bottom left and add a Multi-Output device with your Speaker device and BlackHole 2ch
5. Build and run the project in Xcode

## Usage

1. Launch the application
2. Select the audio device from which you want to transcribe audio. If you want to record from your microphone *and* system audio, use the **System Settings > Sound** to set Output to the Multi-Output device you created earlier and Input to the Aggregate device
3. Start recording
4. Speak into your microphone and/or play audio on the selected device (e.g. MacBook Pro Speakers)
5. Transcription will update in the text area approximately every 10 seconds
7. You can copy the transcribed text at any time
8. When you stop recording, a text file of the session transcript will appear on your desktop

## Future Enhancement Ideas
- Streamlined Whisper installation
- Pre-built, signed releases
- Historical transcripts managed in app (like Voice Memos)
- Speaker tracking / identification
- Keep compressed audio recordings (.m4a)
- Improved application test suite

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