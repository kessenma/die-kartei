#if os(macOS)
import SwiftUI

// MAC-PICTURES: the inbox banner above every place in the Mac window (docs/MAC_PICTURES.md).

/// "2 decks from your iPhone are waiting for pictures · Draw now", then progress while they draw.
/// Hidden when there's nothing to say; "Later" hides it until another order arrives.
struct MacPictureInboxBanner: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme
    @Environment(\.openSettings) private var openSettings
    @State private var inbox = MacPictureInbox.shared
    @State private var deckService = DeckIllustrationService.shared
    @State private var storyRedrawer = MacStoryRedrawer.shared

    var body: some View {
        if inbox.isDrawing {
            bar {
                ProgressView(value: storyRedrawer.totalCount > 0 ? storyRedrawer.progress : deckService.progress)
                    .frame(width: 120)
                Text(drawingText)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Stop") { deckService.stop() }
            }
        } else if let problem = inbox.problem, !inbox.orders.isEmpty {
            bar {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(problem).font(.callout).lineLimit(2)
                Spacer(minLength: 8)
                if inbox.drawingModel == nil {
                    Button("Open Settings") { openSettings() }
                } else {
                    Button("Try Again") { Task { await inbox.drawNow() } }
                }
            }
        } else if !inbox.orders.isEmpty, !inbox.isSnoozed {
            bar {
                Image(systemName: "macbook.and.iphone")
                    .font(.title3)
                    .foregroundStyle(appTheme.accent(model: modelTheme))
                VStack(alignment: .leading, spacing: 1) {
                    Text(waitingTitle).font(.callout.weight(.semibold))
                    Text(waitingDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Later") { inbox.isSnoozed = true }
                if inbox.drawingModel == nil {
                    Button("Get a Model") { openSettings() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Draw Now") { Task { await inbox.drawNow() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var waitingTitle: String {
        let from = inbox.orders.first?.request.fromDevice ?? "iPhone"
        guard inbox.orders.count > 1 else {
            return "„\(inbox.orders[0].topic)“ from your \(from) is waiting for pictures"
        }
        return "\(MacPictureInbox.countPhrase(inbox.orders)) from your \(from) are waiting for pictures"
    }

    private var waitingDetail: String {
        let pictures = inbox.orders.reduce(0) { $0 + $1.pictureCount }
        guard let model = inbox.drawingModel else {
            return "\(pictures) picture\(pictures == 1 ? "" : "s"). Download Z-Image Turbo or FLUX.2 klein to draw them."
        }
        let time = inbox.estimatedMinutes.map { " · about \($0) min" } ?? ""
        return "\(pictures) picture\(pictures == 1 ? "" : "s") with \(model.displayName)\(time). Keep Die Kartei open while it draws."
    }

    private var drawingText: String {
        let title = inbox.drawingTopic.map { "„\($0)“" } ?? "Drawing"
        let of = inbox.orders.count > 1 ? " · \(inbox.drawingIndex) of \(inbox.orders.count)" : ""
        let (done, total) = storyRedrawer.totalCount > 0
            ? (storyRedrawer.completedCount, storyRedrawer.totalCount)
            : (deckService.completedCount, deckService.totalCount)
        return "\(title): picture \(min(done + 1, max(total, 1))) of \(total)\(of)"
    }

    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}
#endif
