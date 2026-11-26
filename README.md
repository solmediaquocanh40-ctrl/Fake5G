# Fake5G 1.1.12 — com.anhdang.fake5g

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

## 1.1.12 — đổi tên nốt icon trong bundle, toàn cây hết file tên icon.png

Bản build 1.1.11 bị dpkg từ chối khi cài: một file `icon.png` tên
chung trong thư mục dùng chung `PreferenceLoader/Preferences` va với
package CallForward 1.0.1 (cùng một đường dẫn, hai package). Từ 1.1.10
icon ở layout đã mang tên riêng `Fake5GPrefs.png`, nhưng trong
`prefs/Resources/` vẫn còn `icon.png`/`icon@2x.png` — 1.1.12 đổi tên
nốt thành `Fake5GPrefs.png`/`Fake5GPrefs@2x.png` để **toàn bộ cây
nguồn không còn file nào tên icon.png**. Code giữ nguyên như 1.1.11.
Lưu ý: nếu trong repo vẫn còn `icon.png`/`icon@2x.png` sót ở
`layout/Library/PreferenceLoader/Preferences/` từ các bản ≤1.1.9 thì
phải xoá hai file đó trong cùng commit (up web không tự xoá file cũ).

## 1.1.11 — pin switcher + quạt Wi-Fi màn hình chính (dò class trên máy) + thanh trượt chỉnh vị trí

Ba việc, đều từ bằng chứng máy thật trên 1.1.10:

1. **Pin gốc chết ở App Switcher (độc chiếm TẮT)**: đối chứng — 1.1.7
   (lệnh phát lại chỉ phủ 10 mục đầu) pin ở switcher còn nguyên; từ
   1.1.9 lệnh phát lại phủ cả 45 mục ở mọi chế độ thì pin mất. 1.1.12
   thu phát lại ở chế độ thường về đúng 10 mục; độc chiếm mới phủ 0–44.
2. **Quạt Wi-Fi ở màn hình chính sống sót mọi lớp chặn** (kể cả độc
   chiếm, vốn đã dập được mọi thứ khác): bỏ hẳn hook theo TÊN class —
   sai tên là im lặng không chạy. Nay tweak tự **dò danh sách class
   thật trên máy** lúc khởi động, class nào có thật mới móc bằng tay:
   view quạt bị kẹp ở cả `layoutSubviews`, `didMoveToWindow` và
   `setAlpha:`; lớp ẩn thanh gốc của độc chiếm cũng đi theo cơ chế dò
   này. Log có dòng chứng minh: `moc runtime: ...` (móc được class
   nào), `luoi wifi: da ep alpha 0 — view ... trong cua so ...`,
   `doc chiem: da an thanh goc ...`.
