// PhotoProofApp.swift
// App entry point. Owns AppState and routes to the right top-level screen.

import SwiftUI
import AppKit

@main
struct PhotoProofApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("PhotoProof") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 520)
                .sheet(isPresented: $appState.showHistory) {
                    HistoryView()
                        .frame(minWidth: 560, minHeight: 360)
                }
                .sheet(isPresented: $appState.showEmptyAlbums) {
                    EmptyAlbumsView()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PhotoProof") {
                    showAboutPanel()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(!appState.isConfigured)
            }
            CommandGroup(after: .appSettings) {
                Divider()
                Button("Verification History") {
                    appState.showHistory = true
                }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(!appState.isConfigured)
            }
            CommandMenu("Library") {
                Button("Manage Empty Albums…") {
                    appState.showEmptyAlbums = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!appState.photosAccessGranted)
            }
        }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: "PhotoProof verifies that your photos are backed up to Immich before you delete them. "
                  + "It never permanently deletes anything — items move to Recently Deleted and Photos' standard "
                  + "30-day timer is the safety net.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: credits,
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
