import Cocoa
import UserNotifications

class NotificationManager {
  static func requestAuthorizationIfNeeded() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      if settings.authorizationStatus == .notDetermined {
        center.requestAuthorization(options: [.alert]) { _, _ in }
      }
    }
  }

  static func deliver(_ message: String, icon: NSImage?) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        self.showNotification(message, icon: icon)
      case .notDetermined:
        center.requestAuthorization(options: [.alert]) { granted, _ in
          if granted {
            self.showNotification(message, icon: icon)
          }
        }
      default:
        break
      }
    }
  }

  private static func showNotification(_ message: String, icon: NSImage?) {
    let content = UNMutableNotificationContent()
    content.body = message

    let request = UNNotificationRequest(
      identifier: "inputSourceChange",
      content: content,
      trigger: nil
    )

    let center = UNUserNotificationCenter.current()
    center.removeAllDeliveredNotifications()
    center.add(request)
  }
}
