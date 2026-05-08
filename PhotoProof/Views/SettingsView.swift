// SettingsView.swift
// Configure the Immich server URL and API key. Save is gated behind a
// successful Test Connection so the user never persists credentials that
// don't actually work.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool

    @State private var url: String = ""
    @State private var apiKey: String = ""
    @State private var hasExistingKey: Bool = false
    @State private var enteringNewKey: Bool = false
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case running
        case success(ImmichUser)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text("Immich Server URL")
                    .font(.headline)
                TextField("https://immich.example.com", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onChange(of: url) { _, _ in invalidateTest() }
                Text("The base URL of your Immich server. A trailing /api or / is fine — we'll clean it up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.headline)
                if hasExistingKey && !enteringNewKey {
                    HStack {
                        Text("•••••••••• (saved in your keychain)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Replace key") {
                            enteringNewKey = true
                            apiKey = ""
                            invalidateTest()
                        }
                    }
                } else {
                    SecureField("API key from Immich → Account Settings → API Keys", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, _ in invalidateTest() }
                }
                requiredPermissionsHint
            }

            HStack(alignment: .center, spacing: 12) {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack(spacing: 6) {
                        if testState == .running {
                            ProgressView().controlSize(.small)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(!canTest || testState == .running)
                .keyboardShortcut("t", modifiers: .command)

                testStatusView
            }

            Spacer(minLength: 0)

            HStack {
                if !isFirstLaunch {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(isFirstLaunch ? "Get Started" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 380)
        .onAppear {
            url = appState.serverURL
            hasExistingKey = KeychainStore.shared.exists()
            enteringNewKey = !hasExistingKey
            if let user = appState.connectedUser, !appState.serverURL.isEmpty, hasExistingKey {
                testState = .success(ImmichUser(id: user.id, email: user.email, name: user.name))
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "server.rack")
                .font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(isFirstLaunch ? "Connect to Immich" : "Settings")
                    .font(.title2.bold())
                Text(isFirstLaunch
                     ? "Tell PhotoProof where your Immich library lives."
                     : "Update your Immich server connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var requiredPermissionsHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("When you create the key in Immich, grant these permissions:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(["user.read", "asset.read", "asset.upload"], id: \.self) { scope in
                    Text(scope)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text("These let PhotoProof read your account, check whether a photo is in Immich, and confirm it isn't in Immich's trash. PhotoProof never creates, modifies, or deletes anything in Immich.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle, .running:
            EmptyView()
        case .success(let user):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected as \(user.name.isEmpty ? user.email : user.name)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
        case .failed(let message):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canTest: Bool {
        guard ImmichClient.normalize(url) != nil else { return false }
        if enteringNewKey { return !apiKey.isEmpty }
        return hasExistingKey
    }

    private var canSave: Bool {
        if case .success = testState { return true }
        return false
    }

    private func invalidateTest() {
        switch testState {
        case .success, .failed: testState = .idle
        default: break
        }
    }

    private func testConnection() async {
        guard let normalized = ImmichClient.normalize(url) else {
            testState = .failed("That URL doesn't look right. It should be like https://immich.example.com.")
            return
        }
        let key: String
        if enteringNewKey {
            key = apiKey
        } else {
            do {
                key = try KeychainStore.shared.read()
            } catch {
                testState = .failed("Couldn't read the saved API key from your keychain.")
                return
            }
        }

        testState = .running
        let client = ImmichClient(baseURL: normalized, apiKey: key)
        do {
            let user = try await client.ping()
            testState = .success(user)
        } catch let immichError as ImmichError {
            testState = .failed(immichError.errorDescription ?? "Unknown error.")
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }

    private func save() {
        guard case .success(let user) = testState else { return }
        guard let normalized = ImmichClient.normalize(url) else { return }

        if enteringNewKey {
            do {
                try KeychainStore.shared.save(apiKey)
            } catch {
                testState = .failed("Couldn't save the API key: \(error.localizedDescription)")
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
