// EmptyAlbumsView.swift
// Reviews empty user-created Photos albums and deletes an explicit selection.

import SwiftUI

struct EmptyAlbumsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var library = PhotoLibrary.shared

    @State private var selectedIDs: Set<String> = []
    @State private var isDeleting = false
    @State private var showingConfirmation = false
    @State private var result: DeletionResult?

    private var albums: [AlbumSummary] {
        library.emptyAlbums
    }

    private var selectedCount: Int {
        selectedIDs.intersection(Set(albums.map(\.id))).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 440)
        .task { await library.start() }
        .onChange(of: library.albums) { _, _ in
            selectedIDs.formIntersection(albums.map(\.id))
        }
        .alert(confirmationTitle, isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(deleteButtonTitle, role: .destructive) {
                Task { await deleteSelection() }
            }
        } message: {
            Text("This removes the selected albums from Photos and devices synchronized with iCloud Photos. No photos or videos will be deleted.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Empty Albums").font(.title3.bold())
                Text("Review user-created albums that contain no photos or videos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await library.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isDeleting || library.isLoading)
            .help("Refresh albums")
            .accessibilityLabel("Refresh albums")
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let result {
                resultBanner(result)
                Divider()
            }

            if library.isLoading && albums.isEmpty {
                ProgressView("Looking for empty albums…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if albums.isEmpty {
                emptyState
            } else {
                albumList
            }
        }
    }

    private var albumList: some View {
        VStack(spacing: 0) {
            HStack {
                Button(allAlbumsSelected ? "Deselect All" : "Select All") {
                    if allAlbumsSelected {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(albums.map(\.id))
                    }
                }
                .buttonStyle(.link)
                .disabled(isDeleting)

                Spacer()

                Text("\(selectedCount) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List(albums) { album in
                Toggle(isOn: selectionBinding(for: album.id)) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.secondary)
                        Text(album.title)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(isDeleting)
                .padding(.vertical, 3)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No empty albums found.")
                .font(.headline)
            Text("Only regular, user-created albums are included.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("Deleting an album does not delete its photos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isDeleting)

            Button {
                showingConfirmation = true
            } label: {
                if isDeleting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Deleting…")
                    }
                } else {
                    Text(deleteButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0 || isDeleting)
        }
        .padding(12)
    }

    private func resultBanner(_ result: DeletionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.deletedCount > 0 {
                Label(
                    "Deleted \(result.deletedCount) album\(result.deletedCount == 1 ? "" : "s").",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }

            ForEach(result.failures) { failure in
                Label {
                    Text("Skipped “\(failure.title)”: \(failure.message)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
    }

    private var allAlbumsSelected: Bool {
        !albums.isEmpty && selectedCount == albums.count
    }

    private var confirmationTitle: String {
        "Delete \(selectedCount) empty album\(selectedCount == 1 ? "" : "s")?"
    }

    private var deleteButtonTitle: String {
        "Delete \(selectedCount) Album\(selectedCount == 1 ? "" : "s")"
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }

    private func deleteSelection() async {
        let selectedAlbums = albums.filter { selectedIDs.contains($0.id) }
        guard !selectedAlbums.isEmpty else { return }

        isDeleting = true
        result = nil

        var deletedCount = 0
        var failures: [DeletionFailure] = []

        for album in selectedAlbums {
            do {
                try await PhotoAlbumManager.deleteEmptyAlbum(localIdentifier: album.id)
                deletedCount += 1
                selectedIDs.remove(album.id)
            } catch {
                failures.append(DeletionFailure(
                    id: album.id,
                    title: album.title,
                    message: error.localizedDescription
                ))
            }
        }

        result = DeletionResult(deletedCount: deletedCount, failures: failures)
        await library.reload()
        isDeleting = false
    }
}

private struct DeletionResult {
    let deletedCount: Int
    let failures: [DeletionFailure]
}

private struct DeletionFailure: Identifiable {
    let id: String
    let title: String
    let message: String
}
