import AVFoundation
import CoreAudio

protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderDidStartRecording()
    func audioRecorderDidStopRecording(fileURL: URL)
    func audioRecorderDidCompleteChunk(fileURL: URL)
    func audioRecorderDidUpdateLevel(_ level: Float)
    func audioRecorderDidFailWithError(_ error: Error)
    func audioRecorderDidDetectDevices(microphoneAvailable: Bool, blackholeAvailable: Bool)
}

class AudioRecorderManager: NSObject {
    weak var delegate: AudioRecorderDelegate?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordedFileURL: URL?
    private(set) var isRecording = false

    // Audio source selection
    enum AudioSource {
        case microphone
        case systemAudio
        case both
    }

    private(set) var currentAudioSource: AudioSource = .microphone
    private(set) var isBlackholeAvailable = false

    // Audio device properties
    private let blackholeDeviceName = "Blackholed Scarlett Mic"
    private var blackholeDeviceID: AudioDeviceID?
    private var defaultInputDeviceID: AudioDeviceID = 0

    // Chunking
    private var chunkTimer: Timer?
    private let chunkInterval: TimeInterval = 10.0
    private var waitingForChunkBoundary = false
    private var consecutiveSilentBuffers = 0
    private let silenceThresholdDB: Float = -35.0   // dBFS below which = silence
    private let requiredSilentBuffers = 4            // ~4 × buffer duration ≈ 300ms

    // Saved so chunk rotation can open the next file in the same format
    private var currentFileSettings: [String: Any] = [:]

    override init() {
        super.init()
        setupDeviceListener()
        detectAudioDevices()
    }

    deinit {
        removeDeviceListener()
    }

    // MARK: - Recording

    func startRecording(from source: AudioSource = .microphone) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording-\(UUID().uuidString).wav"
        recordedFileURL = tempDir.appendingPathComponent(fileName)
        currentAudioSource = source

        let deviceID: AudioDeviceID
        switch source {
        case .microphone:
            deviceID = defaultInputDeviceID
            print("Recording from microphone: ID \(deviceID)")
        case .systemAudio:
            guard let blackholeID = blackholeDeviceID, isBlackholeAvailable else {
                delegate?.audioRecorderDidFailWithError(NSError(
                    domain: "AudioRecorderManager", code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "BlackHole audio device not available"]))
                return
            }
            deviceID = blackholeID
            print("Recording from system audio: ID \(deviceID)")
        case .both:
            delegate?.audioRecorderDidFailWithError(NSError(
                domain: "AudioRecorderManager", code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Recording from both sources simultaneously is not implemented yet"]))
            return
        }

        do {
            let engine = AVAudioEngine()
            try setInputDevice(deviceID, on: engine)

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            print("Input format: \(inputFormat)")

            // Write float32 to match the tap buffer format exactly, avoiding
            // any int16 conversion that can produce silence on playback.
            let fileSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]
            currentFileSettings = fileSettings
            audioFile = try AVAudioFile(forWriting: recordedFileURL!, settings: fileSettings)

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self, self.isRecording else { return }
                try? self.audioFile?.write(from: buffer)
                self.updateMeter(from: buffer)
            }

