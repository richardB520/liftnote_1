import SwiftUI
import UserNotifications

@main
struct LiftNoteApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.tick(now: Date())
            } else {
                store.saveNow()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("训练", systemImage: "dumbbell.fill") }
            WeeklyView()
                .tabItem { Label("每周", systemImage: "chart.bar.fill") }
            HistoryView()
                .tabItem { Label("记录", systemImage: "book.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(isPresented: $store.isWorkoutPresented) {
            ActiveWorkoutView()
                .environmentObject(store)
        }
        .alert("提示", isPresented: errorBinding) {
            Button("好", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.lastError != nil && !store.isWorkoutPresented },
                set: { if !$0 { store.lastError = nil } })
    }
}
