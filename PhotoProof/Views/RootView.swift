// RootView.swift
// Top-level router. Decides which screen to show based on Photos authorization
// and whether Immich has been configured.

import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.photosAccessGranted {
                OnboardingView()
            } else if !appState.isConfigured {
                SettingsView(isFirstLaunch: true)
            } else {
                MainView()
                    .sheet(isPresented: $appState.showSettings) {
                        SettingsView(isFirstLaunch: false)
                            .environmentObject(appState)
                    }
            }
        }
    }
}
