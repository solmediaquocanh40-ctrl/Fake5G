// Tweak.x — Fake5G 1.1.7 (com.anhdang.fake5g)
// Giả hiển thị trên thanh trạng thái: thay icon Wi-Fi bằng nhãn chữ tuỳ chọn
// (4G/5G/tự nhập), hiện vạch sóng giả + tên nhà mạng giả cho máy không SIM,
// ẩn chữ "Không có SIM". Chỉ giả HIỂN THỊ — kết nối thật giữ nguyên 100%.
// Nạp vào SpringBoard. Log: /var/mobile/Documents/Fake5G.log
//
// CƠ CHẾ (đổi hẳn ở 1.1.7, học từ HideStatusBarItemsPro + StatusMagic mà
// anh Quoc gửi): KHÔNG săn view trong cửa sổ nữa — các bản 1.1.4–1.1.6 đã
// chứng minh bằng log máy thật là thanh trạng thái của màn hình chính
// không nằm trong cây view của bất kỳ cửa sổ SpringBoard nào. Mọi thanh
// trạng thái đều vẽ từ MỘT khối dữ liệu trung tâm do
// SBStatusBarStateAggregator dựng và phát. Vì vậy:
//   1) Ẩn đồ gốc TẠI NGUỒN: hook _setItem:enabled: của aggregator, ép tắt
//      các mục gốc (sóng / chữ nhà mạng / icon Wi-Fi / chữ mạng dữ liệu)
//      → chúng biến mất trên MỌI bề mặt cùng lúc.
//   2) Vẽ đồ giả bằng MỘT cửa sổ phủ duy nhất của tweak (trong suốt,
//      không chặn chạm, luôn nằm trên cùng ở dải trạng thái): chữ nhà
//      mạng + vạch sóng + nhãn 5G theo profile máy. Một cửa sổ phủ khắp
//      nơi → sửa prefs là đổi ngay (realtime), mọi bề mặt như nhau.
// Thứ tự mục theo bản đồ iOS 16 trong StatusMagic (StatusBarRawData):
//   4/5 = sóng chính/phụ, 6/7 = chữ nhà mạng chính/phụ,
//   8 = icon Wi-Fi, 9/10 = chữ mạng dữ liệu (5G/LTE) chính/phụ.
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
static NSString *gLayoutPref = @"auto";
// Ý định của hệ thống về mục Wi-Fi (ghi lại trong hook aggregator TRƯỚC
// khi ép tắt): YES = máy đang có Wi-Fi. Phục vụ option "chỉ thay khi có
// Wi-Fi". Mặc định YES để nhãn hiện ngay từ đầu.
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

// Phát lại trạng thái các mục liên quan để aggregator tính lại từ đầu
// (mỗi lần tính lại đều đi qua hook _setItem:enabled: của tweak).
static void FG5RepublishItems(void) {
    @try {
        Class cls = NSClassFromString(@"SBStatusBarStateAggregator");
        if (!cls) return;
        id agg = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        if (!agg) return;
        int items[] = {4, 5, 6, 7, 8, 9, 10};
        for (int i = 0; i < 7; i++) {
            ((void (*)(id, SEL, int))objc_msgSend)(agg,
                @selector(updateStatusBarItem:), items[i]);
        }
    } @catch (NSException *e) {}
}

@interface FG5Engine : NSObject
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIWindow *stripWindow;
@property (nonatomic, strong) UILabel *wifiLabel;
@property (nonatomic, strong) UIView *barsView;
@property (nonatomic, strong) UILabel *carrierLabel;
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
    FG5Log(@"Fake5G 1.1.7 khoi dong — ban quyen: %@", FG5LicenseStatusText());
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
    gLayoutPref = FG5PrefString(FG5_KEY_LAYOUT_PROFILE, @"auto");
    gLicensed = FG5LicenseActive();
}

- (void)prefsChanged {
    [self reloadPrefs];
    FG5Log(@"prefs thay doi — enabled=%d licensed=%d nhan='%@' nha mang='%@' vach=%ld switcher=%d",
           gEnabled, gLicensed, FG5EffectiveLabel(), FG5EffectiveCarrier(),
           (long)FG5EffectiveBarsCount(), gShowInSwitcher);
    FG5RepublishItems();
    [self updateStrip];
}

