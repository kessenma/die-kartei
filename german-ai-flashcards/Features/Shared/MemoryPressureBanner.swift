import SwiftUI

/// A banner that appears when the app runs low on memory during generation, so a shorter answer or
/// an early stop reads as a deliberate act rather than a glitch.
///
/// Attached once at the app root: pressure can build during any generation, and the screen the user
/// happens to be on shouldn't decide whether they hear about it. The matching background case is a
/// local notification, posted by ``MemoryPressureMonitor`` when the app isn't in front.
struct MemoryPressureBanner: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    /// Optional on purpose: the banner sits at the very root, above where most of the
    /// environment is assembled, and a preview or a stripped-down host has no router at all.
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    private let monitor = MemoryPressureMonitor.shared

    /// How long a warning stays up before fading on its own. Critical notices stay until dismissed;
    /// they explain output the user is looking at.
    private let autoDismissSeconds: UInt64 = 7

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let notice = monitor.notice {
                    banner(notice)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: notice.id) {
                            guard notice.level != .critical else { return }
                            try? await Task.sleep(for: .seconds(autoDismissSeconds))
                            withAnimation { monitor.dismiss() }
                        }
                }
            }
            .animation(.snappy, value: monitor.notice)
    }

    private func banner(_ notice: MemoryPressureMonitor.Notice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.isGoverned ? "leaf.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(notice.isGoverned ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The banner sits outside every NavigationStack, so the only way into the memory
                // screen is the router — exactly what it was built for.
                if let settingsRouter {
                    Button("See what's using memory") {
                        withAnimation { monitor.dismiss() }
                        settingsRouter.route = .memory
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation { monitor.dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(14)))
        .overlay(
            RoundedRectangle(cornerRadius: appTheme.innerRadius(14))
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

extension View {
    /// Show memory notices over this view. Applied once, at the root.
    func memoryPressureBanner() -> some View {
        modifier(MemoryPressureBanner())
    }
}
