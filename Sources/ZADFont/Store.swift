import SwiftUI
import AppKit
import CoreText

enum SidebarItem: Hashable {
    case all, active, favorites, google
    case folder(String)
    case collection(UUID)
    case tag(String)
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid = "Lưới", list = "Danh sách", waterfall = "Waterfall"
    var id: String { rawValue }
}

struct FontCollection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var families: [String] = []
}

/// Lưu trong ~/Library/Application Support/ZAD Font/library.json
struct LibraryData: Codable {
    var folders: [String] = []
    var favorites: [String] = []
    var collections: [FontCollection] = []
    var tags: [String: [String]] = [:]
}

struct PairSuggestion: Identifiable {
    let name: String
    let category: FontCategory
    let google: GoogleFamily?
    var id: String { name }
}

@MainActor
final class Store: ObservableObject {
    @Published var data = LibraryData() { didSet { save() } }

    // Thư viện
    @Published var families: [FontFamily] = []
    @Published var activeFiles: Set<String> = []
    @Published var folderTrees: [FolderNode] = []
    @Published var googleDownloaded: Set<String> = []
    @Published var scanning = false
    @Published var message = ""

    // Trạng thái giao diện
    @Published var selection: SidebarItem? = .all
    @Published var selectedFamily: String?
    @Published var previewText = "Hội tụ tinh hoa chữ Việt"
    @Published var fontSize: Double = 36
    @Published var mode: ViewMode = .grid
    @Published var search = ""
    @Published var vietnameseOnly = false
    @Published var compare: [String] = []
    @Published var showCompare = false

    // Google Fonts
    @Published var googleCatalog: [GoogleFamily] = []
    @Published var googleError: String?
    @Published var googleCategory: FontCategory?
    @Published var googlePreviews: [String: CTFontDescriptor] = [:]
    @Published var googleFailed: Set<String> = []
    @Published var googleBusy: Set<String> = []

    let supportDir: URL
    let googleDir: URL
    let previewDir: URL
    private var libraryURL: URL { supportDir.appendingPathComponent("library.json") }
    private var catalogCacheURL: URL { supportDir.appendingPathComponent("google-catalog.json") }
    private var loadingPreviews: Set<String> = []
    private var scanID = 0

