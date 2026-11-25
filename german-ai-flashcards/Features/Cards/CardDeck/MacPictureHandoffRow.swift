import SwiftData
import SwiftUI

// MAC-PICTURES: "Draw on my Mac" on the deck screen (docs/MAC_PICTURES.md).

/// On a phone or iPad: send the deck to the learner's Mac to be illustrated with a big model,
/// see that it's waiting, or cancel it. On the Mac: the same deck's order, with "Draw now".
///
/// Shown only where it can work: iCloud Sync on, a Mac running Die Kartei seen in the device list,
/// a deck that can have pictures. Sits outside the local "image model downloaded" check, so a
/// phone with no picture model of its own can still ask its Mac.
struct MacPictureHandoffRow: View {
    let deck: SavedDeck

    @Environment(\.modelContext) private var modelContext
    @State private var mac: SyncPeer?
    @State private var looked = false
    @State private var confirmingRedraw = false

    init(deck: SavedDeck) {
        self.deck = deck
    }

    /// For rendering the row in tests and previews with a Mac already found.
    init(deck: SavedDeck, mac: SyncPeer?) {
        self.deck = deck
        _mac = State(initialValue: mac)
        _looked = State(initialValue: true)
    }

    var body: some View {
        Group {
            #if os(macOS)
            macBody
            #else
            phoneBody
            #endif
        }
        .task(id: deck.id) {
            if looked, mac != nil { return }   // handed in (tests, previews)
            mac = MacPictureHandoff.macPeer()
            #if DEBUG
            if mac == nil, UserDefaults.standard.bool(forKey: "macPictures.debugFakeMac") {
                mac = SyncPeer(id: "debug-mac", model: "Mac", appVersion: "debug", lastSyncAt: .now,
                               writtenAt: .now, hasPending: false, stuck: 0, digests: [:],
                               isThisDevice: false, macPictureModels: [ImageGenModel.zImageTurbo.rawValue])
            }
            #endif
            looked = true
        }
    }

    // MARK: Phone / iPad

    @ViewBuilder
    private var phoneBody: some View {
        if looked, let mac, MacPictureHandoff.canOrder(deck) {
            VStack(spacing: 8) {
                if deck.hasPendingMacPictures, let request = deck.macPictureRequest {
                    Label("Waiting for your Mac", systemImage: "hourglass")
                        .font(.subheadline.weight(.semibold))
                    Text("\(request.redrawAll ? "Redraws every picture" : "Draws the missing pictures") in \(styleLabel(request)) the next time you open Die Kartei on your Mac. They arrive here through iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Cancel", role: .destructive) {
                        MacPictureHandoff.cancel(deck, in: modelContext)
                    }
                    .font(.caption)
                } else {
                    let missing = deck.cards.filter { $0.imageFileName == nil }.count
                    let ready = !mac.macPictureModels.isEmpty
                    HStack(spacing: 10) {
                        if missing > 0 {
                            Button {
                                MacPictureHandoff.order(deck, redrawAll: false, in: modelContext)
                            } label: {
                                Label("Draw on my Mac", systemImage: "macbook.and.iphone")
                                    .font(.subheadline)
                            }
                        }
                        if missing < deck.cards.count {
                            Button {
                                confirmingRedraw = true
                            } label: {
                                Label(missing > 0 ? "Redraw all" : "Redraw on my Mac", systemImage: "macbook.and.iphone")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!ready)

                    Text(ready ? readyCaption(mac) : "Download a picture model in Die Kartei on your Mac first (Settings ▸ Image generation).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let result = deck.macPictureResult, result.drawn > 0 {
                        Text("Your Mac drew \(result.drawn) picture\(result.drawn == 1 ? "" : "s") \(result.finishedAt.formatted(.relative(presentation: .named))).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)
            .alert("Redraw every picture on your Mac?", isPresented: $confirmingRedraw) {
                Button("Cancel", role: .cancel) {}
                Button("Redraw") { MacPictureHandoff.order(deck, redrawAll: true, in: modelContext) }
            } message: {
                Text("Your Mac replaces all \(deck.cards.count) pictures in \(CardImageStyle.current.label.lowercased()) style the next time you open Die Kartei there.")
            }
        }
    }

    private func readyCaption(_ mac: SyncPeer) -> String {
        let model = mac.macPictureModels.first.flatMap(ImageGenModel.init(rawValue:))?.displayName ?? "a big picture model"
        let seen = (mac.writtenAt ?? mac.lastSyncAt).map { " Last seen \($0.formatted(.relative(presentation: .named)))." } ?? ""
        let style = CardImageStyle.current.label.lowercased()
        return "Your Mac draws them with \(model), in \(style) style, the next time you open Die Kartei there.\(seen)"
    }

    private func styleLabel(_ request: MacPictureOrder.Request) -> String {
        let style = request.styleRaw.flatMap(CardImageStyle.init(rawValue:))?.label.lowercased() ?? "your"
        return "\(style) style"
    }

    // MARK: Mac

    #if os(macOS)
    @ViewBuilder
    private var macBody: some View {
        let inbox = MacPictureInbox.shared
        if deck.hasPendingMacPictures, let request = deck.macPictureRequest,
           request.fromDevice != ThisDevice.name {
            VStack(spacing: 8) {
                Label("Your \(request.fromDevice) asked for pictures", systemImage: "macbook.and.iphone")
                    .font(.subheadline.weight(.semibold))
                Text("\(request.redrawAll ? "Every picture, redrawn" : "The missing pictures") in \(styleLabel(request)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await inbox.drawNow() }
                } label: {
                    Label(inbox.isDrawing ? "Drawing…" : "Draw now", systemImage: "paintbrush.pointed")
                }
                .buttonStyle(.borderedProminent)
                .disabled(inbox.isDrawing || inbox.drawingModel == nil)
                if inbox.drawingModel == nil {
                    Text("Download Z-Image Turbo or FLUX.2 klein in Settings ▸ Image generation first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }
    #endif
}
