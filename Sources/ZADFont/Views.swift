import SwiftUI
import AppKit
import CoreText

// Ba cột: thanh bên (trái), danh sách font (giữa), chi tiết (phải).

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } content: {
            Group {
                if store.selection == .google { GoogleFontsView() } else { LibraryView() }
            }
            .navigationSplitViewColumnWidth(min: 460, ideal: 720)
        } detail: {
            DetailView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        }
        .sheet(isPresented: $store.showCompare) {
            CompareView().environmentObject(store)
        }
    }
}

// MARK: - Thanh bên

struct SidebarView: View {
    @EnvironmentObject var store: Store
    @State private var renaming: FontCollection?
    @State private var newName = ""

    var body: some View {
        List(selection: $store.selection) {
            Section("Thư viện") {
                Label("Tất cả font", systemImage: "textformat").badge(store.families.count).tag(SidebarItem.all)
                Label("Đang bật", systemImage: "power").badge(store.families.filter { store.isActive($0) }.count).tag(SidebarItem.active)
                Label("Yêu thích", systemImage: "star").badge(store.data.favorites.count).tag(SidebarItem.favorites)
                Label("Google Fonts", systemImage: "globe").tag(SidebarItem.google)
            }

            Section("Thư mục theo dõi") {
                OutlineGroup(store.folderTrees, children: \.children) { node in
                    Label(node.name, systemImage: "folder")
                        .tag(SidebarItem.folder(node.path))
                        .help(node.path)
                        .contextMenu {
                            Button("Hiện trong Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
                            if store.data.folders.contains(node.path) {
                                Button("Bỏ theo dõi", role: .destructive) { store.removeFolder(node.path) }
                            }
                        }
                }
                Button { store.addFolder() } label: { Label("Thêm thư mục…", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Section("Collection") {
                ForEach(store.data.collections) { c in
                    Label(c.name, systemImage: "square.stack").badge(c.families.count)
                        .tag(SidebarItem.collection(c.id))
                        .contextMenu {
                            Button("Bật cả collection") { store.setActive(collection: c, true) }
                            Button("Tắt cả collection") { store.setActive(collection: c, false) }
                            Divider()
                            Button("Đổi tên…") { newName = c.name; renaming = c }
                            Button("Xoá collection", role: .destructive) { store.deleteCollection(c.id) }
                        }
                }
                Button { store.newCollection() } label: { Label("Collection mới", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if !store.allTags.isEmpty {
                Section("Tag") {
                    ForEach(store.allTags, id: \.self) { t in
                        Label(t, systemImage: "tag").tag(SidebarItem.tag(t))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("Đổi tên collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên collection", text: $newName)
            Button("Lưu") {
                if let c = renaming { store.renameCollection(c.id, newName) }
                renaming = nil
            }
            Button("Huỷ", role: .cancel) { renaming = nil }
        }
    }
}

// MARK: - Thanh điều khiển xem trước

struct PreviewControls: View {
    @EnvironmentObject var store: Store
    var showMode = true

    var body: some View {
        HStack(spacing: 12) {
            TextField("Gõ chữ để xem trước", text: $store.previewText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)
            Image(systemName: "textformat.size").foregroundStyle(.secondary)
            Slider(value: $store.fontSize, in: 10...160)
                .frame(width: 130)
            Text("\(Int(store.fontSize)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            if showMode {
                Picker("Kiểu xem", selection: $store.mode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
            }
            Toggle("Có dấu TV", isOn: $store.vietnameseOnly)
                .toggleStyle(.checkbox)
                .help("Chỉ hiện font có đủ dấu tiếng Việt")
        }
        .padding(12)
    }
}

struct StatusBar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 8) {
            if store.scanning { ProgressView().controlSize(.small) }
            Text(store.scanning ? "Đang quét font…" : store.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Danh sách font trong thư viện

struct LibraryView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let list = store.visibleFamilies
        VStack(spacing: 0) {
            PreviewControls()
            Divider()
            if list.isEmpty {
                EmptyLibrary()
            } else {
                ScrollView {
                    switch store.mode {
                    case .grid:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                            ForEach(list) { FamilyCard(family: $0) }
                        }
                        .padding(16)
                    case .list:
                        LazyVStack(spacing: 0) {
                            ForEach(list) { f in
                                FamilyRow(family: f)
                                Divider()
                            }
                        }
                    case .waterfall:
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(list) { f in
                                WaterfallBlock(family: f)
                                Divider()
                            }
                        }
                    }
                }
            }
            StatusBar()
        }
        .navigationTitle(store.title)
        .navigationSubtitle("\(list.count) family")
        .searchable(text: $store.search, prompt: "Tìm font")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let c = store.selectedCollection {
                    Button { store.setActive(collection: c, true) } label: { Label("Bật collection", systemImage: "power") }
                        .help("Bật tất cả font trong collection")
                    Button { store.setActive(collection: c, false) } label: { Label("Tắt collection", systemImage: "poweroff") }
                        .help("Tắt tất cả font trong collection")
                }
                Button { store.showCompare = true } label: {
                    Label("So sánh (\(store.compare.count))", systemImage: "rectangle.split.2x1")
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.compare.count < 2)
                .help("Chuột phải vào font > Thêm vào so sánh (2 đến 4 font)")
                Button { store.addFolder() } label: { Label("Thêm thư mục", systemImage: "folder.badge.plus") }
                    .help("Thêm thư mục theo dõi")
                Button { store.rescan() } label: { Label("Quét lại", systemImage: "arrow.clockwise") }
                    .help("Quét lại các thư mục")
            }
        }
    }
}

struct EmptyLibrary: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "textformat").font(.system(size: 44)).foregroundStyle(.secondary)
            if store.families.isEmpty && !store.scanning {
                Text("Chưa có font nào").font(.title3.weight(.semibold))
                Text("Thêm thư mục chứa font, kể cả thư mục Google Drive đã sync.\nApp đọc font tại chỗ, không copy file.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Thêm thư mục…") { store.addFolder() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Duyệt Google Fonts") { store.selection = .google }
            } else {
                Text(store.scanning ? "Đang quét font…" : "Không có font phù hợp").font(.title3)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CardStyle: ViewModifier {
    var selected: Bool

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
    }
}

struct FamilyCard: View {
    @EnvironmentObject var store: Store
    let family: FontFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(family.name).font(.headline).lineLimit(1)
                    Text("\(family.faces.count) kiểu · \(family.category.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                FavoriteButton(name: family.name)
                Toggle("Bật", isOn: store.activeBinding(family))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            Text(store.previewText.isEmpty ? family.name : store.previewText)
                .font(Font(FontKit.font(family.primary, size: store.fontSize)))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: min(store.fontSize * 1.3, 210), alignment: .leading)
            if family.vietnamese { VietBadge() }
        }
        .modifier(CardStyle(selected: store.selectedFamily == family.name))
        .onTapGesture { store.selectedFamily = family.name }
        .contextMenu { FamilyMenu(family: family) }
    }
}

struct FamilyRow: View {
    @EnvironmentObject var store: Store
    let family: FontFamily

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Bật", isOn: store.activeBinding(family))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(family.faces.count) kiểu").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)
            Text(store.previewText.isEmpty ? family.name : store.previewText)
                .font(Font(FontKit.font(family.primary, size: min(store.fontSize, 48))))
                .lineLimit(1)
            Spacer(minLength: 0)
            if family.vietnamese { VietBadge() }
            FavoriteButton(name: family.name)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(store.selectedFamily == family.name ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedFamily = family.name }
        .contextMenu { FamilyMenu(family: family) }
    }
}

struct WaterfallBlock: View {
    @EnvironmentObject var store: Store
    let family: FontFamily
    static let sizes: [CGFloat] = [12, 16, 24, 36, 48, 72]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(family.name).font(.headline)
                if family.vietnamese { VietBadge() }
                Spacer()
                FavoriteButton(name: family.name)
                Toggle("Bật", isOn: store.activeBinding(family))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            ForEach(WaterfallBlock.sizes, id: \.self) { s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(s))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(store.previewText.isEmpty ? family.name : store.previewText)
                        .font(Font(FontKit.font(family.primary, size: s)))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(store.selectedFamily == family.name ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedFamily = family.name }
        .contextMenu { FamilyMenu(family: family) }
    }
}

