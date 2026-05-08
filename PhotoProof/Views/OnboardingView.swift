// OnboardingView.swift
// First-launch welcome screen and Photos library permission gate.

import SwiftUI
import Photos
import AppKit

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Welcome to PhotoProof")
                    .font(.largeTitle.bold())
                Text("PhotoProof verifies that your photos are backed up to Immich before you delete them. Pick an album in Photos, and PhotoProof will tell you which items are safe to remove.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
            }

            switch appState.photosAuthorization {
            case .denied, .restricted:
                deniedSection
            case .notDetermined:
                Button("Grant Photos Access") {
                    Task { await appState.requestPhotosAccess() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedSection: some View {
        VStack(spacing: 12) {
            Text("Photos access was denied.")
                .font(.headline)
            Text("PhotoProof needs read/write access to your Photos library so it can read photos for hashing and move verified items to Recently Deleted. Grant access in System Settings, then return here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            Button("Open System Settings → Privacy → Photos") {
                openPhotosPrivacySettings()
            }
            .controlSize(.large)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func openPhotosPrivacySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
