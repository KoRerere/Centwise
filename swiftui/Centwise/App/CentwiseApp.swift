import SwiftUI

@main
struct CentwiseApp: App {
    @State private var store = LedgerStore.open()
    @Environment(\.scenePhase) private var scenePhase
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            app
        }
    }

    private var app: some View {
        RootView()
            .id(store.languageVersion)
            .environment(store)
            .environment(\.locale, L10n.locale)
            .preferredColorScheme(store.colorScheme)
            .tint(.cwInk)
            .onReceive(clock) { _ in store.refreshDay() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: store.refreshDay()
                case .background: store.dismissUndo()
                default: break
                }
            }
    }
}
