import SwiftUI
import AppKit

// ZAD Font: quản lý font cho Mac. Bật/tắt font tại chỗ bằng CoreText, không copy file.

struct ZADFontApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("ZAD Font") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 640)
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Thêm thư mục theo dõi…") { store.addFolder() }
                    .keyboardShortcut("o")
            }
        }
    }
}

NSApplication.shared.setActivationPolicy(.regular)
ZADFontApp.main()
