import Foundation
import UserNotifications
import SwiftData

struct NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()
    private static let delegate = NotificationDelegate()
    
    private init() {
        center.delegate = Self.delegate
    }
    
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                print("Notification permission not granted")
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }
    
    func refreshNotifications(for items: [Item]) async {
        // clear only our requests
        center.removeAllPendingNotificationRequests()
        
        for item in items where item.remind {
            await scheduleReminder(for: item)
        }
        await scheduleDailyCheck(for: items)
    }
    
    @MainActor
    func scheduleReminder(for item: Item) async {
        guard let fireDate = item.nextTriggerDate else { return }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        
        let content = UNMutableNotificationContent()
        content.title = item.name
        content.body = "今天是\(item.name)，别忘了哦！"
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "anniversary-\(item.id)", content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule reminder: \(error)")
        }
    }
    
    func scheduleDailyCheck(for items: [Item]) async {
        let checkTime = computeDailyCheckTime(from: items)
        var comps = DateComponents()
        comps.hour = checkTime.hour
        comps.minute = checkTime.minute
        
        let content = UNMutableNotificationContent()
        content.title = "日期检查"
        content.body = "查看今天是否有日期需要提醒"
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-check", content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule daily check: \(error)")
        }
    }
    
    private func computeDailyCheckTime(from items: [Item]) -> (hour: Int, minute: Int) {
        let defaultHour = 8
        let defaultMinute = 0
        let defaultTotal = defaultHour * 60 + defaultMinute

        let earliestTotalMinutes = items.reduce(Int?.none) { current, item in
            guard item.remind else { return current }
            let minutes = item.reminderHour * 60 + item.reminderMinute
            if let current {
                return min(current, minutes)
            } else {
                return minutes
            }
        }

        guard let earliest = earliestTotalMinutes else {
            return (defaultHour, defaultMinute)
        }

        if earliest < defaultTotal {
            let adjusted = max(0, earliest - 15)
            return (adjusted / 60, adjusted % 60)
        }

        return (defaultHour, defaultMinute)
    }
}
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
