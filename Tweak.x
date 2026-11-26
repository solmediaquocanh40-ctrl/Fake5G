// Tweak.x — Fake5G 1.1.10 (com.anhdang.fake5g) — LÕI HIỂN THỊ (SpringBoard)
//
// BẢN 1.1.10: sửa Reset phía prefs (ghi mặc định qua setPreferenceValue
// thay vì xoá key trần — bản 1.1.9 bị trang Cài đặt ghi ngược ô gạt Bật
// thành ON) + đổi tên icon PreferenceLoader icon.png → Fake5GPrefs.png.
// File này chỉ đổi số bản; phần lõi giữ nguyên như 1.1.9 dưới đây.
//
// BẢN 1.1.9 (theo các mục anh Quoc chốt 26/11):
//   1. MẶC ĐỊNH TẮT: cài mới xong tweak nằm im (enabled mặc định false ở cả
//      Root.plist lẫn fallback trong code) — vào Cài đặt bật lên mới dùng.
//   2. Tuỳ chọn "None (trống)" cho Chữ hiển thị / Số vạch sóng / Tên nhà
//      mạng: chọn None là mục đó ẩn hẳn, thắng cả ô tự nhập (xem FG5License.m).
//   3. Công tắc "Hiện ở màn hình khoá" (mặc định Bật): theo dõi trạng thái
//      khoá máy qua Darwin notify "com.apple.springboard.lockstate" mỗi giây.
//   4. VỊ TRÍ CỤM GIẢ theo từng dòng máy (sideClassic/sideNotch/sideIsland,
//      Trái/Phải; mặc định Cổ điển=Trái, Tai thỏ/Island=Phải). Tai thỏ chọn
//      Trái thì cả cụm [vạch][nhãn][nhà mạng] nằm hàng 2 dưới giờ gốc.
//   5. CỔ ĐIỂN TRÊN MÁY TAI THỎ: dùng chiều cao dải THẬT (safeArea top) và
//      neo giữa dải — sửa lỗi 1.1.8 cụm bị ép sát mép trên, lệch giờ gốc.
//   6. ĐỘC CHIẾM 2 LỚP: (lớp 1) mỗi giây phát lại lệnh ẩn cả 45 mục qua
//      tổng đài; (lớp 2) hook ẩn nguyên cây thanh gốc UIStatusBar_Modern /
//      _UIStatusBar khi độc chiếm — giờ và pin là hai mục tổng đài gần như
//      không gọi lại _setItem sau khởi động nên 1.1.8 dập không hết.
//   7. Pin độc chiếm: log "pin: xx%" mỗi khi % đổi (bằng chứng đọc được pin)
//      và hiện khung pin + "--" kể cả khi đọc lỗi, không mất hút.
//   Nút Reset về mặc định nằm ở phía prefs (xoá cài đặt + key, GIỮ mốc
//   thời gian kích hoạt — xem FG5RootListController.m + FG5License.m).
//
// ENGINE (từ 1.1.7, giữ nguyên): can thiệp ở NGUỒN DỮ LIỆU — hook
// SBStatusBarStateAggregator ép các mục gốc về "tắt" (4/5 sóng, 6/7 nhà
// mạng, 8 Wi-Fi, 9/10 chữ mạng) theo bản đồ iOS 16 của StatusMagic, rồi
// MỘT cửa sổ phủ của mình vẽ nhà mạng + vạch + nhãn. Phát lại lệnh qua
// -[SBStatusBarStateAggregator updateStatusBarItem:] mỗi khi prefs đổi,
// ở nhịp đầu và khi khoá/mở màn hình. Dò Wi-Fi bằng SBWiFiManager
// isAssociated mỗi giây (1.1.8). Lưới an toàn: hook
// _UIStatusBarWifiSignalView ép alpha 0.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "FG5Shared.h"
#import "FG5License.h"

// Các class SpringBoard không có header trong SDK — khai báo phần cần dùng.
@interface SBStatusBarStateAggregator : NSObject
@end

@interface SBCoverSheetPresentationManager : NSObject
+ (instancetype)sharedInstance;
- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated withCompletion:(id)completion;
@end

@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isAssociated;
@end

@interface BCBatteryDevice : NSObject
@property (nonatomic, readonly) long long percentCharge;
@property (nonatomic, readonly, getter=isCharging) BOOL charging;
@property (nonatomic, readonly, getter=isBatterySaverModeActive) BOOL batterySaverModeActive;
@end

@interface BCBatteryDeviceController : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, copy, readonly) NSArray *connectedDevices;
@end

@interface UIStatusBar_Modern : UIView
@end

@interface _UIStatusBar : UIView
@end

@interface _UIStatusBarStringView : UILabel
- (void)setText:(NSString *)text;
@end

@interface _UIStatusBarWifiSignalView : UIView
@end

#pragma mark - Trạng thái (nạp từ prefs)

static BOOL gEnabled = NO; // 1.1.10: cài mới = CHƯA bật, vào Cài đặt bật lên mới dùng
static BOOL gLicensed = NO;
static BOOL gFakeBars = YES;
static BOOL gFakeCarrier = YES;
static BOOL gHideNoSim = YES;
static BOOL gOnlyOnWifi = YES;
static BOOL gShowInSwitcher = YES;
static BOOL gShowOnLockScreen = YES;
static BOOL gExclusive = NO;
static BOOL gWifiPresent = NO;
static BOOL gDeviceLocked = NO;
static NSString *gLayoutProfilePref = @"auto";
static NSString *gSideClassic = @"left";
static NSString *gSideNotch = @"right";
static NSString *gSideIsland = @"right";

// 0 = cổ điển, 1 = tai thỏ, 2 = Dynamic Island
static NSInteger FG5EffectiveProfile(void);
static BOOL FG5SideIsRight(NSInteger profile) {
    if (profile == 0) return [gSideClassic isEqualToString:@"right"];
    if (profile == 2) return [gSideIsland isEqualToString:@"right"];
    return [gSideNotch isEqualToString:@"right"];
}

static void FG5ReloadPrefs(void) {
    gEnabled = FG5PrefBool(FG5_KEY_ENABLED, NO);
    gFakeBars = FG5PrefBool(FG5_KEY_FAKE_BARS, YES);
    gFakeCarrier = FG5PrefBool(FG5_KEY_FAKE_CARRIER, YES);
    gHideNoSim = FG5PrefBool(FG5_KEY_HIDE_NOSIM, YES);
    gOnlyOnWifi = FG5PrefBool(FG5_KEY_ONLY_ON_WIFI, YES);
    gShowInSwitcher = FG5PrefBool(FG5_KEY_SHOW_IN_SWITCHER, YES);
    gShowOnLockScreen = FG5PrefBool(FG5_KEY_SHOW_ON_LOCKSCREEN, YES);
    gExclusive = FG5PrefBool(FG5_KEY_EXCLUSIVE_MODE, NO);
    gLayoutProfilePref = FG5PrefString(FG5_KEY_LAYOUT_PROFILE, @"auto");
    gSideClassic = FG5PrefString(FG5_KEY_SIDE_CLASSIC, @"left");
    gSideNotch = FG5PrefString(FG5_KEY_SIDE_NOTCH, @"right");
    gSideIsland = FG5PrefString(FG5_KEY_SIDE_ISLAND, @"right");
    gLicensed = FG5LicenseActive();
}

#pragma mark - Tổng đài trạng thái (nguồn dữ liệu của thanh trạng thái)

static id gAggregator = nil;

// Mượn font từ một StringView thật của thanh gốc (đúng cỡ + độ đậm của iOS).
static UIFont *FG5FontFromView(UIView *v) {
    if ([v isKindOfClass:[UILabel class]]) {
        UIFont *f = ((UILabel *)v).font;
        if (f) return f;
    }
    for (UIView *sub in v.subviews) {
        UIFont *f = FG5FontFromView(sub);
        if (f) return f;
    }
    return nil;
}

static UIFont *FG5BorrowStatusFont(void) {
    Class cls = objc_getClass("_UIStatusBarStringView");
    if (!cls) return nil;
    UIApplication *app = [UIApplication sharedApplication];
    NSArray<UIWindow *> *wins = nil;
    if (@available(iOS 13.0, *)) {
        NSMutableArray *all = [NSMutableArray array];
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]])
                [all addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
        wins = all;
    }
    if (!wins) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        wins = [app valueForKey:@"windows"];
