// Tweak.x — Fake5G 1.1.8 (com.anhdang.fake5g)
// Giả hiển thị trên thanh trạng thái: thay icon Wi-Fi bằng nhãn chữ tuỳ chọn
// (4G/5G/tự nhập), hiện vạch sóng giả + tên nhà mạng giả cho máy không SIM,
// ẩn chữ "Không có SIM". Chỉ giả HIỂN THỊ — kết nối thật giữ nguyên 100%.
// Nạp vào SpringBoard. Log: /var/mobile/Documents/Fake5G.log
//
// CƠ CHẾ (từ 1.1.7, học từ HideStatusBarItemsPro + StatusMagic): mọi thanh
// trạng thái đều vẽ từ MỘT khối dữ liệu trung tâm do
// SBStatusBarStateAggregator dựng và phát cho mọi bề mặt (màn hình chính,
// trong app, switcher...). Vì vậy:
//   1) Ẩn đồ gốc TẠI NGUỒN: hook _setItem:enabled: của aggregator, ép tắt
//      các mục gốc (sóng / chữ nhà mạng / icon Wi-Fi / chữ mạng dữ liệu)
//      → chúng biến mất trên MỌI bề mặt cùng lúc. Máy thật 1.1.7 đã chứng
//      minh: quạt Wi-Fi và sóng gốc chết thật trong cả app Cài đặt.
//   2) Vẽ đồ giả bằng MỘT cửa sổ phủ duy nhất của tweak (trong suốt,
//      không chặn chạm, luôn nằm trên cùng ở dải trạng thái).
// Thứ tự mục theo bản đồ iOS 16 trong StatusMagic (StatusBarRawData):
//   4/5 = sóng chính/phụ, 6/7 = chữ nhà mạng chính/phụ,
//   8 = icon Wi-Fi, 9/10 = chữ mạng dữ liệu (5G/LTE) chính/phụ.
//
// 1.1.8 sửa 2 lỗi bố cục/dò của 1.1.7 (ảnh máy thật 19:37):
//   - Tên nhà mạng KHÔNG còn nhét vào tai phải của máy tai thỏ (tai chỉ
//     rộng ~95pt, phần kéo sang trái rơi đúng rãnh tai thỏ đen không có
//     điểm ảnh → không thấy). Nay: tai phải chỉ còn [vạch][nhãn] trước
//     pin gốc; nhà mạng chuyển xuống HÀNG 2 của tai trái (dưới giờ —
//     vùng này nằm dưới rãnh tai thỏ, luôn có điểm ảnh).
//   - Dò "đang có Wi-Fi" không còn phụ thuộc mục 8 của aggregator:
//     hỏi thẳng SBWiFiManager (isAssociated) mỗi giây.
// Thêm CHẾ ĐỘ ĐỘC CHIẾM (pref exclusiveMode, mặc định tắt): hook ép tắt
// TOÀN BỘ 45 mục của aggregator (kể cả giờ và pin gốc) + chặn cập nhật
// giờ; cửa sổ phủ tự vẽ trọn thanh: giờ thật, nhà mạng, vạch, nhãn và
// pin thật (đọc từ BCBatteryDeviceController). Bật khi máy cài nhiều
// tweak tranh thanh trạng thái hoặc đồ gốc vẫn lọt ra ngoài.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "FG5Shared.h"
#import "FG5License.h"

// Cờ đã nạp từ prefs (làm mới ở -reloadPrefs), hook đọc các cờ này cho nhẹ
static BOOL gEnabled = YES;
static BOOL gLicensed = NO;
static BOOL gFakeBars = YES;
static BOOL gFakeCarrier = YES;
static BOOL gHideNoSim = YES;
static BOOL gOnlyOnWifi = YES;
static BOOL gShowInSwitcher = YES;
static BOOL gExclusive = NO;
static NSString *gLayoutPref = @"auto";
// Máy đang có Wi-Fi hay không: nguồn chính là SBWiFiManager (hỏi mỗi
// giây trong tick), nguồn phụ là lưu lượng mục 8 qua hook aggregator.
static BOOL gWifiPresent = YES;

