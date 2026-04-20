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
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .visible
                window.backgroundColor = .windowBackgroundColor
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

