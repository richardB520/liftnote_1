import ActivityKit
import Foundation
import UserNotifications

/// 休息到点提醒（App 在后台或锁屏时也会提醒）。
enum RestAlerts {
    static let identifier = "liftnote.rest.finished"
    private static var didRequest = false

    static func requestAuthorizationIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(endsAt: Date, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { _ in }
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

/// App 在前台时也显示横幅和声音。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

/// 锁屏和灵动岛上的休息倒计时（Live Activity）。
@MainActor
final class RestLiveActivity {
    static let shared = RestLiveActivity()

    func show(workoutTitle: String, exerciseName: String, detail: String, startedAt: Date, endsAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(exerciseName: exerciseName, detail: detail,
                                                        startedAt: min(startedAt, endsAt), endsAt: endsAt)
        let content = ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(30))
        let attributes = RestActivityAttributes(workoutTitle: workoutTitle)
        Task {
            let existing = Activity<RestActivityAttributes>.activities
            if let current = existing.first {
                await current.update(content)
                for extra in existing.dropFirst() {
                    await extra.end(nil, dismissalPolicy: .immediate)
                }
            } else {
                _ = try? Activity<RestActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
            }
        }
    }

    func end() {
        Task {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
