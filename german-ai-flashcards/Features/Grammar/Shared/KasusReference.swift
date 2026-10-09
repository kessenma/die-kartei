import SwiftUI

/// What the question-mark menu may pin: the article table for the case path, the reflexive
/// pronoun table for the reflexive topic.
enum KasusReferenceContent: Hashable {
    case articles([GrammarCase])
    case reflexivePronouns

    var title: String {
        switch self {
        case .articles:          "Artikeltabelle · Article table"
        case .reflexivePronouns: "Reflexivpronomen · Reflexive pronouns"
        }
    }

    var pinLabel: String {
        switch self {
        case .articles:          "Artikeltabelle · Reference"
        case .reflexivePronouns: "Pronomen · Reference"
        }
    }
}

/// Reference visibility belongs to this activity: survives questions, resets on leaving.
/// This neutral table never highlights the current answer or changes the hint level.
private struct KasusReferenceModifier: ViewModifier {
    var reference: KasusReferenceContent
    /// The activity's own pin state, when it wants to know (the drill shell marks answers given
    /// with the table pinned as scaffolded). Nil keeps the state here.
    var external: Binding<Bool>?
    @State private var ownPinned = false
    @State private var sheet: ReferenceSheet?

    private var pinned: Binding<Bool> { external ?? $ownPinned }

    private enum ReferenceSheet: String, Identifiable {
        case table, check
        var id: String { rawValue }
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if pinned.wrappedValue {
                    VStack(spacing: 6) {
                        HStack {
                            Label(reference.pinLabel, systemImage: "pin.fill")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                pinned.wrappedValue = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .padding(8)
                            }
                            .accessibilityLabel("Hide article table")
                        }
                        // A bounded scroll area preserves room for the question and controls
                        // on a small phone and lets larger accessibility text remain readable.
                        ScrollView {
                            switch reference {
                            case .articles(let cases):
                                CaseEndingsTable(cases: cases, compact: true, articlesOnly: true)
                            case .reflexivePronouns:
                                ReflexivPronounTable(compact: true)
                            }
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
                        Toggle(isOn: pinned) {
                            Label("Tabelle sichtbar lassen · Keep table visible", systemImage: "pin")
                        }
                        Button {
                            sheet = .check
                        } label: {
                            Label("Der Kasus-Check · Choose the case", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: pinned.wrappedValue ? "pin.circle.fill" : "questionmark.circle")
                    }
                    .accessibilityLabel("Case help and article table")
                    .accessibilityValue(pinned.wrappedValue ? "Table pinned" : "Table hidden")
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
                                switch reference {
                                case .articles(let cases):
                                    Text("Choose the row by case, then the column by gender or plural.")
                                        .font(.subheadline)
                                    CaseEndingsTable(cases: cases)
                                    Text("The top form is the definite article (der/die/das). The lower form shows ein and possessives such as mein; the plural uses mein. There is no plural ein.")
                                        .font(.caption).foregroundStyle(.secondary)
                                case .reflexivePronouns:
                                    Text("Choose the row by the subject, then the column by case.")
                                        .font(.subheadline)
                                    ReflexivPronounTable()
                                    Text("Only ich and du change between the cases. With nothing after the verb the person is the Akkusativ object; a second object after the verb puts the person in the Dativ.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Toggle("Sichtbar lassen · Keep visible in this activity", isOn: pinned)
                                Text("Close this reference to return to the same question. A pinned table stays until you hide it or leave this activity.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                        }
                        .background(ThemedBackground().ignoresSafeArea())
                        .navigationTitle(reference.title)
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
    func kasusReference(cases: [GrammarCase] = GrammarCase.allCases, pinned: Binding<Bool>? = nil) -> some View {
        modifier(KasusReferenceModifier(reference: .articles(cases), external: pinned))
    }

    func kasusReference(content: KasusReferenceContent, pinned: Binding<Bool>? = nil) -> some View {
        modifier(KasusReferenceModifier(reference: content, external: pinned))
    }
}
