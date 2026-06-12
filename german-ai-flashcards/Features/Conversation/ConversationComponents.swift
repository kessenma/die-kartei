import SwiftUI

// MARK: - Model picker (downloaded-first)

/// A compact model selector for the conversation setup, listing downloaded models first.
/// Mirrors the styling of the main Settings model rows.
struct ChatModelPickerSection: View {
    @Binding var selected: MLXModel
    var cacheRefreshID: UUID
    var title: String = "Conversation model"
    var footerText: String = "Downloaded models are listed first. Picking one that isn’t downloaded yet will download it (~once) when the chat starts."
    @State private var modelForInfo: MLXModel?

    private var deviceRAMGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }

    private var sortedModels: [MLXModel] {
        _ = cacheRefreshID
        return MLXModel.allCases.sorted { a, b in
            let da = a.isDownloaded, db = b.isDownloaded
            if da != db { return da }            // downloaded first
            return a.germanQualityScore > b.germanQualityScore
        }
    }

    var body: some View {
        Section {
            ForEach(sortedModels) { model in
                row(model)
            }
        } header: {
            Text(title)
        } footer: {
            Text(footerText)
                .font(.caption2)
        }
        // An alert (not a sheet) avoids a sheet-on-sheet conflict, since this picker
        // lives inside the setup sheet.
        .alert(item: $modelForInfo) { model in
            Alert(
                title: Text(model.rawValue),
                message: Text(infoMessage(model)),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func infoMessage(_ model: MLXModel) -> String {
        let size = model.approximateSizeMB >= 1000
            ? String(format: "%.1f GB", Double(model.approximateSizeMB) / 1000.0)
            : "\(model.approximateSizeMB) MB"
        return "\(model.description)\n\nParameters: \(model.parameterCount) · ~\(size)\nRecommended: \(model.deviceNote)"
    }

    @ViewBuilder private func row(_ model: MLXModel) -> some View {
        let downloaded = model.isDownloaded
        Button {
            selected = model
        } label: {
            HStack(spacing: 12) {
                Image(model.logoName)
                    .resizable().scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.rawValue).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("~\(formattedSize(model.approximateSizeMB))")
                        if downloaded {
                            Text("Downloaded").fontWeight(.medium).foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    modelForInfo = model
                } label: {
                    Image(systemName: "info.circle").foregroundStyle(.tint)
                }
                .buttonStyle(.plain)

                if selected == model {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formattedSize(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
    }
}

// MARK: - Grammar focus picker

/// Multi-select grammar-focus rows with a German label, English subheader, and an info button.
struct GrammarFocusPickerSection: View {
    @Binding var selected: Set<GrammarFocus>
    @State private var infoFocus: GrammarFocus?

    var body: some View {
        Section {
            ForEach(GrammarFocus.allCases) { focus in
                row(focus)
            }
        } header: {
            Text("Grammar focus")
        } footer: {
            Text(selected.isEmpty
                 ? "Optional. Pick one or more structures to practice and the AI will steer the conversation toward them and prioritize them when correcting you."
                 : "The AI will steer the chat toward \(selected.count) selected structure\(selected.count == 1 ? "" : "s") and focus its corrections there.")
                .font(.caption2)
        }
        .alert(item: $infoFocus) { focus in
            Alert(
                title: Text("\(focus.germanLabel) — \(focus.englishLabel)"),
                message: Text(focus.explanation),
                dismissButton: .default(Text("Got it"))
            )
        }
    }

    @ViewBuilder private func row(_ focus: GrammarFocus) -> some View {
        let isOn = selected.contains(focus)
        HStack(spacing: 12) {
            Button {
                toggle(focus)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(focus.germanLabel).foregroundStyle(.primary)
                        Text(focus.englishLabel)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                infoFocus = focus
            } label: {
                Image(systemName: "info.circle").foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggle(_ focus: GrammarFocus) {
        if selected.contains(focus) { selected.remove(focus) } else { selected.insert(focus) }
    }
}

// MARK: - Deck multi-select

/// Multi-select list of the user's saved decks for deck-based conversations.
struct DeckMultiSelectSection: View {
    let decks: [SavedDeck]
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        Section {
            if decks.isEmpty {
                Text("You don’t have any saved decks yet. Generate a deck first, or use Freestyle / Scenario mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(decks) { deck in
                    Button {
                        toggle(deck.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(deck.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(deck.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                .imageScale(.large)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(deck.topic).foregroundStyle(.primary)
                                Text("\(deck.cards.count) words")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let logo = deck.generatorLogoName {
                                Image(logo).resizable().scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Decks")
        } footer: {
            Text("The AI weaves words from the selected decks into the conversation and nudges you to use them.")
                .font(.caption2)
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
}
