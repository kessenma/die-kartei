import SwiftUI

/// The "Stories" tab of the Settings screen. Home for how story study is tracked (time, streak,
/// what flows to the coach) and for the defaults every new story starts from — the story-side
/// counterpart to `ConversationSettingsView`.
struct StorySettingsView: View {
    @Bindable var modelManager: MLXModelManager

    var body: some View {
        Section {
            StoryModelRow(selected: $modelManager.selectedStoryModel)
        } header: {
            Text("Story model").themedSectionHeader()
        } footer: {
            Text("Any of the German Tutor models can write and grade stories — pick by what this iPhone has room for. Stories you already have keep the tutor that wrote them.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Toggle("Reading counts as study", isOn: $modelManager.storyTimeCountsTowardStreak)
            NavigationLink {
                StoryProgressView()
            } label: {
                Label("Reading progress", systemImage: "chart.bar.xaxis")
            }
        } header: {
            Text("Reading").themedSectionHeader()
        } footer: {
            Text(modelManager.storyTimeCountsTowardStreak
                 ? "Time spent reading or listening to a story keeps your streak alive on its own — no questions needed. A story has to hold you for a minute before the day counts, and the clock only runs while a story is open and the app is in front."
                 : "Only answered questions count toward your streak. Reading time is still tracked and shown in Reading progress.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Toggle("Share story words with the coach", isOn: $modelManager.storyFeedsCoach)
        } header: {
            Text("Coaching").themedSectionHeader()
        } footer: {
            Text(modelManager.storyFeedsCoach
                 ? "Words you save while reading, blanks you miss, and the fixes the model suggests on your written answers go into the coach's memory — so they come back in conversations and in Coach's Notes."
                 : "Off — story reading stays out of the coach's memory.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            // Level isn't a story default any more — it's the app-wide anchor, so this links to the
            // one screen that owns it rather than offering a second place to change it.
            NavigationLink {
                LevelSettingsView(modelManager: modelManager)
            } label: {
                HStack {
                    Text("Level")
                    Spacer()
                    Text(modelManager.germanLevel.rawValue)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Questions", selection: Binding(
                get: { modelManager.storyQuestionCount },
                set: { modelManager.storyQuestionCount = $0 }
            )) {
                ForEach([4, 6, 8, 10], id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Illustrate new stories", isOn: Binding(
                get: { modelManager.storyIllustrationsEnabled },
                set: { modelManager.storyIllustrationsEnabled = $0 }
            ))
            Toggle("Translate into English", isOn: Binding(
                get: { modelManager.storyTranslationEnabled },
                set: { modelManager.storyTranslationEnabled = $0 }
            ))
        } header: {
            Text("New story defaults").themedSectionHeader()
        } footer: {
            Text("Where the setup screen starts. Everything here can still be changed per story. Level comes from Your Level and is shared with conversations — changing it for one story leaves it alone.")
                .font(.caption2)
        }
        .themedListRow()
    }
}