// Profile khung màn hình: 0 = cổ điển (nút Home), 1 = tai thỏ, 2 = Dynamic Island
static void FG5ParamsForProfile(NSInteger profile, CGFloat *fontSize,
                                CGFloat *labelMaxW, CGFloat *carrierMaxW) {
    switch (profile) {
        case 1: // tai thỏ: 2 tai hẹp, chữ phải gọn
            *fontSize = 11.5; *labelMaxW = 36; *carrierMaxW = 46; break;
        case 2: // Dynamic Island: tai rộng hơn tai thỏ một chút
            *fontSize = 12; *labelMaxW = 40; *carrierMaxW = 54; break;
        default: // cổ điển: thanh trạng thái rộng rãi
            *fontSize = 12; *labelMaxW = 64; *carrierMaxW = 120; break;
    }
}

static NSString *FG5ProfileName(NSInteger profile) {
    switch (profile) {
        case 1: return @"tai tho";
        case 2: return @"Dynamic Island";
        default: return @"co dien";
    }
}

// Phát lại trạng thái các mục để aggregator tính lại từ đầu (mỗi lần
// tính lại đều đi qua hook _setItem:enabled: của tweak). Độc chiếm thì
// phát cả 45 mục, thường thì chỉ các mục liên quan.
static void FG5RepublishItems(void) {
    @try {
        Class cls = NSClassFromString(@"SBStatusBarStateAggregator");
        if (!cls) return;
        id agg = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        if (!agg) return;
        int last = gExclusive ? 44 : 10;
        for (int item = 0; item <= last; item++) {
            ((void (*)(id, SEL, int))objc_msgSend)(agg,
                @selector(updateStatusBarItem:), item);
        }
    } @catch (NSException *e) {}
}

// Hỏi thẳng trình quản lý Wi-Fi của SpringBoard. Không rõ thì mặc
// định là CÓ Wi-Fi (nhãn hiện — thà hiện nhầm còn hơn mất nhãn).
static BOOL FG5WifiAssociated(void) {
    @try {
        Class cls = NSClassFromString(@"SBWiFiManager");
        if (!cls) return YES;
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        if (!mgr) return YES;
        if ([mgr respondsToSelector:@selector(isAssociated)]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(mgr, @selector(isAssociated));
        }
    } @catch (NSException *e) {}
    return YES;
}

// Đọc pin thật: ưu tiên BCBatteryDeviceController của SpringBoard,
// dự phòng UIDevice. percent < 0 = không đọc được.
static void FG5BatteryInfo(NSInteger *percent, BOOL *charging, BOOL *saver) {
    *percent = -1; *charging = NO; *saver = NO;
    @try {
        Class cls = NSClassFromString(@"BCBatteryDeviceController");
        if (cls) {
            id ctrl = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
            NSArray *devices = nil;
            if ([ctrl respondsToSelector:@selector(devices)]) {
                devices = ((id (*)(id, SEL))objc_msgSend)(ctrl, @selector(devices));
            }
            id dev = devices.firstObject;
            if (dev) {
                if ([dev respondsToSelector:@selector(percentCharge)]) {
                    *percent = (NSInteger)((long long (*)(id, SEL))objc_msgSend)(dev, @selector(percentCharge));
                }
                if ([dev respondsToSelector:@selector(isCharging)]) {
                    *charging = ((BOOL (*)(id, SEL))objc_msgSend)(dev, @selector(isCharging));
                }
                if ([dev respondsToSelector:@selector(isBatterySaverModeActive)]) {
                    *saver = ((BOOL (*)(id, SEL))objc_msgSend)(dev, @selector(isBatterySaverModeActive));
                }
                if (*percent >= 0) return;
            }
        }
    } @catch (NSException *e) {}
    UIDevice *d = [UIDevice currentDevice];
    d.batteryMonitoringEnabled = YES;
    if (d.batteryLevel >= 0) {
        *percent = (NSInteger)lroundf(d.batteryLevel * 100.0f);
        *charging = (d.batteryState == UIDeviceBatteryStateCharging ||
                     d.batteryState == UIDeviceBatteryStateFull);
    }
}

