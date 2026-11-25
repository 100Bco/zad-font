import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

// Bước 1: app thử bật/tắt 1 file font bằng CoreText (không copy file).

struct ZADFontApp: App {
    var body: some Scene {
        WindowGroup("ZAD Font (bản thử)") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var url: URL?
    @State private var families: [String] = []
    @State private var active = false
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Chọn file font…", action: pick)

            if let url {
                Text(url.lastPathComponent).font(.headline)
                Text(families.joined(separator: ", ")).foregroundStyle(.secondary)
                Toggle("Bật font", isOn: Binding(get: { active }, set: { setActive($0) }))
                    .toggleStyle(.switch)
                if let name = families.first, active {
                    Text("Hội tụ tinh hoa chữ Việt")
                        .font(.custom(name, size: 28))
                }
            }

            Text(status)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 480, alignment: .leading)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        url = picked
        families = familyNames(picked)
        active = isRegistered(picked)
        status = "Trạng thái hiện tại: \(active ? "đang bật" : "đang tắt")"
    }

    private func setActive(_ on: Bool) {
        guard let url else { return }
        var error: Unmanaged<CFError>?
        let ok = on
            ? CTFontManagerRegisterFontsForURL(url as CFURL, .persistent, &error)
            : CTFontManagerUnregisterFontsForURL(url as CFURL, .persistent, &error)
        active = isRegistered(url)
        if ok {
            status = on ? "Đã bật. Mở Illustrator kiểm tra menu font." : "Đã tắt."
        } else {
            let message = error?.takeRetainedValue().localizedDescription ?? "không rõ"
            status = "Lỗi: \(message)"
        }
    }

    private func isRegistered(_ url: URL) -> Bool {
        CTFontManagerGetScopeForURL(url as CFURL) != CTFontManagerScope.none
    }

    private func familyNames(_ url: URL) -> [String] {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        let names = descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
        }
        return Array(Set(names)).sorted()
    }
}

NSApplication.shared.setActivationPolicy(.regular)
ZADFontApp.main()
