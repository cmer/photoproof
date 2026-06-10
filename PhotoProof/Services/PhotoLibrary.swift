// PhotoLibrary.swift
// Reads user-created albums via PhotoKit and republishes the list when the
// library changes (e.g. the user creates an album, drags photos in, etc.).

import Foundation
import Photos

@MainActor
final class PhotoLibrary: ObservableObject {
    static let shared = PhotoLibrary()

    @Published var albums: [AlbumSummary] = []
    @Published var isLoading: Bool = false

    private var observer: ChangeObserver?

    private init() {}

    var emptyAlbums: [AlbumSummary] {
        albums.filter { $0.isEmpty && $0.isDeletable }
    }

    var emptyAlbumCount: Int {
        emptyAlbums.count
    }

    func start() async {
        if observer == nil {
            let obs = ChangeObserver { [weak self] in
                Task { await self?.reload() }
            }
            PHPhotoLibrary.shared().register(obs)
            observer = obs
        }
        await reload()
    }

    func reload() async {
        isLoading = true
        let albums = await Task.detached(priority: .userInitiated) {
            Self.fetchUserAlbums()
        }.value
        self.albums = albums
        isLoading = false
    }

    /// Sorted alphabetically. Smart albums and shared albums are excluded by
    /// passing only `.album` / `.albumRegular` to PhotoKit.
    nonisolated private static func fetchUserAlbums() -> [AlbumSummary] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )

        var out: [AlbumSummary] = []
        out.reserveCapacity(collections.count)

        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            var photos = 0
            var videos = 0
            assets.enumerateObjects { asset, _, _ in
                switch asset.mediaType {
                case .image: photos += 1
                case .video: videos += 1
                default: break
                }
            }
            out.append(AlbumSummary(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled",
                photoCount: photos,
                videoCount: videos,
                assetCount: assets.count,
                isDeletable: collection.canPerform(.delete)
            ))
        }

        return out.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    let onChange: @Sendable () -> Void
    init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}
