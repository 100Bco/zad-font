import SwiftUI
import AppKit
import CoreText

// Cột phải (chi tiết font), cửa sổ so sánh và gợi ý cặp font.

struct Panel<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let name = store.selectedFamily, let fam = store.family(named: name) {
            FamilyDetail(family: fam).id(fam.name)
        } else if let name = store.selectedFamily, let g = store.googleCatalog.first(where: { $0.family == name }) {
            GoogleDetail(g: g).id(g.family)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right").font(.system(size: 32)).foregroundStyle(.secondary)
                Text("Chọn một font để xem chi tiết").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FamilyDetail: View {
    @EnvironmentObject var store: Store
    let family: FontFamily

    @State private var faceID = ""
    @State private var size: Double = 56
    @State private var axisValues: [Int: Double] = [:]
    @State private var features: [String: Bool] = [:]
    @State private var tagText = ""
    @State private var chars: [String] = []
    @State private var showPairs = false

    private var face: FontFace { family.faces.first { $0.id == faceID } ?? family.primary }
    private var sample: String { store.previewText.isEmpty ? family.name : store.previewText }

    var body: some View {
        let base = FontKit.font(face, size: 12)
        let axes = FontKit.axes(base)
        let tags = FontKit.featureTags(base)
        let big = FontKit.font(face, size: size, features: features, variations: axisValues)
        let small = FontKit.font(face, size: 20, features: features, variations: axisValues)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text(sample)
                        .font(Font(big))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Text(FontKit.alphabet)
                        .font(Font(small))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack {
                        Image(systemName: "textformat.size").foregroundStyle(.secondary)
                        Slider(value: $size, in: 10...200)
                        Text("\(Int(size)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 50)
                    }
                }

                Panel("Kiểu chữ (\(family.faces.count))") {
                    ForEach(family.faces) { f in
                        HStack(spacing: 10) {
                            Toggle("Bật", isOn: store.fileBinding(f.url))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.mini)
                            Text(f.style).fontWeight(f.id == face.id ? .semibold : .regular)
                            Spacer()
                            Text(f.url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(f.id == face.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            faceID = f.id
                            axisValues = [:]
                            features = [:]
                        }
                    }
                }

                if !axes.isEmpty {
                    Panel("Trục variable") {
                        ForEach(axes) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(a.name)
                                    Spacer()
                                    Text(String(format: "%.0f", axisValues[a.id] ?? a.def))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(get: { axisValues[a.id] ?? a.def }, set: { axisValues[a.id] = $0 }),
                                       in: a.min...a.max)
                            }
                        }
                        Button("Đặt lại") { axisValues = [:] }.controlSize(.small)
                    }
                }

                if !tags.isEmpty {
                    Panel("Tính năng OpenType") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 6) {
                            ForEach(tags, id: \.self) { t in
                                Toggle(isOn: Binding(get: { features[t] ?? FontKit.defaultOnFeatures.contains(t) },
                                                     set: { features[t] = $0 })) {
                                    Text(FontKit.featureName(t)) + Text("  \(t)").font(.caption).foregroundColor(.secondary)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }

                Panel("Tag") {
                    TextField("vd: logo, tiêu đề, khách A", text: $tagText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.setTags(tagText, for: family.name) }
                    Text("Cách nhau bằng dấu phẩy, bấm Enter để lưu.").font(.caption).foregroundStyle(.secondary)
                }

                Panel("Collection") {
                    if store.data.collections.isEmpty {
                        Text("Chưa có collection nào.").foregroundStyle(.secondary)
                    }
                    ForEach(store.data.collections) { c in
                        Toggle(c.name, isOn: Binding(get: { c.families.contains(family.name) },
                                                     set: { $0 ? store.add(family.name, to: c.id) : store.remove(family.name, from: c.id) }))
                            .toggleStyle(.checkbox)
                    }
                    Button("Collection mới với font này") { store.newCollection(with: family.name) }
                        .controlSize(.small)
                }

                Panel("Bảng ký tự (\(chars.count)\(chars.count >= 2000 ? "+" : ""))") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 4)], spacing: 4) {
                        ForEach(chars, id: \.self) { c in
                            Text(c)
                                .font(Font(FontKit.font(face, size: 24, variations: axisValues)))
                                .frame(width: 46, height: 46)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                                .help(c.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))
                        }
                    }
                }
            }
            .padding(20)
        }
        .task(id: face.id) { chars = FontKit.characters(FontKit.font(face, size: 12)) }
        .onAppear { tagText = (store.data.tags[family.name] ?? []).joined(separator: ", ") }
        .onDisappear { store.setTags(tagText, for: family.name) }
        .sheet(isPresented: $showPairs) {
            PairingView(name: family.name, category: family.category, vietnamese: family.vietnamese)
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(family.name).font(.title2.bold()).textSelection(.enabled)
                    Text("\(family.faces.count) kiểu · \(family.category.label)\(face.variable ? " · Variable" : "")")
                        .foregroundStyle(.secondary)
                    if family.vietnamese {
                        VietBadge()
                    } else {
                        Text("Thiếu dấu tiếng Việt")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.orange)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                Spacer()
                FavoriteButton(name: family.name)
                Toggle("Bật", isOn: store.activeBinding(family)).toggleStyle(.switch)
            }
            HStack {
                Button { showPairs = true } label: { Label("Gợi ý cặp font", systemImage: "sparkles") }
                Button { store.toggleCompare(family.name) } label: {
                    Label(store.compare.contains(family.name) ? "Bỏ so sánh" : "So sánh", systemImage: "rectangle.split.2x1")
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting(family.files) } label: {
                    Label("Finder", systemImage: "folder")
                }
            }
            .controlSize(.small)
        }
    }
}

