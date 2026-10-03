#if os(macOS)
import SwiftUI

/// The Mac window's sidebar layout: the places down the left, the chosen one on the right.
///
/// The sidebar is either full (icon and name) or compact (icons only, names as tooltips), switched by
/// the toolbar button or View ▸ Compact Sidebar (⌃⌘S). It replaces the system's hide-sidebar
/// toggle, so there is one control. Compact is not a narrower split-view column: the system holds
/// a sidebar to about 140 pt at the least, so compact hides the column and draws a 64 pt rail at
/// the content's leading edge instead.
///
/// Only the chosen place is alive, unlike the iPhone's tabs, which keep every visited tab's stack.
/// A Mac window has one toolbar, and every live navigation stack writes its title and toolbar
/// buttons into it, so a hidden place would name the window and leave its buttons behind.
/// Choosing a place (or the current one again) opens it at its first screen.
struct MacSidebarShell: View {
    @Bindable var coordinator: GenerationCoordinator
    /// Bubbles up to ContentView, which owns the card-selection sheet + generated-deck save.
    var onGenerationComplete: () -> Void

    @Environment(MacNavigator.self) private var navigator
    @Environment(\.openSettings) private var openSettings
    @AppStorage("mac.sidebarCompact") private var compact = false

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { compact ? .detailOnly : .all },
            set: { _ in }   // the compact toggle is the only control
        )) {
            sidebar
                .navigationSplitViewColumnWidth(224)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                if compact {
                    rail
                    Divider()
                }
                destinationView(navigator.selection)
                    .id("\(navigator.selection.rawValue)-\(navigator.resetToken(for: navigator.selection))")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The app-wide ground behind every place, so switching never flashes it.
                    .themedScreen()
                    // A list's toolbar backdrop would stop at the readable column and leave a
                    // faint band under the title bar.
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            }
            // On the content's side of the toolbar: an item over the sidebar would hold the
            // sidebar at least as wide as the item plus the traffic lights, and compact never
            // gets narrow.
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.snappy) { compact.toggle() }
                    } label: {
                        Label(compact ? "Expand Sidebar" : "Compact Sidebar", systemImage: "sidebar.left")
                    }
                    .help(compact ? "Show names in the sidebar (⌃⌘S)" : "Show only icons in the sidebar (⌃⌘S)")
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(
            get: { navigator.selection },
            set: { if let destination = $0 { navigator.go(to: destination) } }
        )) {
            ForEach(MacDestination.Section.allCases, id: \.self) { section in
                Section {
                    ForEach(section.destinations) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                            // Clicking the place you're on returns it to its first screen; a List
                            // selection that doesn't change never reaches the binding above.
                            .simultaneousGesture(TapGesture().onEnded {
                                if navigator.selection == destination { navigator.go(to: destination) }
                            })
                    }
                } header: {
                    if let title = section.title { Text(title) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer(compact: false) }
    }

    /// Compact mode: the same places as icons in a 64 pt column, names as tooltips.
    private var rail: some View {
        VStack(spacing: 4) {
            ForEach(MacDestination.Section.allCases, id: \.self) { section in
                ForEach(section.destinations) { destination in
                    railButton(destination)
                }
                if section != MacDestination.Section.allCases.last {
                    Divider().frame(width: 28).padding(.vertical, 6)
                }
            }
            Spacer(minLength: 8)
            footer(compact: true)
        }
        .padding(.top, 10)
        .frame(width: 64)
        .background(SidebarMaterial())
    }

    private func railButton(_ destination: MacDestination) -> some View {
        let selected = navigator.selection == destination
        return Button {
            navigator.go(to: destination)
        } label: {
            Image(systemName: destination.systemImage)
                .font(.title3)
                .frame(width: 44, height: 34)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(destination.title)
        .accessibilityLabel(destination.title)
    }

    /// What the iPhone shows as badges on its tab bar (a download in progress, a generation
    /// running) plus the way to Settings, pinned under the list.
    private func footer(compact: Bool) -> some View {
        VStack(alignment: compact ? .center : .leading, spacing: 10) {
            let service = coordinator.mlxService
            if service.isLoading {
                statusRow(
                    title: service.downloadProgress == nil ? "Loading the tutor…" : "Downloading the tutor…",
                    help: "Model & Downloads",
                    compact: compact
                ) {
                    DownloadBadge(progress: service.downloadProgress)
                }
                .onTapGesture { openSettings(at: .model) }
            }
            if coordinator.isGenerating || BatchQueueService.shared.isRunning {
                statusRow(title: "Generating…", help: "Something is being generated", compact: compact) {
                    GeneratingBadge()
                }
            }
            Divider()
            Button {
                openSettings(at: nil)
            } label: {
                if compact {
                    Image(systemName: "gearshape").font(.title3).frame(maxWidth: .infinity)
                } else {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, compact ? 8 : 16)
        .padding(.vertical, 10)
    }

    private func statusRow<Badge: View>(
        title: String, help: String, compact: Bool, @ViewBuilder badge: () -> Badge
    ) -> some View {
        HStack(spacing: 8) {
            badge()
            if !compact {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: compact ? .infinity : nil, alignment: compact ? .center : .leading)
        .help(help)
    }

    private func openSettings(at pane: SettingsPane?) {
        if let pane { MacSettingsSelection.shared.pane = pane }
        openSettings()
    }

    // MARK: - Detail

    @ViewBuilder
    private func destinationView(_ destination: MacDestination) -> some View {
        switch destination {
        case .home:
            // For You only: the All Activities grid is the sidebar now.
            HomeHubView(
                coordinator: coordinator,
                onGenerationComplete: onGenerationComplete,
                showsModePicker: false
            )
        case .library:
            UnifiedLibraryView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
        case .deutschkurs:
            NavigationStack {
                ClassNotesHubView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            }
        case .jobPrep:
            NavigationStack {
                JobPrepHubView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            }
        default:
            if let category = destination.category {
                NavigationStack {
                    ActivityCategoryDestination(
                        category: category,
                        coordinator: coordinator,
                        onGenerationComplete: onGenerationComplete
                    )
                }
            }
        }
    }
}
/// The translucent sidebar material, for the compact rail that stands in for the sidebar column.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif
