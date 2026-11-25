import SwiftData
import SwiftUI

/// In-memory stores for previews and tests.
///
/// Every `ModelConfiguration` in this app passes `cloudKitDatabase: .none`. The default,
/// `.automatic`, turns on SwiftData's own CloudKit mirroring because the app has an iCloud
/// container entitlement (for iCloud Sync, which runs on CKSyncEngine instead), and the schema
/// doesn't meet mirroring's rules, so the store fails to load. `.modelContainer(for:inMemory:)` has
/// no way to say that, so previews use `inMemoryModelContainer(for:)`.
extension ModelContainer {
    static func inMemory(_ types: [any PersistentModel.Type]) -> ModelContainer {
        let schema = Schema(types)
        let config = SwiftData.ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // Previews and tests only: an in-memory store with a valid schema doesn't fail to open.
        return try! ModelContainer(for: schema, configurations: [config])
    }
}

extension View {
    func inMemoryModelContainer(for types: [any PersistentModel.Type]) -> some View {
        modelContainer(ModelContainer.inMemory(types))
    }
}
