//
//  Item.swift
//  DateReminder
//
//  Created by Dennis on 2026/3/20.
//

import Foundation
import SwiftData

enum CalendarType: String, Codable, CaseIterable, Identifiable {
    case solar
    case lunar
    
    var id: String { rawValue }
    var displayName: String { rawValue == "solar" ? "阳历" : "阴历" }
}

@Model
final class Item {
    var name: String
    var date: Date
    var year: Int?
    var calendarType: CalendarType
    var remind: Bool
    var reminderHour: Int
    var reminderMinute: Int
    
    init(
        name: String,
        date: Date,
        year: Int? = nil,
        calendarType: CalendarType = .solar,
        remind: Bool = true,
        reminderHour: Int = 11,
        reminderMinute: Int = 0
    ) {
        self.name = name
        self.date = date
        self.year = year
        self.calendarType = calendarType
        self.remind = remind
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

extension Item {
    var reminderTimeText: String {
        let comps = DateComponents(hour: reminderHour, minute: reminderMinute)
        return comps.formatAsTime()
    }
    
    var nextTriggerDate: Date? {
        let now = Date()
        let components = DateComponents(hour: reminderHour, minute: reminderMinute)
        switch calendarType {
        case .solar:
            return Self.nextSolarOccurrence(from: date, reminderTime: components, now: now)
        case .lunar:
            return Self.nextLunarOccurrence(from: date, reminderTime: components, now: now)
        }
    }
    
    static func nextSolarOccurrence(from date: Date, reminderTime: DateComponents, now: Date) -> Date? {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        var target = calendar.dateComponents([.month, .day], from: date)
        target.year = currentYear
        target.hour = reminderTime.hour
        target.minute = reminderTime.minute
        
        if let thisYear = calendar.date(from: target), thisYear >= now {
            return thisYear
        }
        target.year = currentYear + 1
        return calendar.date(from: target)
    }
    
    static func nextLunarOccurrence(from date: Date, reminderTime: DateComponents, now: Date) -> Date? {
        let lunarCalendar = Calendar(identifier: .chinese)
        let gregorian = Calendar.current
        
        var lunarComponents = lunarCalendar.dateComponents([.month, .day], from: date)
        let currentLunarYear = lunarCalendar.component(.year, from: now)
        lunarComponents.year = currentLunarYear
        lunarComponents.hour = reminderTime.hour
        lunarComponents.minute = reminderTime.minute
        
        if let thisYearLunar = lunarCalendar.date(from: lunarComponents),
           thisYearLunar >= now {
            return thisYearLunar
        }
        lunarComponents.year = currentLunarYear + 1
        return lunarCalendar.date(from: lunarComponents).flatMap {
            gregorian.date(from: gregorian.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: $0))
        }
    }
}

private extension DateComponents {
    func formatAsTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let calendar = Calendar.current
        guard let date = calendar.date(from: self) else { return "—" }
        return formatter.string(from: date)
    }
}
