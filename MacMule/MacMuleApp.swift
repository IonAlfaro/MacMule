import SwiftUI

@main
struct MacMuleApp: App {
    @StateObject private var store = MacMuleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1020, minHeight: 660)
                .onOpenURL { url in
                    store.handleOpenURL(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("eD2k") {
                Button("Paste eD2k Link") {
                    store.pasteED2KLink()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}
