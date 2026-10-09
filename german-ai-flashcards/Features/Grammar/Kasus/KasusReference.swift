import SwiftUI

/// Reference visibility belongs to this activity: survives questions, resets on leaving.
/// This neutral table never highlights the current answer or changes the hint level.
private struct KasusReferenceModifier: ViewModifier {
    var cases: [GrammarCase]
    @State private var pinned = false
    @State private var sheet: ReferenceSheet?

    private enum ReferenceSheet: String, Identifiable {
        case table, check
        var id: String { rawValue }
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if pinned {
                    VStack(spacing: 6) {
                        HStack {
                            Label("Artikeltabelle · Reference", systemImage: "pin.fill")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                pinned = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .padding(8)
                            }
                            .accessibilityLabel("Hide article table")
                        }
                        // A bounded scroll area preserves room for the question and controls
                        // on a small phone and lets larger accessibility text remain readable.
                        ScrollView {
                            CaseEndingsTable(cases: cases, compact: true, articlesOnly: true)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sheet = .table
                        } label: {
                            Label("Tabelle öffnen · Open table", systemImage: "tablecells")
                        }
                        Toggle(isOn: $pinned) {
                            Label("Tabelle sichtbar lassen · Keep table visible", systemImage: "pin")
                        }
                        Button {
                            sheet = .check
                        } label: {
                            Label("Der Kasus-Check · Choose the case", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: pinned ? "pin.circle.fill" : "questionmark.circle")
                    }
                    .accessibilityLabel("Case help and article table")
                    .accessibilityValue(pinned ? "Table pinned" : "Table hidden")
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .check:
                    KasusCheckSheet()
                case .table:
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                Text("Choose the row by case, then the column by gender or plural.")
                                    .font(.subheadline)
                                CaseEndingsTable(cases: cases)
                                Text("The top form is the definite article (der/die/das). The lower form shows ein and possessives such as mein; the plural uses mein. There is no plural ein.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Toggle("Sichtbar lassen · Keep visible in this activity", isOn: $pinned)
                                Text("Close this reference to return to the same question. A pinned table stays until you hide it or leave this activity.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                        }
                        .background(ThemedBackground().ignoresSafeArea())
                        .navigationTitle("Artikeltabelle · Article table")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { sheet = nil }
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func kasusReference(cases: [GrammarCase] = GrammarCase.allCases) -> some View {
        modifier(KasusReferenceModifier(cases: cases))
    }
}
