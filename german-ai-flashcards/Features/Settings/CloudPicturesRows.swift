import AuthenticationServices
import SwiftUI

/// The cloud half of Settings ▸ Model ▸ Image generation: which model draws, the learner's
/// OpenRouter connection, and what it has cost. Rows only, so it slots into the existing section.
struct CloudPicturesRows: View {
    @AppStorage(CloudImageModel.selectionDefaultsKey) private var selectedModel: CloudImageModel = .museImage
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var showingPasteKey = false
    @State private var confirmingDisconnect = false

    private var account: OpenRouterAccount { .shared }

    var body: some View {
        Picker("Picture model", selection: $selectedModel) {
            ForEach(CloudImageModel.allCases) { model in
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                    Text("\(model.maker) · \(model.approxCostLabel) a picture · about \(Int(model.typicalSeconds)) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(model)
            }
        }
        .pickerStyle(.inline)

        if selectedModel.needsAgeConfirmation, !selectedModel.hasDrawnBefore {
            ageConfirmationRow(for: selectedModel)
        }

        if account.isConnected {
            connectedRows
        } else {
            signInRows
        }

        if account.isWorking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking with OpenRouter…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let error = account.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Rows

    /// Muse is the cheap default and the one model with a step outside the app: OpenRouter won't
    /// serve it until the account owner ticks an 18+ box on its model page, once.
    private func ageConfirmationRow(for model: CloudImageModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("One-time step for \(model.displayName)", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.medium))
            Text("OpenRouter asks for an 18+ confirmation before it will draw with \(model.displayName). Open the model page, tick \u{201C}I confirm that I am 18 years of age or older\u{201D}, and tap Confirm. You only do this once per account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: model.openRouterPage) {
                Label("Open \(model.displayName) on OpenRouter", systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var connectedRows: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRouter connected")
                    .fontWeight(.medium)
                if let caption = usageCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let masked = account.maskedKey {
                    Text(masked)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .task { await account.refresh() }

        // OpenRouter only reports the account balance to management keys, not to the key the app
        // holds, so the balance lives on their page; the row above shows this key's own spend.
        Link(destination: URL(string: "https://openrouter.ai/settings/credits")!) {
            Label("Add credit on OpenRouter", systemImage: "creditcard")
        }

        Link(destination: URL(string: "https://openrouter.ai/keys")!) {
            Label("Spending limit and key on OpenRouter", systemImage: "arrow.up.right.square")
        }

        Button(role: .destructive) {
            confirmingDisconnect = true
        } label: {
            Label("Disconnect", systemImage: "xmark.circle")
        }
        .alert("Disconnect OpenRouter?", isPresented: $confirmingDisconnect) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) { account.disconnect() }
        } message: {
            Text("This phone forgets the key. It still works on OpenRouter until you delete it at openrouter.ai/keys. Pictures you already have stay.")
        }
    }

    @ViewBuilder
    private var signInRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cloud pictures use your own OpenRouter account. OpenRouter is a pay-as-you-go service for AI models: you add credit there, and each picture costs a cent or a few. This app never charges you.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)

        Button {
            Task {
                await account.signIn { url in
                    try await webAuthenticationSession.authenticate(
                        using: url,
                        callback: .customScheme(OpenRouterPKCE.callbackScheme),
                        preferredBrowserSession: nil,
                        additionalHeaderFields: [:]
                    )
                }
            }
        } label: {
            Label("Sign in with OpenRouter", systemImage: "person.crop.circle.badge.checkmark")
        }
        .disabled(account.isWorking)

        Button {
            showingPasteKey = true
        } label: {
            Label("Paste a key instead", systemImage: "key")
        }
        .disabled(account.isWorking)
        .sheet(isPresented: $showingPasteKey) {
            PasteOpenRouterKeySheet()
        }
    }

    /// "$0.23 spent · $99.77 left on this key", or just the spend when the key has no limit.
    private var usageCaption: String? {
        guard let info = account.keyInfo, let usage = info.usage else { return nil }
        let spent = Self.dollars(usage) + " spent"
        guard let left = info.limitRemaining else { return spent }
        return spent + " · " + Self.dollars(left) + " left on this key"
    }

    private static func dollars(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

// MARK: - Paste a key

/// The fallback when the sign-in page can't hand a key back: make a key at openrouter.ai/keys and
/// paste it. Checked with OpenRouter before it's saved.
private struct PasteOpenRouterKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    private var account: OpenRouterAccount { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-or-v1-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } footer: {
                    Text("Create a key at openrouter.ai/keys, copy it, and paste it here. It's kept in this phone's Keychain and only ever sent to OpenRouter.")
                }

                Section {
                    Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                        Label("Open openrouter.ai/keys", systemImage: "arrow.up.right.square")
                    }
                }

                if let error = account.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("OpenRouter key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if account.isWorking {
                        ProgressView()
                    } else {
                        Button("Connect") {
                            Task {
                                if await account.connect(apiKey: key) { dismiss() }
                            }
                        }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - Consent

/// Shown the first time the learner switches pictures to the cloud: what leaves the phone, where
/// it goes, and who pays. Nothing is sent until they say yes.
struct CloudPicturesConsentSheet: View {
    var onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    static let acceptedDefaultsKey = "cloudPictures.consentAccepted"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("The English meaning of each card you illustrate, the scene descriptions your tutor writes for a story's pictures, and a story's first picture so the later ones match.")
                    } icon: {
                        Image(systemName: "arrow.up.doc")
                    }
                } header: {
                    Text("What's sent")
                }

                Section {
                    Label {
                        Text("OpenRouter, which passes it to the picture model's maker: Meta for Muse Image, Google for Nano Banana.")
                    } icon: {
                        Image(systemName: "network")
                    }
                } header: {
                    Text("Where it goes")
                }

                Section {
                    Label {
                        Text("Your OpenRouter account, about 1 to 4 cents a picture. This app never charges you and never sees your payment details.")
                    } icon: {
                        Image(systemName: "creditcard")
                    }
                    Label {
                        Text("Your decks, chats, notes and progress stay on this phone.")
                    } icon: {
                        Image(systemName: "checkmark.shield")
                    }
                } header: {
                    Text("Who pays")
                }

                Section {
                    Button {
                        UserDefaults.standard.set(true, forKey: Self.acceptedDefaultsKey)
                        onAccept()
                        dismiss()
                    } label: {
                        Text("Use cloud pictures")
                            .frame(maxWidth: .infinity)
                    }
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .font(.subheadline)
            .navigationTitle("Draw pictures in the cloud?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
