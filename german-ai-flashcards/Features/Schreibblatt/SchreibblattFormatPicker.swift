//
//  SchreibblattFormatPicker.swift
//  german-ai-flashcards
//
//  A sheet's shape, chosen with a picture of it: Hochformat, Querformat or Endlos, and for an
//  endless sheet how the tables sit (a list, two to four across, or one long row). The setup
//  screen uses it for a new sheet; a sheet's Format screen uses it to turn or rearrange one.
//
//  The pictures are drawn from a real `SchreibblattLayout` of the same word count and passes, so
//  what is shown is what will be built, never a sketch that drifts from it.
//

import SwiftUI

struct SchreibblattFormatPicker: View {
    @Binding var format: SchreibblattFormat
    let wordCount: Int
    let repetitions: Int
    var accent: Color = SchreibblattTile.tint

    private enum Kind: Hashable {
        case portrait, landscape, endless
    }

    private var kind: Binding<Kind> {
        Binding {
            if format.arrangement.isEndless { return .endless }
            return format.orientation == .portrait ? .portrait : .landscape
        } set: { kind in
            switch kind {
            case .portrait: format = SchreibblattFormat(orientation: .portrait, arrangement: .pages)
            case .landscape: format = SchreibblattFormat(orientation: .landscape, arrangement: .pages)
            case .endless:
                if !format.arrangement.isEndless { format.arrangement = .list }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Format", selection: kind) {
                Label("Hochformat", systemImage: "rectangle.portrait").tag(Kind.portrait)
                Label("Querformat", systemImage: "rectangle").tag(Kind.landscape)
                Label("Endlos", systemImage: "infinity").tag(Kind.endless)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if format.arrangement.isEndless {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(SchreibblattArrangement.endless) { arrangement in
                            arrangementOption(arrangement)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            SchreibblattFormatPreview(layout: layout(for: format), accent: accent)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.25), value: format)
                .accessibilityHidden(true)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func arrangementOption(_ arrangement: SchreibblattArrangement) -> some View {
        let chosen = format.arrangement == arrangement
        return Button {
            format.arrangement = arrangement
        } label: {
            VStack(spacing: 6) {
                SchreibblattFormatPreview(
                    layout: layout(for: SchreibblattFormat(orientation: format.orientation, arrangement: arrangement)),
                    accent: accent, compact: true)
                    .frame(width: 76, height: 50)
                Text(arrangement.title)
                    .font(.caption2.weight(chosen ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chosen ? accent.opacity(0.14) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(chosen ? accent : Color.secondary.opacity(0.25), lineWidth: chosen ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(arrangement.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func layout(for format: SchreibblattFormat) -> SchreibblattLayout {
        let words = max(1, wordCount)
        let placeholders = (0..<words).map { _ in SchreibblattWord(german: "", english: "") }
        return SchreibblattLayout(words: placeholders, repetitions: repetitions, prefillEnglish: true,
                                  paper: format.paper(wordCount: words, repetitions: repetitions))
    }

    private var caption: String {
        let sheet = layout(for: format)
        let tables = sheet.tables.count
        if format.arrangement.isEndless {
            return "One endless sheet, \(tables) tables \(format.arrangement == .row ? "in a row" : "in a grid"). "
                + "Written on the iPad only: endless sheets are not printed or shared."
        }
        let pages = sheet.pageCount == 1 ? "1 page" : "\(sheet.pageCount) pages"
        return format.orientation == .portrait
            ? "\(pages), the tables one under another."
            : "\(pages) on their side, the tables two by two."
    }
}

/// A sheet in miniature: the first page, or the whole endless sheet, with its tables. The Vorlage
/// is filled in, the writing tables are outlines.
struct SchreibblattFormatPreview: View {
    let layout: SchreibblattLayout
    var accent: Color = SchreibblattTile.tint
    var compact = false

    var body: some View {
        Canvas { context, size in
            let page = layout.pageCount > 0 ? layout.pageRect(0) : CGRect(origin: .zero, size: layout.paper.size)
            guard page.width > 0, page.height > 0 else { return }
            let inset: CGFloat = compact ? 2 : 8
            let scale = min((size.width - inset * 2) / page.width, (size.height - inset * 2) / page.height)
            let origin = CGPoint(x: (size.width - page.width * scale) / 2, y: (size.height - page.height * scale) / 2)
            func place(_ rect: CGRect) -> CGRect {
                CGRect(x: origin.x + (rect.minX - page.minX) * scale, y: origin.y + (rect.minY - page.minY) * scale,
                       width: rect.width * scale, height: rect.height * scale)
            }

            let paper = Path(roundedRect: place(page), cornerRadius: compact ? 2 : 4)
            context.fill(paper, with: .color(.white))
            context.stroke(paper, with: .color(.black.opacity(0.18)), lineWidth: 1)

            for table in layout.tables(onPage: 0) {
                let frame = place(table.frame)
                let box = Path(roundedRect: frame, cornerRadius: 1)
                if table.isVorlage {
                    context.fill(box, with: .color(accent.opacity(0.28)))
                }
                context.stroke(box, with: .color(accent.opacity(0.75)), lineWidth: compact ? 0.75 : 1)
                if !compact {
                    var divider = Path()
                    let x = origin.x + (table.columnDividerX - page.minX) * scale
                    divider.move(to: CGPoint(x: x, y: frame.minY))
                    divider.addLine(to: CGPoint(x: x, y: frame.maxY))
                    context.stroke(divider, with: .color(accent.opacity(0.4)), lineWidth: 0.75)
                }
            }
        }
        .shadow(color: .black.opacity(compact ? 0.05 : 0.1), radius: compact ? 1 : 4, y: 1)
    }
}
