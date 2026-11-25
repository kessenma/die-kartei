//
//  WorksheetItemsView.swift
//  german-ai-flashcards
//
//  One exercise page as controls: her instruction, then each item as its sentence with the blanks
//  and choices live. A blank whose answers the sheet names (dem / der / den, a word bank, A–E)
//  is a slot filled from the chip tray, by tap or by dragging a chip onto it; any other blank is a
//  text field (iPadOS Scribble turns Pencil writing into text there). Choices are a tap, the others
//  struck through as on paper. "Markiere" and "Unterstreiche" make the words tappable; "Notiere
//  den Fall" adds a case to each blank; sentence tasks get a line under the item.
//

import SwiftUI

struct WorksheetItemsView: View {
    @Bindable var session: WorksheetSession
    let exercise: WorksheetExercise
    /// The text field being typed in, by answer key; owned by the screen so the keyboard's
    /// umlaut row can reach it.
    var typing: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.displayTitle)
                    .font(.title3.weight(.semibold))
                if let instruction = exercise.instruction {
                    Text(instruction)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(exercise.sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if let heading = section.heading, exercise.sections.count > 1 {
                        Text("\(section.key.dropFirst()): \(heading)")
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(section.items) { item in
                        WorksheetItemRow(session: session, item: item, options: section.options, typing: typing)
                    }
                }
            }
            if !exercise.notes.isEmpty {
                Text(exercise.notes.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One item

struct WorksheetItemRow: View {
    @Bindable var session: WorksheetSession
    let item: WorksheetItem
    let options: WorksheetOptions?
    var typing: FocusState<String?>.Binding

    @Environment(\.appTheme) private var appTheme

    /// The item's segments cut at its line breaks, each line one flow.
    private var lines: [[WorksheetSegment]] {
        item.segments.split(omittingEmptySubsequences: false, whereSeparator: { $0 == .lineBreak }).map(Array.init)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.label.map { Int($0) != nil ? "\($0)." : $0 } ?? "")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, segments in
                    KasusWordFlow {
                        ForEach(Array(pieces(segments, lineIndex: lineIndex).enumerated()), id: \.offset) { _, piece in
                            pieceView(piece)
                        }
                    }
                }
                if item.writeBelow {
                    HStack(alignment: .top, spacing: 4) {
                        WorksheetSentenceField(session: session, item: item, typing: typing)
                        WorksheetCheckBadge(answer: session.answer(item.writeKey))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
    }

    // MARK: Pieces

    private enum Piece {
        case word(String, index: Int)
        case gap(WorksheetGap)
        case choice(WorksheetChoice)
    }

    /// Words numbered across the whole item, in the order `WorksheetItem.words` lists them, so a
    /// mark's index means the same word on screen and on the slide.
    private func pieces(_ segments: [WorksheetSegment], lineIndex: Int) -> [Piece] {
        var wordIndex = wordsBefore(line: lineIndex)
        var out: [Piece] = []
        for segment in segments {
            switch segment {
            case .text(let text, let range):
                let words = WorksheetText.words(in: text, base: range.location)
                // Punctuation rides on the word before it, as printed.
                let ns = text as NSString
                for (offset, word) in words.enumerated() {
                    let localEnd = word.range.upperBound - range.location
                    let nextStart = offset + 1 < words.count ? words[offset + 1].range.location - range.location : ns.length
                    let trailing = ns.substring(with: NSRange(location: localEnd, length: max(0, nextStart - localEnd)))
                        .trimmingCharacters(in: .whitespaces)
                    let leading = offset == 0
                        ? ns.substring(to: word.range.location - range.location).trimmingCharacters(in: .whitespaces)
                        : ""
                    out.append(.word(leading + word.text + trailing, index: wordIndex))
                    wordIndex += 1
                }
                if words.isEmpty, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append(.word(text.trimmingCharacters(in: .whitespaces), index: -1))
                }
            case .gap(let gap): out.append(.gap(gap))
            case .choice(let choice): out.append(.choice(choice))
            case .lineBreak: break
            }
        }
        return out
    }

    private func wordsBefore(line: Int) -> Int {
        lines.prefix(line).flatMap { $0 }.reduce(0) { count, segment in
            if case .text(let text, let range) = segment {
                return count + WorksheetText.words(in: text, base: range.location).count
            }
            return count
        }
    }

    @ViewBuilder
    private func pieceView(_ piece: Piece) -> some View {
        switch piece {
        case .word(let text, let index):
            wordChip(text, index: index)
        case .gap(let gap):
            HStack(spacing: 3) {
                if let options, !gap.isLong {
                    WorksheetGapSlot(session: session, gap: gap, options: options)
                } else {
                    WorksheetGapField(session: session, gap: gap, typing: typing)
                }
                if item.caseTag {
                    WorksheetCaseMenu(session: session, key: gap.key)
                }
                WorksheetCheckBadge(answer: session.answer(gap.key))
            }
        case .choice(let choice):
            HStack(spacing: 3) {
                WorksheetChoiceChips(session: session, choice: choice)
                WorksheetCheckBadge(answer: session.answer(choice.key), given: picked(choice))
            }
        }
    }

    private func picked(_ choice: WorksheetChoice) -> String? {
        guard let index = session.answer(choice.key)?.choice, choice.options.indices.contains(index) else { return nil }
        return choice.options[index].text
    }

    @ViewBuilder
    private func wordChip(_ text: String, index: Int) -> some View {
        if let marks = item.marks, index >= 0 {
            let marked = session.answer(item.markKey)?.marks?.contains(index) ?? false
            KasusChip(style: KasusChipStyle(
                wash: marked && marks == .highlight ? Color.yellow.opacity(0.45) : nil,
                underline: marked && marks == .underline ? Color.blue : nil
            ), action: {
                session.toggleMark(index, for: item.markKey)
            }) {
                Text(text)
            }
            .accessibilityAddTraits(marked ? .isSelected : [])
        } else {
            KasusChip { Text(text) }
        }
    }
}

// MARK: - The check's mark

/// ✓, ? or ✗ beside an answer the optional check looked at, with the expected form on a wrong
/// one. Nothing when unchecked, or when the answer changed since.
struct WorksheetCheckBadge: View {
    let answer: WorksheetAnswer?
    /// A choice's picked option; a blank's text is read from the answer.
    var given: String? = nil

    var body: some View {
        if let answer, let check = answer.check,
           (given ?? answer.text?.trimmingCharacters(in: .whitespacesAndNewlines)) == check.answer {
            HStack(spacing: 3) {
                Image(systemName: icon(check.outcome))
                    .foregroundStyle(color(check.outcome))
                if check.outcome == .wrong, let correction = check.correction {
                    Text(correction)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(check.outcome))
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label(check))
            .help(check.reason ?? "")
        }
    }

    private func icon(_ outcome: WorksheetCheck.Outcome) -> String {
        switch outcome {
        case .right: "checkmark.circle.fill"
        case .unsure: "questionmark.circle"
        case .wrong: "xmark.circle.fill"
        }
    }

    private func color(_ outcome: WorksheetCheck.Outcome) -> Color {
        switch outcome {
        case .right: .teal
        case .unsure: .secondary
        case .wrong: .orange
        }
    }

    private func label(_ check: WorksheetCheck) -> String {
        switch check.outcome {
        case .right: "Checked: right"
        case .unsure: "Checked: ask your teacher"
        case .wrong: "Checked: should be \(check.correction ?? "different")"
        }
    }
}

// MARK: - A blank with named answers

/// A slot the chip tray fills. Tap to aim the tray at it; drop a chip on it to fill it directly.
struct WorksheetGapSlot: View {
    @Bindable var session: WorksheetSession
    let gap: WorksheetGap
    let options: WorksheetOptions

    var body: some View {
        let text = session.answer(gap.key)?.text ?? ""
        let focused = session.focusedKey == gap.key
        KasusChip(style: KasusChipStyle(
            foreground: text.isEmpty ? .secondary : Color.blue,
            outline: text.isEmpty || focused ? Color.accentColor.opacity(focused ? 1 : 0.5) : nil,
            dashed: text.isEmpty,
            selected: focused
        ), action: {
            session.focusedKey = focused ? nil : gap.key
        }) {
            Text(text.isEmpty ? (gap.number.map { "(\($0)) ＿＿" } ?? "＿＿＿") : text)
                .fontWeight(text.isEmpty ? .regular : .semibold)
                .frame(minWidth: 44)
        }
        .dropDestination(for: String.self) { dropped, _ in
            guard let word = dropped.first else { return false }
            session.setText(word, for: gap.key)
            session.focusedKey = gap.key
            return true
        }
        .accessibilityLabel(text.isEmpty ? "Blank" : "Blank, \(text)")
        .accessibilityHint("Pick the word from the tray below")
    }
}

/// The tray under the page: the sheet's named answers for the focused blank.
struct WorksheetChipTray: View {
    @Bindable var session: WorksheetSession
    let exercise: WorksheetExercise

    @Environment(\.appTheme) private var appTheme

    private var focused: (gap: WorksheetGap, options: WorksheetOptions)? {
        guard let key = session.focusedKey else { return nil }
        for section in exercise.sections {
            guard let options = section.options else { continue }
            for item in section.items {
                if let gap = item.gaps.first(where: { $0.key == key }), !gap.isLong { return (gap, options) }
            }
        }
        return nil
    }

    /// Words a "use each once" bank has already given to other blanks.
    private var used: Set<String> {
        guard let focused, focused.options.usedOnce else { return [] }
        let keys = exercise.items.flatMap(\.gaps).map(\.key).filter { $0 != focused.gap.key }
        return Set(keys.compactMap { session.answer($0)?.text })
    }

    var body: some View {
        if let focused {
            VStack(alignment: .leading, spacing: 8) {
                if case .letters(let letters) = focused.options {
                    Text(letters.map { "\($0.letter) \($0.text)" }.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(focused.options.choices, id: \.self) { word in
                            let isUsed = used.contains(word)
                            Button {
                                session.setText(word, for: focused.gap.key)
                                advance(from: focused.gap.key)
                            } label: {
                                Text(word)
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Color.accentColor.opacity(isUsed ? 0.06 : 0.14),
                                                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                                    .opacity(isUsed ? 0.45 : 1)
                            }
                            .buttonStyle(.plain)
                            .draggable(word)
                        }
                        Button {
                            session.setText("", for: focused.gap.key)
                        } label: {
                            Image(systemName: "delete.left")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear this blank")
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    /// On to the next empty blank this tray can fill, so a page of articles is a run of taps.
    private func advance(from key: String) {
        let keys = exercise.sections.flatMap { section -> [String] in
            guard section.options != nil else { return [] }
            return section.items.flatMap(\.gaps).filter { !$0.isLong }.map(\.key)
        }
        guard let index = keys.firstIndex(of: key) else { return }
        let later = keys[(index + 1)...] + keys[..<index]
        session.focusedKey = later.first { (session.answer($0)?.text ?? "").isEmpty }
    }
}

// MARK: - A blank to type into

struct WorksheetGapField: View {
    @Bindable var session: WorksheetSession
    let gap: WorksheetGap
    var typing: FocusState<String?>.Binding

    var body: some View {
        TextField(gap.number.map { "(\($0))" } ?? "…", text: Binding(
            get: { session.answer(gap.key)?.text ?? "" },
            set: { session.setText($0, for: gap.key) }
        ))
        .focused(typing, equals: gap.key)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(Color.blue)
        .fontWeight(.semibold)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: gap.isLong ? 220 : 90)
        .fixedSize(horizontal: !gap.isLong, vertical: false)
        .background(alignment: .bottom) {
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
        }
        .submitLabel(.next)
    }
}

// MARK: - A choice

struct WorksheetChoiceChips: View {
    @Bindable var session: WorksheetSession
    let choice: WorksheetChoice

    var body: some View {
        let picked = session.answer(choice.key)?.choice
        HStack(spacing: 2) {
            ForEach(Array(choice.options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Text("/").foregroundStyle(.tertiary)
                }
                KasusChip(style: KasusChipStyle(
                    foreground: picked == index ? Color.blue : nil,
                    outline: picked == nil ? Color.accentColor.opacity(0.4) : (picked == index ? Color.blue : nil),
                    strikethrough: picked != nil && picked != index,
                    selected: false
                ), action: {
                    session.setChoice(index, for: choice.key)
                }) {
                    Text(option.text)
                        .strikethrough(picked != nil && picked != index)
                        .fontWeight(picked == index ? .semibold : .regular)
                }
                .accessibilityAddTraits(picked == index ? .isSelected : [])
            }
        }
    }
}

// MARK: - The case of a blank

struct WorksheetCaseMenu: View {
    @Bindable var session: WorksheetSession
    let key: String

    var body: some View {
        let kasus = session.answer(key)?.kasus
        Menu {
            ForEach(GrammarCase.allCases) { candidate in
                Button {
                    session.setCase(candidate, for: key)
                } label: {
                    Label(candidate.name, systemImage: kasus == candidate ? "checkmark" : candidate.symbol)
                }
            }
        } label: {
            Text(kasus?.short ?? "Fall?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(kasus.map(\.color) ?? .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background((kasus?.color ?? .secondary).opacity(0.12), in: Capsule())
        }
        .accessibilityLabel(kasus.map { "Case: \($0.name)" } ?? "Note the case")
    }
}

// MARK: - A sentence under the item

struct WorksheetSentenceField: View {
    @Bindable var session: WorksheetSession
    let item: WorksheetItem
    var typing: FocusState<String?>.Binding

    /// "Ich kaufe Brot für einen Salat." from "Ich / kaufe / Brot / für / ___ Salat." and the
    /// blank's answer: a start the learner edits, never the answer itself.
    private var startingPoint: String? {
        guard let chunks = item.chunks else { return nil }
        let filled = item.gaps.first.flatMap { session.answer($0.key)?.text } ?? "___"
        return chunks.joined(separator: " ").replacingOccurrences(of: "___", with: filled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Write the whole sentence", text: Binding(
                get: { session.answer(item.writeKey)?.text ?? "" },
                set: { session.setText($0, for: item.writeKey) }
            ), axis: .vertical)
            .focused(typing, equals: item.writeKey)
            .foregroundStyle(Color.blue)
            .lineLimit(1...4)
            .padding(.vertical, 6)
            .background(alignment: .bottom) {
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
            }
            if let startingPoint, (session.answer(item.writeKey)?.text ?? "").isEmpty {
                Button {
                    session.setText(startingPoint, for: item.writeKey)
                    typing.wrappedValue = item.writeKey
                } label: {
                    Label("Start from the words", systemImage: "text.insert")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
