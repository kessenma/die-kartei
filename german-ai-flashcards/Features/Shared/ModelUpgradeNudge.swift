import SwiftUI

/// "You're on a lesser tier; here's what the better one gives you, and here's the way there."
///
/// One component with three variants rather than three lookalikes, because that sentence is the
/// whole of what Home, the conversation setup and the flashcard options each needed to say. They
/// differ in the claim, not the shape.
///
/// Two rules every variant obeys:
///
/// * **Never pitch a download this device can't use.** Onboarding learned this the hard way — a
///   hard-wired hero meant a 4 GB phone was offered a 5 GB model it could never load — so a variant
///   that can't be satisfied here renders nothing at all.
/// * **Point somewhere real.** Before `SettingsRouter` existed, ten places in the app printed
///   "go to Settings → Model" as plain text with no way to get there. Every nudge here is a button.
struct ModelUpgradeNudge: View {
    enum Kind: String {
        /// Home. No tutor downloaded — either nothing at all, or Apple Intelligence only.
        case tutor
        /// Conversation setup, when the picked model is the built-in one.
        case chatQuality
        /// Wherever pictures are made, when the image model isn't on disk.
        case pictures
    }

    let kind: Kind

    /// Only Home passes this, so the card can become a progress line while a download runs. The
    /// other two sit on screens where a download is not the subject.
    var mlxService: MLXGenerationService?

    @Environment(\.appTheme) private var appTheme
    @Environment(\.scenePhase) private var scenePhase
    /// Optional so previews and any host that hasn't got one still render.
    @Environment(SettingsRouter.self) private var router: SettingsRouter?

    /// `MLXModel.isDownloaded` reads the filesystem and publishes nothing, so nothing here would
    /// ever notice a finished download. Bumping this re-reads it. Same trick `ModelSettingsView`
    /// uses with its `cacheRefreshID`.
    @State private var refreshID = UUID()

    /// Dismissed for good. The two in-feature nudges sit on screens people use daily, so they have
    /// to be silenceable; the Home card is not dismissible and has no key.
    @AppStorage private var dismissed: Bool

    init(kind: Kind, mlxService: MLXGenerationService? = nil) {
        self.kind = kind
        self.mlxService = mlxService
        _dismissed = AppStorage(wrappedValue: false, "nudge.\(kind.rawValue).dismissed")
    }

    private var readiness: ModelReadiness {
        _ = refreshID
        return ModelReadiness.current
    }

    var body: some View {
        if let content = content(for: readiness) {
            banner(content)
                .onAppear { refreshID = UUID() }
                .onChange(of: scenePhase) { refreshID = UUID() }
                .onChange(of: mlxService?.isLoading) { refreshID = UUID() }
        }
    }

    // MARK: - What to say

    private struct Content {
        var symbol: String
        var tint: Color
        var title: String
        var message: String
        var isDismissible: Bool
        /// Nil while a download is running: the card reports rather than asks.
        var action: String?
        /// Whether to draw the live bar and byte count under the message. Only the in-flight
        /// download sets it — this is the one state where the card's job is to be watched rather
        /// than read, and it is the card the learner lands on after starting a tutor.
        var showsProgress = false
    }

    private func content(for readiness: ModelReadiness) -> Content? {
        guard !dismissed else { return nil }
        switch kind {
        case .tutor:    return tutorContent(readiness)
        case .chatQuality: return chatContent(readiness)
        case .pictures: return picturesContent(readiness)
        }
    }

    private func tutorContent(_ readiness: ModelReadiness) -> Content? {
        // A download in flight outranks everything: the learner already said yes.
        if let mlxService, mlxService.isLoading {
            return Content(
                symbol: "arrow.down.circle.fill",
                tint: (mlxService.loadedModel ?? readiness.fittingTutor)?.theme.accent ?? .accentColor,
                title: "Your tutor is loading",
                message: mlxService.downloadInfo ?? "Downloading your teacher. You can keep using the app.",
                isDismissible: false,
                action: nil,
                showsProgress: true
            )
        }
        guard readiness.canOfferTutor, let tutor = readiness.offerableTutor else { return nil }
        let size = tutor.approximateSizeLabel

        if readiness.appleIntelligence {
            // The app works here, so this is an invitation, not a warning. Apple Intelligence is a
            // glimpse of the app rather than the app: flashcards and basic chat, no stories.
            return Content(
                symbol: "sparkles",
                tint: .blue,
                title: "Du nutzt Apple Intelligence",
                message: "Good for flashcards and basic chat. Stories need the German teacher, and "
                       + "conversations get much better with it. One download, ~\(size).",
                isDismissible: false,
                action: "See the teacher"
            )
        }
        return Content(
            symbol: "exclamationmark.triangle.fill",
            tint: .orange,
            title: "Kein Tutor geladen",
            message: "Drills and der · die · das work offline. Everything the AI writes — stories, "
                   + "conversations, flashcards — needs a teacher. One download, ~\(size).",
            isDismissible: false,
            action: "Get the teacher"
        )
    }

    private func chatContent(_ readiness: ModelReadiness) -> Content? {
        // Conversations are deliberately not gated on a tutor: someone who hasn't downloaded one
        // can still practise. This offers the upgrade rather than blocking the feature.
        guard readiness.canOfferTutor, let tutor = readiness.offerableTutor else { return nil }
        return Content(
            symbol: "wand.and.stars",
            tint: tutor.theme.accent,
            title: "Want more natural conversations?",
            message: "On-device Siri intelligence handles basic German well. For richer vocabulary "
                   + "and more natural phrasing, download one of the models fine-tuned for this app "
                   + "(~\(tutor.approximateSizeLabel)).",
            isDismissible: true,
            action: "See the models"
        )
    }

    private func picturesContent(_ readiness: ModelReadiness) -> Content? {
        guard !readiness.hasImageModel else { return nil }
        return Content(
            symbol: "photo.on.rectangle.angled",
            tint: .purple,
            title: "Add pictures to your cards",
            message: "An optional \(ImageGenModel.current.downloadSizeLabel) download draws a picture "
                   + "for each card, on your phone. Nothing is sent anywhere.",
            isDismissible: true,
            action: "Get the picture model"
        )
    }

    // MARK: - How it looks

    /// The live bar, and the bytes beneath it.
    ///
    /// The bar is drawn only once the fraction is real — same rule `ModelDownloadStrip` follows.
    /// A determinate bar pinned at zero while a download connects reads as a stall, which is
    /// exactly the wrong thing to tell someone who just committed to five gigabytes.
    @ViewBuilder private var progress: some View {
        if let mlxService, mlxService.isLoading {
            VStack(alignment: .leading, spacing: 3) {
                if let fraction = mlxService.downloadProgress, fraction > 0 {
                    ProgressView(value: fraction)
                        .controlSize(.mini)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
                if let bytes = mlxService.downloadBytesInfo {
                    Text(bytes)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 3)
        }
    }

    /// The `supersessionBanner` shape from Settings, so a notice reads the same wherever it turns
    /// up. `innerRadius` and not `cornerRadius`: the latter is the *card* token and would swallow a
    /// shape this small (Sanft's 20pt on a 10pt corner is a blob).
    private func banner(_ content: Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: content.symbol)
                .foregroundStyle(content.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(content.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if content.showsProgress {
                    progress
                }
                if let action = content.action {
                    Button(action) { router?.route = .model }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.borderless)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if content.isDismissible {
                Button {
                    withAnimation { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(10)
        .background(
            content.tint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10))
        )
    }
}
