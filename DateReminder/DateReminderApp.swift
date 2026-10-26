//
//  DateReminderApp.swift
//  DateReminder
//
//  Created by Dennis on 2026/3/20.
//

import SwiftUI
import SwiftData

@main
struct DateReminderApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        // 关闭 iCloud，同步改为手动 CSV 导入/导出
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
