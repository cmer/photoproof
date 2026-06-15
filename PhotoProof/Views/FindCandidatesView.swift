// FindCandidatesView.swift
// Guided cleanup flow: configure a search, review matches, automatically create
// a staging album, and continue directly into safe Immich verification.

import SwiftUI
import AppKit

struct FindCandidatesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let onAlbumCreated: (String) -> Void

    @AppStorage("PhotoProof.Find.MinAge") private var minAge = 3
    @AppStorage("PhotoProof.Find.AgeUnit") private var ageUnitRaw = CandidateFilter.AgeUnit.years.rawValue
    @AppStorage("PhotoProof.Find.MinSize") private var minSize = 10
    @AppStorage("PhotoProof.Find.SizeUnit") private var sizeUnitRaw = CandidateFilter.SizeUnit.megabytes.rawValue
    @AppStorage("PhotoProof.Find.MediaType") private var mediaTypeRaw = CandidateFilter.MediaTypeFilter.all.rawValue
    @AppStorage("PhotoProof.Find.SkipFav") private var skipFavorites = true
    @AppStorage("PhotoProof.Find.SkipHidden") private var skipHidden = true

    @State private var stage: Stage = .configuring
    @State private var candidates: [Candidate] = []
    @State private var deselected: Set<String> = []
    @State private var processed = 0
    @State private var total = 0
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var verificationRun: VerificationRun?

    enum Stage {
        case configuring
        case searching
        case results
        case creating
    }

    var body: some View {
        ZStack {
            PhotoProofBackdrop()

            if let verificationRun {
                RunSheetView(run: verificationRun) {
                    dismiss()
                }
            } else {
                finder
            }
        }
        .frame(minWidth: 820, minHeight: 640)
        .onDisappear { searchTask?.cancel() }
    }

    private var finder: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch stage {
                case .configuring:
                    configureView
                case .searching:
                    searchingView
                case .results:
                    resultsView
                case .creating:
                    creatingView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ProofIcon(systemName: "sparkle.magnifyingglass", size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Cleanup")
                        .font(.title2.bold())
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(stage == .creating)
            }

            HStack(spacing: 0) {
                FinderStep(
                    title: "Find",
                    systemName: "line.3.horizontal.decrease.circle",
                    state: stepState(for: 0)
                )
                FinderStepLine(isComplete: stepIndex > 0)
                FinderStep(
                    title: "Review",
                    systemName: "square.grid.2x2",
                    state: stepState(for: 1)
                )
                FinderStepLine(isComplete: stepIndex > 1)
                FinderStep(
                    title: "Verify",
                    systemName: "checkmark.shield",
                    state: stepState(for: 2)
                )
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
    }

    private var headerSubtitle: String {
        switch stage {
        case .configuring:
            return "Set the guardrails for this cleanup."
        case .searching:
            return total > 0 ? "Scanning \(processed) of \(total) library items…" : "Reading your Photos library…"
        case .results:
            if candidates.isEmpty {
                return "No matches found"
            }
            return "\(selectedCandidates.count) selected · \(formatBytes(selectedBytes))"
        case .creating:
            return "Creating a Photos album and preparing verification…"
        }
    }

    private var stepIndex: Int {
        switch stage {
        case .configuring, .searching: return 0
        case .results: return 1
        case .creating: return 2
        }
    }

    private func stepState(for index: Int) -> FinderStep.State {
        if index < stepIndex { return .complete }
        if index == stepIndex { return .active }
        return .pending
    }

    private var configureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should PhotoProof look for?")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Broad filters find cleanup opportunities. You will review every match before anything is added to an album.")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    filterCard(
                        icon: "calendar.badge.clock",
                        color: PhotoProofStyle.accent,
                        title: "Older than"
                    ) {
                        HStack(spacing: 10) {
                            TextField("3", value: $minAge, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .frame(width: 70)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                                .onChange(of: minAge) { _, value in minAge = max(0, value) }

                            Picker("Age unit", selection: $ageUnitRaw) {
                                ForEach(CandidateFilter.AgeUnit.allCases) { unit in
                                    Text(unit.label.capitalized).tag(unit.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    filterCard(
                        icon: "externaldrive.badge.minus",
                        color: PhotoProofStyle.cyan,
                        title: "Larger than"
                    ) {
                        HStack(spacing: 10) {
                            TextField("10", value: $minSize, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .frame(width: 80)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                                .onChange(of: minSize) { _, value in minSize = max(0, value) }

                            Picker("Size unit", selection: $sizeUnitRaw) {
                                ForEach(CandidateFilter.SizeUnit.allCases) { unit in
                                    Text(unit.label).tag(unit.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    filterCard(
                        icon: "photo.on.rectangle.angled",
                        color: PhotoProofStyle.mint,
                        title: "Media"
                    ) {
                        Picker("Media", selection: $mediaTypeRaw) {
                            ForEach(CandidateFilter.MediaTypeFilter.allCases) { type in
                                Text(type.shortLabel).tag(type.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Protect special items")
                                .font(.headline)
                            Text("These are excluded from the search before results are shown.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProofPill(title: "RECOMMENDED", systemName: "lock.fill", color: PhotoProofStyle.mint)
                    }

                    HStack(spacing: 12) {
                        ProtectionToggle(
                            title: "Favorites",
                            detail: "Skip anything you starred",
                            systemName: "heart.fill",
                            color: .pink,
                            isOn: $skipFavorites
                        )
                        ProtectionToggle(
                            title: "Hidden",
                            detail: "Leave hidden items untouched",
                            systemName: "eye.slash.fill",
                            color: .purple,
                            isOn: $skipHidden
                        )
                    }
                }
                .proofSurface()

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                HStack {
                    Label("This scan is read-only.", systemImage: "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        runSearch()
                    } label: {
                        Label("Find cleanup candidates", systemImage: "magnifyingglass")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(PhotoProofStyle.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: 980)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private func filterCard<Content: View>(
        icon: String,
        color: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProofIcon(systemName: icon, color: color, size: 36)
                Text(title).font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proofSurface(padding: 18)
    }

    private var searchingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(PhotoProofStyle.accent.opacity(0.12), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: searchFraction)
                    .stroke(
                        PhotoProofStyle.heroGradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: searchFraction)
                VStack(spacing: 2) {
                    Text(total > 0 ? "\(Int(searchFraction * 100))%" : "…")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("SCANNED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 6) {
                Text("Finding your best cleanup opportunities")
                    .font(.title2.bold())
                Text(total > 0 ? "\(processed) of \(total) items checked" : "Preparing your library…")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button("Cancel scan") {
                searchTask?.cancel()
                stage = .configuring
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private var resultsView: some View {
        if candidates.isEmpty {
            VStack(spacing: 16) {
                ProofIcon(systemName: "checkmark", color: PhotoProofStyle.mint, size: 58)
                Text("No matches with these filters")
                    .font(.title2.bold())
                Text("Your library is already lean by this definition. Try a younger age or a smaller file size.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Button("Adjust filters") { stage = .configuring }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                resultToolbar
                CandidateGridView(candidates: candidates, deselected: $deselected)
                resultFooter
            }
        }
    }

    private var resultToolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(candidates.count) candidates found")
                    .font(.headline)
                Text("Click any item to keep it out of this cleanup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Adjust filters") { stage = .configuring }
            Button(deselected.isEmpty ? "Deselect all" : "Select all") {
                if deselected.isEmpty {
                    deselected = Set(candidates.map(\.id))
                } else {
                    deselected.removeAll()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var resultFooter: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(selectedCandidates.count) selected")
                    .font(.headline)
                Text("\(formatBytes(selectedBytes)) · album name generated automatically")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await createAlbumAndVerify() }
            } label: {
                Label("Create album & verify", systemImage: "checkmark.shield")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(PhotoProofStyle.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCandidates.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
    }

    private var creatingView: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("Building your cleanup album")
                    .font(.title2.bold())
                Text("Photos is collecting \(selectedCandidates.count) selected items. Verification starts next.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ProofPill(title: "ALBUM", systemName: "rectangle.stack.badge.plus", color: PhotoProofStyle.cyan)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                ProofPill(title: "VERIFY", systemName: "checkmark.shield", color: PhotoProofStyle.mint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var selectedCandidates: [Candidate] {
        candidates.filter { !deselected.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.totalSizeBytes }
    }

    private var searchFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(processed) / Double(total))
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func runSearch() {
        errorMessage = nil
        candidates = []
        deselected = []
        processed = 0
        total = 0
        stage = .searching

        let filter = CandidateFilter(
            minAge: minAge,
            ageUnit: CandidateFilter.AgeUnit(rawValue: ageUnitRaw) ?? .years,
            minSize: minSize,
            sizeUnit: CandidateFilter.SizeUnit(rawValue: sizeUnitRaw) ?? .megabytes,
            mediaType: CandidateFilter.MediaTypeFilter(rawValue: mediaTypeRaw) ?? .all,
            skipFavorites: skipFavorites,
            skipHidden: skipHidden
        )

        searchTask?.cancel()
        searchTask = Task { @MainActor in
            let results = await CandidateSearch.search(filter: filter) { processed, total in
                self.processed = processed
                self.total = total
            }
            guard !Task.isCancelled else { return }
            candidates = results.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
            stage = .results
        }
    }

    private func createAlbumAndVerify() async {
        let chosen = selectedCandidates
        guard !chosen.isEmpty else { return }

        stage = .creating
        errorMessage = nil
        let albumTitle = automaticAlbumName()

        do {
            let albumID = try await CandidateAlbum.create(
                title: albumTitle,
                assetLocalIDs: chosen.map(\.id)
            )
            onAlbumCreated(albumID)

            let photoCount = chosen.filter { $0.kind == .photo || $0.kind == .livePhoto }.count
            let videoCount = chosen.filter { $0.kind == .video }.count
            let album = AlbumSummary(
                id: albumID,
                title: albumTitle,
                photoCount: photoCount,
                videoCount: videoCount,
                assetCount: chosen.count,
                isDeletable: true
            )
            let run = VerificationRun(album: album, appState: appState)
            verificationRun = run
            run.start()
        } catch let error as CandidateAlbumError {
            errorMessage = error.errorDescription
            stage = .results
        } catch {
            errorMessage = error.localizedDescription
            stage = .results
        }
    }
}

private struct FinderStep: View {
    enum State {
        case pending
        case active
        case complete
    }

    let title: String
    let systemName: String
    let state: State

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state == .complete ? "checkmark" : systemName)
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .background(stepColor.opacity(0.13), in: Circle())
                .foregroundStyle(stepColor)
            Text(title)
                .font(.callout.weight(state == .active ? .bold : .medium))
                .foregroundStyle(state == .pending ? .secondary : .primary)
        }
    }

    private var stepColor: Color {
        switch state {
        case .pending: return .secondary
        case .active: return PhotoProofStyle.accent
        case .complete: return PhotoProofStyle.mint
        }
    }
}

private struct FinderStepLine: View {
    let isComplete: Bool

    var body: some View {
        Rectangle()
            .fill(isComplete ? PhotoProofStyle.mint.opacity(0.7) : Color.primary.opacity(0.10))
            .frame(height: 2)
            .frame(maxWidth: 90)
            .padding(.horizontal, 10)
    }
}

private struct ProtectionToggle: View {
    let title: String
    let detail: String
    let systemName: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.bold())
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CandidateGridView: View {
    let candidates: [Candidate]
    @Binding var deselected: Set<String>

    private let columns = Array(
        repeating: GridItem(.fixed(160), spacing: 14),
        count: 4
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(candidates) { candidate in
                    CandidateCell(
                        candidate: candidate,
                        isSelected: !deselected.contains(candidate.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if deselected.contains(candidate.id) {
                            deselected.remove(candidate.id)
                        } else {
                            deselected.insert(candidate.id)
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}

private struct CandidateCell: View {
    let candidate: Candidate
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Color.secondary.opacity(0.10)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }

                HStack(spacing: 5) {
                    if let badgeIcon {
                        Image(systemName: badgeIcon)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .font(.callout.bold())
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.42), in: Capsule())
                .padding(8)
            }
            .frame(width: 142, height: 138)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? PhotoProofStyle.accent : Color.clear, lineWidth: 3)
            }
            .opacity(isSelected ? 1 : 0.45)

            Text(candidate.displayFilename)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 142, alignment: .leading)

            HStack {
                Text(formatBytes(candidate.totalSizeBytes))
                    .fontWeight(.semibold)
                Spacer()
                if let date = candidate.creationDate {
                    Text(date, format: .dateTime.year())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 142)
        }
        .padding(9)
        .frame(width: 160)
        .background(
            isSelected ? PhotoProofStyle.accent.opacity(0.055) : Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 17)
        )
        .task(id: candidate.id) {
            thumbnail = await AssetThumbnailer.shared.thumbnail(for: candidate.id, points: 180)
        }
    }

    private var badgeIcon: String? {
        switch candidate.kind {
        case .video: return "play.fill"
        case .livePhoto: return "livephoto"
        default: return nil
        }
    }
}

private func automaticAlbumName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH.mm"
    return "PhotoProof Cleanup - \(formatter.string(from: Date()))"
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private extension CandidateFilter.MediaTypeFilter {
    var shortLabel: String {
        switch self {
        case .all: return "Photos & Videos"
        case .photos: return "Photos"
        case .videos: return "Videos"
        }
    }
}
