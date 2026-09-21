import SwiftUI
import UIKit

/// The keys themselves.
///
/// Built with gestures rather than `Button` because a keyboard needs things a button doesn't do:
/// output on touch *down*, a long-press that opens alternates and picks one by sliding, and a
/// backspace that repeats while held.
struct KeyboardKeysView: View {

    let onType: (String) -> Void
    let onBackspace: () -> Void
    let onGlobe: () -> Void
    let showsGlobe: Bool

    @State private var plane: Plane = .letters
    @State private var shift: ShiftState = .on   // sentences start capitalised
    @State private var alternatesFor: String?
    @State private var alternateIndex = 0
    @State private var repeatTask: Task<Void, Never>?

    /// Shift is a three-way control on every phone keyboard: off, on for one character, or locked.
    enum ShiftState { case off, on, locked }

    private let spacing: CGFloat = 5
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(KeyLayout.rows(for: plane).enumerated()), id: \.offset) { _, row in
                GeometryReader { geo in
                    HStack(spacing: spacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            keyView(key, width: width(for: key, in: row, total: geo.size.width))
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 3)
        .onDisappear { repeatTask?.cancel() }
    }

    /// Widths are shared out by weight, so a row always fills exactly and never drifts.
    private func width(for key: Key, in row: [Key], total: CGFloat) -> CGFloat {
        let gaps = CGFloat(row.count - 1) * spacing
        let unit = (total - gaps) / row.reduce(0) { $0 + CGFloat($1.weight) }
        return unit * CGFloat(key.weight)
    }

    // MARK: - One key

    @ViewBuilder
    private func keyView(_ key: Key, width: CGFloat) -> some View {
        switch key {
        case .character(let base):
            let character = shifted(base)
            characterKey(base: base, character: character, width: width)

        case .shift:
            furniture(
                width: width,
                active: shift != .off,
                action: { shift = (shift == .off) ? .on : .off },
                longPress: { shift = .locked }
            ) {
                Image(systemName: shift == .locked ? "capslock.fill" : "shift.fill")
                    .font(.system(size: 17))
            }

        case .backspace:
            furniture(
                width: width,
                action: { onBackspace() },
                longPress: { startRepeatingBackspace() }
            ) {
                Image(systemName: "delete.left").font(.system(size: 17))
            }

        case .plane(let target, let label):
            furniture(width: width, action: { plane = target }) {
                Text(label).font(.system(size: 15, weight: .medium))
            }

        case .globe:
            if showsGlobe {
                furniture(width: width, action: onGlobe) {
                    Image(systemName: "globe").font(.system(size: 17))
                }
            } else {
                Color.clear.frame(width: width)
            }

        case .space:
            furniture(
                width: width,
                background: Color(.systemBackground),
                action: { type(" ") }
            ) {
                Text("Deutsch").font(.system(size: 13)).foregroundStyle(.secondary)
            }

        case .return:
            furniture(width: width, action: { type("\n") }) {
                Image(systemName: "return").font(.system(size: 17))
            }
        }
    }

    /// A letter key. Touch-down types; a long press opens the alternates and a slide picks one.
    private func characterKey(base: String, character: String, width: CGFloat) -> some View {
        let alternates = KeyLayout.alternates[base.lowercased()] ?? []
        let isOpen = alternatesFor == base

        return Text(character)
            .font(.system(size: 22))
            .frame(width: width, height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
            )
            .overlay(alignment: .bottom) {
                if isOpen, !alternates.isEmpty {
                    alternatePopup(for: base, options: alternates)
                        .offset(y: -rowHeight - 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isOpen else { return }
                        // Slide across the popup to choose; each option is ~40pt wide.
                        let slot = Int((value.location.x + width / 2) / 40)
                        alternateIndex = min(max(slot, 0), alternates.count - 1)
                    }
                    .onEnded { _ in
                        if isOpen, !alternates.isEmpty {
                            type(shifted(alternates[alternateIndex], from: base))
                            alternatesFor = nil
                        } else {
                            type(character)
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    guard !alternates.isEmpty else { return }
                    alternateIndex = 0
                    alternatesFor = base
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
    }

    private func alternatePopup(for base: String, options: [String]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(shifted(option, from: base))
                    .font(.system(size: 20))
                    .frame(width: 38, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(index == alternateIndex ? Color.accentColor : Color(.systemBackground))
                    )
                    .foregroundStyle(index == alternateIndex ? Color.white : Color.primary)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .fixedSize()
    }

    /// Shift, space, return, plane switches — anything that isn't a letter.
    private func furniture(
        width: CGFloat,
        active: Bool = false,
        background: Color = Color(.secondarySystemBackground),
        action: @escaping () -> Void,
        longPress: (() -> Void)? = nil,
        @ViewBuilder label: () -> some View
    ) -> some View {
        label()
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: width, height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(active ? Color.accentColor : background)
            )
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in longPress?() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onEnded { _ in stopRepeating() }
            )
    }

    // MARK: - Behaviour

    private func type(_ text: String) {
        onType(text)
        // A one-shot shift falls away after the character it capitalised.
        if shift == .on { shift = .off }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func shifted(_ text: String, from base: String? = nil) -> String {
        guard shift != .off else { return text }
        // Only letters have a case; punctuation keys must not be touched by shift.
        guard (base ?? text).rangeOfCharacter(from: .letters) != nil else { return text }
        return text.uppercased()
    }

    /// Hold backspace to keep deleting: slow at first, then faster, like the system keyboard.
    private func startRepeatingBackspace() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            var interval = 120
            while !Task.isCancelled {
                onBackspace()
                try? await Task.sleep(for: .milliseconds(interval))
                interval = max(40, interval - 10)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