            try engine.start()
            audioEngine = engine
            isRecording = true
            delegate?.audioRecorderDidStartRecording()
            startChunkTimer()

        } catch {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            audioFile = nil
            delegate?.audioRecorderDidFailWithError(error)
        }
    }

    func stopRecording() {
        // Set flag first so any in-flight tap callbacks skip writing.
        isRecording = false
        chunkTimer?.invalidate()
        chunkTimer = nil
        waitingForChunkBoundary = false
        consecutiveSilentBuffers = 0

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil  // closes and flushes

        if let fileURL = recordedFileURL {
            delegate?.audioRecorderDidStopRecording(fileURL: fileURL)
        }
    }

    // MARK: - Chunking

    private func startChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) { [weak self] _ in
            print("Chunk boundary pending — waiting for silence...")
            self?.waitingForChunkBoundary = true
        }
    }

    /// Called from the audio tap thread when silence is detected after a chunk boundary.
    private func splitChunk() {
        guard let completedURL = recordedFileURL, isRecording else { return }

        let newURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).wav")

        // Close the current file and open a new one.
        // Both happen on the audio thread so there is no concurrent access.
        audioFile = nil
        recordedFileURL = newURL
        audioFile = try? AVAudioFile(forWriting: newURL, settings: currentFileSettings)

        print("Chunk split: dispatching \(completedURL.lastPathComponent)")

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.audioRecorderDidCompleteChunk(fileURL: completedURL)
        }
    }

    // MARK: - Device setup

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(domain: "AudioRecorderManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not access input audio unit"])
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw NSError(domain: "AudioRecorderManager", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to set input device (OSStatus \(status))"])
        }
    }

    // MARK: - Metering

    private func updateMeter(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = channelData[channel][frame]
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Float(channelCount * frameCount))
        let db = 20 * log10(max(rms, 1e-7))
        let level = max(0, min(1, (db + 50) / 50))

        // Silence detection for chunk splitting
        if waitingForChunkBoundary {
            if db < silenceThresholdDB {
                consecutiveSilentBuffers += 1
                if consecutiveSilentBuffers >= requiredSilentBuffers {
                    waitingForChunkBoundary = false
                    consecutiveSilentBuffers = 0
                    splitChunk()
                }
            } else {
                consecutiveSilentBuffers = 0
            }
        } else {
            consecutiveSilentBuffers = 0
        }

        DispatchQueue.main.async {
            self.delegate?.audioRecorderDidUpdateLevel(level)
        }
    }

    // MARK: - Device Detection

    private func setupDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertySelectorWildcard,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementWildcard)

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (_, _, _, context) -> OSStatus in
                let manager = Unmanaged<AudioRecorderManager>.fromOpaque(context!).takeUnretainedValue()
                manager.detectAudioDevices()
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        if status != noErr {
            print("Error setting up device listener: \(status)")
        }
    }

    private func removeDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertySelectorWildcard,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementWildcard)

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (_, _, _, context) -> OSStatus in
                let manager = Unmanaged<AudioRecorderManager>.fromOpaque(context!).takeUnretainedValue()
                manager.detectAudioDevices()
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    func detectAudioDevices() {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize)

        if result != noErr {
            print("Error getting devices property size: \(result)")
            updateDeviceAvailability(microphoneAvailable: true, blackholeAvailable: false)
            return
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs)

        if result != noErr {
            print("Error getting device IDs: \(result)")
            updateDeviceAvailability(microphoneAvailable: true, blackholeAvailable: false)
            return
        }

        // Get default input device
        address.mSelector = kAudioHardwarePropertyDefaultInputDevice
        var defaultDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultDeviceID)

        if result == noErr {
            defaultInputDeviceID = defaultDeviceID
        }

        var blackholeFound = false

        for deviceID in deviceIDs {
            address.mSelector = kAudioDevicePropertyDeviceNameCFString
            var deviceName: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<CFString>.size)

            result = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &deviceName)

            if result == noErr, let cfName = deviceName?.takeRetainedValue() {
                let name = cfName as String
                print("Audio device found: '\(name)' (ID \(deviceID))")
                if name.contains(blackholeDeviceName) {
                    blackholeFound = true
                    blackholeDeviceID = deviceID
                    break
                }
            }
        }

        isBlackholeAvailable = blackholeFound
        updateDeviceAvailability(microphoneAvailable: true, blackholeAvailable: blackholeFound)
    }

    private func updateDeviceAvailability(microphoneAvailable: Bool, blackholeAvailable: Bool) {
        DispatchQueue.main.async {
            self.delegate?.audioRecorderDidDetectDevices(
                microphoneAvailable: microphoneAvailable,
                blackholeAvailable: blackholeAvailable)
        }
    }

    @objc private func handleAudioRouteChange(notification: Notification) {
        detectAudioDevices()
    }
}
