import AVFoundation
import CoreAudio

protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderDidStartRecording()
    func audioRecorderDidStopRecording(fileURL: URL)
    func audioRecorderDidCompleteChunk(fileURL: URL)
    func audioRecorderDidUpdateLevel(_ levels: [Float])
    func audioRecorderDidFailWithError(_ error: Error)
    func audioRecorderDidDetectDevices(devices: [AudioRecorderManager.AudioDevice], microphoneAvailable: Bool)
}

class AudioRecorderManager: NSObject {
    weak var delegate: AudioRecorderDelegate?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordedFileURL: URL?
    private(set) var isRecording = false
    private(set) var isMonitoring = false
    private var monitoredDeviceID: AudioDeviceID?
    // Format used when the tap was installed; file writes must use this exact format.
    private var tapFormat: AVAudioFormat?

    struct AudioDevice: Identifiable, Equatable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    private(set) var inputDevices: [AudioDevice] = []
    private(set) var defaultInputDeviceID: AudioDeviceID = 0

    // Chunking
    private var chunkTimer: Timer?
    private let chunkInterval: TimeInterval = 10.0
    private var waitingForChunkBoundary = false
    private var consecutiveSilentBuffers = 0
    private let silenceThresholdDB: Float = -35.0   // dBFS below which = silence
    private let requiredSilentBuffers = 4            // ~4 × buffer duration ≈ 300ms

    // Saved so chunk rotation can open the next file in the same format
    private var currentFileSettings: [String: Any] = [:]

    // Serial queue that owns all AVAudioFile lifecycle + writes, so the render
    // thread tap callback never blocks on disk I/O. All reads/writes of
    // `audioFile`, `recordedFileURL`, and `currentFileSettings` that touch
    // disk go through this queue.
    private let writeQueue = DispatchQueue(
        label: "net.beefstew.microwhisper.audioWrite",
        qos: .userInitiated)

    /// Copy a tap buffer so the underlying PCM storage can be handed off to
    /// another thread safely. AVAudioEngine is free to reuse the backing store
    /// after the tap callback returns.
    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                          frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    override init() {
        super.init()
        setupDeviceListener()
        // detectAudioDevices() intentionally omitted: delegate is not yet wired up at init time.
        // AppDelegate.applicationDidFinishLaunching calls detectAudioDevices() explicitly after
        // delegates are set, so the result actually reaches the UI.
    }

    deinit {
        removeDeviceListener()
    }

    // MARK: - Recording

    func startRecording(device: AudioDevice) {
        print("Recording from device: '\(device.name)' (ID \(device.id))")
        startRecordingWithDeviceID(device.id)
    }

    private func startRecordingWithDeviceID(_ deviceID: AudioDeviceID) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording-\(UUID().uuidString).wav"
        recordedFileURL = tempDir.appendingPathComponent(fileName)

        do {
            // Reuse the monitoring engine if it's already running on the same device;
            // otherwise tear it down and set up fresh.
            if !isMonitoring || monitoredDeviceID != deviceID {
                stopMonitoring()
                let engine = AVAudioEngine()
                try setInputDevice(deviceID, on: engine)

                // Use inputFormat(forBus:) to read the hardware format BEFORE starting the
                // engine. installTap must be called before engine.start() on macOS, otherwise
                // the tap may never receive buffers.
                let inputNode = engine.inputNode
                let liveFormat = inputNode.inputFormat(forBus: 0)
                print("Input format: \(liveFormat)")

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: liveFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    // Level meter math is CPU-only and safe on the render thread.
                    self.updateMeter(from: buffer)
                    guard self.isRecording else { return }
                    // Copy the buffer so the engine can reuse its backing storage,
                    // then perform the actual disk write off the render thread.
                    if let copy = Self.copyBuffer(buffer) {
                        self.writeQueue.async { [weak self] in
                            guard let self = self else { return }
                            do {
                                try self.audioFile?.write(from: copy)
                            } catch {
                                NSLog("audioFile write error: %@", String(describing: error))
                            }
                        }
                    }
                }

                engine.prepare()
                try engine.start()

                audioEngine = engine
                tapFormat = liveFormat
                isMonitoring = true
                monitoredDeviceID = deviceID
            }

            // Open the output file using the exact same format the tap was installed with,
            // so AVAudioFile.write(from:) never sees a format mismatch.
            guard let liveFormat = tapFormat else {
                throw NSError(domain: "AudioRecorderManager", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Tap format unavailable"])
            }
            // Write float32 to match the tap buffer format exactly, avoiding
            // any int16 conversion that can produce silence on playback.
            let fileSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: liveFormat.sampleRate,
                AVNumberOfChannelsKey: liveFormat.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]
            currentFileSettings = fileSettings
            // Own all AVAudioFile lifecycle on writeQueue. Using sync here so any
            // error propagates into the surrounding do/catch.
            let fileURL = recordedFileURL!
            try writeQueue.sync {
                audioFile = try AVAudioFile(forWriting: fileURL, settings: fileSettings)
            }

