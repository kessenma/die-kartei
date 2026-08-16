import SwiftUI

/// A soft-sell wizard for the hero model (our in-house German-tuned Gemma 4 E4B). Reachable any
/// time from Settings → Model ("Why this model?"); on first launch the same pitch opens the
/// onboarding wizard instead (`OnboardingWizardView`). It never forces the download — "Maybe
/// later" keeps whatever instant model is already selected (typically Apple Intelligence).
struct HeroModelIntroSheet: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.dismiss) private var dismiss

    private var hero: MLXModel { .hero }
    private var heroDownloaded: Bool { hero.isDownloaded }

    var body: some View {
        NavigationStack {
            ScrollView {
                HeroModelPitchContent()
                    .padding()
                    .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .background { ModelSheetBackground(model: hero) }
            .navigationTitle("The model made for this app")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                useHero()
            } label: {
                Text(heroDownloaded ? "Use \(hero.rawValue)" : "Download \(hero.rawValue) (~\(hero.approximateSizeLabel))")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(hero.theme.accent)

            Button("Maybe later") { dismiss() }
                .font(.subheadline)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Actions

    /// Adopt the hero model as the card model and start loading it (downloads on first use). The
    /// load progress surfaces on Home and Settings via the shared loading panel.
    private func useHero() {
        modelManager.selectedMLXModel = hero
        dismiss()
        Task { await mlxService.loadModel(hero) }
    }
}

// MARK: - Shared pitch content

/// The hero pitch's body — logo chip, tagline, selling points, compatibility note — shared by the
/// standalone sheet above and the first page of `OnboardingWizardView`, so the two can't drift.
struct HeroModelPitchContent: View {
    /// Set this to the published article URL to reveal the "Read the story" link. While it's `nil`
    /// the link stays hidden — flip it on once the portfolio article is live.
    var articleURL: URL? = nil

    @Environment(\.appTheme) private var appTheme

    private var hero: MLXModel { .hero }

    var body: some View {
        VStack(spacing: 24) {
            header
            sellingPoints
            compatibilityNote
            if let articleURL {
                Link(destination: articleURL) {
                    Label("Read the story behind this model", systemImage: "book")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            // A frosted chip so the blue Gemma logo lifts off the blue brand wash behind it.
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle().strokeBorder(hero.theme.accent.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: hero.theme.accent.opacity(0.25), radius: 14, y: 6)
                hero.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)

            Text(hero.rawValue)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(hero.heroTagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sellingPoints: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(hero.heroSellingPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(hero.theme.accent)
                        .font(.body)
                    Text(point)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))
    }

    private var compatibilityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready for your device")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(hero.deviceNote). One-time ~\(hero.approximateSizeLabel) download, then it runs privately on-device, free and offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MLXModel {
    /// "~4.2 GB"-style label for the one-time download, shared by every hero pitch surface.
    var approximateSizeLabel: String {
        approximateSizeMB >= 1000
            ? String(format: "%.1f GB", Double(approximateSizeMB) / 1000.0)
            : "\(approximateSizeMB) MB"
    }
}