struct FamilyMenu: View {
    @EnvironmentObject var store: Store
    let family: FontFamily

    var body: some View {
        let active = store.isActive(family)
        Button(active ? "Tắt font" : "Bật font") { store.setActive(family, !active) }
        Button(store.isFavorite(family.name) ? "Bỏ yêu thích" : "Yêu thích") { store.toggleFavorite(family.name) }
        Button(store.compare.contains(family.name) ? "Bỏ khỏi so sánh" : "Thêm vào so sánh") { store.toggleCompare(family.name) }
        Menu("Thêm vào collection") {
            ForEach(store.data.collections) { c in
                Button(c.name) { store.add(family.name, to: c.id) }
            }
            Divider()
            Button("Collection mới với font này") { store.newCollection(with: family.name) }
        }
        if let c = store.selectedCollection {
            Button("Bỏ khỏi \(c.name)") { store.remove(family.name, from: c.id) }
        }
        Divider()
        Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting(family.files) }
    }
}

struct FavoriteButton: View {
    @EnvironmentObject var store: Store
    let name: String

    var body: some View {
        let on = store.isFavorite(name)
        Button { store.toggleFavorite(name) } label: {
            Image(systemName: on ? "star.fill" : "star")
                .foregroundStyle(on ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(on ? "Bỏ yêu thích" : "Yêu thích")
    }
}

struct VietBadge: View {
    var body: some View {
        Text("Có dấu tiếng Việt")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(Color.green)
            .background(Capsule().fill(Color.green.opacity(0.15)))
    }
}

// MARK: - Google Fonts

struct GoogleFontsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let list = store.visibleGoogle
        VStack(spacing: 0) {
            PreviewControls(showMode: false)
            HStack {
                Picker("Nhóm", selection: $store.googleCategory) {
                    Text("Tất cả nhóm").tag(FontCategory?.none)
                    ForEach([FontCategory.serif, .sans, .display, .handwriting, .mono]) { c in
                        Text(c.label).tag(Optional(c))
                    }
                }
                .frame(width: 240)
                Spacer()
                Text("\(list.count) family").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Divider()
            if store.googleCatalog.isEmpty {
                VStack(spacing: 12) {
                    if let e = store.googleError {
                        Text(e).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Thử lại") { Task { await store.loadGoogleCatalog() } }
                    } else {
                        ProgressView("Đang tải danh sách Google Fonts…")
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(list) { GoogleCard(g: $0) }
                    }
                    .padding(16)
                }
            }
            StatusBar()
        }
        .navigationTitle("Google Fonts")
        .navigationSubtitle("\(list.count) family")
        .searchable(text: $store.search, prompt: "Tìm Google Fonts")
        .task { await store.loadGoogleCatalog() }
    }
}

struct GoogleCard: View {
    @EnvironmentObject var store: Store
    let g: GoogleFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.family).font(.headline).lineLimit(1)
                    Text("\(g.styles.count) kiểu · \(g.kind.label)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                GoogleAction(g: g)
            }
            Group {
                if let d = store.googlePreviews[g.family] {
                    Text(store.previewText.isEmpty ? g.family : store.previewText)
                        .font(Font(CTFontCreateWithFontDescriptor(d, store.fontSize, nil)))
                } else if store.googleFailed.contains(g.family) {
                    Text("Không tải được bản xem trước").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: min(store.fontSize * 1.3, 210), alignment: .leading)
            if g.vietnamese { VietBadge() }
        }
        .modifier(CardStyle(selected: store.selectedFamily == g.family))
        .onTapGesture { store.selectedFamily = g.family }
        .task { await store.loadGooglePreview(g) }
    }
}

struct GoogleAction: View {
    @EnvironmentObject var store: Store
    let g: GoogleFamily

    var body: some View {
        if store.googleBusy.contains(g.family) {
            ProgressView().controlSize(.small)
        } else if store.googleDownloaded.contains(g.family) {
            Toggle("Bật", isOn: store.googleActiveBinding(g.family))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        } else {
            Button("Tải & bật") { Task { await store.downloadGoogle(g) } }
                .controlSize(.small)
        }
    }
}
