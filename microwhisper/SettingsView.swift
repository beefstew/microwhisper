import SwiftUI
import UniformTypeIdentifiers

enum SettingsKey {
    static let whisperModelPath = "whisperModelPath"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.whisperModelPath) private var whisperModelPath: String = ""

    private var modelFileExists: Bool {
        !whisperModelPath.isEmpty && FileManager.default.fileExists(atPath: whisperModelPath)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Whisper.cpp model location")
                        .font(.headline)

                    HStack(alignment: .bottom) {
                        TextField("Path to ggml model (.bin file)", text: $whisperModelPath)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)

                        Button("Choose…") { chooseModelFile() }
                    }

                    Group {
                        if whisperModelPath.isEmpty {
                            Text("No model selected. Transcription will fail until a model is chosen.")
                                .foregroundStyle(.orange)
                        } else if !modelFileExists {
                            Text("File does not exist at this path.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Looking good!")
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 650, height: 200)
    }

    private func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Whisper model (.bin)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        if let binType = UTType(filenameExtension: "bin") {
            panel.allowedContentTypes = [binType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            whisperModelPath = url.path
        }
    }
}

#Preview("No model selected") {
    UserDefaults.standard.removeObject(forKey: SettingsKey.whisperModelPath)
    return SettingsView()
}

#Preview("Invalid path") {
    UserDefaults.standard.set("/does/not/exist/ggml.bin", forKey: SettingsKey.whisperModelPath)
    return SettingsView()
}

#Preview("Valid path") {
    // /bin/ls exists on every Mac — handy for a "file found" preview.
    UserDefaults.standard.set("/bin/ls", forKey: SettingsKey.whisperModelPath)
    return SettingsView()
}