struct GoogleDetail: View {
    @EnvironmentObject var store: Store
    let g: GoogleFamily
    @State private var showPairs = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(g.family).font(.title2.bold()).textSelection(.enabled)
                Text("\(g.styles.count) kiểu · \(g.kind.label) · Google Fonts").foregroundStyle(.secondary)
                if g.vietnamese { VietBadge() }
                if let d = store.googlePreviews[g.family] {
                    Text(store.previewText.isEmpty ? g.family : store.previewText)
                        .font(Font(CTFontCreateWithFontDescriptor(d, 52, nil)))
                    Text(FontKit.alphabet)
                        .font(Font(CTFontCreateWithFontDescriptor(d, 20, nil)))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    GoogleAction(g: g)
                    Button { showPairs = true } label: { Label("Gợi ý cặp font", systemImage: "sparkles") }
                        .controlSize(.small)
                }
                Text("Tải về sẽ lưu ở ~/Library/Application Support/ZAD Font/Google Fonts và bật luôn. Sau khi tải, chọn font này trong Tất cả font để xem trục variable, OpenType và bảng ký tự.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await store.loadGooglePreview(g) }
        .sheet(isPresented: $showPairs) {
            PairingView(name: g.family, category: g.kind, vietnamese: g.vietnamese).environmentObject(store)
        }
    }
}

// MARK: - So sánh

struct CompareView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var size: Double = 44

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("So sánh \(store.compare.count) font").font(.title3.bold())
                Spacer()
                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                Slider(value: $size, in: 12...140).frame(width: 180)
                Text("\(Int(size)) pt").monospacedDigit().frame(width: 50)
                Button("Xoá danh sách") { store.compare.removeAll(); dismiss() }
                Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.compare, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(name).font(.headline)
                                if store.family(named: name)?.vietnamese == true { VietBadge() }
                                Spacer()
                                Button { store.toggleCompare(name) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                            }
                            Text(store.previewText.isEmpty ? name : store.previewText)
                                .font(store.swiftUIFont(named: name, size: size))
                                .lineLimit(2)
                            Text(FontKit.alphabet)
                                .font(store.swiftUIFont(named: name, size: 18))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        Divider()
                    }
                }
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }
}

// MARK: - Gợi ý cặp font

struct PairingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let name: String
    let category: FontCategory
    let vietnamese: Bool

    var body: some View {
        let rule = FontKit.pairRule(category)
        let items = store.pairSuggestions(name: name, targets: rule.targets, vietnamese: vietnamese)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gợi ý cặp cho \(name)").font(.title3.bold())
                    Text("Nhóm: \(category.label). \(rule.note)\(vietnamese ? " Chỉ gợi ý font có dấu tiếng Việt." : "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            if items.isEmpty {
                VStack(spacing: 8) {
                    if store.googleCatalog.isEmpty && store.googleError == nil {
                        ProgressView("Đang tải danh sách Google Fonts…")
                    } else {
                        Text(store.googleError ?? "Chưa tìm được font phù hợp.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { PairCard(base: name, other: $0, otherIsHeading: rule.otherIsHeading) }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .task {
            await store.loadGoogleCatalog()
            if store.family(named: name) == nil, let g = store.googleCatalog.first(where: { $0.family == name }) {
                await store.loadGooglePreview(g)
            }
        }
    }
}

struct PairCard: View {
    @EnvironmentObject var store: Store
    let base: String
    let other: PairSuggestion
    let otherIsHeading: Bool

    static let paragraph = "Chữ Việt có nhiều dấu thanh và dấu phụ, nên một cặp font tốt phải giữ được nhịp đọc khi dấu chồng lên nhau. Đoạn này giúp bạn xem phần nội dung có dễ đọc ở cỡ nhỏ không, và có hợp với tiêu đề phía trên không."

    var body: some View {
        let heading = otherIsHeading ? other.name : base
        let bodyFont = otherIsHeading ? base : other.name
        VStack(alignment: .leading, spacing: 10) {
            Text(store.previewText.isEmpty ? "Hội tụ tinh hoa chữ Việt" : store.previewText)
                .font(store.swiftUIFont(named: heading, size: 30))
                .lineLimit(2)
            Text(PairCard.paragraph)
                .font(store.swiftUIFont(named: bodyFont, size: 14))
                .lineSpacing(3)
            HStack {
                Text("Tiêu đề: \(heading)   Nội dung: \(bodyFont)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(other.google == nil ? "Trong thư viện" : "Google Fonts")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
                if let g = other.google {
                    GoogleAction(g: g)
                } else if let f = store.family(named: other.name) {
                    Toggle("Bật", isOn: store.activeBinding(f)).toggleStyle(.switch).controlSize(.small)
                }
            }
        }
        .modifier(CardStyle(selected: false))
        .task { if let g = other.google { await store.loadGooglePreview(g) } }
    }
}
