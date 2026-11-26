# Fake5G 1.1.4 — com.anhdang.fake5g

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

## 1.1.4 — mọi bề mặt + option Switcher + khoá trang bằng key

1. **Áp dụng lên MỌI bề mặt**: máy thật cho thấy bản cũ chỉ bám một
   thanh trạng thái (trong cửa sổ màn hình khoá) nên ra màn hình chính
   và App Switcher là mất. Nay tweak quét mọi cửa sổ, cửa sổ nào chứa
   thanh trạng thái thì áp dụng riêng cho cửa sổ đó — màn hình khoá,
   màn hình chính, trong app, switcher đều được giả. Log ghi từng bề
   mặt tìm thấy (`them be mat: ...`).
2. **Option "Hiện trong App Switcher"** (nhóm Bật/Tắt, mặc định Bật):
   tắt thì riêng trình đa nhiệm giữ thanh trạng thái gốc.
3. **Khoá trang điều chỉnh bằng key** (yêu cầu của anh): chưa kích hoạt
   key thì mở Cài đặt → Fake5G là phủ mờ + popup nhập key như ZUS, kể cả
   đang dùng thử. Dùng thử 3 ngày chỉ chạy phần hiển thị trên thanh
   trạng thái bằng cấu hình sẵn có; nhập key xong mới mở được trang
   điều chỉnh. Key phụ còn hạn cũng mở được; key hết hạn lại khoá.

## 1.1.3 — sửa theo ảnh + log 1.1.2 (máy thật 26/11/2026)

1. **Chữ nhà mạng bay giữa màn hình**: dải dự phòng tính chiều cao từ
   chiều cao cửa sổ (844) thay vì chiều cao thanh trạng thái — đã sửa lấy
   theo safeTop (tai thỏ 47). Đồng thời **nhận diện view nhà mạng theo vị
   trí** (trong dải trạng thái, nửa trái, không phải chữ giờ): máy có SIM
   (chữ là tên nhà mạng thật như MobiFone) giờ cũng được thay chữ ngay
   trên view thật như máy không SIM, không cần nhãn dự phòng nữa.
2. **Icon Wi-Fi còn hằn mờ sau chữ 5G**: trước chỉ ẩn các view con của
   icon; nay ẩn cả chính view icon Wi-Fi và view vạch sóng (khôi phục đầy
   đủ khi tắt tweak).
3. **Font nhãn**: lấy font thật từ view chữ của thanh trạng thái (đúng
   font SF hệ thống đang dùng), không tự chọn font nữa.

Đã kiểm chứng trên máy thật ở 1.1.2: bám đúng thanh trạng thái thật
trong SBCoverSheetWindow (chuỗi view cha trong log), nhãn 5G đúng vị
trí, profile tai thỏ đúng.

## 1.1.2 — sửa lỗi chọn cửa sổ (log 1.1.1, máy thật 26/11/2026)

Bản 1.1.1 loại mọi cửa sổ cao trên 70pt — nhưng log cho thấy SpringBoard
trên iOS 16 không có cửa sổ thanh trạng thái riêng thấp nào: cả 15 cửa sổ
đều cao bằng màn hình (844) hoặc 340. Hệ quả: 1.1.1 không bám được vào
cửa sổ nào, icon Wi-Fi không đổi. Bản 1.1.4 đổi hẳn cách tìm: quét mọi
cửa sổ (bỏ cửa sổ đang ẩn) và bám theo cửa sổ chứa icon Wi-Fi thật; kho
ReusePool chỉ là dự phòng cuối. Nhận diện dòng máy cũng đổi sang
`safeAreaInsets.top` thay cho chiều cao cửa sổ. Log mới ghi thêm chuỗi
view cha của icon Wi-Fi để vòng sau hiệu chỉnh tiếp nếu cần.

Đã kiểm chứng trên máy thật ở 1.1.1: trang Cài đặt hết đen (chọn được
Chữ hiển thị / nhà mạng — log prefs 16:51–16:53), key chủ kích hoạt
thành công (vĩnh viễn).

## 1.1.1 — sửa 2 lỗi từ máy thật (log 26/11/2026, iPhone 12 Pro)

1. **Thanh trạng thái không đổi gì** (bản đã cài trên máy): hàm chọn cửa sổ
   bắt nhầm `SBStatusBarReusePoolWindow` — kho chứa thanh trạng thái tái sử
   dụng, khung bằng cả màn hình và rỗng — nên không bao giờ tìm thấy icon
   Wi-Fi. Đã sửa: loại thẳng ReusePool, chỉ xét cửa sổ cao ≤70pt, quét mọi
   cửa sổ và bám theo cửa sổ chứa view trạng thái thật; log ghi rõ cửa sổ
   đã bám.
2. **Trang chọn Chữ hiển thị / Số vạch sóng / Tên nhà mạng đen thui**: các
   mục `PSLinkListCell` trong Root.plist thiếu khoá
   `detail = PSListItemsController` (mọi bundle chạy tốt đều có). Đã bổ sung
   cho cả 4 mục danh sách.

## Khung màn hình (profile)

Mục **Cài đặt → Fake5G → Dòng máy** cho chọn profile theo đời máy, máy nào
cũng chọn được:

- **Tự động** (mặc định): nhận diện theo chiều cao vùng trạng thái —
  ≤24pt cổ điển, 44–47pt tai thỏ, ≥52pt Dynamic Island.
- **Cổ điển (nút Home)**: iPhone 8/7/6s, SE — thanh trạng thái 20pt.
- **Tai thỏ**: iPhone X, XS, 11, 12, 13, 14 — nhãn/sóng nằm trong tai phải,
  cỡ chữ gọn hơn, không lấn vùng giữa.
- **Dynamic Island**: iPhone 14 Pro, 15, 16 — như tai thỏ nhưng tai rộng hơn.

Mọi profile đều canh nhãn và vạch sóng theo **khung thật của icon gốc** trên
chính máy đó (vị trí + dải dọc), profile chỉ chỉnh cỡ chữ, độ rộng tối đa và
vị trí dự phòng. Profile đã nhận diện được ghi vào log kèm kích thước cửa sổ
để đối chiếu.

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

## Checklist test trên máy thật (bản tĩnh, chưa test máy)

1. Cài .deb rootless → respring → mở Cài đặt: có mục **Fake5G** không?
2. Thanh trạng thái: icon Wi-Fi đã thành chữ **5G** chưa? Có vạch sóng + tên
   Viettel chưa? Chữ "Không có SIM" còn không?
3. Đổi nhãn sang 4G / tự nhập chữ khác, đổi tên nhà mạng, đổi số vạch:
   có áp dụng ngay không?
4. Trang Cài đặt → mục Bản quyền hiện "Đang dùng thử — còn 3 ngày"?
5. Mục **Dòng máy**: để Tự động trước; nếu lệch, chọn tay đúng dòng máy rồi
   xem lại. Test thêm trên iPhone tai thỏ (12 Pro) nếu có: nhãn 5G trong tai
   phải có đè lên pin/giờ không, tên nhà mạng có lấn vùng giữa không?
6. Gửi lại file `/var/mobile/Documents/Fake5G.log` nếu có mục nào chưa chạy —
   trong log đã có sẵn dump cây thanh trạng thái + profile đã nhận diện để
   vòng sau chỉnh đúng class/khung của từng đời máy.
