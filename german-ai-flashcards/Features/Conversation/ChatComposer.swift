import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Composer language

/// Which keyboard the composer asks for. German is the point of the app, but a learner reaching
/// for the "say it in German" flow — or writing a note to themselves — wants English without
/// hunting through the globe key.
enum ComposerLanguage: String, CaseIterable, Codable, Identifiable {
    case german
    case english

    var id: String { rawValue }

    /// The two-letter badge on the switch.
    var shortLabel: String {
        switch self {
        case .german:  "DE"
        case .english: "EN"
        }
    }

    var spokenName: String {
        switch self {
        case .german:  "German keyboard"
        case .english: "English keyboard"
        }
    }

    /// Prefix matched against `UITextInputMode.primaryLanguage`.
    var primaryLanguagePrefix: String {
        switch self {
        case .german:  "de"
        case .english: "en"
        }
    }

    var toggled: ComposerLanguage { self == .german ? .english : .german }

    #if canImport(UIKit)
    /// Whether the device actually has a keyboard for this language enabled. iOS can only be
    /// *asked* to prefer an input mode that exists — with none installed the switch would silently
    /// do nothing, so the UI hides it instead.
    @MainActor
    var isInstalled: Bool {
        UITextInputMode.activeInputModes.contains {
            $0.primaryLanguage?.hasPrefix(primaryLanguagePrefix) == true
        }
    }
    #else
    var isInstalled: Bool { false }
    #endif
}

// MARK: - Controller

/// A handle on the live composer field, so SwiftUI chrome around it (the umlaut strip, the
/// language switch) can type into it and swap its keyboard without owning the text.
@MainActor
@Observable
final class ChatComposerController {
    /// True while the field holds the keyboard — the umlaut strip only earns its space then.
    var isFocused = false

    #if canImport(UIKit)
    weak var field: UITextView?
    #endif

    /// Type a character at the cursor (not the end of the line), exactly as the keyboard would.
    func insert(_ text: String) {
        #if canImport(UIKit)
        field?.insertText(text)
        #endif
    }

    func focus() {
        #if canImport(UIKit)
        field?.becomeFirstResponder()
        #endif
    }

    /// Empty the field. Setting `text` programmatically doesn't call the delegate, so the change is
    /// replayed by hand — otherwise the binding and the measured height keep the old value.
    func clear() {
        #if canImport(UIKit)
        guard let field else { return }
        field.text = ""
        field.delegate?.textViewDidChange?(field)
        #endif
    }

    func dismissKeyboard() {
        #if canImport(UIKit)
        field?.resignFirstResponder()
        #endif
    }

    /// Re-ask iOS for the keyboard after the preferred language changes. A no-op unless the
    /// field is on screen and first responder.
    func reloadKeyboard() {
        #if canImport(UIKit)
        guard let field, field.isFirstResponder else { return }
        field.reloadInputViews()
        #endif
    }
}

#if canImport(UIKit)

// MARK: - Language-preferring text view

/// A `UITextView` that asks for a particular keyboard language. `textInputMode` is the only
/// supported way to express this: an app can prefer an installed input mode, never install one,
/// so this falls back to the system's choice when the language isn't enabled on the device.
final class LanguagePreferringTextView: UITextView {
    var preferredLanguagePrefix: String?

    override var textInputMode: UITextInputMode? {
        if let prefix = preferredLanguagePrefix,
           let match = UITextInputMode.activeInputModes.first(where: {
               $0.primaryLanguage?.hasPrefix(prefix) == true
           }) {
            return match
        }
        return super.textInputMode
    }
}

// MARK: - Representable

