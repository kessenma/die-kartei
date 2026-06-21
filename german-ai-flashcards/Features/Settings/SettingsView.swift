import SwiftUI

/// The Settings screen shell — a segmented switcher over the Cards, Conversation, and Model tabs.
/// Each tab's content lives in its own file (`CardSettingsView`, `ConversationSettingsView`,
/// `ModelSettingsView`) and is composed here. The title icon mirrors the selected tab.
struct SettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Bumped by the tab bar when Settings is re-tapped while already active. Changing it
    /// re-identifies the NavigationStack below, popping any pushed sub-screen back to root.
    var resetToken: Int = 0

    @State private var selectedTab: SettingsTab = .cards

    enum SettingsTab: String, CaseIterable, Identifiable {
        case cards        = "Cards"
        case conversation = "Conversation"
        case model        = "Model"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .cards:        "rectangle.stack"
            case .conversation: "bubble.left.and.bubble.right"
            case .model:        "cpu"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Custom large-title header so we can show a tab-matching icon beside "Settings".
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: selectedTab.systemImage)
                            .foregroundStyle(.tint)
                            // Fixed slot (both axes) anchored toward the text so the icon morphs in
                            // place: width keeps "Settings" from shifting, height keeps the header
                            // row a constant size regardless of each symbol's intrinsic height.
                            .frame(width: 44, height: 44, alignment: .trailing)
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.snappy(duration: 0.3), value: selectedTab)
                        Text("Settings")
                    }
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Settings", selection: $selectedTab) {
                        ForEach(SettingsTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch selectedTab {
                case .cards:
                    CardSettingsView(modelManager: modelManager)
                case .conversation:
                    ConversationSettingsView(modelManager: modelManager, mlxService: mlxService)
                case .model:
                    ModelSettingsView(modelManager: modelManager, mlxService: mlxService)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 120)
            // Keep last-loaded in sync regardless of which tab is showing.
            .onChange(of: mlxService.currentModel) { _, newModel in
                if let model = newModel {
                    modelManager.lastLoadedModel = model
                }
            }
        }
        // Re-tapping the Settings tab bumps `resetToken`, which gives the stack a fresh
        // identity and tears down any pushed sub-screen — returning to root Settings.
        // `selectedTab` lives outside this subtree, so the current segment is preserved.
        .id(resetToken)
    }
}
