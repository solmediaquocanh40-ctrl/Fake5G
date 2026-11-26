// FG5License.h — Fake5G 1.1.11
// Hệ bản quyền theo đúng mẫu ZUS 1.2.x đã chạy thật trên máy:
//  - Dùng thử 3 ngày tự động từ lần chạy đầu; mốc ghi 3 nơi (prefs + Keychain
//    + file trong Documents), lấy mốc sớm nhất, chống vặn ngược đồng hồ
//    bằng mốc thời gian lớn nhất từng thấy (maxSeen).
//  - Key ECDSA P-256 ký số, định dạng FG51-<base32(payload||chữ ký DER)>.
//    kind 1 = key chính, vĩnh viễn, không buộc máy.
//    kind 3 = key phụ, 3 ngày tính từ lúc kích hoạt.
//  - Chữ ký lưu dạng DER (đúng hợp đồng của SecKeyVerifySignature X962).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FG5LicState) {
    FG5LicStateTrial = 0,        // đang dùng thử, còn hạn
    FG5LicStateTrialExpired,     // hết dùng thử, chưa có key
    FG5LicStatePermanent,        // key chính vĩnh viễn
    FG5LicStateTimed,            // key phụ còn hạn
    FG5LicStateTimedExpired      // key phụ đã hết 3 ngày
};

// Trạng thái hiện tại; daysLeft = số ngày còn lại (làm tròn lên), -1 nếu vĩnh viễn.
FG5LicState FG5LicenseCurrentState(NSInteger * _Nullable daysLeftOut,
                                   NSString * _Nullable * _Nullable nameOut);
// YES khi tweak được chạy tính năng (còn dùng thử hoặc key còn hạn)
BOOL FG5LicenseActive(void);
// YES chỉ khi có KEY đang còn hạn (vĩnh viễn hoặc key phụ chưa hết 3 ngày).
// Trang Cài đặt mở khoá bằng hàm này: chưa kích hoạt key thì không vào
// được phần điều chỉnh, kể cả đang trong dùng thử (yêu cầu của anh Quoc).
BOOL FG5LicenseHasActiveKey(void);
// Dòng trạng thái hiển thị trong Cài đặt
NSString *FG5LicenseStatusText(void);
// Kiểm tra + lưu key. Thành công trả YES và (nếu có) tên chủ key qua nameOut.
BOOL FG5LicenseTryActivateKey(NSString *key,
                              NSString * _Nullable * _Nullable nameOut,
                              NSString * _Nullable * _Nullable errorOut);

NS_ASSUME_NONNULL_END
