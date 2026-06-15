// RunSheetView.swift
// Guided verification workspace with progress, safety results, preview,
// export, and the final move-to-Recently-Deleted action.

import SwiftUI
import AppKit

struct RunSheetView: View {
    @ObservedObject var run: VerificationRun
    var onClose: () -> Void

    var body: some View {
        ZStack {
            PhotoProofBackdrop()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ProofIcon(systemName: headerIcon, color: headerColor, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(run.stage == .completed ? "Verification complete" : "Verifying cleanup")
                        .font(.title2.bold())
                    if run.stage == .completed {
                        ProofPill(title: "IMMICH CHECKED", systemName: "checkmark.shield.fill", color: PhotoProofStyle.mint)
                    }
                }
                Text("\(run.album.title) · \(headerSubtitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
    }

    private var headerSubtitle: String {
        switch run.stage {
        case .scanning: return "Reading album…"
        case .hashing: return run.hashDetail
        case .checkingBulk: return "Checking Immich \(run.bulkCheckedCount) of \(run.bulkTotal)"
        case .checkingTrash: return "Verifying trash status \(run.trashCheckedCount) of \(run.trashTotal)"
        case .completed: return "\(run.verifiedAssets.count) safe · \(run.needsAttentionAssets.count) blocked"
        case .cancelled: return "Cancelled"
        case .error(let m): return m
        }
    }

    private var headerIcon: String {
        switch run.stage {
        case .completed: return "checkmark.shield.fill"
        case .cancelled: return "xmark"
        case .error: return "exclamationmark.triangle.fill"
        default: return "waveform.path.ecg"
        }
    }

    private var headerColor: Color {
        switch run.stage {
        case .completed: return PhotoProofStyle.mint
        case .cancelled: return .secondary
        case .error: return PhotoProofStyle.amber
        default: return PhotoProofStyle.accent
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
        VStack(spacing: 22) {
            ProgressView().controlSize(.large)
            VStack(spacing: 6) {
                Text(run.deleteState == .writingLog ? "Saving your audit log" : "Waiting for Photos")
                    .font(.title2.bold())
                Text(run.deleteState == .writingLog
                     ? "No assets move until this record is safely written."
                     : "Confirm the macOS prompt to move verified items to Recently Deleted.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 22) {
            ProgressView().controlSize(.large)
            VStack(spacing: 6) {
                Text("Reading original assets")
                    .font(.title2.bold())
                Text("PhotoProof is mapping every photo, video, and Live Photo resource in this album.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressView: some View {
        HStack(spacing: 34) {
            VerificationProgressRing(
                fraction: overallProgress,
                title: overallProgressTitle
            )

            VStack(spacing: 12) {
                StageProgress(
                    label: "Hash originals",
                    detail: run.hashDetail,
                    fraction: run.hashFraction,
                    state: state(for: .hashing),
                    systemName: "number"
                )
                StageProgress(
                    label: "Match in Immich",
                    detail: "\(run.bulkCheckedCount) of \(run.bulkTotal)",
                    fraction: run.bulkFraction,
                    state: state(for: .checkingBulk),
                    systemName: "server.rack"
                )
                StageProgress(
                    label: "Confirm not trashed",
                    detail: run.trashTotal == 0 ? "—" : "\(run.trashCheckedCount) of \(run.trashTotal)",
                    fraction: run.trashFraction,
                    state: state(for: .checkingTrash),
                    systemName: "trash.slash"
                )
            }
            .frame(maxWidth: 520)
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var overallProgress: Double {
        switch run.stage {
        case .hashing: return run.hashFraction * 0.55
        case .checkingBulk: return 0.55 + run.bulkFraction * 0.25
        case .checkingTrash: return 0.80 + run.trashFraction * 0.20
        case .completed: return 1
        default: return 0
        }
    }

    private var overallProgressTitle: String {
        switch run.stage {
        case .hashing: return "HASHING"
        case .checkingBulk: return "MATCHING"
        case .checkingTrash: return "CONFIRMING"
        default: return "PREPARING"
        }
    }
}

// MARK: - Stage progress

private struct VerificationProgressRing: View {
    let fraction: Double
    let title: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(PhotoProofStyle.accent.opacity(0.12), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    PhotoProofStyle.heroGradient,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 174, height: 174)
    }
}

private struct StageProgress: View {
    enum State { case pending, active, done }

    let label: String
    let detail: String
    let fraction: Double
    let state: State
    let systemName: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.12))
                statusIcon
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label).bold()
                    Spacer()
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: state == .done ? 1 : fraction)
                    .progressViewStyle(.linear)
                    .tint(iconColor)
                    .opacity(state == .pending ? 0.30 : 1)
            }
        }
        .proofSurface(padding: 14, cornerRadius: 16)
        .opacity(state == .pending ? 0.68 : 1)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .pending: Image(systemName: systemName).foregroundStyle(.secondary)
        case .active: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark").foregroundStyle(PhotoProofStyle.mint)
        }
    }

    private var iconColor: Color {
        switch state {
        case .pending: return .secondary
        case .active: return PhotoProofStyle.accent
        case .done: return PhotoProofStyle.mint
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
            resultSummary
            sectionBar
            list
            footer
        }
        .alert(
            "Move \(run.verifiedAssets.count) item\(run.verifiedAssets.count == 1 ? "" : "s") to Recently Deleted?",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Move to Recently Deleted", role: .destructive) {
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

    private var resultSummary: some View {
        HStack(spacing: 14) {
            ResultMetric(
                value: "\(run.verifiedAssets.count)",
                label: "Safe to remove",
                systemName: "checkmark.shield.fill",
                color: PhotoProofStyle.mint
            )
            ResultMetric(
                value: "\(run.needsAttentionAssets.count)",
                label: "Kept in Photos",
                systemName: "exclamationmark.triangle.fill",
                color: PhotoProofStyle.amber
            )
            ResultMetric(
                value: formatSize(run.verifiedAssets.reduce(0) { $0 + $1.totalSizeBytes }),
                label: "Recoverable space",
                systemName: "internaldrive",
                color: PhotoProofStyle.accent
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
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
                Label("Safe to remove  \(run.verifiedAssets.count)", systemImage: "checkmark.seal.fill")
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .onChange(of: section) { _, _ in selectedID = nil }
    }

    private var list: some View {
        let rows = section == .verified ? run.verifiedAssets : run.needsAttentionAssets
        return Group {
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: section == .verified ? "checkmark.seal" : "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(section == .verified ? PhotoProofStyle.accent : PhotoProofStyle.mint)
            Text(section == .verified
                 ? "No items are safe to remove."
                 : "Everything is safely backed up.")
                .font(.headline)
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
                    Label("These items stay in Photos.", systemImage: "lock.fill")
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
                            .font(.headline)
                            .padding(.horizontal, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(run.verifiedAssets.isEmpty)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var deleteButtonTitle: String {
        let n = run.verifiedAssets.count
        return "Move \(n) to Recently Deleted"
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

private struct ResultMetric: View {
    let value: String
    let label: String
    let systemName: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ProofIcon(systemName: systemName, color: color, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .proofSurface(padding: 14, cornerRadius: 16)
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
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(PhotoProofStyle.mint.opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(PhotoProofStyle.mint)
            }

            Text("\(count) item\(count == 1 ? "" : "s") moved to Recently Deleted")
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)

            if bytes > 0 {
                ProofPill(
                    title: "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) recoverable",
                    systemName: "internaldrive",
                    color: PhotoProofStyle.mint
                )
            }

            Text("They remain recoverable in Photos for 30 days. Items that did not pass verification were left exactly where they were.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)

            if let logURL {
                VStack(spacing: 4) {
                    Text("Audit log saved")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    } label: {
                        Label(logURL.lastPathComponent, systemImage: "doc.text")
                    }
                    .buttonStyle(.link)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                        .tint(.red)
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
