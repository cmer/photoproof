// AppState.swift
// App-wide observable state: Photos authorization, server config, and the
// currently "connected" Immich user (saved after a successful Test Connection).

import Foundation
import Photos

@MainActor
final class AppState: ObservableObject {
    @Published var photosAuthorization: PHAuthorizationStatus
    @Published var serverURL: String
    @Published var connectedUser: ConnectedUser?
    @Published var showSettings: Bool = false
    @Published var showHistory: Bool = false
    @Published var defaultAlbumID: String?

    private static let serverURLKey = "PhotoProof.ImmichServerURL"
    private static let defaultAlbumKey = "PhotoProof.DefaultAlbumID"

    init() {
        self.photosAuthorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.serverURL = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""
        self.connectedUser = ConnectedUser.load()
        self.defaultAlbumID = UserDefaults.standard.string(forKey: Self.defaultAlbumKey)
    }

    func setDefaultAlbumID(_ id: String?) {
        defaultAlbumID = id
        if let id {
            UserDefaults.standard.set(id, forKey: Self.defaultAlbumKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultAlbumKey)
        }
    }

    var hasAPIKey: Bool { KeychainStore.shared.exists() }

    var isConfigured: Bool {
        !serverURL.isEmpty && connectedUser != nil && hasAPIKey
    }

    var photosAccessGranted: Bool {
        photosAuthorization == .authorized || photosAuthorization == .limited
    }

    func setServerURL(_ url: String) {
        serverURL = url
        UserDefaults.standard.set(url, forKey: Self.serverURLKey)
    }

    func setConnectedUser(_ user: ConnectedUser?) {
        connectedUser = user
        if let user {
            user.save()
        } else {
            ConnectedUser.clear()
        }
    }

    func requestPhotosAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.photosAuthorization = status
    }

    /// Build an Immich client from the saved server URL + the API key in the
    /// keychain. Throws if either is missing or unreadable.
    func makeImmichClient() throws -> ImmichClient {
        guard let url = ImmichClient.normalize(serverURL) else {
            throw ImmichError.invalidURL
        }
        let key = try KeychainStore.shared.read()
        return ImmichClient(baseURL: url, apiKey: key)
    }
}

struct ConnectedUser: Codable, Equatable {
    let id: String
    let email: String
    let name: String

    private static let storageKey = "PhotoProof.ImmichConnectedUser"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> ConnectedUser? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ConnectedUser.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
