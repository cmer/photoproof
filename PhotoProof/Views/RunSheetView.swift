// RunSheetView.swift
// Modal sheet that walks a VerificationRun through scanning → hashing →
// bulk-check → trash-check → completed, with three stage progress bars during
// the run and a Verified / Needs-Attention split once it's done.

import SwiftUI
import AppKit

struct RunSheetView: View {
    @ObservedObject var run: VerificationRun
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.album.title).font(.title3.bold())
                Text(headerSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            switch run.stage {
            case .scanning, .hashing, .checkingBulk, .checkingTrash:
                Button("Cancel", role: .cancel) { run.cancel() }
            case .completed, .cancelled, .error:
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(run.deleteState.isInProgress)
            }
        }
        .padding(16)
    }

    private var headerSubtitle: String {
        switch run.stage {
        case .scanning: return "Reading album…"
        case .hashing: return run.hashDetail
        case .checkingBulk: return "Checking Immich \(run.bulkCheckedCount) of \(run.bulkTotal)"
        case .checkingTrash: return "Verifying trash status \(run.trashCheckedCount) of \(run.trashTotal)"
        case .completed: return "\(run.verifiedAssets.count) verified · \(run.needsAttentionAssets.count) need attention"
        case .cancelled: return "Cancelled"
        case .error(let m): return m
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch run.stage {
        case .scanning:
            scanningView
        case .hashing, .checkingBulk, .checkingTrash:
            progressView
        case .completed:
            switch run.deleteState {
            case .finished(let count, let bytes, let logURL):
                DeleteSuccessView(run: run, count: count, bytes: bytes, logURL: logURL)
            case .deleting, .writingLog:
                deletingView
            default:
                ResultsView(run: run)
            }
        case .cancelled:
            cancelledView
        case .error(let m):
            errorView(m)
        }
    }

    private var deletingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(run.deleteState == .writingLog ? "Saving CSV log…" : "Deleting from MacOS Photos…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading album from Photos…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                StageProgress(
                    label: "Reading photos",
                    detail: run.hashDetail,
                    fraction: run.hashFraction,
                    state: state(for: .hashing)
                )
                StageProgress(
                    label: "Checking Immich",
                    detail: "\(run.bulkCheckedCount) of \(run.bulkTotal)",
                    fraction: run.bulkFraction,
                    state: state(for: .checkingBulk)
                )
                StageProgress(
                    label: "Verifying trash status",
                    detail: run.trashTotal == 0 ? "—" : "\(run.trashCheckedCount) of \(run.trashTotal)",
                    fraction: run.trashFraction,
                    state: state(for: .checkingTrash)
                )
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cancelledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Run cancelled.")
                .foregroundStyle(.secondary)
            Text("No photos were modified.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text(msg)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .foregroundStyle(.secondary)
            Text("No photos were modified.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func state(for active: VerificationRun.Stage) -> StageProgress.State {
        let order: [VerificationRun.Stage] = [.hashing, .checkingBulk, .checkingTrash]
        guard let activeIdx = order.firstIndex(of: active) else { return .pending }
        let currentIdx = order.firstIndex(of: run.stage) ?? order.count
        if currentIdx > activeIdx { return .done }
        if currentIdx == activeIdx { return .active }
        return .pending
    }
}

// MARK: - Stage progress

private struct StageProgress: View {
    enum State { case pending, active, done }

    let label: String
    let detail: String
    let fraction: Double
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusIcon
                Text(label).bold()
                Spacer()
                Text(detail)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: state == .done ? 1 : fraction)
                .progressViewStyle(.linear)
                .opacity(state == .pending ? 0.35 : 1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .active: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

// MARK: - Results view

private struct ResultsView: View {
    @ObservedObject var run: VerificationRun
    @State private var section: Section = .verified
    @State private var viewMode: ViewMode = .grid
    @State private var selectedID: String?
    @State private var exportError: String?
    @State private var previewError: String?
    @State private var showDeleteConfirmation: Bool = false

    enum Section: String, CaseIterable, Identifiable {
        case verified, attention
        var id: String { rawValue }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list, grid
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionBar
            Divider()
            list
            Divider()
            footer
        }
        .alert(
            "Delete \(run.verifiedAssets.count) item\(run.verifiedAssets.count == 1 ? "" : "s") from MacOS Photos?",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete from MacOS Photos", role: .destructive) {
                    Task { await run.deleteVerified() }
                }
            },
            message: {
                Text(deleteConfirmationMessage)
            }
        )
        .alert(
            "Couldn't complete the deletion",
            isPresented: deleteFailedBinding,
            actions: { Button("OK", role: .cancel) {} },
            message: {
                if case .failed(let m) = run.deleteState { Text(m) }
            }
        )
    }

    private var deleteFailedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = run.deleteState { return true }
                return false
            },
            set: { newValue in
                if !newValue {
                    Task { @MainActor in run.dismissDeleteError() }
                }
            }
        )
    }

    private var deleteConfirmationMessage: String {
        let verified = run.verifiedAssets
        let sample = verified.prefix(5).map(\.asset.displayFilename)
        let rest = verified.count - sample.count
        var lines = sample
        if rest > 0 {
            lines.append("…and \(rest) more")
        }
        let list = lines.joined(separator: "\n")
        return """
        \(list)

        Photos will keep them in Recently Deleted for 30 days. You can recover any of them from Photos → Recently Deleted before then.
        """
    }

    private var sectionBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $section) {
                Label("Verified  \(run.verifiedAssets.count)", systemImage: "checkmark.seal.fill")
                    .tag(Section.verified)
                Label("Needs attention  \(run.needsAttentionAssets.count)", systemImage: "exclamationmark.triangle.fill")
                    .tag(Section.attention)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer()

            Picker("View mode", selection: $viewMode) {
                Image(systemName: "list.bullet")
                    .accessibilityLabel("List view")
                    .tag(ViewMode.list)
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel("Grid view")
                    .tag(ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .help("Switch between list and grid view")
        }
        .padding(12)
        .onChange(of: section) { _, _ in selectedID = nil }
    }

    @ViewBuilder
    private var list: some View {
        let rows = section == .verified ? run.verifiedAssets : run.needsAttentionAssets
        if rows.isEmpty {
            emptyState
        } else if viewMode == .grid {
            AssetGridView(
                rows: rows,
                showReason: section == .attention,
                selection: $selectedID,
                onPreview: openQuickLook
            )
        } else if section == .verified {
            VerifiedTable(
                rows: rows,
                selection: $selectedID,
                onPreview: openQuickLook
            )
        } else {
            AttentionTable(
                rows: rows,
                selection: $selectedID,
                onPreview: openQuickLook
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: section == .verified ? "checkmark.seal" : "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(section == .verified
                 ? "Nothing was verified in this run."
                 : "Nothing needs attention — every item is in Immich.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let exportError {
                Label(exportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let previewError {
                Label(previewError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
                if section == .attention, !run.needsAttentionAssets.isEmpty {
                    Text("Re-upload these to Immich, then run PhotoProof again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Press space or double-click to preview.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await exportCSV() }
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.down")
                }
                .disabled(currentRows.isEmpty)

                if section == .verified {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label(deleteButtonTitle, systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(run.verifiedAssets.isEmpty)
                }
            }
        }
        .padding(12)
    }

    private var deleteButtonTitle: String {
        let n = run.verifiedAssets.count
        return "Delete \(n) from MacOS Photos"
    }

    private var currentRows: [AssetVerification] {
        section == .verified ? run.verifiedAssets : run.needsAttentionAssets
    }

    // MARK: - Actions

    private func openQuickLook(_ assetLocalID: String) {
        previewError = nil
        Task {
            do {
                let url = try await AssetExporter.shared.exportForPreview(assetLocalID: assetLocalID)
                QuickLookPresenter.shared.show(urls: [url])
            } catch let error as AssetExporterError {
                previewError = error.errorDescription
            } catch {
                previewError = "Couldn't open preview: \(error.localizedDescription)"
            }
        }
    }

    private func exportCSV() async {
        let suggested = section == .verified
            ? "photoproof-verified.csv"
            : "photoproof-needs-attention.csv"
        guard let url = await CSVExporter.promptForSaveURL(suggestedFilename: suggested) else { return }
        do {
            try CSVExporter.write(currentRows, to: url)
            exportError = nil
        } catch {
            exportError = "Couldn't write CSV: \(error.localizedDescription)"
        }
    }
}

// MARK: - Tables

private struct VerifiedTable: View {
    let rows: [AssetVerification]
    @Binding var selection: String?
    let onPreview: (String) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("File") { row in
                HStack(spacing: 8) {
                    Image(systemName: row.asset.kind.iconName)
                        .foregroundStyle(.secondary)
                    Text(row.asset.displayFilename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Kind") { row in
                Text(row.asset.kind.label).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Date") { row in
                Text(formatDate(row.asset.creationDate))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Size") { row in
                Text(formatSize(row.totalSizeBytes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 80)
        }
        .onKeyPress(.space) { triggerPreview() }
        .onKeyPress(.return) { triggerPreview() }
    }

    private func triggerPreview() -> KeyPress.Result {
        guard let id = selection else { return .ignored }
        onPreview(id)
        return .handled
    }
}

private struct AttentionTable: View {
    let rows: [AssetVerification]
    @Binding var selection: String?
    let onPreview: (String) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("File") { row in
                HStack(spacing: 8) {
                    Image(systemName: row.asset.kind.iconName)
                        .foregroundStyle(.secondary)
                    Text(row.asset.displayFilename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn("Date") { row in
                Text(formatDate(row.asset.creationDate))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Reason") { row in
                Text(row.attentionReasons.joined(separator: " · "))
                    .lineLimit(2)
                    .foregroundStyle(.red)
            }
        }
        .onKeyPress(.space) { triggerPreview() }
        .onKeyPress(.return) { triggerPreview() }
    }

    private func triggerPreview() -> KeyPress.Result {
        guard let id = selection else { return .ignored }
        onPreview(id)
        return .handled
    }
}

// MARK: - Grid

private struct AssetGridView: View {
    let rows: [AssetVerification]
    let showReason: Bool
    @Binding var selection: String?
    let onPreview: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    // Manual double-click detection. Using a paired (count:2 + count:1)
    // .onTapGesture forces SwiftUI to wait `NSEvent.doubleClickInterval` to
    // disambiguate, which feels laggy. Mirroring NSTableView's behaviour —
    // select on every click, promote a fast same-item second click to a
    // "preview" action — selection lands immediately.
    @State private var lastClickedID: String?
    @State private var lastClickAt = Date.distantPast

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(rows) { row in
                    AssetCell(
                        row: row,
                        showReason: showReason,
                        isSelected: selection == row.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { handleClick(row.id) }
                }
            }
            .padding(14)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { triggerPreview() }
        .onKeyPress(.return) { triggerPreview() }
    }

    private func handleClick(_ id: String) {
        let now = Date()
        if lastClickedID == id, now.timeIntervalSince(lastClickAt) < NSEvent.doubleClickInterval {
            onPreview(id)
            lastClickedID = nil
            lastClickAt = .distantPast
        } else {
            selection = id
            lastClickedID = id
            lastClickAt = now
        }
    }

    private func triggerPreview() -> KeyPress.Result {
        guard let id = selection else { return .ignored }
        onPreview(id)
        return .handled
    }
}

private struct AssetCell: View {
    let row: AssetVerification
    let showReason: Bool
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    private let cellSize: CGFloat = 112

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Color.secondary.opacity(0.12)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }

                if let badge = badgeIcon {
                    Image(systemName: badge)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            Text(row.asset.displayFilename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: cellSize)

            if showReason {
                Text(row.attentionReasons.first ?? "")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: cellSize)
            }
        }
        .task(id: row.id) {
            thumbnail = await AssetThumbnailer.shared.thumbnail(for: row.asset.id, points: cellSize)
        }
    }

    private var badgeIcon: String? {
        switch row.asset.kind {
        case .video: return "play.fill"
        case .livePhoto: return "livephoto"
        default: return nil
        }
    }
}

// MARK: - Delete success

private struct DeleteSuccessView: View {
    @ObservedObject var run: VerificationRun
    let count: Int
    let bytes: Int64
    let logURL: URL?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("\(count) item\(count == 1 ? "" : "s") moved to Recently Deleted")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if bytes > 0 {
                Text("Frees about \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) once Photos clears them out.")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            Text("Photos will permanently remove them in 30 days, or you can recover any of them from Photos → Recently Deleted before then.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)

            if let logURL {
                VStack(spacing: 4) {
                    Text("A CSV log of this run was saved to:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    } label: {
                        Label(logURL.lastPathComponent, systemImage: "doc.text")
                    }
                    .buttonStyle(.link)
                }
                .padding(.top, 4)
            }

            albumFollowUp

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var albumFollowUp: some View {
        switch run.albumDeleteState {
        case .idle:
            if run.albumIsEmpty {
                VStack(spacing: 10) {
                    Divider().frame(maxWidth: 360)
                    Text("The “\(run.album.title)” album is now empty.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Keep album") { run.dismissAlbumPrompt() }
                        Button {
                            Task { await run.deleteSourceAlbum() }
                        } label: {
                            Label("Delete album", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 8)
            }
        case .deleting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Deleting album…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        case .deleted:
            Label("Album “\(run.album.title)” deleted.", systemImage: "checkmark.seal.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .padding(.top, 8)
        case .failed(let m):
            Label("Couldn't delete album: \(m)", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 8)
        }
    }
}

// MARK: - Formatting

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

private func formatDate(_ d: Date?) -> String {
    guard let d else { return "—" }
    return dateFormatter.string(from: d)
}

private func formatSize(_ b: Int64) -> String {
    guard b > 0 else { return "—" }
    return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}

private extension ScannedAsset.Kind {
    var label: String {
        switch self {
        case .photo: return "Photo"
        case .livePhoto: return "Live Photo"
        case .video: return "Video"
        case .other: return "Other"
        }
    }
    var iconName: String {
        switch self {
        case .photo: return "photo"
        case .livePhoto: return "livephoto"
        case .video: return "video"
        case .other: return "doc"
        }
    }
}