@interface FG5Engine : NSObject
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIWindow *stripWindow;
@property (nonatomic, strong) UILabel *wifiLabel;
@property (nonatomic, strong) UIView *barsView;
@property (nonatomic, strong) UILabel *carrierLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *batteryPercentLabel;
@property (nonatomic, strong) UIView *batteryBody;
@property (nonatomic, strong) UIView *batteryFill;
@property (nonatomic, strong) UIView *batteryCap;
@property (nonatomic, assign) BOOL republishedOnce;
@property (nonatomic, assign) BOOL loggedProfile;
- (void)start;
- (void)tick;
- (void)prefsChanged;
- (void)reloadPrefs;
- (void)updateStrip;
- (void)ensureStrip;
- (void)layoutStrip;
- (void)styleStripLabel:(UILabel *)label;
- (NSInteger)effectiveProfile;
- (NSArray<UIWindow *> *)allWindows;
@end

static FG5Engine *gEngine = nil;

static void FG5PrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [gEngine prefsChanged];
    });
}

@implementation FG5Engine

- (void)start {
    [self reloadPrefs];
    gWifiPresent = FG5WifiAssociated();
    FG5Log(@"Fake5G 1.1.8 khoi dong — ban quyen: %@ — docchiem=%d wifi=%@",
           FG5LicenseStatusText(), gExclusive, gWifiPresent ? @"co" : @"khong");
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];
    [self tick];
}

- (void)reloadPrefs {
    gEnabled = FG5PrefBool(FG5_KEY_ENABLED, YES);
    gFakeBars = FG5PrefBool(FG5_KEY_FAKE_BARS, YES);
    gFakeCarrier = FG5PrefBool(FG5_KEY_FAKE_CARRIER, YES);
    gHideNoSim = FG5PrefBool(FG5_KEY_HIDE_NOSIM, YES);
    gOnlyOnWifi = FG5PrefBool(FG5_KEY_ONLY_ON_WIFI, YES);
    gShowInSwitcher = FG5PrefBool(FG5_KEY_SHOW_IN_SWITCHER, YES);
    gExclusive = FG5PrefBool(FG5_KEY_EXCLUSIVE_MODE, NO);
    gLayoutPref = FG5PrefString(FG5_KEY_LAYOUT_PROFILE, @"auto");
    gLicensed = FG5LicenseActive();
}

- (void)prefsChanged {
    [self reloadPrefs];
    FG5Log(@"prefs thay doi — enabled=%d licensed=%d nhan='%@' nha mang='%@' vach=%ld switcher=%d docchiem=%d",
           gEnabled, gLicensed, FG5EffectiveLabel(), FG5EffectiveCarrier(),
           (long)FG5EffectiveBarsCount(), gShowInSwitcher, gExclusive);
    FG5RepublishItems();
    [self updateStrip];
}

- (void)tick {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
        return;
    }
    // Dò lại Wi-Fi mỗi giây từ SBWiFiManager (nguồn tin cậy chính)
    BOOL w = FG5WifiAssociated();
    if (w != gWifiPresent) {
        gWifiPresent = w;
        FG5Log(@"wifi thay doi: %@", w ? @"co" : @"khong");
    }
    if (!self.republishedOnce) {
        self.republishedOnce = YES;
        FG5RepublishItems();
    }
    [self updateStrip];
}

- (NSArray<UIWindow *> *)allWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (windows.count == 0) {
        // Dự phòng qua KVC như các tweak trước (tránh API windows đã deprecated)
        NSArray *kv = [[UIApplication sharedApplication] valueForKey:@"windows"];
        if ([kv isKindOfClass:[NSArray class]]) [windows addObjectsFromArray:kv];
    }
    return windows;
}

- (NSInteger)effectiveProfile {
    if ([gLayoutPref isEqualToString:@"classic"]) return 0;
    if ([gLayoutPref isEqualToString:@"notch"]) return 1;
    if ([gLayoutPref isEqualToString:@"island"]) return 2;
    // auto: theo chiều cao dải trạng thái thật của máy (safeAreaInsets.top)
    CGFloat top = 0;
    for (UIWindow *w in [self allWindows]) top = MAX(top, w.safeAreaInsets.top);
    if (top >= 50) return 2;
    if (top >= 30) return 1;
    if (top > 0) return 0;
    // Chưa đọc được (mới khởi động): đoán theo kích thước màn hình
    CGSize s = [UIScreen mainScreen].bounds.size;
    return (s.height >= 780 && s.width >= 360) ? 1 : 0;
}

