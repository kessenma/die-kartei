//
//  JournalTextEditor.swift
//  german-ai-flashcards
//
//  The keyboard half of the Schreiben room's editor: a full-height text view that asks for the
//  German or English keyboard (`LanguagePreferringTextView`, the chat composer's), with the
//  umlaut strip, the DE/EN switch and a way out of the keyboard underneath it. Autocorrect is
//  off by default: the point of the room is that the learner's own German gets checked, and an
//  English-locale autocorrect rewriting it first would hide exactly that. A Settings-free toggle
//  in the strip turns it on for someone who wants it.
//
//  On the Mac the field is a plain `TextEditor`: input sources are system-wide there, and the
//  Schreibhilfe covers umlauts.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct JournalTextEditor: View {
    @Binding var text: String
    let controller: ChatComposerController
    var placeholder: String = "Schreib los · Start writing"
    var accent: Color = SchreibenTile.tint
    /// "Nachschlagen" on the selection's edit menu (iOS).
    var onLookup: ((String) -> Void)? = nil

    @AppStorage("schreiben.language") private var languageRaw = ComposerLanguage.german.rawValue
    @AppStorage("schreiben.autocorrect") private var autocorrect = false
    @Environment(\.appTheme) private var appTheme

    private var language: ComposerLanguage {
        get { ComposerLanguage(rawValue: languageRaw) ?? .german }
        nonmutating set { languageRaw = newValue.rawValue }
    }

    var body: some View {
        #if canImport(UIKit)
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                JournalTextView(text: $text, language: language, autocorrect: autocorrect, controller: controller,
                                onLookup: onLookup)
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { controller.focus() }

            if controller.isFocused {
                strip
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: controller.isFocused)
        #else
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    #if canImport(UIKit)
    static let germanCharacters = ["ä", "ö", "ü", "ß", "Ä", "Ö", "Ü"]

    /// Umlauts on the left, the keyboard language and the way out on the right.
    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(Self.germanCharacters, id: \.self) { character in
                Button {
                    controller.insert(character)
                } label: {
                    Text(character)
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert \(character)")
            }

            Menu {
                Picker("Keyboard", selection: Binding(get: { language }, set: { language = $0; controller.reloadKeyboard() })) {
                    ForEach(ComposerLanguage.allCases) { lang in
                        Label(lang.spokenName, systemImage: lang.isInstalled ? "keyboard" : "keyboard.badge.ellipsis")
                            .tag(lang)
                    }
                }
                Toggle("Autocorrect", isOn: $autocorrect)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe").font(.caption2)
                    Text(language.shortLabel).font(.caption2.weight(.bold)).monospaced()
                }
                .foregroundStyle(language.isInstalled ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                .frame(width: 48, height: 30)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
            }
            .accessibilityLabel(language.spokenName)

            Button {
                controller.dismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 30)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide the keyboard")
        }
    }
    #endif
}

#if canImport(UIKit)

// MARK: - The text view

/// A scrolling, full-height `LanguagePreferringTextView`. Made with the plain initializer (TextKit
/// 1): the `usingTextLayoutManager:` initializer skips a subclass's init and leaves its stored
/// properties unset.
struct JournalTextView: UIViewRepresentable {
    @Binding var text: String
    var language: ComposerLanguage
    var autocorrect: Bool
    let controller: ChatComposerController
    var onLookup: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> LanguagePreferringTextView {
        let view = LanguagePreferringTextView()
        view.delegate = context.coordinator
        view.isEditable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 120, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.autocorrectionType = autocorrect ? .yes : .no
        view.spellCheckingType = .no          // German in an English-locale checker is all red
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.returnKeyType = .default
        view.preferredLanguagePrefix = language.primaryLanguagePrefix
        view.text = text
        controller.field = view
        return view
    }

    func updateUIView(_ view: LanguagePreferringTextView, context: Context) {
        if view.text != text { view.text = text }
        let prefix = language.primaryLanguagePrefix
        if view.preferredLanguagePrefix != prefix {
            view.preferredLanguagePrefix = prefix
            if view.isFirstResponder { view.reloadInputViews() }
        }
        let wanted: UITextAutocorrectionType = autocorrect ? .yes : .no
        if view.autocorrectionType != wanted {
            view.autocorrectionType = wanted
            if view.isFirstResponder { view.reloadInputViews() }
        }
        if controller.field !== view { controller.field = view }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: JournalTextView

        init(_ parent: JournalTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        /// "Nachschlagen" ahead of the system's actions on a short selection.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let onLookup = parent.onLookup, range.length > 0, range.length <= 40,
                  let text = textView.text, let swiftRange = Range(range, in: text) else { return nil }
            let selected = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty, !selected.contains("\n") else { return nil }
            let lookup = UIAction(title: "Nachschlagen", image: UIImage(systemName: "character.book.closed")) { _ in
                onLookup(selected)
            }
            return UIMenu(children: [UIMenu(title: "", options: .displayInline, children: [lookup])] + suggestedActions)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.controller.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.controller.isFocused = false
        }
    }
}

#endif
