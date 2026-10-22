import SwiftUI

@main
struct CentwiseApp: App {
    @StateObject private var store = LedgerStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .onOpenURL { store.prepareImport($0) }
                #if os(macOS)
                .frame(minWidth: 380, idealWidth: 430, minHeight: 740, idealHeight: 900)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 900)
        #endif
    }
}
