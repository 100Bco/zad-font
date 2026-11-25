import Foundation
import CoreText

// Các hàm CoreText thuần: đọc file font, kiểm dấu tiếng Việt, phân loại, OpenType, variable, bật/tắt.

enum FontCategory: String, Codable, CaseIterable, Identifiable {
    case serif, sans, display, handwriting, mono, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .serif: return "Serif"
        case .sans: return "Sans Serif"
        case .display: return "Display"
        case .handwriting: return "Viết tay"
        case .mono: return "Monospace"
        case .other: return "Chưa phân loại"
        }
    }

    init(google: String) {
        switch google {
        case "Serif": self = .serif
        case "Sans Serif": self = .sans
        case "Display": self = .display
        case "Handwriting": self = .handwriting
        case "Monospace": self = .mono
        default: self = .other
        }
    }
}

struct FontFace: Identifiable {
    let id: String
    let url: URL
    let family: String
    let style: String
    let postScriptName: String
    let descriptor: CTFontDescriptor
    let weight: Double
    let italic: Bool
    let vietnamese: Bool
    let category: FontCategory
    let variable: Bool
}

struct FontFamily: Identifiable {
    let name: String
    let faces: [FontFace]
    let primary: FontFace
    let files: [URL]
    var id: String { name }
    var vietnamese: Bool { primary.vietnamese }
    var category: FontCategory { primary.category }

    init(name: String, faces: [FontFace]) {
        self.name = name
        self.faces = faces.sorted { ($0.italic ? 1 : 0, $0.weight) < ($1.italic ? 1 : 0, $1.weight) }
        self.primary = faces.min { FontFamily.score($0) < FontFamily.score($1) }!
        var seen = Set<String>()
        self.files = self.faces.map(\.url).filter { seen.insert($0.path).inserted }
    }

    // Kiểu gần Regular nhất: không nghiêng, độ đậm gần 0.
    static func score(_ f: FontFace) -> Double { (f.italic ? 10 : 0) + abs(f.weight) }
}

struct FolderNode: Identifiable, Hashable {
    let path: String
    let name: String
    var children: [FolderNode]?
    var id: String { path }
}

struct FontAxis: Identifiable {
    let id: Int
    let name: String
    let min: Double
    let max: Double
    let def: Double
}

