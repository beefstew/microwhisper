//
//  microwhisperApp.swift
//  microwhisper
//
//  Created by Chris Gatzonis on 2/10/25.
//  Modified by Chris Horn 2026-04-20
//

import SwiftUI

@main
struct MicrowhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarMenuContent(appDelegate: appDelegate)
        } label: {
            MenuBarLabel(appDelegate: appDelegate)
        }
    }
}

private struct MenuBarMenuContent: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Button(appDelegate.isRecording ? "Stop Recording" : "Start Recording") {
            appDelegate.toggleRecording()
        }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Image(systemName: appDelegate.isRecording ? "mic.fill" : "mic")
    }
}

