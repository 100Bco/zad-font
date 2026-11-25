# Bàn giao: ZAD Font (app quản lý font cho Mac)

Tài liệu này để tiếp tục làm trong Claude Code, trên repo GitHub `zad-font`.

## Quy tắc làm việc với Minh

- Luôn trả lời bằng tiếng Việt, kể cả báo cáo sau chuỗi thao tác dài.
- Trước khi sửa code, trình bày kế hoạch (sửa gì, sửa thế nào) rồi chờ. Chỉ bắt tay vào sửa khi Minh nói "làm" hoặc "sửa".
- Làm kiểu "lazy senior dev": thay đổi nhỏ nhất mà vẫn đủ, không thêm abstraction, tuỳ chọn hay dependency mà Minh không yêu cầu. Cuối mỗi câu trả lời, ghi 1 đến 2 dòng về những gì đã bỏ qua và rủi ro chưa kiểm tra.
- Trước khi tự viết từ đầu, tìm xem đã có thư viện hoặc công cụ làm sẵn việc đó chưa.
- Đề xuất nào cũng phải kiểm chứng là làm được trước khi đưa ra.
- Không dùng dịch vụ trả phí. Minh chỉ trả cho Claude Max và Magnific.
- Gặp lỗi nào cũng báo ra và xử lý đến cùng, không lờ đi.
- Văn bản không dùng gạch ngang dài (em dash).

## Mục tiêu

Một app quản lý font native cho Mac, gom những điểm mạnh nhất của Typeface, RightFont, FontBase và Connect Fonts. Minh chỉ dùng Mac, nên không cần bản Windows.

## Quyết định kỹ thuật đã chốt

- **Swift + SwiftUI + CoreText**, build bằng Swift Package Manager (`swift build`), không cần Xcode.
- **Bật font không copy file**: dùng `CTFontManagerRegisterFontsForURL(url, .persistent, &err)`, tắt bằng `CTFontManagerUnregisterFontsForURL`, kiểm trạng thái bằng `CTFontManagerGetScopeForURL`. Font vẫn nằm nguyên chỗ cũ, kể cả trong thư mục Google Drive đã sync.
- Đóng gói `.app` bằng `build.sh` (tự tạo bundle, Info.plist, ký ad-hoc `codesign -s -`).
- Đã xem qua ZFontManager (GPL-3.0, Tauri, v0.2.0, rất mới) chỉ để tham khảo cách tổ chức tính năng. Không fork.

## Môi trường máy Minh (đã kiểm tra 25/11/2026)

- Mac chip Apple (arm64), SDK macOS 27.0
- Apple Swift 6.4, có Command Line Tools ở `/Library/Developer/CommandLineTools`, **không có Xcode**
- Có Illustrator 2023 và 2026, InDesign 2026, Photoshop 2026

## Cách build (trên cloud)

Session Claude Code chạy trên cloud (Linux), không build được app Mac. Mỗi lần push lên GitHub, workflow `.github/workflows/build.yml` tự build trên runner `macos-latest` (repo công khai nên miễn phí) và xuất artifact `ZAD-Font` (file zip chứa `ZAD Font.app`).
- Sau khi push, kiểm tra kết quả build trong tab Actions của repo. Đọc log nếu lỗi, sửa rồi push lại cho đến khi build xanh.
- Claude trên cloud không chạy thử app được. Minh tải artifact về Mac, giải nén, mở app (lần đầu: System Settings > Privacy & Security > Open Anyway, hoặc chạy `xattr -dr com.apple.quarantine "ZAD Font.app"`), rồi báo kết quả.
- `build.sh` vẫn chạy được trên Mac của Minh: `bash build.sh` (biến CI trống thì tự mở app).

## Hiện trạng

- Nhánh `full-app` có bản đầy đủ bước 2 đến 6 (build xanh trên GitHub, Minh chưa mở thử). `main` vẫn là bản thử bước 1.
- `Sources/ZADFont/`:
  - `main.swift`: khai báo app, cửa sổ, phím tắt Cmd+O thêm thư mục.
  - `FontKit.swift`: hàm CoreText thuần (quét file, nhóm family, kiểm dấu tiếng Việt, phân loại, OpenType đọc từ bảng GSUB, trục variable, bảng ký tự, bật/tắt `.persistent`, luật gợi ý cặp).
  - `GoogleFonts.swift`: danh sách lấy từ `fonts.google.com/metadata/fonts`, file .ttf lấy link qua `fonts.googleapis.com/css2` (không cần API key, đã kiểm chứng 25/11/2026).
  - `Store.swift`: trạng thái app, lưu `library.json` (thư mục theo dõi, yêu thích, collection, tag) trong `~/Library/Application Support/ZAD Font`. Google Fonts tải về `.../ZAD Font/Google Fonts/<Family>/`, bản xem trước cache ở `~/Library/Caches/ZAD Font/Google Preview`.
  - `Views.swift`, `DetailViews.swift`: giao diện ba cột, thẻ font, Google Fonts, chi tiết, so sánh, gợi ý cặp.
- `build.sh`: build release, đóng gói, ký ad-hoc. `bash build.sh install` chép thêm vào `/Applications`.
- Bước 1 (Illustrator có nhận font bật bằng `.persistent` không) vẫn chưa kiểm tra.

## Kế hoạch các bước

1. **(chờ kiểm tra Illustrator)** Build app thử, chọn 1 font chưa cài, bật lên, mở Illustrator 2026 kiểm tra font có trong menu không. Nếu Adobe không nhận font đăng ký bằng `.persistent` thì tìm cách khác trước khi đi tiếp.
2. **(đã code, chờ Minh thử)** Thư viện: thư mục theo dõi, giữ nguyên cấu trúc thư mục, nhóm font theo family. Xem trước bằng chữ tự gõ, kéo cỡ chữ, xem dạng lưới, danh sách hoặc waterfall.
3. Bật/tắt theo font, family hoặc collection. Collection, tag, yêu thích lưu bằng JSON trong `~/Library/Application Support/ZAD Font`.
4. Chi tiết font: kéo trục variable, bật/tắt tính năng OpenType, bảng ký tự. So sánh 2 đến 4 font.
5. Google Fonts (duyệt, tải, bật). Lọc font có đủ dấu tiếng Việt bằng cách kiểm cmap với ạ ơ ư đ ỗ ằ ể ự ộ ỹ. Gợi ý cặp font theo phân loại font, chạy ngay trên máy (app ngoài không dùng được Claude).
6. **(đã code, chờ Minh thử)** Bước 3 đến 5 cũng vậy. Đóng gói vào `/Applications`, kiểm tra lại từng tính năng.

**Bản 2:** tự bật font khi mở file trong Adobe qua plugin (InDesign/Photoshop dùng UXP, Illustrator có thể phải dùng CEP, cần kiểm tra), tìm font thiếu trong file .ai/.pdf, phát hiện font trùng, dùng chung font cho team qua thư mục Drive đã sync.

## Giao diện dự kiến

Ba cột:
- **Trái**: Tất cả font, Đang bật, Yêu thích, Google Fonts, các thư mục theo dõi, các collection
- **Giữa**: ô gõ chữ xem trước, thanh kéo cỡ chữ, nút đổi kiểu xem, lưới thẻ font có công tắc bật/tắt và nhãn "Có dấu tiếng Việt"
- **Phải**: chi tiết font gồm trục variable, OpenType, bảng ký tự và nút gợi ý cặp font
