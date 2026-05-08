// HistoryView.swift
// Window that lists past verification runs (CSV log files written before
// each delete). The intent is for the user to be able to convince
// themselves "yes, I really did verify those photos before deleting them"
// without leaving the app.

import SwiftUI
import AppKit

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [RunLogEntry] = []
    @State private var selectedID: RunLogEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 360)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verification History").font(.title3.bold())
                Text("CSV logs of each run, written before any deletion happens.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .accessibilityLabel("Refresh history")
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            emptyState
        } else {
            Table(entries, selection: $selectedID) {
                TableColumn("Date") { e in
                    Text(formatDate(e.timestamp))
                        .font(.callout.monospacedDigit())
                }
                .width(min: 150, ideal: 180)

                TableColumn("Album") { e in
                    Text(e.albumTitle).lineLimit(1).truncationMode(.middle)
                }
                .width(min: 180, ideal: 240)

                TableColumn("Size") { e in
                    Text(ByteCountFormatter.string(fromByteCount: e.fileSize, countStyle: .file))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No verification logs yet.")
                .foregroundStyle(.secondary)
            Text("PhotoProof saves a CSV here every time you move items to Recently Deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button {
                if let dir = RunLog.runsDirectory() {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            } label: {
                Label("Reveal folder in Finder", systemImage: "folder")
            }
            .disabled(RunLog.runsDirectory() == nil)

            Spacer()

            Button {
                openSelected()
            } label: {
                Label("Open CSV", systemImage: "doc.text")
            }
            .disabled(selectedURL == nil)

            Button {
                if let url = selectedURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Reveal", systemImage: "magnifyingglass")
            }
            .disabled(selectedURL == nil)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var selectedURL: URL? {
        guard let id = selectedID else { return nil }
        return entries.first(where: { $0.id == id })?.url
    }

    private func openSelected() {
        if let url = selectedURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        entries = RunLog.entries()
    }
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

private func formatDate(_ d: Date) -> String {
    dateFormatter.string(from: d)
}
