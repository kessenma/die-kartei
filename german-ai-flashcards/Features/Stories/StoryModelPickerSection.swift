import SwiftUI

/// The story feature's model chooser: the in-house German tutors, and only them.
///
/// Stories used to be pinned to the hero tutor. They aren't any more — every model in
/// ``StoryStudyService/eligibleModels`` is fine-tuned on the same German material, so the pick is
/// about what the device can hold, not about whether the prose and answer keys can be trusted.
/// Shared by the story setup screen (where the choice applies to the story about to be written)
/// and Settings ▸ Stories (where it's the remembered default) so the two can't drift apart.
///
/// Tutors too big for this device are listed rather than hidden: tapping one opens the memory
/// check instead of selecting it, which is the same deal the model settings offer.
struct StoryModelPickerSection: View {
    @Binding var selected: MLXModel
    var title: String = "Story model"
    var footerText: String = "Every tutor here is trained on the same German material — what differs is size, and how much the smaller ones let slip. Whichever you pick writes the story, sets the questions, and grades your answers."
    /// The oversized tutor whose memory check is up, if any.
    @State private var memoryCheckFor: MLXModel?

    private var models: [MLXModel] { StoryStudyService.eligibleModels }

    var body: some View {
        Section {
            ForEach(models) { model in
                row(model)
            }
        } header: {
            Text(title).themedSectionHeader()
        } footer: {
            Text(footerText).font(.caption2)
        }
        .sheet(item: $memoryCheckFor) { model in
            MemoryCheckSheet(
                model: model,
                // The best tutor that *does* fit here, so the sheet's one-tap way out is a model
                // that can actually write a story. Falling back to `model` when nothing fits is
                // what makes the sheet drop that button entirely.
                alternative: StoryStudyService.runnableModels.first ?? model,
                onUseAnyway: { selected = model },
                onUseAlternative: { selected = $0 }
            )
        }
    }

    @ViewBuilder private func row(_ model: MLXModel) -> some View {
        let runnable = DeviceCapability.mayRun(model)
        Button {
            if runnable {
                selected = model
            } else {
                memoryCheckFor = model
            }
        } label: {
            HStack(spacing: 12) {
                model.logoImage
                    .resizable().scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(runnable ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.rawValue)
                            .foregroundStyle(runnable ? .primary : .secondary)
                        if model.isDownloaded {
                            Text("Downloaded")
                                .font(.caption).fontWeight(.medium)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(tagline(model))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(runnable
                         ? "~\(formattedSize(model.approximateSizeMB))"
                         : "~\(formattedSize(model.approximateSizeMB)) · needs a \(model.minimumRAMGB) GB device")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if selected == model {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                } else if !runnable {
                    Image(systemName: "memorychip").foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The hero's shared `tutorTagline` is a sentence fragment built for the "Recommended" footer
    /// ("…just for this app,"), so it gets a standalone line here; the others read fine as-is.
    private func tagline(_ model: MLXModel) -> String {
        model.isHero
            ? "The best measured German of the tutors, and the steadiest at holding a story to one level."
            : model.tutorTagline
    }

    private func formattedSize(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
    }
}

// MARK: - Compact entry points

/// The full-screen version of ``StoryModelPickerSection``, pushed from ``StoryModelRow``.
struct StoryModelPickerView: View {
    @Binding var selected: MLXModel

    var body: some View {
        Form {
            StoryModelPickerSection(selected: $selected)
                .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Story Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The one-row summary of which tutor stories use, pushing the picker when tapped. Keeps the story
/// setup form and the Stories settings tab light while still making the choice visible on both.
struct StoryModelRow: View {
    @Binding var selected: MLXModel
    var caption: String = "Writes the story, sets the questions, and grades your answers — fully on-device."

    var body: some View {
        NavigationLink {
            StoryModelPickerView(selected: $selected)
        } label: {
            HStack(spacing: 12) {
                selected.logoImage
                    .resizable().scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