#pragma clang diagnostic pop
    }
    // Duyệt cây view bằng stack (hàm C không đệ quy qua block — bài học #13)
    for (UIWindow *w in wins) {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            if ([v isKindOfClass:cls]) {
                UIFont *f = FG5FontFromView(v);
                if (f) return f;
            }
            [stack addObjectsFromArray:v.subviews];
        }
    }
    return nil;
}

// Phát lại lệnh cập nhật cho CẢ 45 mục để tổng đài áp trạng thái đã ép.
// (1.1.7 chỉ phát 0–10; 1.1.10 phát hết: độc chiếm cần dập cả giờ/pin, và
// khi prefs bị reset lúc đang độc chiếm thì mọi mục cũng phải được trả lại.)
static void FG5RepublishItems(void) {
    if (!gAggregator) return;
    SEL sel = NSSelectorFromString(@"updateStatusBarItem:");
    if (![gAggregator respondsToSelector:sel]) return;
    void (*send)(id, SEL, int) = (void (*)(id, SEL, int))objc_msgSend;
    for (int i = 0; i < 45; i++) send(gAggregator, sel, i);
}

// Ép trạng thái một mục: trả về YES nếu mục này phải bị TẮT theo cấu hình.
// itemIsEnabled theo iOS 16 (StatusMagic): 4/5 = sóng di động, 6/7 = dịch
// vụ nhà mạng, 8 = Wi-Fi, 9/10 = chữ loại mạng, 12 = pin chính.
static BOOL FG5ItemForcedOff(int item) {
    if (!gEnabled || !gLicensed) return NO;
    if (gExclusive) return YES; // độc chiếm: tắt HẾT, dải của mình tự vẽ lại
    switch (item) {
        case 4: case 5:  return gFakeBars;
        case 6: case 7:  return gFakeCarrier || gHideNoSim;
        case 8:          return YES; // Wi-Fi: nhãn của mình thay chỗ
        case 9: case 10: return (!gOnlyOnWifi || gWifiPresent);
        default:         return NO;
    }
}

%hook SBStatusBarStateAggregator

- (void)_setItem:(int)item enabled:(BOOL)enabled {
    if (item == 8) gWifiPresent = enabled; // tín hiệu phụ: có traffic mục 8 = có Wi-Fi
    if (FG5ItemForcedOff(item)) enabled = NO;
    %orig;
}

// Mục giờ: độc chiếm thì chặn luôn nhịp cập nhật giờ của thanh gốc.
- (void)_updateTimeItems {
    if (gEnabled && gLicensed && gExclusive) return;
    %orig;
}

%end

// Lưới an toàn cho icon Wi-Fi: nếu vì lý do gì đó mục 8 không tắt được ở
// nguồn, view quạt Wi-Fi vẫn bị ép alpha 0 khi tweak đang chạy.
static const void *kFG5WifiAlphaKey = &kFG5WifiAlphaKey;

%hook _UIStatusBarWifiSignalView

- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    NSNumber *saved = objc_getAssociatedObject(v, kFG5WifiAlphaKey);
    if (gEnabled && gLicensed) {
        if (!saved) {
            objc_setAssociatedObject(v, kFG5WifiAlphaKey, @(v.alpha),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        v.alpha = 0;
    } else if (saved) {
        v.alpha = saved.floatValue;
        objc_setAssociatedObject(v, kFG5WifiAlphaKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

// ĐỘC CHIẾM LỚP 2 (1.1.10): ẩn nguyên cây thanh gốc. Giờ và pin gần như
// không được tổng đài gọi lại _setItem sau khởi động nên ép ở nguồn không
// đủ — ẩn thẳng view là chắc chắn. Đánh dấu bằng associated object để chỉ
// khôi phục đúng những view mình đã ẩn.
static const void *kFG5BarKilledKey = &kFG5BarKilledKey;

static void FG5ApplyExclusiveBarKill(UIView *bar) {
    BOOL killed = [objc_getAssociatedObject(bar, kFG5BarKilledKey) boolValue];
    if (gEnabled && gLicensed && gExclusive) {
        if (!killed) {
            objc_setAssociatedObject(bar, kFG5BarKilledKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!bar.hidden) bar.hidden = YES;
    } else if (killed) {
        objc_setAssociatedObject(bar, kFG5BarKilledKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        bar.hidden = NO;
    }
}

%hook UIStatusBar_Modern

- (void)layoutSubviews {
    %orig;
    FG5ApplyExclusiveBarKill((UIView *)self);
}

%end

%hook _UIStatusBar

- (void)layoutSubviews {
    %orig;
    FG5ApplyExclusiveBarKill((UIView *)self);
}

%end

// Khoá/mở màn hình: tổng đài thường tự phát lại các mục — tranh thủ phát
// lại lệnh của mình để trạng thái ép được áp ngay.
%hook SBCoverSheetPresentationManager

- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated withCompletion:(id)completion {
    %orig;
    FG5RepublishItems();
}

%end

#pragma mark - Pin thật (chế độ độc chiếm tự vẽ pin)

static void FG5BatteryInfo(NSInteger *pctOut, BOOL *chargingOut, BOOL *saverOut) {
    NSInteger pct = -1;
    BOOL charging = NO, saver = NO;
    Class cls = objc_getClass("BCBatteryDeviceController");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id ctrl = [cls sharedInstance];
        NSArray *devs = nil;
        if ([ctrl respondsToSelector:@selector(connectedDevices)])
            devs = [ctrl connectedDevices];
        for (id dev in devs) {
            if ([dev respondsToSelector:@selector(percentCharge)]) {
                pct = (NSInteger)[dev percentCharge];
                if ([dev respondsToSelector:@selector(isCharging)])
                    charging = [dev isCharging];
                if ([dev respondsToSelector:@selector(isBatterySaverModeActive)])
                    saver = [dev isBatterySaverModeActive];
                break; // thiết bị đầu tiên = pin máy
            }
        }
    }
    if (pct < 0) { // dự phòng bằng UIDevice
        UIDevice *d = [UIDevice currentDevice];
        d.batteryMonitoringEnabled = YES;
        if (d.batteryLevel >= 0) {
            pct = (NSInteger)lroundf(d.batteryLevel * 100);
            charging = (d.batteryState == UIDeviceBatteryStateCharging ||
                        d.batteryState == UIDeviceBatteryStateFull);
        }
    }
    if (pctOut) *pctOut = pct;
    if (chargingOut) *chargingOut = charging;
    if (saverOut) *saverOut = saver;
}

static BOOL FG5WifiAssociated(void) {
    Class cls = objc_getClass("SBWiFiManager");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = [cls sharedInstance];
        if ([mgr respondsToSelector:@selector(isAssociated)])
            return [mgr isAssociated];
    }
    return gWifiPresent; // không có class thì quay về tín hiệu mục 8
}

#pragma mark - Engine dải phủ

@interface FG5Engine : NSObject
@property (nonatomic, strong) UIWindow *stripWindow;
@property (nonatomic, strong) UILabel *carrierLabel;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIView *barsView;
@property (nonatomic, strong) NSMutableArray<UIView *> *barRects;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *batteryPercentLabel;
@property (nonatomic, strong) UIView *batteryBody;
@property (nonatomic, strong) UIView *batteryFill;
@property (nonatomic, strong) UIView *batteryCap;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIFont *borrowedFont;
@property (nonatomic, assign) CGFloat safeTop;
@property (nonatomic, assign) BOOL loggedProfile;
+ (instancetype)shared;
- (void)start;
- (void)tick;
- (void)prefsChanged;
- (NSArray<UIWindow *> *)allWindows;
- (UIWindow *)keySBWindow;
- (void)ensureStrip;
- (void)updateStrip;
- (void)layoutStrip;
- (void)applyTextStyles;
@end

@implementation FG5Engine

+ (instancetype)shared {
    static FG5Engine *e = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [[FG5Engine alloc] init]; });
    return e;
}

- (void)start {
    FG5ReloadPrefs();
    FG5RepublishItems();
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];
    FG5Log(@"Fake5G 1.1.10 khoi dong — engine tong dai + dai phu (doc chiem 2 lop), profile: %@, docchiem=%d wifi=%@",
           gLayoutProfilePref, gExclusive, FG5WifiAssociated() ? @"co" : @"khong");
}

- (void)prefsChanged {
    FG5ReloadPrefs();
    FG5RepublishItems();
    [self updateStrip];
    FG5Log(@"prefs: bat=%d key=%d vach=%d mang=%d anNoSim=%d chiWifi=%d khuon=%@ switcher=%d khoa=%d docchiem=%d",
           gEnabled, gLicensed, gFakeBars, gFakeCarrier, gHideNoSim,
           gOnlyOnWifi, gLayoutProfilePref, gShowInSwitcher,
           gShowOnLockScreen, gExclusive);
}

- (void)tick {
    // Dò Wi-Fi mỗi giây qua SBWiFiManager (chính xác hơn suy từ mục 8)
    gWifiPresent = FG5WifiAssociated();
    // Trạng thái khoá máy cho công tắc "Hiện ở màn hình khoá"
    static int fg5LockToken = 0;
    static BOOL fg5LockReady = NO;
    if (!fg5LockReady) {
        fg5LockReady = (notify_register_check("com.apple.springboard.lockstate",
                                              &fg5LockToken) == NOTIFY_STATUS_OK);
    }
    if (fg5LockReady) {
        uint64_t lockState = 0;
        if (notify_get_state(fg5LockToken, &lockState) == NOTIFY_STATUS_OK)
            gDeviceLocked = (lockState != 0);
    }
    // Độc chiếm lớp 1: mỗi giây phát lại lệnh ẩn cả 45 mục — mục nào tổng
    // đài tự bật lại (giờ, pin...) cũng bị dập ngay.
    if (gEnabled && gLicensed && gExclusive) FG5RepublishItems();
    if (!gAggregator) FG5RepublishItems(); // thử bắt tổng đài nếu nó xuất hiện muộn
    [self updateStrip];
}

- (NSArray<UIWindow *> *)allWindows {
    UIApplication *app = [UIApplication sharedApplication];
    NSMutableArray<UIWindow *> *all = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]])
                [all addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (all.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *wins = [app valueForKey:@"windows"];
#pragma clang diagnostic pop
        if ([wins isKindOfClass:[NSArray class]]) [all addObjectsFromArray:wins];
    }
    return all;
}

