import Foundation

// Google Fonts không cần API key:
// - Danh sách: https://fonts.google.com/metadata/fonts (có nhóm, subsets, độ phổ biến)
// - File .ttf: lấy link từ https://fonts.googleapis.com/css2 (client lạ được trả về truetype)

struct GoogleStyle: Hashable, Comparable {
    let ital: Int
    let wght: Int

    init(ital: Int, wght: Int) {
        self.ital = ital
        self.wght = wght
    }

    // "400" -> thường 400, "700i" -> nghiêng 700
    init?(key: String) {
        let italic = key.hasSuffix("i")
        guard let w = Int(italic ? String(key.dropLast()) : key) else { return nil }
        self.init(ital: italic ? 1 : 0, wght: w)
    }

    static func < (a: GoogleStyle, b: GoogleStyle) -> Bool { (a.ital, a.wght) < (b.ital, b.wght) }
}

struct GoogleFamily: Decodable, Identifiable {
    struct Info: Decodable {}

    let family: String
    let category: String
    let subsets: [String]?
    let fonts: [String: Info]?
    let popularity: Int?

    var id: String { family }
    var kind: FontCategory { FontCategory(google: category) }
    var vietnamese: Bool { subsets?.contains("vietnamese") == true }
    var styles: [GoogleStyle] { (fonts.map { Array($0.keys) } ?? []).compactMap { GoogleStyle(key: $0) }.sorted() }
    var regular: GoogleStyle? { styles.first { $0 == GoogleStyle(ital: 0, wght: 400) } ?? styles.first }
}

enum GoogleFonts {
    static let catalogURL = URL(string: "https://fonts.google.com/metadata/fonts")!

    private struct Catalog: Decodable { let familyMetadataList: [GoogleFamily] }

    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("ZADFont/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw NSError(domain: "HTTP", code: h.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Máy chủ \(url.host ?? "") trả về mã \(h.statusCode)"])
        }
        return data
    }

    static func decodeCatalog(_ data: Data) throws -> [GoogleFamily] {
        // Phản hồi có thể có vài ký tự rác trước dấu {
        guard let start = data.firstIndex(of: UInt8(ascii: "{")) else {
            throw NSError(domain: "GoogleFonts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Danh sách Google Fonts không đúng định dạng"])
        }
        return try JSONDecoder().decode(Catalog.self, from: data[start...]).familyMetadataList
            .sorted { ($0.popularity ?? .max) < ($1.popularity ?? .max) }
    }

    static func cssURL(_ family: String, _ styles: [GoogleStyle]) -> URL? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")
        let name = (family.addingPercentEncoding(withAllowedCharacters: allowed) ?? family)
            .replacingOccurrences(of: " ", with: "+")
        if styles.isEmpty { return URL(string: "https://fonts.googleapis.com/css2?family=\(name)") }
        let spec = styles.map { "\($0.ital),\($0.wght)" }.joined(separator: ";")
        return URL(string: "https://fonts.googleapis.com/css2?family=\(name):ital,wght@\(spec)")
    }

    /// Link .ttf cho từng kiểu chữ. Nếu yêu cầu đủ kiểu bị từ chối thì lấy kiểu mặc định.
    static func fontFiles(_ family: String, _ styles: [GoogleStyle]) async throws -> [(style: GoogleStyle, url: URL)] {
        guard let full = cssURL(family, styles), let plain = cssURL(family, []) else {
            throw NSError(domain: "GoogleFonts", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tên font không hợp lệ: \(family)"])
        }
        let css: Data
        do { css = try await get(full) } catch { css = try await get(plain) }
        let files = parse(String(decoding: css, as: UTF8.self))
        if files.isEmpty {
            throw NSError(domain: "GoogleFonts", code: 3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy file font của \(family)"])
        }
        return files
    }

    static func parse(_ css: String) -> [(style: GoogleStyle, url: URL)] {
        var out: [(style: GoogleStyle, url: URL)] = []
        for block in css.components(separatedBy: "@font-face").dropFirst() {
            guard let src = capture(block, "src: url\\((.+?)\\)"), let url = URL(string: src) else { continue }
            let weight = Int(capture(block, "font-weight: (\\d+)") ?? "") ?? 400
            let italic = block.contains("font-style: italic")
            out.append((GoogleStyle(ital: italic ? 1 : 0, wght: weight), url))
        }
        return out
    }

    private static func capture(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
