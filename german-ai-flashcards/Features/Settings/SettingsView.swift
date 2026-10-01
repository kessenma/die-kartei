import SwiftUI

/// The Settings screen — a grouped list (App / Learning / Model / About) whose rows push to detail
/// screens. Replaces the old four-tab segmented switcher: the theme-upgrade IA gives app-level
/// settings a home and lands the theme picker at App ▸ Appearance. Every screen (root + each pushed
/// section) wears the same morphing `SettingsHeader`, so the header look Kyle likes is preserved —
/// now driven by navigation instead of segments.
struct SettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Bumped by the tab bar when Settings is re-tapped while already active. Changing it
    /// re-identifies the NavigationStack below, popping any pushed sub-screen back to root.
    var resetToken: Int = 0

    /// A destination another screen asked for — the Home tutor card, an upgrade nudge. Cleared when
    /// the pushed screen pops, so asking for the same route twice pushes twice.
    ///
    /// Deliberately separate from `resetToken`: that one *rebuilds* this stack and would throw a
    /// pushed destination away, so a deep link must never touch it.
    @Binding var route: SettingsRoute?

    var body: some View {
        NavigationStack {
            List {
                SettingsHeader(icon: "gearshape", title: "Settings")

                // The rows come from `SettingsPane`, which the Mac's Settings window lists too.
                ForEach(SettingsPane.Group.allCases) { group in
                    let panes = SettingsPane.panes(in: group)
                    if !panes.isEmpty {
                        Section(group.rawValue) {
                            ForEach(panes) { pane in
                                NavigationLink {
                                    pane.destination(modelManager: modelManager, mlxService: mlxService)
                                        #if os(macOS)
                                        // The Mac draws no SettingsHeader; the title bar names the screen.
                                        .navigationTitle(pane.title)
                                        #endif
                                } label: {
                                    SettingsPaneRow(pane: pane, modelManager: modelManager, mlxService: mlxService)
                                }
                            }
                            if group == .about {
                                // Straight to the App Store's write-review sheet. An explicit tap, so
                                // it skips every gate in `ReviewPromptService` — those throttle the
                                // *system* prompt.
                                Link(destination: ReviewPromptService.writeReviewURL) {
                                    Label("Rate on the App Store", systemImage: "star")
                                }
                            }
                        }
                        .themedListRow()
                    }
                }
            }
            .themedListScreen()
            .navigationBarTitleDisplayMode(.inline)
            // Keep last-loaded in sync regardless of which screen is showing.
            .onChange(of: mlxService.currentModel) { _, newModel in
                if let model = newModel {
                    modelManager.lastLoadedModel = model
                }
            }
            // The same destinations the rows above push, reachable by route. The rows stay: a deep
            // link is an extra door, not a replacement for the one people find by looking.
            .navigationDestination(item: $route) { destination in
                SettingsPane(route: destination).destination(modelManager: modelManager, mlxService: mlxService)
            }
        }
        // Re-tapping the Settings tab bumps `resetToken`, giving the stack a fresh identity and
        // tearing down any pushed sub-screen — returning to root Settings.
        .id(resetToken)
    }
}

// MARK: - Detail screens
//
// The Learning/Model settings bodies emit bare `Section`s — they were composed into one shared
// `Form` in the old segmented shell. Each detail screen now wraps them in its own `Form` behind a
// morphing `SettingsHeader`. (Reminders, Voice, Appearance, Sources bring their own containers.)

struct FlashcardsSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var body: some View {
        Form {
            SettingsHeader(icon: "rectangle.stack", title: "Flashcards")
            CardSettingsView(modelManager: modelManager)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConversationSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var body: some View {
        Form {
            SettingsHeader(icon: "bubble.left.and.bubble.right", title: "Conversation")
            ConversationSettingsView(modelManager: modelManager, mlxService: mlxService)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StoriesSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var body: some View {
        Form {
            SettingsHeader(icon: "book.pages", title: "Stories")
            StorySettingsView(modelManager: modelManager)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ModelSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var body: some View {
        Form {
            SettingsHeader(icon: "cpu", title: "Model")
            ModelSettingsView(modelManager: modelManager, mlxService: mlxService)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedbackScreen: View {
    let loadedModelName: String?
    var body: some View {
        Form {
            SettingsHeader(icon: "envelope", title: "Feedback")
            FeedbackSection(loadedModelName: loadedModelName)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
