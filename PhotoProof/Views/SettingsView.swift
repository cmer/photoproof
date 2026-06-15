// SettingsView.swift
// Configures and validates the read-only Immich connection before saving it.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool

    @State private var url = ""
    @State private var apiKey = ""
    @State private var hasExistingKey = false
    @State private var enteringNewKey = false
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case running
        case success(ImmichUser)
        case failed(String)
    }

    var body: some View {
        ZStack {
            PhotoProofBackdrop()

            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    serverCard
                    keyCard
                    connectionCard
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear(perform: loadCurrentSettings)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProofIcon(systemName: "server.rack", size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(isFirstLaunch ? "Connect to Immich" : "Immich Connection")
                    .font(.title2.bold())
                Text(isFirstLaunch
                     ? "The final setup step before your first cleanup."
                     : "Manage the server PhotoProof uses for verification.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isFirstLaunch, let user = appState.connectedUser {
                ProofPill(
                    title: user.name.isEmpty ? user.email : user.name,
                    systemName: "checkmark.circle.fill",
                    color: PhotoProofStyle.mint
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingTitle(
                icon: "network",
                title: "Server address",
                detail: "Your self-hosted Immich URL"
            )
            TextField("https://immich.example.com", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .disableAutocorrection(true)
                .onChange(of: url) { _, _ in invalidateTest() }
            Text("A trailing /api or slash is fine. PhotoProof normalizes it before connecting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .proofSurface(padding: 14, cornerRadius: 16)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingTitle(
                icon: "key.fill",
                title: "API key",
                detail: "Stored securely in your macOS Keychain"
            )

            if hasExistingKey && !enteringNewKey {
                HStack {
                    Label("Saved key", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(PhotoProofStyle.mint)
                    Spacer()
                    Button("Replace key") {
                        enteringNewKey = true
                        apiKey = ""
                        invalidateTest()
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                SecureField("Paste your Immich API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, _ in invalidateTest() }
            }

            HStack(spacing: 7) {
                Text("Required scopes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(["user.read", "asset.read", "asset.upload"], id: \.self) { scope in
                    Text(scope)
                        .font(.caption2.monospaced().weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(PhotoProofStyle.accent.opacity(0.10), in: Capsule())
                }
            }

            Text("These permissions read your account and check asset hashes. PhotoProof never creates, changes, or deletes anything in Immich.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .proofSurface(padding: 14, cornerRadius: 16)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                settingTitle(
                    icon: "bolt.horizontal.circle",
                    title: "Connection check",
                    detail: "Credentials must work before they can be saved"
                )
                Spacer()
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack(spacing: 7) {
                        if testState == .running {
                            ProgressView().controlSize(.small)
                        }
                        Text("Test connection")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(PhotoProofStyle.accent)
                .disabled(!canTest || testState == .running)
                .keyboardShortcut("t", modifiers: .command)
            }

            testStatusView
        }
        .proofSurface(padding: 14, cornerRadius: 16)
    }

    private func settingTitle(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            ProofIcon(systemName: icon, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            Label("Not tested yet", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .running:
            Text("Asking Immich for the connected user…")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .success(let user):
            Label(
                "Connected as \(user.name.isEmpty ? user.email : user.name)",
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(PhotoProofStyle.mint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PhotoProofStyle.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var footer: some View {
        HStack {
            if !isFirstLaunch {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Label("Step 2 of 2", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isFirstLaunch ? "Open PhotoProof" : "Save connection") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(PhotoProofStyle.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
    }

    private var canTest: Bool {
        guard ImmichClient.normalize(url) != nil else { return false }
        return enteringNewKey ? !apiKey.isEmpty : hasExistingKey
    }

    private var canSave: Bool {
        if case .success = testState { return true }
        return false
    }

    private func loadCurrentSettings() {
        url = appState.serverURL
        hasExistingKey = KeychainStore.shared.exists()
        enteringNewKey = !hasExistingKey
        if let user = appState.connectedUser, !appState.serverURL.isEmpty, hasExistingKey {
            testState = .success(ImmichUser(id: user.id, email: user.email, name: user.name))
        }
    }

    private func invalidateTest() {
        switch testState {
        case .success, .failed:
            testState = .idle
        default:
            break
        }
    }

    private func testConnection() async {
        guard let normalized = ImmichClient.normalize(url) else {
            testState = .failed("Enter a URL like https://immich.example.com.")
            return
        }

        let key: String
        if enteringNewKey {
            key = apiKey
        } else {
            do {
                key = try KeychainStore.shared.read()
            } catch {
                testState = .failed("PhotoProof could not read the saved key from Keychain.")
                return
            }
        }

        testState = .running
        let client = ImmichClient(baseURL: normalized, apiKey: key)
        do {
            testState = .success(try await client.ping())
        } catch let error as ImmichError {
            testState = .failed(error.errorDescription ?? "Immich returned an unknown error.")
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }

    private func save() {
        guard case .success(let user) = testState,
              let normalized = ImmichClient.normalize(url) else {
            return
        }

        if enteringNewKey {
            do {
                try KeychainStore.shared.save(apiKey)
            } catch {
                testState = .failed("Could not save the API key: \(error.localizedDescription)")
                return
            }
        }

        appState.setServerURL(normalized.absoluteString)
        appState.setConnectedUser(ConnectedUser(id: user.id, email: user.email, name: user.name))

        if !isFirstLaunch {
            dismiss()
        }
    }
}
