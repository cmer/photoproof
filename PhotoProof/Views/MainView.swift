// MainView.swift
// Album picker + summary card + Verify button. Once a verification run is
// kicked off, presents RunSheetView as a modal until the user dismisses it.

import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var library = PhotoLibrary.shared

    @State private var selectedAlbumID: String?
    @State private var run: VerificationRun?
    @State private var tipDismissed: Bool = UserDefaults.standard.bool(forKey: "PhotoProof.TipDismissed")
    @State private var showFindCandidates: Bool = false
    @State private var pendingAlbumIDFromCandidates: String?

    private var selectedAlbum: AlbumSummary? {
        guard let id = selectedAlbumID else { return nil }
        return library.albums.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            connectionHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !tipDismissed {
                        tipBanner
                    }

                    albumPickerSection

                    if let album = selectedAlbum {
                        summaryCard(album)
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }

            Divider()
            verifyBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await library.start() }
        .onChange(of: library.albums) { _, _ in
            // Drop a stale selection if the album disappeared.
            if let id = selectedAlbumID, !library.albums.contains(where: { $0.id == id }) {
                selectedAlbumID = nil
            }
            // If we just created a candidates album, select it once the
            // change observer has caught up.
            if let pending = pendingAlbumIDFromCandidates,
               library.albums.contains(where: { $0.id == pending }) {
                selectedAlbumID = pending
                pendingAlbumIDFromCandidates = nil
            }
            // Apply the remembered default album once the list has loaded.
            if selectedAlbumID == nil,
               let defaultID = appState.defaultAlbumID,
               library.albums.contains(where: { $0.id == defaultID }) {
                selectedAlbumID = defaultID
            }
        }
        .onChange(of: selectedAlbumID) { _, newValue in
            // Persist the user's pick so next launch lands on the same album.
            if let newValue {
                appState.setDefaultAlbumID(newValue)
            }
        }
        .sheet(item: $run, onDismiss: handleRunDismiss) { run in
            RunSheetView(run: run) { self.run = nil }
                .frame(minWidth: 640, minHeight: 480)
        }
        .sheet(isPresented: $showFindCandidates) {
            FindCandidatesView { newAlbumID in
                // The PhotoLibrary change observer fires when the new album
                // is committed; the .onChange handler above selects it then.
                pendingAlbumIDFromCandidates = newAlbumID
                Task { await library.reload() }
            }
        }
    }

    // MARK: - Header

    private var connectionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            if let user = appState.connectedUser {
                Text("Connected to Immich as ")
                    .foregroundStyle(.secondary)
                + Text(user.email).bold()
            }
            Spacer()
            Button {
                appState.showHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .help("Verification history (⌘Y)")
            .accessibilityLabel("Verification history")
            .keyboardShortcut("y", modifiers: .command)
            Button {
                appState.showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Tip

    private var tipBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("How it works")
                    .font(.headline)
                Text("Create an album in Photos (e.g. \u{201C}To Delete\u{201D}) and drag in any photos you'd like to remove. PhotoProof will check them against Immich and tell you which are safe to delete.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                tipDismissed = true
                UserDefaults.standard.set(true, forKey: "PhotoProof.TipDismissed")
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss tip")
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Album picker

    private var albumPickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Album")
                .font(.headline)

            HStack(spacing: 10) {
                if library.isLoading && library.albums.isEmpty {
                    ProgressView().controlSize(.small)
                    Text("Loading albums…").foregroundStyle(.secondary)
                } else if library.albums.isEmpty {
                    Text("No user-created albums found.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Album", selection: $selectedAlbumID) {
                        Text("Choose an album…").tag(String?.none)
                        ForEach(library.albums) { album in
                            Text("\(album.title) · \(album.totalCount)")
                                .tag(Optional(album.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)

                    Button {
                        Task { await library.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh albums")
                    .accessibilityLabel("Refresh albums")
                }
                Spacer()
            }

            Button {
                showFindCandidates = true
            } label: {
                Label("Find photos to clean up…", systemImage: "sparkle.magnifyingglass")
                    .font(.callout)
            }
            .buttonStyle(.link)
            .help("Filter your library by age and size, then bundle the matches into a new album.")
        }
    }

    // MARK: - Summary card

    private func summaryCard(_ album: AlbumSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.title3.bold())
                Text(formatCounts(album))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatCounts(_ album: AlbumSummary) -> String {
        var parts: [String] = []
        if album.photoCount > 0 {
            parts.append("\(album.photoCount) \(album.photoCount == 1 ? "photo" : "photos")")
        }
        if album.videoCount > 0 {
            parts.append("\(album.videoCount) \(album.videoCount == 1 ? "video" : "videos")")
        }
        if parts.isEmpty { return "Empty album" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Verify bar

    private var verifyBar: some View {
        HStack {
            Spacer()
            Button {
                startRun()
            } label: {
                Label("Verify", systemImage: "checkmark.seal")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(selectedAlbum == nil || (selectedAlbum?.totalCount ?? 0) == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func startRun() {
        guard let album = selectedAlbum, album.totalCount > 0 else { return }
        let newRun = VerificationRun(album: album, appState: appState)
        run = newRun
        newRun.start()
    }

    private func handleRunDismiss() {
        run?.cancel()
        run = nil
    }
}

extension VerificationRun: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
