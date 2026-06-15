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
        ZStack {
            PhotoProofBackdrop()

            VStack(spacing: 0) {
                header
                content
                    .padding(20)
                footer
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProofIcon(systemName: "clock.arrow.circlepath", size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verification History").font(.title2.bold())
                Text("Audit logs written before any item moves to Recently Deleted.")
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
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ProofIcon(systemName: "doc.text.magnifyingglass", color: .secondary, size: 56)
            Text("No audit logs yet")
                .font(.title3.bold())
            Text("PhotoProof saves a CSV here every time you move items to Recently Deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .proofSurface()
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
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
