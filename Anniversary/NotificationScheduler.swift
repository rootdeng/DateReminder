import Foundation
import UserNotifications
import SwiftData

struct NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()
    
    private init() {}
    
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
        await center.removeAllPendingNotificationRequests()
        
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
        content.title = "纪念日检查"
        content.body = "查看今天是否有纪念日需要提醒"
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
        let earliest = items
            .filter { $0.remind }
            .map { ($0.reminderHour, $0.reminderMinute) }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
            .first
        
        guard let earliestTime = earliest else {
            return (defaultHour, defaultMinute)
        }
        
        if earliestTime.0 < defaultHour || (earliestTime.0 == defaultHour && earliestTime.1 < defaultMinute) {
            let totalMinutes = earliestTime.0 * 60 + earliestTime.1
            let adjusted = max(0, totalMinutes - 15)
            return (adjusted / 60, adjusted % 60)
        } else {
            return (defaultHour, defaultMinute)
        }
    }
}
