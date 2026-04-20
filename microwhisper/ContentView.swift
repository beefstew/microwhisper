import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: TranscriptionViewModel
    @State private var hoveringCopy: Bool = false

    var body: some View {
        return ZStack {
            VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Spacer(minLength: 10)
                        
                        // Audio source selector
                        HStack(alignment: .center, spacing: 12) {
                            Picker("Audio Device", selection: $viewModel.selectedDevice) {
                                Text("None").tag(Optional<AudioRecorderManager.AudioDevice>.none)
                                ForEach(viewModel.availableInputDevices) { device in
                                    Text(device.name).tag(Optional(device))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 350)
                            .disabled(viewModel.isRecording)
                          
                            // Record button
                            Button(action: {
                                viewModel.toggleRecording()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)

                                    if viewModel.isRecording {
                                        // Stop button (square)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.red)
                                            .frame(width: 20, height: 20)
                                    } else {
                                        // Record button (circle)
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 20, height: 20)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(viewModel.isRecording ? "Stop recording" : "Start recording")

                            AudioLevelMeter(levels: viewModel.audioLevels)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Transcript area with flexible sizing
                        if viewModel.isRecording || viewModel.showTranscript {
                            VStack(alignment: .trailing, spacing: 8) {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        viewModel.copyTranscriptToPasteboard()
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 14))
                                            .foregroundColor(hoveringCopy ? .primary : .secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .onHover { hovering in
                                        hoveringCopy = hovering
                                    }
                                    .help("Copy transcript to clipboard")
                                }
                                .padding(.trailing, 10)

                                AutoScrollTextView(text: viewModel.transcript)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 200, maxHeight: .infinity)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                    )
                            }
                            .padding(.horizontal, 30)
                            .frame(minHeight: 200, maxHeight: .infinity)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
                            .transition(.opacity)
                        }
                        
                        Spacer(minLength: 20)
                        
                    }
                }
                .background(Color.clear)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

#Preview("Default") {
    let vm = TranscriptionViewModel()
    vm.isRecording = false
    return ContentView().environmentObject(vm)
}

#Preview("Recording") {
    let vm = TranscriptionViewModel()
    vm.isRecording = true
    vm.audioLevels = [0.8, 0.5]
    vm.transcript = "This is a sample transcript that has been captured from the microphone."
    vm.showTranscript = true
    return ContentView().environmentObject(vm)
}


// MARK: - Auto-scrolling transcript view

struct AutoScrollTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.didLiveScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }

        textView.string = text

        if context.coordinator.shouldAutoScroll {
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
            }
        }
    }

    class Coordinator: NSObject {
        var shouldAutoScroll = true

        @objc func didLiveScroll(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView,
                  let documentView = scrollView.documentView else { return }
            let distanceFromBottom = documentView.frame.maxY - scrollView.documentVisibleRect.maxY
            shouldAutoScroll = distanceFromBottom < 30
        }
    }
}

// MARK: - Audio level meter

struct AudioLevelMeter: View {
    let levels: [Float]  // one entry per channel; row count matches channelCount

    private let segmentCount = 5
    // Colors left-to-right: low → high level
    private let colors: [Color] = [.green, .green, .green, .yellow, .red]

    var body: some View {
        return VStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { ch in
                row(for: levels[ch])
            }
        }
    }

    private func row(for level: Float) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { i in
                let threshold = Float(i) / Float(segmentCount)
                let lit = level > threshold
                RoundedRectangle(cornerRadius: 2)
                    .fill(lit ? colors[i] : colors[i].opacity(0.12))
                    .frame(width: 3, height: 8)
                    .animation(.easeOut(duration: 0.08), value: lit)
            }
        }
    }
}

// Helper for NSVisualEffectView to enable window transparency
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