#pragma mark - Cửa sổ phủ (strip)

- (void)styleStripLabel:(UILabel *)label {
    label.textColor = [UIColor whiteColor];
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOpacity = 0.55;
    label.layer.shadowRadius = 2.0;
    label.layer.shadowOffset = CGSizeMake(0, 1);
}

- (void)ensureStrip {
    if (self.stripWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 60);
    w.windowLevel = UIWindowLevelStatusBar + 500;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = NO; // không chặn chạm: mọi thao tác xuyên qua
    self.stripWindow = w;

    self.wifiLabel = [[UILabel alloc] init];
    self.wifiLabel.textAlignment = NSTextAlignmentCenter;
    self.wifiLabel.adjustsFontSizeToFitWidth = YES;
    self.wifiLabel.minimumScaleFactor = 0.65;
    [self styleStripLabel:self.wifiLabel];
    [w addSubview:self.wifiLabel];

    self.carrierLabel = [[UILabel alloc] init];
    self.carrierLabel.adjustsFontSizeToFitWidth = YES;
    self.carrierLabel.minimumScaleFactor = 0.65;
    [self styleStripLabel:self.carrierLabel];
    [w addSubview:self.carrierLabel];

    self.barsView = [[UIView alloc] init];
    self.barsView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.barsView.layer.shadowOpacity = 0.55;
    self.barsView.layer.shadowRadius = 2.0;
    self.barsView.layer.shadowOffset = CGSizeMake(0, 1);
    for (NSInteger i = 0; i < 4; i++) {
        UIView *bar = [[UIView alloc] init];
        bar.backgroundColor = [UIColor whiteColor];
        [self.barsView addSubview:bar];
    }
    [w addSubview:self.barsView];

    // Chỉ dùng ở chế độ độc chiếm: giờ thật + pin thật do tweak tự vẽ
    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.adjustsFontSizeToFitWidth = YES;
    self.timeLabel.minimumScaleFactor = 0.7;
    [self styleStripLabel:self.timeLabel];
    [w addSubview:self.timeLabel];

    self.batteryPercentLabel = [[UILabel alloc] init];
    self.batteryPercentLabel.textAlignment = NSTextAlignmentRight;
    [self styleStripLabel:self.batteryPercentLabel];
    [w addSubview:self.batteryPercentLabel];

    self.batteryBody = [[UIView alloc] init];
    self.batteryBody.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45].CGColor;
    self.batteryBody.layer.borderWidth = 1.0;
    self.batteryBody.layer.cornerRadius = 3.5;
    [w addSubview:self.batteryBody];

    self.batteryFill = [[UIView alloc] init];
    self.batteryFill.backgroundColor = [UIColor whiteColor];
    self.batteryFill.layer.cornerRadius = 1.5;
    [w addSubview:self.batteryFill];

    self.batteryCap = [[UIView alloc] init];
    self.batteryCap.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    self.batteryCap.layer.cornerRadius = 1.0;
    [w addSubview:self.batteryCap];

    FG5Log(@"da tao cua so phu thanh trang thai");
}

