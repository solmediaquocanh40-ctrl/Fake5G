# Fake5G 1.0.0 — com.anhdang.fake5g

Tweak giả **hiển thị** trên thanh trạng thái cho máy jailbreak (mục tiêu chính:
iPhone 8 / iOS 16.7.12 / Dopamine rootless; test kèm iPhone 12 Pro / iOS 16.3.1).

## Chức năng

- Thay icon Wi-Fi bằng nhãn chữ: chọn sẵn **4G / 5G / 5G+ / 5G UW / LTE / 6G**
  hoặc **tự nhập bất cứ chữ gì** (ô tự nhập thắng ô chọn sẵn).
- **Sóng SIM giả** cho máy không SIM: bật/tắt, chọn 1–4 vạch.
- **Tên nhà mạng giả**: chọn sẵn (Viettel, VinaPhone, MobiFone, Vietnamobile,
  Y!mobile) hoặc **tự nhập tự do**.
- **Ẩn chữ "Không có SIM"** trên thanh trạng thái.
- Mọi thay đổi trong Cài đặt áp dụng ngay, không cần respring.
- Chỉ giả hiển thị — kết nối Wi-Fi/dữ liệu thật giữ nguyên 100%, tốc độ không đổi.

## Bản quyền (đúng mẫu ZUS)

- **Dùng thử 3 ngày** tự động từ lần chạy đầu. Mốc dùng thử ghi ở **3 nơi**
  (prefs + Keychain `com.anhdang.fake5g.state` + file `/var/mobile/Documents/.fg5state`),
  lấy mốc sớm nhất và chống vặn ngược đồng hồ bằng mốc thời gian lớn nhất từng thấy —
  gỡ/cài lại không reset được dùng thử.
- Hết hạn: mở trang **Cài đặt → Fake5G** sẽ hiện **popup Active**
  (nút **OK** kiểm key, **Huỷ** đóng; popup **tự tắt sau 30 giây**, đếm tạm dừng
  trong lúc đang gõ key) và trang bị **phủ mờ** cho tới khi kích hoạt.
  Thanh trạng thái về nguyên bản khi hết hạn; máy dùng bình thường.
- Key định dạng `FG51-...` (ECDSA P-256, chữ ký DER):
  **key chính** = vĩnh viễn, không buộc máy; **key phụ** = 3 ngày tính từ lúc kích hoạt.
  Key do công cụ riêng sinh, khoá bí mật KHÔNG nằm trong repo này.

## Cấu trúc

- `Tweak.x` — nạp vào SpringBoard: dò cây view của thanh trạng thái, thay icon
  Wi-Fi, vẽ sóng giả, thay/ẩn chữ nhà mạng; hook `_UIStatusBarStringView.setText:`
  để chặn chữ "Không có SIM"/tên nhà mạng ngay khi hệ thống gán; log chẩn đoán
  (dump cây view + mọi chữ StringView thấy được) vào
  `/var/mobile/Documents/Fake5G.log`.
- `FG5License.m/.h`, `FG5Shared.h` — prefs + bản quyền, biên dịch vào cả tweak
  lẫn prefs bundle.
- `prefs/` — PreferenceBundle biên dịch (chỉ link UIKit + dynamic_lookup,
  entry có `isController = true`).

## Build

Đẩy cả cây lên GitHub, workflow `.github/workflows/build.yml` tự chạy
(macos-latest, 3 scheme rootless/rootful/roothide). Máy iPhone 8 + Dopamine
thì cài bản **rootless**.

## Checklist test trên máy thật (1.0.0 là bản tĩnh, chưa test máy)

1. Cài .deb rootless → respring → mở Cài đặt: có mục **Fake5G** không?
2. Thanh trạng thái: icon Wi-Fi đã thành chữ **5G** chưa? Có vạch sóng + tên
   Viettel chưa? Chữ "Không có SIM" còn không?
3. Đổi nhãn sang 4G / tự nhập chữ khác, đổi tên nhà mạng, đổi số vạch:
   có áp dụng ngay không?
4. Trang Cài đặt → mục Bản quyền hiện "Đang dùng thử — còn 3 ngày"?
5. Gửi lại file `/var/mobile/Documents/Fake5G.log` nếu có mục nào chưa chạy —
   trong log đã có sẵn dump cây thanh trạng thái để vòng sau chỉnh đúng class
   của iOS 16.7.12.