- (void)tick {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
        return;
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
    self.carrierLabel.font = font;

    CGFloat W = [UIScreen mainScreen].bounds.size.width;
    CGFloat sbH = (profile == 0) ? 20 : (profile == 2 ? 54 : 47);
    if ([gLayoutPref isEqualToString:@"auto"]) {
        CGFloat top = 0;
        for (UIWindow *win in [self allWindows]) top = MAX(top, win.safeAreaInsets.top);
        if (top >= 20) sbH = top;
    }
    w.frame = CGRectMake(0, 0, W, sbH);
    // Tâm dọc của cụm phải/trái trên thanh thật (đo từ dump máy thật:
    // chữ nhà mạng có tâm ≈ 54% chiều cao dải ở máy tai thỏ)
    CGFloat centerY = (profile == 0) ? sbH / 2.0 : sbH * 0.54;
    CGFloat labelH = 20, barsH = 12, barsW = 17;

    NSString *label = FG5EffectiveLabel();
    CGSize labelSize = [label sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat labelW = MIN(ceil(labelSize.width) + 4, labelMaxW + 8);
    NSString *carrier = FG5EffectiveCarrier();
    CGSize carrierSize = [carrier sizeWithAttributes:@{NSFontAttributeName: font}];

    if (profile == 0) {
        // Cổ điển: cụm trái — [vạch sóng][nhà mạng][nhãn], như thanh gốc
        self.barsView.frame = CGRectMake(8, centerY - barsH / 2.0, barsW, barsH);
        CGFloat cx = 8 + barsW + 5;
        CGFloat cw = gFakeCarrier ? MIN(ceil(carrierSize.width) + 2, carrierMaxW) : 0;
        self.carrierLabel.frame = CGRectMake(cx, centerY - labelH / 2.0, cw, labelH);
        self.carrierLabel.textAlignment = NSTextAlignmentLeft;
        self.wifiLabel.frame = CGRectMake(cx + (gFakeCarrier ? cw + 6 : 0),
                                          centerY - labelH / 2.0, labelW, labelH);
    } else {
        // Tai thỏ / Island: cụm tai phải, từ phải sang — [pin gốc][nhãn]
        // [vạch sóng][nhà mạng]. Chừa chỗ cho pin gốc ở sát mép phải.
        CGFloat labelRight = W - ((profile == 2) ? 58 : 54);
        self.wifiLabel.frame = CGRectMake(labelRight - labelW,
                                          centerY - labelH / 2.0, labelW, labelH);
        CGFloat barsRight = labelRight - labelW - 5;
        self.barsView.frame = CGRectMake(barsRight - barsW,
                                         centerY - barsH / 2.0, barsW, barsH);
        CGFloat carrierRight = barsRight - barsW - 5;
        CGFloat cw = MIN(ceil(carrierSize.width) + 2, 74);
        CGFloat minX = W * 0.52;
        if (carrierRight - cw < minX) cw = carrierRight - minX;
        self.carrierLabel.frame = CGRectMake(carrierRight - cw,
                                             centerY - labelH / 2.0, cw, labelH);
        self.carrierLabel.textAlignment = NSTextAlignmentRight;
    }
    // Vạch sóng con: 4 cột cao dần, đáy thẳng hàng
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat h = 4 + i * 2;
        self.barsView.subviews[i].frame = CGRectMake(i * 4.5, barsH - h, 3, h);
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
}

@end

#pragma mark - Hook aggregator: ẩn đồ gốc tại nguồn dữ liệu

// Khai báo class hệ thống không có header trong SDK (bài học AGENTS #41:
// khai đầy đủ trước %hook; các class này chỉ dùng trong SpringBoard).
@interface SBStatusBarStateAggregator : NSObject
+ (instancetype)sharedInstance;
- (BOOL)_setItem:(int)item enabled:(BOOL)enabled;
- (void)updateStatusBarItem:(int)item;
@end

@interface SBCoverSheetPresentationManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface _UIStatusBarWifiSignalView : UIView
@end

%hook SBStatusBarStateAggregator

- (BOOL)_setItem:(int)item enabled:(BOOL)enabled {
    if (item == 8) {
        // Ghi lại ý định thật của hệ thống về Wi-Fi cho option onlyOnWifi
        if (gWifiPresent != enabled) {
            gWifiPresent = enabled;
            dispatch_async(dispatch_get_main_queue(), ^{
                [gEngine updateStrip];
            });
        }
    }
    if (gEnabled && gLicensed) {
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