- (UIWindow *)keySBWindow {
    for (UIWindow *w in [self allWindows]) {
        NSString *cls = NSStringFromClass([w class]);
        if ([cls containsString:@"CoverSheet"] || [cls containsString:@"HomeScreen"]) return w;
    }
    return [self allWindows].firstObject;
}

- (void)ensureStrip {
    if (self.stripWindow) return;
    UIWindow *anchor = [self keySBWindow];
    if (!anchor) return;
    UIWindowScene *scene = nil;
    if (@available(iOS 13.0, *)) scene = anchor.windowScene;
    UIWindow *w = nil;
    if (scene) {
        w = [[UIWindow alloc] initWithWindowScene:scene];
        w.frame = scene.coordinateSpace.bounds;
    } else {
        w = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    if (!w) return;
    // Nằm trên mọi cửa sổ của SpringBoard (kể cả switcher/control center)
    CGFloat level = anchor.windowLevel;
    for (UIWindow *win in [self allWindows]) level = MAX(level, win.windowLevel);
    w.windowLevel = MIN(level + 10, 1990);
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = NO;
    w.rootViewController = [[UIViewController alloc] init];
    w.rootViewController.view.backgroundColor = [UIColor clearColor];
    w.hidden = NO;
    self.stripWindow = w;
    UIView *root = w.rootViewController.view;

    self.carrierLabel = [[UILabel alloc] init];
    self.carrierLabel.textColor = [UIColor whiteColor];
    [root addSubview:self.carrierLabel];

    self.barsView = [[UIView alloc] init];
    self.barRects = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        UIView *r = [[UIView alloc] init];
        r.layer.cornerRadius = 1;
        [self.barsView addSubview:r];
        [self.barRects addObject:r];
    }
    [root addSubview:self.barsView];

    self.label = [[UILabel alloc] init];
    self.label.textColor = [UIColor whiteColor];
    [root addSubview:self.label];

    // Giờ + pin của riêng mình (chỉ hiện ở chế độ độc chiếm)
    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.textColor = [UIColor whiteColor];
    [root addSubview:self.timeLabel];
    self.batteryPercentLabel = [[UILabel alloc] init];
    self.batteryPercentLabel.textColor = [UIColor whiteColor];
    self.batteryPercentLabel.textAlignment = NSTextAlignmentRight;
    [root addSubview:self.batteryPercentLabel];
    self.batteryBody = [[UIView alloc] init];
    self.batteryBody.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45].CGColor;
    self.batteryBody.layer.borderWidth = 1;
    self.batteryBody.layer.cornerRadius = 3.5;
    [root addSubview:self.batteryBody];
    self.batteryFill = [[UIView alloc] init];
    self.batteryFill.layer.cornerRadius = 1.5;
    [self.batteryBody addSubview:self.batteryFill];
    self.batteryCap = [[UIView alloc] init];
    self.batteryCap.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    self.batteryCap.layer.cornerRadius = 1;
    [root addSubview:self.batteryCap];

    [self applyTextStyles];
    FG5Log(@"dai phu: da tao (level %.0f)", w.windowLevel);
}

