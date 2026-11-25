import Foundation

/// Model-download notifications, expressed on top of `LocalNotificationService`. Keeps the same
/// API the download flow already calls (`MLXGenerationService`).
enum ModelDownloadNotificationService {
    static func requestAuthorizationIfNeeded() async {
        await LocalNotificationService.requestAuthorizationIfNeeded()
    }

    static func notifyDownloadFinished(modelName: String) async {
        await LocalNotificationService.post(
            id: "model-download-\(modelName)",
            title: "Model downloaded",
            body: "\(modelName) is ready to use offline."
        )
    }
}
