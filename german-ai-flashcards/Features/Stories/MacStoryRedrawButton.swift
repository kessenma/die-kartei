import SwiftData
import SwiftUI

// MAC-PICTURES: "Redraw on my Mac" in the story reader's toolbar (docs/MAC_PICTURES.md).

/// On a phone or iPad: a toolbar menu that sends the story's pictures to the learner's Mac to be
/// redrawn with a big model, or shows that they're waiting. On the Mac: "Draw Now" for a story
/// another device sent. Hidden when it can't work (no sync, no Mac seen, no pictures).
struct MacStoryRedrawButton: View {
    let story: StudyStory

    @Environment(\.modelContext) private var modelContext
    @State private var mac: SyncPeer?
    @State private var confirming = false

    var body: some View {
        content
            .task(id: story.id) {
                mac = MacPictureHandoff.macPeer()
                #if DEBUG
                if mac == nil, UserDefaults.standard.bool(forKey: "macPictures.debugFakeMac") {
                    mac = SyncPeer(id: "debug-mac", model: "Mac", appVersion: "debug", lastSyncAt: .now,
                                   writtenAt: .now, hasPending: false, stuck: 0, digests: [:],
                                   isThisDevice: false, macPictureModels: [ImageGenModel.zImageTurbo.rawValue])
                }
                #endif
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        if story.hasPendingMacPictures, let request = story.macPictureRequest,
           request.fromDevice != ThisDevice.name {
            let inbox = MacPictureInbox.shared
            Button {
                Task { await inbox.drawNow() }
            } label: {
                Label("Draw Now", systemImage: "paintbrush.pointed")
            }
            .help("Your \(request.fromDevice) asked for these pictures to be redrawn")
            .disabled(inbox.isDrawing || inbox.drawingModel == nil)
        }
        #else
        if let mac, MacPictureHandoff.canOrder(story), !mac.macPictureModels.isEmpty {
            Menu {
                if story.hasPendingMacPictures {
                    Text("Waiting for your Mac")
                    Button("Cancel Redraw", role: .destructive) {
                        MacPictureHandoff.cancel(story, in: modelContext)
                    }
                } else {
                    Button {
                        confirming = true
                    } label: {
                        Label("Redraw Pictures on My Mac", systemImage: "macbook.and.iphone")
                    }
                }
            } label: {
                Image(systemName: story.hasPendingMacPictures ? "hourglass" : "macbook.and.iphone")
            }
            .alert("Redraw these pictures on your Mac?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Redraw") { MacPictureHandoff.order(story, in: modelContext) }
            } message: {
                let model = mac.macPictureModels.first.flatMap(ImageGenModel.init(rawValue:))?.displayName ?? "its picture model"
                Text("Your Mac redraws all \(story.images.count) pictures with \(model) the next time you open Die Kartei there. The new ones replace these.")
            }
        }
        #endif
    }
}