- (void)applyTextStyles {
    UIFont *font = self.borrowedFont;
    if (!font) {
        font = FG5BorrowStatusFont();
        if (font) self.borrowedFont = font;
    }
    if (!font) font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    self.label.font = font;
    self.label.text = FG5EffectiveLabel();
    self.carrierLabel.font = [UIFont systemFontOfSize:font.pointSize - 0.5
                                                weight:UIFontWeightSemibold];
    self.carrierLabel.text = FG5EffectiveCarrier();
    self.timeLabel.font = font;
    self.batteryPercentLabel.font = [UIFont systemFontOfSize:font.pointSize - 0.5
                                                         weight:UIFontWeightRegular];
    for (UILabel *l in @[self.label, self.carrierLabel, self.timeLabel, self.batteryPercentLabel]) {
        l.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        l.shadowOffset = CGSizeMake(0, 0.5);
    }
}

static NSInteger FG5EffectiveProfile(void) {
    if ([gLayoutProfilePref isEqualToString:@"classic"]) return 0;
    if ([gLayoutProfilePref isEqualToString:@"notch"]) return 1;
    if ([gLayoutProfilePref isEqualToString:@"island"]) return 2;
    CGFloat top = [FG5Engine shared].safeTop;
    if (top >= 54) return 2;
    if (top >= 30) return 1;
    return 0;
}

- (void)updateStrip {
    if (!gEnabled || !gLicensed) {
        self.stripWindow.hidden = YES;
        return;
    }
    [self ensureStrip];
    UIWindow *w = self.stripWindow;
    if (!w) return;

    // Mốc neo: safeArea top lớn nhất trong các cửa sổ SpringBoard
    CGFloat safeTop = 0;
    BOOL switcherVisible = NO;
    for (UIWindow *win in [self allWindows]) {
        safeTop = MAX(safeTop, win.safeAreaInsets.top);
        if ([NSStringFromClass([win class]) isEqualToString:@"SBMainSwitcherWindow"] && !win.hidden)
            switcherVisible = YES;
    }
    self.safeTop = safeTop;

    // Nâng level lên trên cửa sổ cao nhất hiện có (switcher/CC khi mở)
    CGFloat level = 0;
    for (UIWindow *win in [self allWindows]) {
        if (win != w) level = MAX(level, win.windowLevel);
    }
    w.windowLevel = MIN(MAX(level + 10, w.windowLevel), 1990);

    w.hidden = (switcherVisible && !gShowInSwitcher) ||
               (gDeviceLocked && !gShowOnLockScreen);

    [self applyTextStyles];

    NSString *effLabel = FG5EffectiveLabel();
    BOOL showLabel = (!gOnlyOnWifi || gWifiPresent) && effLabel.length > 0;
    self.label.hidden = !showLabel;
    BOOL showCarrier = gFakeCarrier && FG5EffectiveCarrier().length > 0;
    self.carrierLabel.hidden = !showCarrier;
    NSInteger bars = FG5EffectiveBarsCount();
    self.barsView.hidden = !gFakeBars || bars <= 0;
    for (int i = 0; i < 4; i++) {
        UIView *r = self.barRects[i];
        r.backgroundColor = (i < bars)
            ? [UIColor whiteColor]
            : [[UIColor whiteColor] colorWithAlphaComponent:0.3];
    }
    BOOL showOwnTimeBatt = gExclusive;
    self.timeLabel.hidden = !showOwnTimeBatt;
    self.batteryPercentLabel.hidden = !showOwnTimeBatt;
    self.batteryBody.hidden = !showOwnTimeBatt;
    self.batteryCap.hidden = !showOwnTimeBatt;

    if (!self.loggedProfile) {
        self.loggedProfile = YES;
        NSInteger p = FG5EffectiveProfile();
        FG5Log(@"profile: %@ (pref='%@', safeTop=%.0f)",
               p == 0 ? @"co dien" : (p == 2 ? @"dynamic island" : @"tai tho"),
               gLayoutProfilePref, safeTop);
    }
    [self layoutStrip];
}

