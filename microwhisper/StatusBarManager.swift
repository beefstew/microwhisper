import Cocoa

protocol StatusBarManagerDelegate: AnyObject {
    func statusBarManagerDidToggleRecording()
}

class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?

    weak var delegate: StatusBarManagerDelegate?

    override init() {
        super.init()
        setupStatusBarItem()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Microwhisper")
        }

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Start Recording", action: #selector(menuToggleRecording), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    func updateRecordingState(isRecording: Bool) {
        let symbolName = isRecording ? "mic.fill" : "mic"
        let description = isRecording ? "Recording" : "Microwhisper"

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        }

        toggleItem?.title = isRecording ? "Stop Recording" : "Start Recording"
    }

    @objc private func menuToggleRecording() {
        delegate?.statusBarManagerDidToggleRecording()
    }
}
