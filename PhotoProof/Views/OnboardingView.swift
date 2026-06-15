// OnboardingView.swift
// First-launch introduction and Photos permission gate.

import SwiftUI
import Photos
import AppKit

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            PhotoProofBackdrop()

            HStack(spacing: 54) {
                intro
                permissionCard
            }
            .frame(maxWidth: 980)
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                PhotoProofStyle.heroGradient
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: PhotoProofStyle.accent.opacity(0.3), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Free space in\nApple Photos.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(-1)

                Text("PhotoProof finds photos and videos taking up space in Apple Photos, proves their originals are backed up in Immich, then moves only verified items to Photos' Recently Deleted.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingPromise(
                    icon: "externaldrive.badge.minus",
                    title: "Built for Photos storage",
                    detail: "Targets large Apple Photos items so your Mac and iCloud Photos library can shrink after deletion."
                )
                OnboardingPromise(
                    icon: "checkmark.seal",
                    title: "Immich backup required",
                    detail: "Every original photo, video, and Live Photo companion must already exist in Immich."
                )
                OnboardingPromise(
                    icon: "arrow.uturn.backward.circle",
                    title: "Recoverable by design",
                    detail: "Verified items first go to Photos' Recently Deleted album, where Apple's recovery window applies."
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProofPill(title: "STEP 1 OF 2", systemName: "photo.on.rectangle")

            VStack(alignment: .leading, spacing: 7) {
                Text("Connect Apple Photos")
                    .font(.title2.bold())
                Text("PhotoProof needs read/write access to inspect original Photos files, create cleanup albums, and move verified items to Recently Deleted. If iCloud Photos is enabled, Photos syncs that change through iCloud.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Label("Immich is read-only. Photos asks again before anything moves.", systemImage: "lock.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PhotoProofStyle.mint)

            switch appState.photosAuthorization {
            case .denied, .restricted:
                deniedSection
            case .notDetermined:
                Button {
                    Task { await appState.requestPhotosAccess() }
                } label: {
                    Label("Allow Photos access", systemImage: "arrow.right")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(PhotoProofStyle.accent)
                .keyboardShortcut(.defaultAction)
            default:
                ProgressView()
            }
        }
        .frame(width: 330, alignment: .leading)
        .proofSurface(padding: 26, cornerRadius: 22)
    }

    private var deniedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Photos access is currently blocked.", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(PhotoProofStyle.amber)
            Text("Enable access in System Settings, then return to PhotoProof.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Photos privacy settings") {
                openPhotosPrivacySettings()
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(PhotoProofStyle.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func openPhotosPrivacySettings() {
        let value = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        if let url = URL(string: value) {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct OnboardingPromise: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PhotoProofStyle.accent)
                .frame(width: 30, height: 30)
                .background(PhotoProofStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