- (void)layoutStrip {
    UIWindow *w = self.stripWindow;
    if (!w) return;
    NSInteger profile = [self effectiveProfile];
    if (!self.loggedProfile) {
        self.loggedProfile = YES;
        FG5Log(@"profile: %@ (pref='%@')", FG5ProfileName(profile), gLayoutPref);
    }
    CGFloat fontSize, labelMaxW, carrierMaxW;
    FG5ParamsForProfile(profile, &fontSize, &labelMaxW, &carrierMaxW);
    UIFont *font = [UIFont systemFontOfSize:fontSize + 2.5
                                     weight:UIFontWeightSemibold];
    self.wifiLabel.font = font;

    CGFloat W = [UIScreen mainScreen].bounds.size.width;
    CGFloat sbH = (profile == 0) ? 20 : (profile == 2 ? 54 : 47);
    if ([gLayoutPref isEqualToString:@"auto"]) {
        CGFloat top = 0;
        for (UIWindow *win in [self allWindows]) top = MAX(top, win.safeAreaInsets.top);
        if (top >= 20) sbH = top;
    }
    w.frame = CGRectMake(0, 0, W, sbH);
    // Tâm dọc của cụm trên thanh thật (đo từ dump máy thật: chữ nhà mạng
    // có tâm ≈ 54% chiều cao dải ở máy tai thỏ)
    CGFloat centerY = (profile == 0) ? sbH / 2.0 : sbH * 0.54;
    CGFloat labelH = 20, barsH = 12, barsW = 17;

    NSString *label = FG5EffectiveLabel();
    CGSize labelSize = [label sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat labelW = MIN(ceil(labelSize.width) + 4, labelMaxW + 8);
    NSString *carrier = FG5EffectiveCarrier();
    CGSize carrierSize = [carrier sizeWithAttributes:@{NSFontAttributeName: font}];

    // Chuỗi pin của chế độ độc chiếm (từ phải sang): [thân pin][%]
    CGFloat battW = 25, battH = 12;
    CGFloat battRight = (profile == 0) ? W - 8 : W - 11;
    self.batteryBody.frame = CGRectMake(battRight - battW, centerY - battH / 2.0, battW, battH);
    self.batteryCap.frame = CGRectMake(battRight + 1, centerY - 2, 2, 4);
    self.batteryPercentLabel.font = [UIFont systemFontOfSize:fontSize + 1.5
                                                        weight:UIFontWeightSemibold];
    NSString *pctText = self.batteryPercentLabel.text.length ? self.batteryPercentLabel.text : @"100";
    CGSize pctSize = [pctText sizeWithAttributes:@{NSFontAttributeName: self.batteryPercentLabel.font}];
    CGFloat pctW = MIN(ceil(pctSize.width) + 2, 38);
    self.batteryPercentLabel.frame = CGRectMake(battRight - battW - 4 - pctW,
                                                centerY - labelH / 2.0, pctW, labelH);

    // Mép phải của nhãn: thường = chừa pin gốc; độc chiếm = nối chuỗi pin giả
    CGFloat labelRight;
    if (gExclusive) {
        labelRight = battRight - battW - 4 - pctW - 6;
    } else {
        labelRight = W - ((profile == 2) ? 58 : 54);
    }

    if (profile == 0) {
        // Cổ điển: cụm trái — [vạch sóng][nhà mạng][nhãn], như thanh gốc
        self.barsView.frame = CGRectMake(8, centerY - barsH / 2.0, barsW, barsH);
        CGFloat cx = 8 + barsW + 5;
        CGFloat cw = gFakeCarrier ? MIN(ceil(carrierSize.width) + 2, carrierMaxW) : 0;
        self.carrierLabel.font = font;
        self.carrierLabel.frame = CGRectMake(cx, centerY - labelH / 2.0, cw, labelH);
        self.carrierLabel.textAlignment = NSTextAlignmentLeft;
        self.wifiLabel.frame = CGRectMake(cx + (gFakeCarrier ? cw + 6 : 0),
                                          centerY - labelH / 2.0, labelW, labelH);
        // Độc chiếm cổ điển: giờ nằm giữa thanh như máy nút Home đời cũ
        self.timeLabel.font = [UIFont systemFontOfSize:fontSize + 1.5
                                                weight:UIFontWeightSemibold];
        self.timeLabel.frame = CGRectMake((W - 70) / 2.0, centerY - labelH / 2.0, 70, labelH);
        self.timeLabel.textAlignment = NSTextAlignmentCenter;
    } else {
        // Tai thỏ / Island: tai phải chỉ [nhãn][vạch] (theo thứ tự từ
        // phải sang), nhà mạng xuống hàng 2 của tai trái dưới giờ —
        // hàng 2 nằm dưới rãnh tai thỏ nên luôn có điểm ảnh.
        self.wifiLabel.frame = CGRectMake(labelRight - labelW,
                                          centerY - labelH / 2.0, labelW, labelH);
        CGFloat barsRight = labelRight - labelW - 5;
        self.barsView.frame = CGRectMake(barsRight - barsW,
                                         centerY - barsH / 2.0, barsW, barsH);
        UIFont *carrierFont = [UIFont systemFontOfSize:fontSize - 0.5
                                                weight:UIFontWeightSemibold];
        self.carrierLabel.font = carrierFont;
        CGSize cSize = [carrier sizeWithAttributes:@{NSFontAttributeName: carrierFont}];
        CGFloat cw = MIN(ceil(cSize.width) + 2, 120);
        self.carrierLabel.frame = CGRectMake(20, sbH - 16, cw, 14);
        self.carrierLabel.textAlignment = NSTextAlignmentLeft;
        // Độc chiếm tai thỏ: giờ của tweak ở tai trái, đúng chỗ giờ gốc
        self.timeLabel.font = [UIFont systemFontOfSize:15
                                                weight:UIFontWeightSemibold];
        self.timeLabel.frame = CGRectMake(27, centerY - labelH / 2.0, 64, labelH);
        self.timeLabel.textAlignment = NSTextAlignmentLeft;
    }
    // Vạch sóng con: 4 cột cao dần, đáy thẳng hàng
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat h = 4 + i * 2;
        self.barsView.subviews[i].frame = CGRectMake(i * 4.5, barsH - h, 3, h);
    }
    // Ruột pin: độ rộng theo % thật (updateStrip gọi mỗi giây)
    NSInteger pct = -1; BOOL charging = NO, saver = NO;
    FG5BatteryInfo(&pct, &charging, &saver);
    if (pct >= 0) {
        CGFloat innerW = (battW - 4) * (pct / 100.0);
        if (pct > 0 && innerW < 2) innerW = 2;
        CGRect bf = self.batteryBody.frame;
        self.batteryFill.frame = CGRectMake(bf.origin.x + 2, bf.origin.y + 2, innerW, battH - 4);
        self.batteryFill.backgroundColor =
            charging ? [UIColor colorWithRed:0.20 green:0.85 blue:0.35 alpha:1.0] :
            saver    ? [UIColor colorWithRed:1.00 green:0.85 blue:0.20 alpha:1.0] :
            (pct <= 20) ? [UIColor colorWithRed:1.00 green:0.25 blue:0.20 alpha:1.0] :
                          [UIColor whiteColor];
        self.batteryPercentLabel.text = [NSString stringWithFormat:@"%ld", (long)pct];
    }
}

