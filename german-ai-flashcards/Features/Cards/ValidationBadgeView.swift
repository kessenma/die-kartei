import SwiftUI

struct ValidationBadgeView: View {
    let result: ValidationResult
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let label = result.status.badgeLabel,
           let icon = result.status.badgeSystemImage,
           let color = result.status.badgeColor,
           let background = result.status.badgeBackgroundColor {
            let badge = Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(background, in: Capsule())

            if let onTap, result.status.isCorrectable {
                Button(action: onTap) {
                    badge
                }
                .buttonStyle(.plain)
            } else {
                badge
            }
        }
    }
}
