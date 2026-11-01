import SwiftUI

@main @MainActor struct MikaConsoleApp: App {
    @StateObject private var store = ConsoleStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .privacySensitive()
                .overlay {
                    if scenePhase != .active {
                        Color(.systemBackground).ignoresSafeArea()
                            .overlay(Text("Mika 控制台").font(.title))
                    }
                }
                .task(id: "\(scenePhase)-\(store.connectionID)") {
                    if scenePhase == .active { await store.refresh() }
                }
        }
    }
}

@MainActor struct RootView: View {
    @EnvironmentObject private var store: ConsoleStore
    var body: some View {
        TabView {
            TaskListView().id(store.connectionID)
                .tabItem { Label("任务", systemImage: "list.bullet") }
            ConnectionView().tabItem { Label("连接", systemImage: "network") }
        }
    }
}

@MainActor struct SafetyNotice: View {
    var body: some View {
        Text("仅在可信局域网或私有 VPN 使用。HTTP 明文传输。付款、同意和手机接管步骤只能在安卓手机处理，远程回答不能代替确认。")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