- (void)updateStrip {
    BOOL active = gEnabled && gLicensed;
    if (!active) {
        self.stripWindow.hidden = YES;
        return;
    }
    [self ensureStrip];
    UIWindow *w = self.stripWindow;
    if (!w) return;
    // Luôn nằm trên mọi cửa sổ khác của SpringBoard (dưới cảnh báo hệ
    // thống): tự nâng tầng theo cửa sổ cao nhất hiện có.
    CGFloat topLevel = UIWindowLevelStatusBar + 500;
    BOOL switcherVisible = NO;
    for (UIWindow *win in [self allWindows]) {
        if (win == w) continue;
        if (win.windowLevel < 1990) topLevel = MAX(topLevel, win.windowLevel + 1);
        if ([NSStringFromClass([win class]) containsString:@"MainSwitcher"] &&
            !win.hidden && win.alpha > 0.01) {
            switcherVisible = YES;
        }
    }
    w.windowLevel = MIN(topLevel, 1990);
    w.hidden = (switcherVisible && !gShowInSwitcher);
    if (w.hidden) return;
    [self layoutStrip];
    BOOL showLabel = !gOnlyOnWifi || gWifiPresent;
    self.wifiLabel.hidden = !showLabel;
    if (showLabel) self.wifiLabel.text = FG5EffectiveLabel();
    self.carrierLabel.hidden = !gFakeCarrier;
    if (gFakeCarrier) self.carrierLabel.text = FG5EffectiveCarrier();
    self.barsView.hidden = !gFakeBars;
    if (gFakeBars) {
        NSInteger activeBars = FG5EffectiveBarsCount();
        for (NSInteger i = 0; i < (NSInteger)self.barsView.subviews.count; i++) {
            self.barsView.subviews[i].backgroundColor =
                (i < activeBars) ? [UIColor whiteColor]
                                 : [[UIColor whiteColor] colorWithAlphaComponent:0.35];
        }
    }
    // Độc chiếm: hiện giờ + pin của tweak; thường: giấu cả hai
    self.timeLabel.hidden = !gExclusive;
    self.batteryPercentLabel.hidden = !gExclusive;
    self.batteryBody.hidden = !gExclusive;
    self.batteryFill.hidden = !gExclusive;
    self.batteryCap.hidden = !gExclusive;
    if (gExclusive) {
        static NSDateFormatter *fmt = nil;
        if (!fmt) {
            fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"HH:mm";
        }
        self.timeLabel.text = [fmt stringFromDate:[NSDate date]];
    }
}