- (void)layoutStrip {
    UIWindow *w = self.stripWindow;
    if (!w) return;
    CGFloat W = w.bounds.size.width;
    if (W < 50) return;
    NSInteger profile = FG5EffectiveProfile();
    BOOL excl = gExclusive;
    BOOL sideRight = FG5SideIsRight(profile);
    UIFont *font = self.label.font;
    UIFont *carrierFont = self.carrierLabel.font;
    if (!font) return;

    CGFloat sbH = (profile == 0) ? 20 : (profile == 2 ? 54 : 47);
    // Cổ điển ép lên máy tai thỏ: dùng chiều cao dải THẬT và neo giữa dải
    // như tai thỏ — cụm không còn bị ép sát mép trên (lỗi 1.1.8).
    BOOL classicOnNotch = (profile == 0 && self.safeTop >= 30);
    if (classicOnNotch) sbH = self.safeTop;
    CGFloat centerY = (profile == 0 && !classicOnNotch) ? sbH / 2 : sbH * 0.54;

    NSString *labelText = FG5EffectiveLabel();
    NSString *carrier = FG5EffectiveCarrier();

    // --- Pin của mình (độc chiếm): neo phải, vẽ TRƯỚC để cụm bên phải
    // biết giới hạn mà dừng lại trước pin ---
    CGFloat battRight = (profile == 0) ? (W - 8) : (W - 11);
    if (excl) {
        NSInteger pct = -1;
        BOOL charging = NO, saver = NO;
        FG5BatteryInfo(&pct, &charging, &saver);
        static NSInteger fg5LastLoggedPct = -2;
        if (pct >= 0 && pct != fg5LastLoggedPct) {
            fg5LastLoggedPct = pct;
            FG5Log(@"pin: %ld%% dangSac=%d tietKiem=%d", (long)pct, charging, saver);
        }
        CGFloat bodyW = 25, bodyH = 12;
        CGFloat bodyX = battRight - bodyW;
        self.batteryBody.frame = CGRectMake(bodyX, centerY - bodyH / 2, bodyW, bodyH);
        self.batteryCap.frame = CGRectMake(battRight + 1.5, centerY - 2, 1.5, 4);
        CGFloat innerW = bodyW - 4;
        CGFloat fillW = (pct >= 0) ? innerW * (pct / 100.0) : 0;
        self.batteryFill.frame = CGRectMake(2, 2, fillW, bodyH - 4);
        UIColor *fillColor = [UIColor whiteColor];
        if (charging) fillColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.35 alpha:1];
        else if (saver) fillColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1];
        else if (pct >= 0 && pct <= 20) fillColor = [UIColor colorWithRed:1.0 green:0.25 blue:0.2 alpha:1];
        self.batteryFill.backgroundColor = fillColor;
        self.batteryFill.hidden = (pct < 0);
        // Đọc lỗi vẫn hiện số dạng "--" để biết pin nằm đó, không mất hút
        self.batteryPercentLabel.text = (pct >= 0)
            ? [NSString stringWithFormat:@"%ld%%", (long)pct] : @"--";
        CGFloat pctW = ceil([self.batteryPercentLabel.text
            sizeWithAttributes:@{NSFontAttributeName: self.batteryPercentLabel.font}].width) + 2;
        self.batteryPercentLabel.frame = CGRectMake(bodyX - 4 - pctW, centerY - 10, pctW, 20);

        // Giờ của mình: cổ điển ở giữa; tai thỏ/Island ở tai trái như gốc
        static NSDateFormatter *tfmt = nil;
        if (!tfmt) { tfmt = [[NSDateFormatter alloc] init]; tfmt.dateFormat = @"HH:mm"; }
        self.timeLabel.text = [tfmt stringFromDate:[NSDate date]];
        if (profile == 0) {
            self.timeLabel.frame = CGRectMake((W - 60) / 2, centerY - 10, 60, 20);
            self.timeLabel.textAlignment = NSTextAlignmentCenter;
        } else {
            self.timeLabel.frame = CGRectMake(27, centerY - 10, 60, 20);
            self.timeLabel.textAlignment = NSTextAlignmentLeft;
        }
    }

    // --- Cụm giả theo dòng máy + phía đã chọn ---
    BOOL row2Cluster = (profile != 0 && !sideRight);
    UIFont *labelFontUsed = row2Cluster ? carrierFont : font;
    if (labelFontUsed) self.label.font = labelFontUsed;
    CGFloat labelH = row2Cluster ? 14 : 20;
    CGFloat labelW = ceil([labelText sizeWithAttributes:
        @{NSFontAttributeName: labelFontUsed ?: font}].width) + 2;
    if (labelW < 4) labelW = 4;
    CGFloat cw = 0;
    if (carrier.length) {
        cw = ceil([carrier sizeWithAttributes:@{NSFontAttributeName: carrierFont}].width) + 2;
        if (cw > 120) cw = 120;
    }
    CGFloat barsW = 17, barsH = 12;
    // Các vạch con bên trong cụm vạch
    CGFloat heights[4] = {4, 6, 8.5, 11};
    for (int i = 0; i < 4; i++) {
        CGFloat bh = heights[i];
        self.barRects[i].frame = CGRectMake(i * 4.6, barsH - bh, 3, bh);
    }
    // Giới hạn phải cho cụm nằm bên phải (tránh đè pin)
    CGFloat rightLimit;
    if (excl) rightLimit = CGRectGetMinX(self.batteryPercentLabel.frame) - 6;
    else rightLimit = W - ((profile == 0) ? 56 : (profile == 2 ? 58 : 54));

    if (profile == 0) {
        if (!sideRight) {
            CGFloat x = 8;
            self.barsView.frame = CGRectMake(x, centerY - barsH / 2, barsW, barsH);
            x += barsW + 5;
            if (carrier.length) {
                self.carrierLabel.frame = CGRectMake(x, centerY - 10, cw, 20);
                x += cw + 6;
            }
            self.label.frame = CGRectMake(x, centerY - labelH / 2, labelW, labelH);
        } else {
            CGFloat xr = rightLimit;
            self.label.frame = CGRectMake(xr - labelW, centerY - labelH / 2, labelW, labelH);
            xr -= labelW;
            if (carrier.length) {
                xr -= 6 + cw;
                self.carrierLabel.frame = CGRectMake(xr, centerY - 10, cw, 20);
            }
            self.barsView.frame = CGRectMake(xr - 5 - barsW, centerY - barsH / 2, barsW, barsH);
        }
    } else if (!row2Cluster) {
        // Tai phải: [nhãn][vạch] ngay trước pin gốc; nhà mạng ở hàng 2 trái
        self.label.frame = CGRectMake(rightLimit - labelW, centerY - labelH / 2, labelW, labelH);
        self.barsView.frame = CGRectMake(rightLimit - labelW - 5 - barsW,
                                         centerY - barsH / 2, barsW, barsH);
        if (carrier.length) {
            self.carrierLabel.frame = CGRectMake(20, sbH - 16, cw, 14);
        }
    } else {
        // Tai trái: cả cụm ở hàng 2 dưới giờ: [vạch][nhãn][nhà mạng]
        CGFloat y2 = sbH - 16;
        CGFloat x = 20;
        self.barsView.frame = CGRectMake(x, y2 + 1, barsW, barsH);
        x += barsW + 5;
        self.label.frame = CGRectMake(x, y2, labelW, labelH);
        x += labelW + 6;
        if (carrier.length) {
            self.carrierLabel.frame = CGRectMake(x, y2, cw, 14);
        }
    }
}

@end

#pragma mark - Điểm vào

static void FG5PrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFNotificationName name, const void *object,
                                    CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FG5Engine shared] prefsChanged];
    });
}

%ctor {
    @autoreleasepool {
        %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, FG5PrefsChangedCallback,
                                        FG5_PREFS_CHANGED_NOTIFICATION,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[FG5Engine shared] start];
        });
    }
}

// Bắt instance tổng đài: hook -init của nó (khối %hook thứ hai cho cùng
// class — Logos gộp được nhiều khối %hook của một class trong cùng file).
%hook SBStatusBarStateAggregator

- (instancetype)init {
    id obj = %orig;
    if (obj) gAggregator = obj;
    return obj;
}

%end
