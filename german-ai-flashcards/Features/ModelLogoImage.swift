import SwiftUI

extension MLXModel {
    /// The model's logo as a SwiftUI `Image`: the brand asset for downloadable models, or an
    /// SF Symbol for the built-in Apple Intelligence model (which has no logo asset).
    ///
    /// Both `Image(named:)` and `Image(systemName:)` are the same `Image` type, so every existing
    /// `Image(model.logoName)…` call site can swap to `model.logoImage…` and keep its modifiers
    /// (`.resizable()`, `.frame(...)`, `.clipShape(...)`, etc.).
    var logoImage: Image {
        usesSFSymbolLogo ? Image(systemName: sfSymbolLogo) : Image(logoName)
    }
}