3. **Thanh trượt tinh chỉnh vị trí cụm giả** (nhóm "TINH CHỈNH VỊ TRÍ
   CỤM GIẢ" trong Cài đặt): Dịch ngang −40…+40, Dịch dọc −10…+10 —
   kéo là cụm vạch + chữ dịch chuyển ngay trên thanh trạng thái,
   không cần respring. Nhà mạng dịch theo khi nằm cùng cụm. Reset về
   mặc định đưa cả hai về 0.

## 1.1.10 — sửa Reset (trang ghi ngược ô gạt) + đổi tên icon PreferenceLoader

Máy thật 1.1.9 (log 20:35, 26/11): bấm Reset — key bị xoá, trang khoá
lại, các ô chọn/ô nhập về mặc định (nhà mạng MobiFone → Viettel), nhưng
thanh trạng thái vẫn chạy đồ giả. Dòng log ngay giây reset: tweak đọc
`bat=1`. Nguyên nhân: fg5PerformReset xoá key trần trong prefs rồi
reloadSpecifiers — ô gạt "Bật Fake5G" đang hiện trên trang bị trang
Cài đặt ghi ngược giá trị ON của nó vào prefs, nên tweak tưởng vẫn
đang bật và chạy tiếp bằng cấu hình mặc định.

1. **Reset viết lại đúng cách**: ghi giá trị mặc định cho từng ô qua
   đúng đường ghi của PSListController (`setPreferenceValue:specifier:`)
   — ô trên màn hình và dữ liệu khớp nhau ngay, không còn đường ghi
   ngược. Xoá key + giữ nguyên mốc thời gian kích hoạt như 1.1.9.
2. **Đổi tên icon PreferenceLoader của chính Fake5G**: `icon.png` →
   `Fake5GPrefs.png` (+ `@2x`, entry plist trỏ tên mới). Tên chung
   `icon.png` trong thư mục dùng chung là mỏ neo xung đột dpkg cho
   mọi package sau (vụ CallForward chiều 26/11 đá đúng file này).

## 1.1.9 — mặc định Tắt, None, màn khoá, vị trí cụm, Reset, độc chiếm 2 lớp

Theo các mục anh Quoc chốt tối 26/11 sau khi test 1.1.8:

1. **Mặc định TẮT khi cài mới**: công tắc "Bật Fake5G" mặc định Tắt ở cả
   trang Cài đặt lẫn fallback trong code — cài xong tweak nằm im, vào
   Cài đặt bật lên mới dùng. Đồng hồ dùng thử vẫn đếm từ lần chạy đầu.
2. **Tuỳ chọn "None (trống)"**: thêm làm dòng ĐẦU TIÊN cho Chữ hiển thị /
   Số vạch sóng / Tên nhà mạng. Chọn None là mục đó ẩn hẳn — thắng cả ô
   tự nhập.
3. **Công tắc "Hiện ở màn hình khoá"** (mặc định Bật): tweak theo dõi
   trạng thái khoá máy (Darwin notify lockstate) mỗi giây; khoá máy +
   công tắc tắt thì dải giả ẩn ở màn hình khoá. (Đồng thời sửa luôn
   PostNotification của công tắc App Switcher: trước ghi nhầm
   ReloadPrefs nên đổi nó không ăn ngay.)
4. **Vị trí cụm giả theo dòng máy** (Cài đặt → VỊ TRÍ CỤM GIẢ): Cổ điển /
   Tai thỏ / Dynamic Island mỗi dòng một lựa chọn Trái/Phải (mặc định:
   Cổ điển = Trái, Tai thỏ/Island = Phải). Tai thỏ chọn Trái thì cả cụm
   [vạch][nhãn][nhà mạng] nằm ở hàng 2 dưới giờ gốc (hàng 1 là của giờ).
5. **Nút "Reset về mặc định"** (cuối trang Cài đặt, có popup xác nhận):
   xoá toàn bộ cài đặt + xoá key đã nhập (phải nhập lại mới dùng tiếp),
   nhưng GIỮ NGUYÊN các mốc thời gian ở cả 3 nơi lưu — mốc kích hoạt
   nay gắn với dấu vân của chính key đó: nay nhập key, reset, mai nhập
   lại thì hạn vẫn tính từ hôm nay; dùng thử cũng không chạy lại.
6. **Cổ điển trên máy tai thỏ**: dùng chiều cao dải thật (safeArea top)
   và neo giữa dải — sửa cảnh cụm bị ép vào dải 20pt sát mép trên,
   tách rời khỏi giờ gốc như 1.1.8.
7. **Độc chiếm 2 lớp**: lớp 1 — mỗi giây phát lại lệnh ẩn cả 45 mục qua
   aggregator (mục nào hệ thống tự bật lại cũng bị dập); lớp 2 — hook
   ẩn nguyên cây thanh gốc (UIStatusBar_Modern/_UIStatusBar) khi độc
   chiếm, vì giờ và pin gần như không được aggregator gọi lại _setItem
   sau khởi động (chính HideStatusBarItemsPro cũng ghi chú mục giờ
   "not working" qua đường đó). Phát lại lệnh nay phủ cả 45 mục ở mọi
   lần prefs đổi (trước chỉ 0–10) để tắt độc chiếm/reset là thanh gốc
   trở lại đủ. Pin độc chiếm: log "pin: xx%" mỗi khi % đổi và hiện
   "--" khi đọc lỗi thay vì mất hút.

## 1.1.8 — sửa bố cục tai thỏ + dò Wi-Fi mới + chế độ độc chiếm

Máy thật 1.1.7 (19:37, 26/11) chứng minh cơ chế chặn tại nguồn chạy:
quạt Wi-Fi và sóng gốc chết thật ngay trong app Cài đặt, cửa sổ phủ
vẽ được vạch giả, prefs realtime. Hai lỗi còn lại đều ở phần vẽ:

1. **Sửa A — bố cục tai thỏ**: tai phải iPhone chỉ rộng ~95pt, bản
   1.1.7 xếp nhà mạng kéo sang trái rơi đúng rãnh tai thỏ đen (không
   điểm ảnh) nên không thấy. Nay tai phải chỉ còn [nhãn][vạch] trước
   pin gốc; tên nhà mạng chuyển xuống hàng 2 của tai trái (dưới giờ,
   vùng dưới rãnh tai thỏ luôn có điểm ảnh, chữ 11pt). Máy cổ điển
   giữ nguyên cụm trái như cũ.
2. **Sửa A — dò Wi-Fi**: không còn phụ thuộc mục 8 của aggregator;
   hỏi thẳng SBWiFiManager isAssociated mỗi giây (dự phòng: ý định
   mục 8 qua hook). Log khởi động ghi rõ wifi co/khong.
3. **Thêm B — Chế độ độc chiếm** (Cài đặt → CHẾ ĐỘ ĐỘC CHIẾM, mặc
   định tắt): hook ép tắt TOÀN BỘ 45 mục của aggregator + chặn nhịp
   cập nhật giờ gốc; cửa sổ phủ tự vẽ trọn thanh — giờ thật (cập
   nhật mỗi giây), nhà mạng, vạch sóng, nhãn, và pin thật đọc từ
   BCBatteryDeviceController (màu ruột pin: đang sạc = xanh lá,
   tiết kiệm pin = vàng, ≤20% = đỏ). Tắt công tắc là aggregator
   phát lại toàn bộ, thanh gốc trở lại ngay. Đánh đổi: các chỉ báo
   phụ (DND, VPN, định vị, Bluetooth...) không hiện trong chế độ này.

## 1.1.7 — đổi cơ chế: chặn tại nguồn dữ liệu + một cửa sổ phủ

Theo đúng cách của HideStatusBarItemsPro và StatusMagic (anh gửi):
bỏ hẳn engine săn view/cửa sổ của 1.1.4–1.1.6. Mọi thanh trạng thái
đều vẽ từ một khối dữ liệu trung tâm do SBStatusBarStateAggregator
dựng — bản này can thiệp tại đó:

1. **Ẩn đồ gốc tại nguồn**: hook `_setItem:enabled:` của aggregator,
   ép tắt sóng gốc (mục 4/5), chữ nhà mạng gốc (6/7), icon Wi-Fi (8),
   chữ mạng dữ liệu thật (9/10) — theo bản đồ mục iOS 16 của
   StatusMagic. Tắt tại nguồn thì mọi bề mặt (màn hình chính, khoá,
   trong app, switcher) đều mất đồ gốc cùng lúc. Phát lại trạng thái
   khi đổi prefs và khi màn hình khoá đóng/mở để aggregator tính lại
   qua hook. Thêm mạng lưới an toàn: hook theo class
   _UIStatusBarWifiSignalView (ẩn bằng alpha) phòng khi mục 8 lệch.
2. **Một cửa sổ phủ duy nhất** vẽ chữ nhà mạng + vạch sóng + nhãn 5G:
   trong suốt, không chặn chạm, tự nâng tầng lên trên mọi cửa sổ của
   SpringBoard (trần 1990, dưới cảnh báo hệ thống), toạ độ theo
   profile (cổ điển = cụm trái; tai thỏ/Island = cụm tai phải, chừa
   chỗ pin gốc). Option Switcher: cửa sổ phủ tự ẩn khi switcher đang
   hiện và option tắt. Option "chỉ khi có Wi-Fi": hook ghi lại ý định
   bật/tắt mục Wi-Fi thật của hệ thống để biết máy đang có Wi-Fi.
3. Realtime thật: đổi prefs là cửa sổ phủ vẽ lại + aggregator phát
   lại ngay trong cùng tích tắc.

## 1.1.6 — xử lý riêng màn hình chính + sửa nhận diện nhà mạng

Bản đồ quét của 1.1.5 (55 lần quét trên máy thật) đã kết luận dứt
điểm: chỉ 3 cửa sổ từng giữ thanh trạng thái thật — SBCoverSheetWindow,
SBMainSwitcherWindow, SBControlCenterWindow, và chỉ trong lúc bề mặt
đó đang hiện. SBHomeScreenWindow hiện ra 44 lần, cả 44 lần đều 0 view
trạng thái; kho ReusePool luôn bị ẩn. Thanh ở màn hình chính vì thế
không nằm trong cây view của cửa sổ nào — nó được hiển thị qua một
view chủ riêng trong cửa sổ màn hình chính. Bản này:

1. **SBHomeScreenWindow thành bề mặt riêng dù 0 điểm**: tìm view chủ
   của thanh gốc (view sát mép trên, cao 15–65pt, rộng ≥60% cửa sổ,
   ưu tiên class Replicant/StatusBar) và **ẩn nó đi** — ẩn toàn bộ
   phần gốc khi tweak chạy, đúng yêu cầu của anh — rồi vẽ nhãn 5G +
   vạch sóng + tên nhà mạng theo vị trí profile như các bề mặt khác.
   Log ghi rõ view chủ tìm được (`man hinh chinh: an view chu ...`)
   hoặc báo không thấy kèm dump toàn cây của cửa sổ màn hình chính +
   cây của kho ReusePool để đối chiếu.
2. **Sửa nhận diện nhà mạng theo vị trí**: thêm cận dưới cho rect quy
   đổi — log 1.1.5 bắt được một lần nhận diện sai ở y=-821 (màn hình
   khoá đang trượt đi).
3. Realtime: thay đổi trong Cài đặt vốn đã áp dụng ngay trong tích tắc
   (prefsChanged gọi tick ngay) trên các bề mặt bắt được; cảm giác
   "không realtime" trước giờ là do màn hình chính chưa có bề mặt —
   bản này xử lý chính chỗ đó.

## 1.1.5 — quét dày hơn + mở cả kho ReusePool + bản đồ điểm

Log máy thật của 1.1.4: engine đa bề mặt CHẠY (bắt được thanh trong
SBMainSwitcherWindow, prefs có switcher=1) nhưng suốt phiên đó các lần
quét chỉ thấy view trạng thái trong cửa sổ switcher — cửa sổ màn hình
khóa và màn hình chính đều 0 điểm. Hai điểm mù của 1.1.4: (1) chỉ quét
lại mỗi 10 giây nên dễ trượt khoảnh khắc một thanh được dựng; (2) bỏ
qua hẳn cửa sổ SBStatusBarReusePoolWindow. Bản này: quét mỗi 3 giây,
tính cả ReusePool thành một bề mặt ứng viên, và ghi log `ban do quet:`
bản đồ điểm của TỪNG cửa sổ (wifi/cellular/số StringView) mỗi khi bản
đồ thay đổi — log tới sẽ chỉ thẳng cửa sổ nào đang giữ thanh của màn
hình chính. Lưu ý khi test: option "Hiện trong App Switcher" có sẵn
trong gói 1.1.4/1.1.12 nhưng app Cài đặt đang chạy giữ bundle cũ trong
bộ nhớ — phải vuốt tắt hẳn Cài đặt rồi mở lại mới thấy công tắc mới.

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
cửa sổ nào, icon Wi-Fi không đổi. Bản 1.1.12 đổi hẳn cách tìm: quét mọi
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