/// A growing multi-line text view. SwiftUI's `TextField` can't express a keyboard language, which
/// is the whole reason this drops to UIKit.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// Measured content height, so the row grows with the message and stops at `maxHeight`.
    @Binding var height: CGFloat
    var language: ComposerLanguage
    var maxHeight: CGFloat = 132
    let controller: ChatComposerController

    func makeUIView(context: Context) -> LanguagePreferringTextView {
        let view = LanguagePreferringTextView()
        view.delegate = context.coordinator
        view.isEditable = true
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false          // grow instead, until `maxHeight` turns it back on
        view.autocorrectionType = .yes
        view.spellCheckingType = .no          // German in an English-locale checker is all red
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.returnKeyType = .default
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        recalculate(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Measure the text and report the row height back, capped — past the cap the view scrolls.
    private func recalculate(_ view: LanguagePreferringTextView) {
        let width = view.bounds.width
        guard width > 0 else { return }
        let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let capped = min(max(fitted, 36), maxHeight)
        if view.isScrollEnabled != (fitted > maxHeight) {
            view.isScrollEnabled = fitted > maxHeight
        }
        guard abs(capped - height) > 0.5 else { return }
        DispatchQueue.main.async { self.height = capped }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: ComposerTextView

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            if let view = textView as? LanguagePreferringTextView { parent.recalculate(view) }
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

// MARK: - Composer

/// The typing counterpart to the mic: a growing field, a German/English keyboard switch, an
/// umlaut row for when neither keyboard has them, and a send button.
struct ChatComposer: View {
    @Binding var text: String
    @Binding var language: ComposerLanguage
    let controller: ChatComposerController
    /// Placeholder shown while the field is empty — the turn the learner is being asked for.
    let placeholder: String
    let accent: Color
    /// Whether a turn can be taken right now (the AI isn't mid-reply). The field stays editable
    /// either way — composing your next line while the tutor is still typing is the point of a chat.
    let canTakeTurn: Bool
    /// Raise the keyboard as soon as the composer appears — true when the learner just switched
    /// into typing mode, false when a chat simply opens in it.
    var focusOnAppear: Bool = false
    let onSend: () -> Void
    /// Hand the turn back to the microphone.
    let onSwitchToSpeaking: () -> Void

    @State private var fieldHeight: CGFloat = 36
    @Environment(\.appTheme) private var appTheme

    /// Characters an English keyboard hides behind a long-press. Cheap insurance either way:
    /// with a German keyboard installed they're simply a second route to the same letters.
    private static let germanCharacters = ["ä", "ö", "ü", "ß", "Ä", "Ö", "Ü"]

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSend: Bool { canTakeTurn && !trimmed.isEmpty }

    /// iOS can only be asked to prefer a keyboard that exists. When the chosen language has none
    /// installed the switch still flips (and the strip above still types umlauts), but the learner
    /// deserves to know why the keyboard didn't change.
    private var missingKeyboard: Bool { !language.isInstalled }

    var body: some View {
        VStack(spacing: 6) {
            if controller.isFocused || missingKeyboard {
                accessoryRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if missingKeyboard {
                Text("No \(language == .german ? "German" : "English") keyboard installed — add one in iOS Settings ▸ General ▸ Keyboards.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onSwitchToSpeaking) {
                    Image(systemName: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch to speaking")

                field

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(canSend ? AnyShapeStyle(accent) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                    in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: controller.isFocused)
        .animation(.easeInOut(duration: 0.2), value: language)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        .onAppear {
            guard focusOnAppear else { return }
            // The field is built during the same update pass; hop once so it exists to focus.
            DispatchQueue.main.async { controller.focus() }
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                #if canImport(UIKit)
                ComposerTextView(
                    text: $text,
                    height: $fieldHeight,
                    language: language,
                    controller: controller
                )
                .frame(height: fieldHeight)
                #else
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                #endif
            }

            if !text.isEmpty {
                Button {
                    controller.clear()
                    text = ""
                    // Clearing is an edit, not an exit — the keyboard stays up to write the next try.
                    controller.focus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        // A 13pt glyph is not a tappable target; the frame is what the thumb hits.
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear what you wrote")
                .transition(.opacity)
            }

            languageSwitch
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background {
            // Tapping the padding around the field focuses it too; the field itself is left to
            // handle its own taps, or the keyboard never comes up.
            RoundedRectangle(cornerRadius: appTheme.innerRadius(18), style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .onTapGesture { controller.focus() }
        }
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(18), style: .continuous))
    }

    /// One tap flips the keyboard between German and English.
    private var languageSwitch: some View {
        Button {
            language = language.toggled
            controller.reloadKeyboard()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.caption2)
                Text(language.shortLabel)
                    .font(.caption2.weight(.bold))
                    .monospaced()
            }
            .foregroundStyle(missingKeyboard ? AnyShapeStyle(.tertiary)
                             : language == .german ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityLabel(language.spokenName)
        .accessibilityHint("Switches the keyboard to \(language.toggled.spokenName).")
    }

    /// The keyboard accessory: umlauts on the left, and a dedicated way out of the keyboard on the
    /// right. Swipe-to-dismiss alone is too easy to miss — a button you can aim at is not.
    private var accessoryRow: some View {
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

            if controller.isFocused {
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
                .transition(.opacity)
            }
        }
    }
}
