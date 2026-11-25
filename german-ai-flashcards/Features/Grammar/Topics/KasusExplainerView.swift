import SwiftUI

struct KasusExplainerLibraryView: View {
    var unit: KasusUnit? = nil

    /// The reference rows' sheets. The Kasus-Check here is the same `KasusCheckSheet` the hub's
    /// toolbar shows — a twin, never a fork.
    @State private var showKasusCheck = false
    @State private var showArticleRules = false
    @State private var showPrepositionRules = false

    private var explainers: [KasusExplainer] { KasusExplainer.forUnit(unit) }

    var body: some View {
        List {
            Section {
                Text("Compare two sentences, follow the reason, then explain it to yourself. Take any topic at your own pace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .themedListRow()
            ForEach(KasusExplainer.Group.allCases, id: \.self) { group in
                let items = explainers.filter { $0.group == group }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            NavigationLink {
                                KasusExplainerView(explainer: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.headline)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text(group.rawValue).themedSectionHeader()
                    }
                    .themedListRow()
                }
            }
            Section {
                NavigationLink { CaseEndingsView() } label: {
                    Label("Artikel & Endungen · The tables", systemImage: "tablecells")
                }
                NavigationLink { KasusMnemonicsView() } label: {
                    Label("Merkhilfen · Memory aids", systemImage: "lightbulb")
                }
                Button { showKasusCheck = true } label: {
                    Label("Der Kasus-Check · The six steps", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                NavigationLink { EndungsWerkstattView() } label: {
                    Label("Endungs-Werkstatt · Ending workshop", systemImage: "cube.fill")
                }
            } header: {
                Text("Nachschlagen · Reference").themedSectionHeader()
            }
            .themedListRow()
            // An index may list what lives elsewhere: order, not duplication.
            Section {
                Button { showArticleRules = true } label: {
                    Label("Die 18 Regeln · The gender patterns", systemImage: "textformat.abc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { showPrepositionRules = true } label: {
                    Label("Präpositionen-Spickzettel · The cheat sheet", systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Regeln · Rule sheets").themedSectionHeader()
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Warum dieser Fall? · Why this case?")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showKasusCheck) { KasusCheckSheet() }
        .sheet(isPresented: $showArticleRules) { ArticleRulesSheet() }
        .sheet(isPresented: $showPrepositionRules) { PrepositionRulesSheet() }
    }
}

struct KasusExplainerView: View {
    let explainer: KasusExplainer
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explainer.title).font(.title2.bold())
                    Text(explainer.subtitle).font(.headline).foregroundStyle(.secondary)
                    Text(kasusRich: explainer.idea).padding(.top, 4)
                }
                ForEach(Array(explainer.examples.enumerated()), id: \.offset) { index, example in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beispiel \(index + 1) · Example \(index + 1)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(kasusRich: example.de).font(.title3.weight(.semibold))
                        Text(kasusRich: example.en).foregroundStyle(.secondary)
                        Divider()
                        Text(kasusRich: example.why)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .themedCard()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Darauf kommt es an · What to notice", systemImage: "lightbulb")
                        .font(.headline)
                    Text(kasusRich: explainer.takeaway)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("In eigenen Worten · In your own words").font(.headline)
                    Text(kasusRich: explainer.prompt)
                    DisclosureGroup("Erklärung zeigen · Reveal the explanation", isExpanded: $revealed) {
                        Text(kasusRich: explainer.reveal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    Text("Pause and give your reason before opening the explanation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .themedCard()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Weiterüben · Put it into practice").font(.headline)
                    ForEach(explainer.units) { unit in
                        NavigationLink {
                            KasusUnitView(unit: unit)
                        } label: {
                            Label("\(unit.germanTitle) · Verstehen & Übungen", systemImage: "arrow.right.circle")
                        }
                    }
                }
                if let url = URL(string: explainer.source) {
                    Link("Quelle · IDS grammis", destination: url)
                        .font(.caption)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(ThemedBackground().ignoresSafeArea())
        .navigationTitle("Erklärung · Explainer")
        .navigationBarTitleDisplayMode(.inline)
        .kasusReference()
    }
}

#Preview {
    NavigationStack { KasusExplainerLibraryView() }
}