enum FontKit {
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]
    static let vietnameseSample = "ạơưđỗằểựộỹ"
    static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 ạ ơ ư đ ỗ ằ ể ự ộ ỹ"

    // MARK: Quét file

    static func fontFiles(in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where fontExtensions.contains(u.pathExtension.lowercased()) {
            out.append(u)
        }
        return out
    }

    static func faces(in url: URL) -> [FontFace] {
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
        return descs.enumerated().map { i, d in
            let font = CTFontCreateWithFontDescriptor(d, 12, nil)
            let family = CTFontCopyFamilyName(font) as String
            let style = CTFontCopyName(font, kCTFontStyleNameKey).map { $0 as String } ?? "Regular"
            let traits = CTFontCopyTraits(font) as NSDictionary
            let weight = (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
            let sym = CTFontGetSymbolicTraits(font).rawValue
            return FontFace(id: "\(url.path)#\(i)", url: url, family: family, style: style,
                            postScriptName: CTFontCopyPostScriptName(font) as String, descriptor: d,
                            weight: weight, italic: sym & 1 != 0, vietnamese: hasVietnamese(font),
                            category: category(family: family, sym: sym),
                            variable: CTFontCopyVariationAxes(font) != nil)
        }
    }

    static func families(from faces: [FontFace]) -> [FontFamily] {
        Dictionary(grouping: faces, by: \.family)
            .map { FontFamily(name: $0.key, faces: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Cây thư mục con có chứa font, giữ nguyên cấu trúc gốc.
    static func tree(root: String, files: [URL]) -> FolderNode {
        var dirs = Set<String>()
        for f in files {
            var d = f.deletingLastPathComponent().path
            while d.hasPrefix(root + "/") {
                dirs.insert(d)
                d = (d as NSString).deletingLastPathComponent
            }
        }
        func node(_ path: String) -> FolderNode {
            let kids = dirs.filter { ($0 as NSString).deletingLastPathComponent == path }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map(node)
            return FolderNode(path: path, name: (path as NSString).lastPathComponent, children: kids.isEmpty ? nil : kids)
        }
        return node(root)
    }

    // MARK: Thông tin font

    static func hasVietnamese(_ font: CTFont) -> Bool {
        let chars = Array(vietnameseSample.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
    }

    static func category(family: String, sym: UInt32) -> FontCategory {
        if sym & (1 << 10) != 0 { return .mono }
        switch (sym >> 28) & 0xF {
        case 1, 2, 3, 4, 5, 6, 7: return .serif
        case 8: return .sans
        case 9: return .display
        case 10: return .handwriting
        default: break
        }
        // Nhiều font không ghi phân loại, đoán theo tên.
        let n = family.lowercased()
        if n.contains("mono") || n.contains("code") { return .mono }
        if n.contains("sans") || n.contains("grotesk") || n.contains("gothic") { return .sans }
        if n.contains("serif") || n.contains("garamond") || n.contains("times") || n.contains("roman") { return .serif }
        if n.contains("script") || n.contains("hand") || n.contains("brush") || n.contains("signature") { return .handwriting }
        return .other
    }

    static func font(_ face: FontFace, size: CGFloat, features: [String: Bool] = [:], variations: [Int: Double] = [:]) -> CTFont {
        var attrs: [String: Any] = [:]
        if !features.isEmpty {
            attrs[kCTFontFeatureSettingsAttribute as String] = features.map {
                [kCTFontOpenTypeFeatureTag as String: $0.key, kCTFontOpenTypeFeatureValue as String: $0.value ? 1 : 0] as [String: Any]
            }
        }
        if !variations.isEmpty {
            var v: [NSNumber: NSNumber] = [:]
            for (k, val) in variations { v[NSNumber(value: k)] = NSNumber(value: val) }
            attrs[kCTFontVariationAttribute as String] = v
        }
        let desc = attrs.isEmpty ? face.descriptor : CTFontDescriptorCreateCopyWithAttributes(face.descriptor, attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }

    static func axes(_ font: CTFont) -> [FontAxis] {
        guard let arr = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = (d[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue,
                  let mn = (d[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue,
                  let mx = (d[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue,
                  mx > mn else { return nil }
            let def = (d[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue ?? mn
            let name = d[kCTFontVariationAxisNameKey as String] as? String ?? tagString(id)
            return FontAxis(id: id, name: name, min: mn, max: mx, def: def)
        }
    }

    static func tagString(_ v: Int) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xFF) }, encoding: .ascii) ?? "\(v)"
    }

    // MARK: OpenType (đọc danh sách feature trong bảng GSUB)

    static let hiddenFeatures: Set<String> = [
        "ccmp", "locl", "rvrn", "rlig", "mark", "mkmk", "init", "medi", "fina", "isol", "aalt", "dnom", "numr",
        "abvs", "blws", "pres", "psts", "haln", "akhn", "rphf", "blwf", "half", "pstf", "vatu", "cjct", "nukt",
        "abvf", "ljmo", "vjmo", "tjmo", "rclt", "curs", "dist", "abvm", "blwm"
    ]
    static let defaultOnFeatures: Set<String> = ["liga", "calt", "clig", "kern"]
    static let featureNames: [String: String] = [
        "liga": "Chữ ghép chuẩn", "dlig": "Chữ ghép trang trí", "hlig": "Chữ ghép lịch sử",
        "calt": "Thay thế theo ngữ cảnh", "clig": "Chữ ghép ngữ cảnh", "smcp": "Chữ hoa nhỏ",
        "c2sc": "Hoa thành hoa nhỏ", "pcap": "Petite caps", "c2pc": "Hoa thành petite caps", "unic": "Unicase",
        "case": "Dấu theo chữ hoa", "onum": "Số kiểu cũ", "lnum": "Số thẳng hàng", "tnum": "Số đều bề rộng",
        "pnum": "Số tỉ lệ", "zero": "Số 0 có gạch", "frac": "Phân số", "afrc": "Phân số dọc",
        "sups": "Chỉ số trên", "subs": "Chỉ số dưới", "sinf": "Chỉ số khoa học", "ordn": "Số thứ tự",
        "salt": "Kiểu thay thế", "swsh": "Nét bay (swash)", "cswh": "Swash ngữ cảnh", "titl": "Kiểu tiêu đề",
        "ornm": "Hoa văn", "hist": "Kiểu lịch sử", "nalt": "Ký tự khoanh", "kern": "Kerning"
    ]

    static func featureName(_ tag: String) -> String {
        if let n = featureNames[tag] { return n }
        if tag.hasPrefix("ss"), let n = Int(tag.dropFirst(2)) { return "Bộ kiểu \(n)" }
        if tag.hasPrefix("cv"), let n = Int(tag.dropFirst(2)) { return "Biến thể ký tự \(n)" }
        return tag
    }

    static func featureTags(_ font: CTFont) -> [String] {
        guard let data = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [] }
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o >= 0 && o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        let list = u16(6)
        guard list > 0 else { return [] }
        var tags = Set<String>()
        for i in 0..<min(u16(list), 2000) {
            let r = list + 2 + i * 6
            guard r + 4 <= b.count else { break }
            if let t = String(bytes: b[r..<r + 4], encoding: .ascii) { tags.insert(t) }
        }
        return tags.subtracting(hiddenFeatures).sorted()
    }

    static func characters(_ font: CTFont, limit: Int = 2000) -> [String] {
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        var out: [String] = []
        for v in UInt32(0x21)...UInt32(0x2FFFF) {
            guard let s = Unicode.Scalar(v), set.contains(s) else { continue }
            let cat = s.properties.generalCategory
            if s.properties.isWhitespace || cat == .control || cat == .format || cat == .nonspacingMark { continue }
            out.append(String(Character(s)))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: Bật / tắt (không copy file)

    static func isActive(_ url: URL) -> Bool {
        CTFontManagerGetScopeForURL(url as CFURL) != CTFontManagerScope.none
    }

    /// Trả về nil nếu thành công, ngược lại là mô tả lỗi.
    static func setActive(_ url: URL, _ on: Bool) -> String? {
        var error: Unmanaged<CFError>?
        let ok = on
            ? CTFontManagerRegisterFontsForURL(url as CFURL, .persistent, &error)
            : CTFontManagerUnregisterFontsForURL(url as CFURL, .persistent, &error)
        if ok { return nil }
        guard let err = error?.takeRetainedValue() else { return "không rõ lỗi" }
        // 105: đã bật sẵn, 201: vốn chưa bật. Cả hai coi như xong.
        let code = CFErrorGetCode(err)
        if code == 105 || code == 201 { return nil }
        return CFErrorCopyDescription(err) as String
    }

    // MARK: Gợi ý cặp font (luật đơn giản theo phân loại, chạy trên máy)

    static func pairRule(_ c: FontCategory) -> (targets: [FontCategory], otherIsHeading: Bool, note: String) {
        switch c {
        case .serif:
            return ([.sans], false, "Font Serif làm tiêu đề, nội dung dùng Sans Serif cho dễ đọc.")
        case .sans:
            return ([.serif, .display], true, "Font Sans Serif làm nội dung, tiêu đề dùng Serif hoặc Display để tạo tương phản.")
        case .display, .handwriting:
            return ([.sans, .serif], false, "Font trang trí chỉ nên làm tiêu đề, nội dung dùng Sans Serif hoặc Serif.")
        case .mono:
            return ([.sans], true, "Font Monospace làm nội dung kỹ thuật, tiêu đề dùng Sans Serif.")
        case .other:
            return ([.sans, .serif], false, "Chưa rõ nhóm của font này, thử ghép với Sans Serif hoặc Serif.")
        }
    }
}
