// PhotoAlbumManager.swift
// Performs guarded mutations on regular user-created Photos albums.

import Foundation
import Photos

enum PhotoAlbumDeletionError: LocalizedError {
    case unavailable
    case notEmpty
    case notDeletable
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The album is no longer available."
        case .notEmpty:
            return "The album is no longer empty."
        case .notDeletable:
            return "Photos doesn't allow this album to be deleted."
        case .deletionFailed(let message):
            return message
        }
    }
}

enum PhotoAlbumManager {
    /// Re-fetch immediately before deletion so a stale UI cannot delete an
    /// album that has gained assets or is no longer editable.
    static func deleteEmptyAlbum(localIdentifier: String) async throws {
        let fetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let collection = fetch.firstObject else {
            throw PhotoAlbumDeletionError.unavailable
        }
        guard PHAsset.fetchAssets(in: collection, options: nil).count == 0 else {
            throw PhotoAlbumDeletionError.notEmpty
        }
        guard collection.canPerform(.delete) else {
            throw PhotoAlbumDeletionError.notDeletable
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSArray)
            }
        } catch {
            throw PhotoAlbumDeletionError.deletionFailed(error.localizedDescription)
        }
    }
}
