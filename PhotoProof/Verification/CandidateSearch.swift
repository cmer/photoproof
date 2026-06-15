// CandidateSearch.swift
// Finds Photos library assets matching a set of filters (age, size, media
// type) so the user can bundle them into a staging album for verification.
// Read-only: this never modifies anything in Photos. Album creation is
// handled separately in CandidateAlbum.

import Foundation
import Photos

struct CandidateFilter: Equatable, Sendable {
    var minAge: Int = 3
    var ageUnit: AgeUnit = .years
    var minSize: Int = 10
    var sizeUnit: SizeUnit = .megabytes
    var mediaType: MediaTypeFilter = .all
    var skipFavorites: Bool = true
    var skipHidden: Bool = true

    enum AgeUnit: String, CaseIterable, Identifiable, Sendable {
        case days, months, years
        var id: String { rawValue }
        var label: String {
            switch self {
            case .days: return "days"
            case .months: return "months"
            case .years: return "years"
            }
        }
        var calendarComponent: Calendar.Component {
            switch self {
            case .days: return .day
            case .months: return .month
            case .years: return .year
            }
        }
    }

    enum SizeUnit: String, CaseIterable, Identifiable, Sendable {
        case megabytes, gigabytes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .megabytes: return "MB"
            case .gigabytes: return "GB"
            }
        }
        var bytesPerUnit: Int64 {
            switch self {
            case .megabytes: return 1024 * 1024
            case .gigabytes: return 1024 * 1024 * 1024
            }
        }
    }

    enum MediaTypeFilter: String, CaseIterable, Identifiable, Sendable {
        case all, photos, videos
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Photos & Videos"
            case .photos: return "Photos only"
            case .videos: return "Videos only"
            }
        }
    }

    var minSizeBytes: Int64 {
        Int64(max(0, minSize)) * sizeUnit.bytesPerUnit
    }

    var cutoffDate: Date {
        Calendar.current.date(
            byAdding: ageUnit.calendarComponent,
            value: -max(0, minAge),
            to: Date()
        ) ?? .distantPast
    }
}

struct Candidate: Identifiable, Hashable, Sendable {
    let id: String          // PHAsset.localIdentifier
    let displayFilename: String
    let creationDate: Date?
    let kind: ScannedAsset.Kind
    let totalSizeBytes: Int64
}

enum CandidateSearch {

    /// The original-bytes resources we sum for the "larger than" check.
    /// Adjusted variants (.fullSize*) are deliberately ignored — they're
    /// derived from the original and aren't separately uploaded by Immich.
    private static let trackedTypes: Set<PHAssetResourceType> = [.photo, .video, .pairedVideo]

    /// Run the search. Reports `(processed, total)` so the caller can show a
    /// progress bar — the size lookup is per-asset so libraries with tens of
    /// thousands of assets take a few seconds.
    static func search(
        filter: CandidateFilter,
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async -> [Candidate] {
        let opts = PHFetchOptions()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "creationDate <= %@", filter.cutoffDate as CVarArg)
        ]
        if filter.skipFavorites {
            predicates.append(NSPredicate(format: "isFavorite == NO"))
        }
        if filter.skipHidden {
            predicates.append(NSPredicate(format: "isHidden == NO"))
        }
        opts.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets: PHFetchResult<PHAsset>
        switch filter.mediaType {
        case .all:    assets = PHAsset.fetchAssets(with: opts)
        case .photos: assets = PHAsset.fetchAssets(with: .image, options: opts)
        case .videos: assets = PHAsset.fetchAssets(with: .video, options: opts)
        }

        let total = assets.count
        await onProgress(0, total)

        var results: [Candidate] = []
        results.reserveCapacity(min(2000, total))

        for index in 0..<total {
            if Task.isCancelled { break }
            let asset = assets[index]

            let resources = PHAssetResource.assetResources(for: asset)
            var totalSize: Int64 = 0
            var primary: PHAssetResource?
            for r in resources {
                guard trackedTypes.contains(r.type) else { continue }
                if primary == nil, r.type == .photo || r.type == .video {
                    primary = r
                }
                if let size = AssetScanner.estimatedSize(of: r) {
                    totalSize += size
                }
            }

            let processed = index + 1
            if processed % 200 == 0 || processed == total {
                await onProgress(processed, total)
            }

            guard totalSize >= filter.minSizeBytes else { continue }

            results.append(Candidate(
                id: asset.localIdentifier,
                displayFilename: primary?.originalFilename ?? resources.first?.originalFilename ?? "Untitled",
                creationDate: asset.creationDate,
                kind: AssetScanner.kindFor(asset: asset),
                totalSizeBytes: totalSize
            ))
        }

        return results
    }
}

enum CandidateAlbumError: Error, LocalizedError {
    case createFailed(String)
    case noPlaceholder

    var errorDescription: String? {
        switch self {
        case .createFailed(let m): return "Couldn't create the album: \(m)"
        case .noPlaceholder: return "Photos didn't return a new album reference."
        }
    }
}

enum CandidateAlbum {
    /// Create a new user album with the given title and add the given assets.
    /// Returns the new album's local identifier so callers can start
    /// verification immediately and remember it for later.
    static func create(title: String, assetLocalIDs: [String]) async throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "PhotoProof candidates" : trimmed

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: assetLocalIDs, options: nil)
        var phAssets: [PHAsset] = []
        phAssets.reserveCapacity(fetch.count)
        fetch.enumerateObjects { a, _, _ in phAssets.append(a) }

        // The placeholder localIdentifier is what the new album will have
        // once the change finishes committing.
        var placeholderID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: finalTitle)
                placeholderID = req.placeholderForCreatedAssetCollection.localIdentifier
                if !phAssets.isEmpty {
                    req.addAssets(phAssets as NSArray)
                }
            }
        } catch {
            throw CandidateAlbumError.createFailed(error.localizedDescription)
        }

        guard let id = placeholderID else { throw CandidateAlbumError.noPlaceholder }
        return id
    }
}