            isRecording = true
            delegate?.audioRecorderDidStartRecording()
            startChunkTimer()

        } catch {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            isMonitoring = false
            monitoredDeviceID = nil
            tapFormat = nil
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

        // Close the file on writeQueue so any in-flight writes drain first,
        // and so file-handle ownership stays on a single queue.
        writeQueue.sync {
            audioFile = nil  // closes and flushes
        }

        if let fileURL = recordedFileURL {
            delegate?.audioRecorderDidStopRecording(fileURL: fileURL)
        }
    }

    func startMonitoring(deviceID: AudioDeviceID) {
        if isMonitoring && monitoredDeviceID == deviceID { return }
        if isMonitoring { stopMonitoring() }

        do {
            let engine = AVAudioEngine()
            try setInputDevice(deviceID, on: engine)

            // Read the hardware format BEFORE starting the engine, and install the tap
            // BEFORE engine.start(). Installing a tap post-start can silently fail to
            // deliver buffers on macOS.
            let inputNode = engine.inputNode
            let liveFormat = inputNode.inputFormat(forBus: 0)
            print("Monitoring \(deviceID) with format: \(liveFormat)")

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: liveFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                // Level meter math is CPU-only and safe on the render thread.
                self.updateMeter(from: buffer)
                guard self.isRecording else { return }
                // Copy the buffer so the engine can reuse its backing storage,
                // then perform the actual disk write off the render thread.
                if let copy = Self.copyBuffer(buffer) {
                    self.writeQueue.async { [weak self] in
                        guard let self = self else { return }
                        do {
                            try self.audioFile?.write(from: copy)
                        } catch {
                            NSLog("audioFile write error: %@", String(describing: error))
                        }
                    }
                }
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            tapFormat = liveFormat
            monitoredDeviceID = deviceID
            isMonitoring = true
        } catch {
            delegate?.audioRecorderDidFailWithError(error)
        }
    }

    func stopMonitoring() {
        guard !isRecording else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isMonitoring = false
        monitoredDeviceID = nil
        tapFormat = nil
    }

    // MARK: - Chunking

    private func startChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) { [weak self] _ in
            print("Chunk boundary pending — waiting for silence...")
            self?.waitingForChunkBoundary = true
        }
    }

    /// Called on writeQueue when silence is detected after a chunk boundary.
    /// Owning file-handle lifecycle on writeQueue keeps it serialized with the
    /// tap's write path.
    private func splitChunk() {
        guard let completedURL = recordedFileURL, isRecording else { return }

        let newURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).wav")

        // Close the current file and open a new one. Disk I/O runs on
        // writeQueue, never on the render callback.
        audioFile = nil
        recordedFileURL = newURL
        audioFile = try? AVAudioFile(forWriting: newURL, settings: currentFileSettings)

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

        var levels: [Float] = []
        var maxDb: Float = -.infinity

        for channel in 0..<channelCount {
            var sum: Float = 0
            for frame in 0..<frameCount {
                let sample = channelData[channel][frame]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let db = 20 * log10(max(rms, 1e-7))
            maxDb = max(maxDb, db)
            levels.append(max(0, min(1, (db + 50) / 50)))
        }

        // Use the loudest channel's dB (not a cross-channel average) so one
        // quiet channel can't pull the level below the threshold while a hot
        // channel still carries speech. This is the dB equivalent of
        // `levels.max()` on the normalized meter values.
        let loudestDb = maxDb

        // Silence detection for chunk splitting
        if waitingForChunkBoundary {
            if loudestDb < silenceThresholdDB {
                consecutiveSilentBuffers += 1
                if consecutiveSilentBuffers >= requiredSilentBuffers {
                    waitingForChunkBoundary = false
                    consecutiveSilentBuffers = 0
                    writeQueue.async { [weak self] in
                        self?.splitChunk()
                    }
                }
            } else {
                consecutiveSilentBuffers = 0
            }
        } else {
            consecutiveSilentBuffers = 0
        }

        DispatchQueue.main.async {
            self.delegate?.audioRecorderDidUpdateLevel(levels)
        }
    }

    // MARK: - Device Detection

    // Narrow listener: only react to device-list and default-input changes, not every
    // unrelated property change on the system audio object.
    private static let listenedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice
    ]

    private static let deviceListenerCallback: AudioObjectPropertyListenerProc = { (_, _, _, context) -> OSStatus in
        guard let context = context else { return noErr }
        let manager = Unmanaged<AudioRecorderManager>.fromOpaque(context).takeUnretainedValue()
        manager.detectAudioDevices()
        return noErr
    }

    private func setupDeviceListener() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for selector in Self.listenedSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.deviceListenerCallback,
                context)
            if status != noErr {
                print("Error setting up device listener for selector \(selector): \(status)")
            }
        }
    }

    private func removeDeviceListener() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for selector in Self.listenedSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.deviceListenerCallback,
                context)
        }
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
            updateDeviceAvailability(microphoneAvailable: true)
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
            updateDeviceAvailability(microphoneAvailable: true)
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

        var foundDevices: [AudioDevice] = []

        for deviceID in deviceIDs {
            // Skip devices with no input streams
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

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
                foundDevices.append(AudioDevice(id: deviceID, name: name))
            }
        }

        inputDevices = foundDevices
        updateDeviceAvailability(microphoneAvailable: true)
    }

    private func updateDeviceAvailability(microphoneAvailable: Bool) {
        DispatchQueue.main.async {
            self.delegate?.audioRecorderDidDetectDevices(
                devices: self.inputDevices,
                microphoneAvailable: microphoneAvailable)
        }
    }

    @objc private func handleAudioRouteChange(notification: Notification) {
        detectAudioDevices()
    }
}
