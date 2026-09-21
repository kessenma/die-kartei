import SwiftUI
import UIKit   // UIImage — a step only draws its screenshot when the asset exists

/// A numbered instruction with an optional screenshot beneath it, shared by the Settings how-to
/// guides (downloading a German voice, setting up the keyboard).
///
/// The image renders only when its asset is actually in the catalog, so a guide stays intact when a
/// screenshot is renamed, removed, or simply not taken yet: the step quietly degrades to text.
struct SettingsStepRow: View {
    @Environment(\.appTheme) private var appTheme

    private let number: Int
    private let text: String
    private let image: String?

    init(_ number: Int, _ text: String, image: String? = nil) {
        self.number = number
        self.text = text
        self.image = image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let image, UIImage(named: image) != nil {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
                    .overlay(
                        RoundedRectangle(cornerRadius: appTheme.innerRadius(12))
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }
}
