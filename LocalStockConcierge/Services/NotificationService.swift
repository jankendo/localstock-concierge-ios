import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var didRequestAuthorization = false

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        }
    }

    func scheduleRestockReminder(productName: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(productName)の確認"
        content.body = reason
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60 * 6, repeats: false)
        let request = UNNotificationRequest(identifier: "restock-\(productName)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
