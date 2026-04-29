import SwiftUI

@main
struct MoonlitApp: App {
    @StateObject private var taskStore = TaskStore()
    @StateObject private var scheduler: Scheduler

    init() {
        let store = TaskStore()
        _taskStore = StateObject(wrappedValue: store)
        _scheduler = StateObject(wrappedValue: Scheduler(taskStore: store))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(taskStore)
                .environmentObject(scheduler)
        } label: {
            Image(systemName: "moon.stars")
        }
        .menuBarExtraStyle(.window)
    }
}
