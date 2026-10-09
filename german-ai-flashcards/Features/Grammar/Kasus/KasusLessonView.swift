//
//  KasusLessonView.swift
//  german-ai-flashcards
//
//  Verstehen · Lektion: a unit's lesson as paged cards (`KasusLesson.cards`), presented as a
//  sheet like the Kasus-Check. One card at a time with Zurück / Weiter and a row of dots, drawn
//  by hand so it reads the same on the Mac. Each German example has its English twin under it,
//  phrases in their case colors; the worked example lists the Kasus-Check steps that decide each
//  phrase; the last card carries a Merkhilfe and „Üben · Practice: Rollen“.
//
//  `onRead` fires once, when the last card is first shown, with the seconds spent; the presenter
//  records the lesson as read. `onPractice` asks the presenter to dismiss and launch Rollen (a
//  full-screen cover can't come up over a sheet, so the presenter does it on dismiss).
//

import SwiftUI

struct KasusLessonView: View {
    let unit: KasusUnit
    var onRead: (Int) -> Void = { _ in }
    var onPractice: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var page = Self.startPage

    /// `-kasus.debugLessonPage <n>` opens the lesson on that card (from 0), for screenshots.
    private static var startPage: Int {
        #if DEBUG
        max(0, UserDefaults.standard.integer(forKey: "kasus.debugLessonPage"))
        #else
        0
        #endif
    }
    @State private var startedAt = Date()
    @State private var reported = false

    private var cards: [KasusLessonCard] { KasusLesson.cards(for: unit) }

    var body: some View {
        let cards = self.cards
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if cards.indices.contains(page) {
                        card(cards[page], number: page + 1, of: cards.count)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                            .id(page)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                footer(cards.count)
            }
            .background(ThemedBackground().ignoresSafeArea())
            .kasusReference()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Lektion · \(unit.germanTitle)")
                            .font(.headline)
                        Text(unit.englishRole)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(.snappy(duration: 0.3), value: page)
            .onChange(of: page) { _, new in
                if new == cards.count - 1 { reportRead() }
            }
            .onAppear {
                if cards.count == 1 { reportRead() }
            }
        }
        .tint(appTheme.accent(model: nil))
    }

    private func reportRead() {
        guard !reported else { return }
        reported = true
        onRead(max(1, Int(Date().timeIntervalSince(startedAt))))
    }

    // MARK: - Card

    private func card(_ card: KasusLessonCard, number: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .themedLabel(.title2.weight(.bold), size: 22)
                Text(card.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if card.showsColorKey {
                colorKey
            }
            ForEach(card.lines, id: \.self) { line in
                Text(kasusRich: line)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let example = card.example {
                exampleBox(example)
            }
            if let mnemonic = card.mnemonic {
                KasusMnemonicCard(mnemonic: mnemonic)
            }
            if number == count {
                Text(KasusLesson.sourcesLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    /// The cases in play, each in its color: the key every card's colors follow.
    private var colorKey: some View {
        HStack(spacing: 14) {
            ForEach(unit.casesInPlay) { kasus in
                CaseLabel(kasus: kasus, style: .short)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func exampleBox(_ example: KasusLessonExample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scene = example.scene {
                KasusLessonSceneView(scene: scene)
            }
            Text(kasusRich: example.de)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(kasusRich: example.en)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !example.steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(example.steps, id: \.self) { step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(step.checkStep)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 14, alignment: .trailing)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("„\(step.phrase)“")
                                        .fontWeight(.semibold)
                                    CaseLabel(kasus: step.kasus, style: .short)
                                        .font(.caption.weight(.semibold))
                                }
                                Text(kasusRich: step.line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.surface.opacity(appTheme == .klar ? 0 : 0.6),
                    in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    // MARK: - Footer

    private func footer(_ count: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card \(page + 1) of \(count)")
            HStack(spacing: 10) {
                Button {
                    page = max(0, page - 1)
                } label: {
                    Label("Zurück", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(page == 0)
                if page < count - 1 {
                    Button {
                        page = min(count - 1, page + 1)
                    } label: {
                        Text("Weiter")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(action: onPractice) {
                        Text(KasusLesson.practiceLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            if appTheme == .klar {
                Rectangle().fill(.bar).ignoresSafeArea()
            } else {
                appTheme.surface.ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) { Divider() }
    }
}

/// Die Figur acting out a lesson sentence. A still first, and „Abspielen · Play“ swaps in the
/// live scene with its baked motion (the ball passed over, the sheet tapped). Live only on a
/// tap, and only on the card that's showing, so the lesson never holds more than one RealityKit
/// surface; with Reduce Motion the still stays.
struct KasusLessonSceneView: View {
    let scene: KasusLessonScene
    var height: CGFloat = 170

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var appTheme
    @State private var playing = Self.startsPlaying

    /// `-kasus.debugPlayScene 1` opens every lesson scene live, for a simulator that can't tap.
    private static var startsPlaying: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "kasus.debugPlayScene")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if playing {
                    // The canvas frames a whole preposition scene; drawn larger and clipped, the
                    // cast fills the box like the still does (a bigger canvas, not a scaled
                    // bitmap, so it stays sharp).
                    GeometryReader { geo in
                        PrepositionSceneView(word: scene.asset, mode: .resolved(Self.prepositionCase(scene.tint)))
                            .frame(width: geo.size.width * 1.6, height: geo.size.height * 1.6)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2 + geo.size.height * 0.08)
                    }
                } else if let image = PrepositionScene.image(for: scene.asset, state: "dat") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        // The renders leave a wide margin; the cast sits in the middle third.
                        .scaleEffect(1.5)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .accessibilityHidden(true)

            if !reduceMotion, PrepositionScene.pose(for: scene.asset)?.animates == true {
                Button {
                    playing.toggle()
                } label: {
                    Label(playing ? "Stopp" : "Abspielen · Play", systemImage: playing ? "stop.fill" : "play.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.tint.opacity(0.12), in: appTheme.pillShape)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(6)
            }
        }
        .background(Color.secondary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
    }

    /// The tint the scene's subject takes when it resolves.
    static func prepositionCase(_ kasus: GrammarCase) -> PrepositionCase {
        switch kasus {
        case .akkusativ:            .akkusativ
        case .genitiv:              .genitiv
        case .dativ, .nominativ:    .dativ
        }
    }
}

/// One memory aid as a small card: its hook, the line, and why it works.
struct KasusMnemonicCard: View {
    let mnemonic: KasusMnemonic

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let scene = mnemonic.scene {
                KasusLessonSceneView(scene: scene, height: 130)
            }
            Label {
                Text(mnemonic.title)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: mnemonic.symbol)
                    .foregroundStyle(.tint)
            }
            Text(kasusRich: mnemonic.line)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(kasusRich: mnemonic.why)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Lektion · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusLessonView(unit: .dativ)
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}

#Preview("Lektion · Nominativ") {
    KasusLessonView(unit: .nominativ)
}
