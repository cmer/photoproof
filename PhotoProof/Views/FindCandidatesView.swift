// FindCandidatesView.swift
// Sheet that lets the user filter their Photos library by age + size +
// media type, review the matches in a thumbnail grid, and bundle the
// chosen items into a new album for verification. Read-only on Photos
// until the user clicks "Create album".

import SwiftUI
import AppKit

struct FindCandidatesView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called with the new album's localIdentifier on success so the parent
    /// can pre-select it in the main album picker.
    let onAlbumCreated: (String) -> Void

    // Filter — persisted across runs so the user doesn't re-enter every time.
    @AppStorage("PhotoProof.Find.MinAge")     private var minAge: Int = 3
    @AppStorage("PhotoProof.Find.AgeUnit")    private var ageUnitRaw: String = CandidateFilter.AgeUnit.years.rawValue
    @AppStorage("PhotoProof.Find.MinSize")    private var minSize: Int = 10
    @AppStorage("PhotoProof.Find.SizeUnit")   private var sizeUnitRaw: String = CandidateFilter.SizeUnit.megabytes.rawValue
    @AppStorage("PhotoProof.Find.MediaType")  private var mediaTypeRaw: String = CandidateFilter.MediaTypeFilter.all.rawValue
    @AppStorage("PhotoProof.Find.SkipFav")    private var skipFavorites: Bool = true
    @AppStorage("PhotoProof.Find.SkipHidden") private var skipHidden: Bool = true

    @State private var stage: Stage = .configuring
    @State private var candidates: [Candidate] = []
    @State private var deselected: Set<String> = []
    @State private var processed: Int = 0
    @State private var total: Int = 0
    @State private var albumName: String = defaultAlbumName()
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    enum Stage: Equatable {
        case configuring
        case searching
        case results
        case creating
        case done(albumName: String, count: Int, albumID: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Find photos to clean up").font(.title3.bold())
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch stage {
            case .configuring:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .searching:
                Button("Cancel") {
                    searchTask?.cancel()
                    stage = .configuring
                }
                .keyboardShortcut(.cancelAction)
            case .results:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .creating:
                EmptyView()
            case .done:
                Button("Done") {
                    if case .done(_, _, let albumID) = stage {
                        onAlbumCreated(albumID)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var headerSubtitle: String {
        switch stage {
        case .configuring:
            return "Search by age and size, then bundle the matches into an album."
        case .searching:
            return total > 0
                ? "Scanning library — \(processed) of \(total)…"
                : "Scanning library…"
        case .results:
            let selected = candidates.filter { !deselected.contains($0.id) }
            let bytes = selected.reduce(Int64(0)) { $0 + $1.totalSizeBytes }
            return "\(selected.count) of \(candidates.count) selected · \(formatBytes(bytes))"
        case .creating:
            return "Creating album in Photos…"
        case .done(let name, let count, _):
            return "Created “\(name)” with \(count) item\(count == 1 ? "" : "s")."
        }
    }

    // MARK: - Stages

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .configuring: configureView
        case .searching:   searchingView
        case .results:     resultsView
        case .creating:    creatingView
        case .done(_, let count, _): doneView(count: count)
        }
    }

    private var mediaType: CandidateFilter.MediaTypeFilter {
        CandidateFilter.MediaTypeFilter(rawValue: mediaTypeRaw) ?? .all
    }

    private var configureView: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Older than") {
                        HStack(spacing: 8) {
                            TextField("3", value: $minAge, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .onChange(of: minAge) { _, v in
                                    if v < 0 { minAge = 0 }
                                }
                            Picker("Age unit", selection: $ageUnitRaw) {
                                ForEach(CandidateFilter.AgeUnit.allCases) { u in
                                    Text(u.label).tag(u.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                        }
                    }
                    LabeledContent("Larger than") {
                        HStack(spacing: 8) {
                            TextField("10", value: $minSize, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .onChange(of: minSize) { _, v in
                                    if v < 0 { minSize = 0 }
                                }
                            Picker("Size unit", selection: $sizeUnitRaw) {
                                ForEach(CandidateFilter.SizeUnit.allCases) { u in
                                    Text(u.label).tag(u.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 110)
                        }
                    }
                    Picker("Media", selection: $mediaTypeRaw) {
                        ForEach(CandidateFilter.MediaTypeFilter.allCases) { t in
                            Text(t.label).tag(t.rawValue)
                        }
                    }
                }
                Section {
                    Toggle("Skip favorites", isOn: $skipFavorites)
                    Toggle("Skip hidden", isOn: $skipHidden)
                } footer: {
                    Text("PhotoProof only reads your library to find matches. Nothing is moved or modified until you create an album.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button {
                    runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: total > 0 ? Double(processed) / Double(total) : 0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 360)
            Text("Scanning \(processed) of \(total)…")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var resultsView: some View {
        if candidates.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No matches.")
                    .foregroundStyle(.secondary)
                Text("Try loosening the filters — a smaller minimum size or fewer years.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Edit filters") { stage = .configuring }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                CandidateGridView(
                    candidates: candidates,
                    deselected: $deselected
                )
                Divider()
                resultsFooter
            }
        }
    }

    private var resultsFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Edit filters") { stage = .configuring }
                Button("Select all") { deselected.removeAll() }
                    .disabled(deselected.isEmpty)
                Button("Deselect all") {
                    deselected = Set(candidates.map(\.id))
                }
                .disabled(deselected.count == candidates.count)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Album name")
                    .font(.headline)
                TextField("PhotoProof candidates", text: $albumName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Button {
                    Task { await createAlbum() }
                } label: {
                    Label(createButtonTitle, systemImage: "plus.rectangle.on.folder")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCandidates.isEmpty)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
    }

    private var createButtonTitle: String {
        let n = selectedCandidates.count
        return "Create album with \(n) item\(n == 1 ? "" : "s")"
    }

    private var creatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Creating album in Photos…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneView(count: Int) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Album created.")
                .font(.title2.bold())
            Text("\(count) item\(count == 1 ? "" : "s") added. Click Done to return to the main screen — the new album is already selected for verification.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private var selectedCandidates: [Candidate] {
        candidates.filter { !deselected.contains($0.id) }
    }

    private func runSearch() {
        error = nil
        candidates = []
        deselected = []
        processed = 0
        total = 0
        stage = .searching

        let ageUnit = CandidateFilter.AgeUnit(rawValue: ageUnitRaw) ?? .years
        let sizeUnit = CandidateFilter.SizeUnit(rawValue: sizeUnitRaw) ?? .megabytes
        let filter = CandidateFilter(
            minAge: minAge,
            ageUnit: ageUnit,
            minSize: minSize,
            sizeUnit: sizeUnit,
            mediaType: mediaType,
            skipFavorites: skipFavorites,
            skipHidden: skipHidden
        )

        searchTask?.cancel()
        searchTask = Task { @MainActor in
            let results = await CandidateSearch.search(filter: filter) { p, t in
                self.processed = p
                self.total = t
            }
            self.candidates = results.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
            self.stage = .results
        }
    }

    private func createAlbum() async {
        let chosen = selectedCandidates
        guard !chosen.isEmpty else { return }
        stage = .creating
        error = nil
        do {
            let id = try await CandidateAlbum.create(
                title: albumName,
                assetLocalIDs: chosen.map(\.id)
            )
            stage = .done(
                albumName: albumName.isEmpty ? "PhotoProof candidates" : albumName,
                count: chosen.count,
                albumID: id
            )
        } catch let e as CandidateAlbumError {
            error = e.errorDescription
            stage = .results
        } catch {
            self.error = error.localizedDescription
            stage = .results
        }
    }
}

// MARK: - Candidate grid

private struct CandidateGridView: View {
    let candidates: [Candidate]
    @Binding var deselected: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(candidates) { c in
                    CandidateCell(
                        candidate: c,
                        isSelected: !deselected.contains(c.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if deselected.contains(c.id) {
                            deselected.remove(c.id)
                        } else {
                            deselected.insert(c.id)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct CandidateCell: View {
    let candidate: Candidate
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    private let cellSize: CGFloat = 120

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Color.secondary.opacity(0.12)
                if let t = thumbnail {
                    Image(nsImage: t)
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
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.7))
                    .background(isSelected ? Color.white : Color.black.opacity(0.35))
                    .clipShape(Circle())
                    .padding(4)
            }
            .frame(width: cellSize, height: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )
            .opacity(isSelected ? 1.0 : 0.55)

            Text(candidate.displayFilename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: cellSize)

            HStack(spacing: 4) {
                Text(formatBytes(candidate.totalSizeBytes))
                if let date = candidate.creationDate {
                    Text("·")
                    Text(date, format: .dateTime.year())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: cellSize)
        }
        .task(id: candidate.id) {
            thumbnail = await AssetThumbnailer.shared.thumbnail(for: candidate.id, points: cellSize)
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

// MARK: - Helpers

private func defaultAlbumName() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return "PhotoProof – \(f.string(from: Date()))"
}

private func formatBytes(_ b: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}