    init() {
        let fm = FileManager.default
        supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZAD Font", isDirectory: true)
        googleDir = supportDir.appendingPathComponent("Google Fonts", isDirectory: true)
        previewDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZAD Font/Google Preview", isDirectory: true)
        try? fm.createDirectory(at: googleDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: libraryURL) {
            do { data = try JSONDecoder().decode(LibraryData.self, from: raw) } catch {
                message = "Không đọc được library.json: \(error.localizedDescription)"
            }
        }
        rescan()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(data).write(to: libraryURL, options: .atomic) } catch {
            message = "Lỗi lưu dữ liệu: \(error.localizedDescription)"
        }
    }

    // MARK: Quét thư viện

    func rescan() {
        scanID += 1
        let id = scanID
        let roots = data.folders
        let google = googleDir
        scanning = true
        Task.detached(priority: .userInitiated) {
            var faces: [FontFace] = []
            var trees: [FolderNode] = []
            var seen = Set<String>()
            for root in roots {
                let files = FontKit.fontFiles(in: URL(fileURLWithPath: root))
                trees.append(FontKit.tree(root: root, files: files))
                for f in files where seen.insert(f.path).inserted { faces += FontKit.faces(in: f) }
            }
            for f in FontKit.fontFiles(in: google) where seen.insert(f.path).inserted { faces += FontKit.faces(in: f) }
            let families = FontKit.families(from: faces)
            let active = Set(faces.map(\.url).filter(FontKit.isActive).map(\.path))
            let downloaded = Set((try? FileManager.default.contentsOfDirectory(atPath: google.path)) ?? [])
            await MainActor.run {
                guard id == self.scanID else { return }
                self.families = families
                self.folderTrees = trees
                self.activeFiles = active
                self.googleDownloaded = downloaded
                self.scanning = false
                self.message = "\(families.count) family, \(faces.count) kiểu chữ, \(active.count) file đang bật."
            }
        }
    }

    func addFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.prompt = "Theo dõi"
        p.message = "Chọn thư mục chứa font. App đọc font tại chỗ, không copy."
        guard p.runModal() == .OK else { return }
        let new = p.urls.map(\.path).filter { !data.folders.contains($0) }
        guard !new.isEmpty else { return }
        data.folders += new
        rescan()
    }

    func removeFolder(_ path: String) {
        data.folders.removeAll { $0 == path }
        if selection == .folder(path) { selection = .all }
        rescan()
    }

    // MARK: Lọc

    var visibleFamilies: [FontFamily] {
        var list: [FontFamily]
        switch selection ?? .all {
        case .all, .google:
            list = families
        case .active:
            list = families.filter { isActive($0) }
        case .favorites:
            list = families.filter { data.favorites.contains($0.name) }
        case .folder(let p):
            list = families.filter { $0.files.contains { $0.path.hasPrefix(p + "/") } }
        case .collection(let id):
            let names = Set(data.collections.first { $0.id == id }?.families ?? [])
            list = families.filter { names.contains($0.name) }
        case .tag(let t):
            list = families.filter { data.tags[$0.name]?.contains(t) == true }
        }
        if vietnameseOnly { list = list.filter(\.vietnamese) }
        if !search.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        return list
    }

    var title: String {
        switch selection ?? .all {
        case .all: return "Tất cả font"
        case .active: return "Đang bật"
        case .favorites: return "Yêu thích"
        case .google: return "Google Fonts"
        case .folder(let p): return (p as NSString).lastPathComponent
        case .collection(let id): return data.collections.first { $0.id == id }?.name ?? "Collection"
        case .tag(let t): return "Tag: \(t)"
        }
    }

    var selectedCollection: FontCollection? {
        if case .collection(let id) = selection { return data.collections.first { $0.id == id } }
        return nil
    }

    func family(named name: String) -> FontFamily? { families.first { $0.name == name } }

    // MARK: Bật / tắt

    func isActive(_ f: FontFamily) -> Bool { f.files.contains { activeFiles.contains($0.path) } }

    func setActive(_ files: [URL], _ on: Bool) {
        var errors: [String] = []
        for f in files {
            if let e = FontKit.setActive(f, on) { errors.append("\(f.lastPathComponent): \(e)") }
            if FontKit.isActive(f) { activeFiles.insert(f.path) } else { activeFiles.remove(f.path) }
        }
        if errors.isEmpty {
            message = on ? "Đã bật \(files.count) file font." : "Đã tắt \(files.count) file font."
        } else {
            message = "Lỗi: " + errors.joined(separator: "; ")
        }
    }

    func setActive(_ family: FontFamily, _ on: Bool) { setActive(family.files, on) }

    func setActive(collection c: FontCollection, _ on: Bool) {
        let names = Set(c.families)
        setActive(families.filter { names.contains($0.name) }.flatMap(\.files), on)
    }

    func activeBinding(_ f: FontFamily) -> Binding<Bool> {
        Binding(get: { self.isActive(f) }, set: { self.setActive(f, $0) })
    }

    func fileBinding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.activeFiles.contains(url.path) }, set: { self.setActive([url], $0) })
    }

    // MARK: Yêu thích, collection, tag, so sánh

    func isFavorite(_ name: String) -> Bool { data.favorites.contains(name) }

    func toggleFavorite(_ name: String) {
        if let i = data.favorites.firstIndex(of: name) { data.favorites.remove(at: i) } else { data.favorites.append(name) }
    }

    func newCollection(with family: String? = nil) {
        var c = FontCollection(name: "Collection \(data.collections.count + 1)")
        if let family { c.families = [family] }
        data.collections.append(c)
        if family == nil { selection = .collection(c.id) }
        message = family.map { "Đã tạo \(c.name) với \($0)." } ?? "Đã tạo \(c.name). Chuột phải để đổi tên."
    }

    func add(_ family: String, to id: UUID) {
        guard let i = data.collections.firstIndex(where: { $0.id == id }),
              !data.collections[i].families.contains(family) else { return }
        data.collections[i].families.append(family)
    }

    func remove(_ family: String, from id: UUID) {
        guard let i = data.collections.firstIndex(where: { $0.id == id }) else { return }
        data.collections[i].families.removeAll { $0 == family }
    }

    func renameCollection(_ id: UUID, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = data.collections.firstIndex(where: { $0.id == id }) else { return }
        data.collections[i].name = n
    }

    func deleteCollection(_ id: UUID) {
        data.collections.removeAll { $0.id == id }
        if selection == .collection(id) { selection = .all }
    }

    var allTags: [String] { Array(Set(data.tags.values.flatMap { $0 })).sorted() }

    func setTags(_ text: String, for family: String) {
        let t = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let value: [String]? = t.isEmpty ? nil : t
        if data.tags[family] != value { data.tags[family] = value }
    }

    func toggleCompare(_ name: String) {
        if let i = compare.firstIndex(of: name) {
            compare.remove(at: i)
        } else if compare.count < 4 {
            compare.append(name)
            message = "Đang so sánh \(compare.count) font. Bấm nút So sánh trên thanh công cụ."
        } else {
            message = "So sánh tối đa 4 font."
        }
    }

    /// Font SwiftUI theo tên family: ưu tiên thư viện, sau đó bản xem trước Google, cuối cùng là font hệ thống.
    func swiftUIFont(named name: String, size: CGFloat) -> Font {
        if let f = family(named: name) { return Font(FontKit.font(f.primary, size: size)) }
        if let d = googlePreviews[name] { return Font(CTFontCreateWithFontDescriptor(d, size, nil)) }
        return .system(size: size)
    }

    // MARK: Gợi ý cặp font

    func pairSuggestions(name: String, targets: [FontCategory], vietnamese: Bool) -> [PairSuggestion] {
        var out: [PairSuggestion] = []
        let library = families.sorted { isActive($0) && !isActive($1) }
        for f in library where f.name != name && targets.contains(f.category) && (!vietnamese || f.vietnamese) {
            out.append(PairSuggestion(name: f.name, category: f.category, google: nil))
            if out.count >= 4 { break }
        }
        for g in googleCatalog where g.family != name && targets.contains(g.kind) && (!vietnamese || g.vietnamese)
            && !out.contains(where: { $0.name == g.family }) {
            out.append(PairSuggestion(name: g.family, category: g.kind, google: g))
            if out.count >= 12 { break }
        }
        return out
    }

    // MARK: Google Fonts

    func loadGoogleCatalog() async {
        guard googleCatalog.isEmpty else { return }
        googleError = nil
        let cache = catalogCacheURL
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        do {
            var raw: Data
            if age < 7 * 86400, let d = try? Data(contentsOf: cache) {
                raw = d
            } else {
                do {
                    raw = try await GoogleFonts.get(GoogleFonts.catalogURL)
                    try? raw.write(to: cache, options: .atomic)
                } catch {
                    guard let d = try? Data(contentsOf: cache) else { throw error }
                    raw = d  // mất mạng thì dùng bản cũ
                }
            }
            googleCatalog = try GoogleFonts.decodeCatalog(raw)
        } catch {
            googleError = "Không tải được danh sách Google Fonts: \(error.localizedDescription)"
        }
    }

    var visibleGoogle: [GoogleFamily] {
        googleCatalog.filter {
            (googleCategory == nil || $0.kind == googleCategory)
                && (!vietnameseOnly || $0.vietnamese)
                && (search.isEmpty || $0.family.localizedCaseInsensitiveContains(search))
        }
    }

    /// Tải 1 kiểu (Regular) vào cache để xem trước, không bật.
    func loadGooglePreview(_ g: GoogleFamily) async {
        let name = g.family
        guard googlePreviews[name] == nil, !googleFailed.contains(name), !loadingPreviews.contains(name) else { return }
        loadingPreviews.insert(name)
        defer { loadingPreviews.remove(name) }
        let file = previewDir.appendingPathComponent(name + ".ttf")
        do {
            if !FileManager.default.fileExists(atPath: file.path) {
                guard let style = g.regular, let first = try await GoogleFonts.fontFiles(name, [style]).first else {
                    throw NSError(domain: "GoogleFonts", code: 4)
                }
                try await GoogleFonts.get(first.url).write(to: file, options: .atomic)
            }
            if let d = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])?.first {
                googlePreviews[name] = d
            } else {
                googleFailed.insert(name)
            }
        } catch {
            // Thẻ cuộn khỏi màn hình thì task bị huỷ, không tính là lỗi.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            googleFailed.insert(name)
        }
    }

    func downloadGoogle(_ g: GoogleFamily) async {
        let name = g.family
        googleBusy.insert(name)
        defer { googleBusy.remove(name) }
        let dir = googleDir.appendingPathComponent(name, isDirectory: true)
        do {
            let list = try await GoogleFonts.fontFiles(name, g.styles)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var files: [URL] = []
            let base = name.replacingOccurrences(of: " ", with: "")
            for item in list {
                let file = dir.appendingPathComponent("\(base)-\(item.style.wght)\(item.style.ital == 1 ? "Italic" : "").ttf")
                if files.contains(file) { continue }
                try await GoogleFonts.get(item.url).write(to: file, options: .atomic)
                files.append(file)
            }
            setActive(files, true)
            googleDownloaded.insert(name)
            rescan()
            message = "Đã tải và bật \(name) (\(files.count) kiểu), lưu ở \(dir.path)"
        } catch {
            message = "Lỗi tải \(name): \(error.localizedDescription)"
        }
    }

    func googleFiles(_ family: String) -> [URL] {
        let dir = googleDir.appendingPathComponent(family, isDirectory: true)
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { FontKit.fontExtensions.contains($0.pathExtension.lowercased()) }
    }

    func googleActiveBinding(_ family: String) -> Binding<Bool> {
        Binding(get: { self.googleFiles(family).contains { self.activeFiles.contains($0.path) } },
                set: { self.setActive(self.googleFiles(family), $0) })
    }
}