@end

#pragma mark - Hook aggregator: ẩn đồ gốc tại nguồn dữ liệu

// Khai báo class hệ thống không có header trong SDK (bài học AGENTS #41:
// khai đầy đủ trước %hook; các class này chỉ dùng trong SpringBoard).
@interface SBStatusBarStateAggregator : NSObject
+ (instancetype)sharedInstance;
- (BOOL)_setItem:(int)item enabled:(BOOL)enabled;
- (void)updateStatusBarItem:(int)item;
- (void)_updateTimeItems;
@end

@interface SBCoverSheetPresentationManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface _UIStatusBarWifiSignalView : UIView
@end

%hook SBStatusBarStateAggregator

- (BOOL)_setItem:(int)item enabled:(BOOL)enabled {
    if (item == 8) {
        // Ghi lại ý định thật của hệ thống về Wi-Fi (nguồn phụ cho
        // option onlyOnWifi; nguồn chính là SBWiFiManager trong tick)
        if (gWifiPresent != enabled) {
            gWifiPresent = enabled;
            dispatch_async(dispatch_get_main_queue(), ^{
                [gEngine updateStrip];
            });
        }
    }
    if (gEnabled && gLicensed) {
        if (gExclusive) {
            // Độc chiếm: tắt MỌI mục gốc — thanh gốc trống hoàn toàn,
            // cửa sổ phủ vẽ lại trọn thanh. Không phụ thuộc bản đồ mục.
            return %orig(item, NO);
        }
        switch (item) {
            case 4: case 5: // sóng gốc — tweak vẽ vạch giả thay thế
                if (gFakeBars) return %orig(item, NO);
                break;
            case 6: case 7: // chữ nhà mạng gốc / chữ "Không có SIM"
                if (gFakeCarrier || gHideNoSim) return %orig(item, NO);
                break;
            case 8: // icon Wi-Fi gốc — nhãn chữ thay thế
                return %orig(item, NO);
            case 9: case 10: // chữ mạng dữ liệu gốc (5G/LTE thật)
                if (!gOnlyOnWifi || gWifiPresent) return %orig(item, NO);
                break;
            default:
                break;
        }
    }
    return %orig;
}

- (void)_updateTimeItems {
    // Độc chiếm: chặn cả nhịp cập nhật giờ để giờ gốc không ló lại
    if (gEnabled && gLicensed && gExclusive) return;
    %orig;
}

%end

%hook SBCoverSheetPresentationManager

- (void)_notifyDelegateDidPresent {
    %orig;
    FG5RepublishItems();
}

- (void)_notifyDelegateDidDismiss {
    %orig;
    FG5RepublishItems();
}

%end

// Mạng lưới an toàn cho icon Wi-Fi: kể cả khi mục 8 ở aggregator không
// đúng như bản đồ, class này mà bị hook thì icon Wi-Fi ở mọi cây view
// trong SpringBoard đều ẩn (hook theo class, không theo cửa sổ).
static const void *kFG5WifiHiddenKey = &kFG5WifiHiddenKey;

%hook _UIStatusBarWifiSignalView

- (void)layoutSubviews {
    %orig;
    BOOL ours = [objc_getAssociatedObject(self, kFG5WifiHiddenKey) boolValue];
    if (gEnabled && gLicensed) {
        if (!ours) {
            objc_setAssociatedObject(self, kFG5WifiHiddenKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        self.alpha = 0.0;
    } else if (ours) {
        objc_setAssociatedObject(self, kFG5WifiHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.alpha = 1.0;
    }
}

%end

#pragma mark - ctor

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:@"com.apple.springboard"]) return;
        %init;
        gEngine = [[FG5Engine alloc] init];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, FG5PrefsChangedCallback,
                                        FG5_PREFS_CHANGED_NOTIFICATION, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            [gEngine start];
        });
    }
}
