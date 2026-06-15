// MainView.swift
// Cleanup dashboard that makes smart candidate search the primary workflow and
// keeps verification of an existing Photos album as a secondary action.

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var library = PhotoLibrary.shared

    @State private var selectedAlbumID: String?
    @State private var run: VerificationRun?
    @State private var showFindCandidates = false
    @State private var showExistingAlbum = false

    private var selectedAlbum: AlbumSummary? {
        guard let selectedAlbumID else { return nil }
        return verificationAlbums.first { $0.id == selectedAlbumID }
    }

    private var verificationAlbums: [AlbumSummary] {
        library.albums.filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            PhotoProofBackdrop()

            VStack(spacing: 0) {
                appBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        primaryAction
                        existingAlbumAction
                        safetyFooter
                    }
                    .frame(maxWidth: 980)
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await library.start() }
        .onChange(of: library.albums) { _, _ in reconcileAlbumSelection() }
        .onChange(of: selectedAlbumID) { _, newValue in
            if let newValue {
                appState.setDefaultAlbumID(newValue)
            }
        }
        .sheet(isPresented: $showFindCandidates) {
            FindCandidatesView { newAlbumID in
                appState.setDefaultAlbumID(newAlbumID)
                Task { await library.reload() }
            }
            .environmentObject(appState)
        }
        .sheet(item: $run, onDismiss: handleRunDismiss) { run in
            RunSheetView(run: run) { self.run = nil }
                .frame(minWidth: 760, minHeight: 600)
        }
    }

    private var appBar: some View {
        HStack(spacing: 12) {
            ZStack {
                PhotoProofStyle.heroGradient
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .shadow(color: PhotoProofStyle.accent.opacity(0.25), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text("PhotoProof")
                    .font(.headline)
                Text("Free space in Apple Photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let user = appState.connectedUser {
                ProofPill(
                    title: user.name.isEmpty ? user.email : user.name,
                    systemName: "checkmark.circle.fill",
                    color: PhotoProofStyle.mint
                )
                .help("Connected to Immich as \(user.email)")
            }

            HeaderIconControl(systemName: "clock.arrow.circlepath", label: "Verification history") {
                appState.showHistory = true
            }

            HeaderIconControl(systemName: "slider.horizontal.3", label: "Settings") {
                appState.showSettings = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Free up space in Apple Photos")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(-0.8)

            Text("Find large items, prove they're backed up in Immich, then remove them from Apple Photos and iCloud Photos.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 700, alignment: .leading)
        }
        .padding(.bottom, 2)
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                ProofIcon(systemName: "sparkle.magnifyingglass", color: PhotoProofStyle.accent, size: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a cleanup")
                        .font(.system(.title, design: .rounded, weight: .bold))

                    Text("Review matches first. PhotoProof creates the cleanup album automatically, then verifies what is safe to remove.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 680, alignment: .leading)
                }

                Spacer(minLength: 0)
            }

            Button {
                showFindCandidates = true
            } label: {
                Label("Find items to delete", systemImage: "arrow.right")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(PhotoProofStyle.accent)
            .keyboardShortcut(.defaultAction)
        }
        .proofSurface(padding: 24, cornerRadius: 24)
    }

    private var existingAlbumAction: some View {
        DisclosureGroup(isExpanded: $showExistingAlbum) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if library.isLoading && verificationAlbums.isEmpty {
                        ProgressView().controlSize(.small)
                        Text("Loading Photos albums...")
                            .foregroundStyle(.secondary)
                    } else if verificationAlbums.isEmpty {
                        Text("No albums with photos or videos found.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Photos album", selection: $selectedAlbumID) {
                            Text("Choose an album...").tag(String?.none)
                            ForEach(verificationAlbums) { album in
                                Text("\(album.title)  ·  \(album.totalCount) items")
                                    .tag(Optional(album.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 440)

                        if let selectedAlbum {
                            Text(selectedAlbumSummary(selectedAlbum))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await library.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(library.isLoading)
                    .help("Refresh albums")

                    Button {
                        startRun()
                    } label: {
                        Label("Verify album", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAlbum == nil)
                }

                if library.emptyAlbumCount > 0 {
                    Button {
                        appState.showEmptyAlbums = true
                    } label: {
                        Label(
                            "Review \(library.emptyAlbumCount) empty album\(library.emptyAlbumCount == 1 ? "" : "s")",
                            systemImage: "rectangle.stack.badge.minus"
                        )
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                ProofIcon(systemName: "rectangle.stack", color: .secondary, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Use an existing Photos album")
                        .font(.headline)
                    Text("For albums you already prepared.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .proofSurface(padding: 18)
    }

    private var safetyFooter: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(PhotoProofStyle.mint)
            Text("Only Immich-verified originals can be moved to Photos' Recently Deleted. Immich is never changed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func selectedAlbumSummary(_ album: AlbumSummary) -> String {
        var parts: [String] = []
        if album.photoCount > 0 { parts.append("\(album.photoCount) photos") }
        if album.videoCount > 0 { parts.append("\(album.videoCount) videos") }
        return parts.joined(separator: " · ")
    }

    private func reconcileAlbumSelection() {
        if let selectedAlbumID,
           !verificationAlbums.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
        if selectedAlbumID == nil,
           let defaultID = appState.defaultAlbumID,
           verificationAlbums.contains(where: { $0.id == defaultID }) {
            selectedAlbumID = defaultID
        }
    }

    private func startRun() {
        guard let selectedAlbum else { return }
        let newRun = VerificationRun(album: selectedAlbum, appState: appState)
        run = newRun
        newRun.start()
    }

    private func handleRunDismiss() {
        run?.cancel()
        run = nil
    }
}

private struct HeaderIconControl: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .help(label)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

extension VerificationRun: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
