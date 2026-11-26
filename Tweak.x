// Tweak.x — Fake5G 1.1.3 (com.anhdang.fake5g)
// Giả hiển thị trên thanh trạng thái: thay icon Wi-Fi bằng nhãn chữ tuỳ chọn
// (4G/5G/tự nhập), hiện vạch sóng giả + tên nhà mạng giả cho máy không SIM,
// ẩn chữ "Không có SIM". Chỉ giả HIỂN THỊ — kết nối thật giữ nguyên 100%.
// Nạp vào SpringBoard. Log: /var/mobile/Documents/Fake5G.log
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "FG5Shared.h"
#import "FG5License.h"

@interface _UIStatusBarStringView : UIView
@property (nonatomic, copy, readwrite) NSString *text;
@end

static const void *kFG5ServiceViewKey = &kFG5ServiceViewKey;
static const void *kFG5OriginalTextKey = &kFG5OriginalTextKey;

// Cờ đã nạp từ prefs (làm mới ở -reloadPrefs), hook đọc các cờ này cho nhẹ
static BOOL gEnabled = YES;
static BOOL gLicensed = NO;
static BOOL gFakeBars = YES;
static BOOL gFakeCarrier = YES;
static BOOL gHideNoSim = YES;
static BOOL gOnlyOnWifi = YES;
static NSString *gLayoutPref = @"auto";

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

static BOOL FG5IsNoSimText(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return NO;
    static NSSet<NSString *> *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithObjects:@"No SIM", @"No SIM Card", @"No Service",
               @"Không có SIM", @"Không có dịch vụ", @"Searching", @"Đang tìm kiếm", nil];
    });
    return [set containsObject:text];
}

@interface FG5Engine : NSObject
@property (nonatomic, strong) UILabel *wifiLabel;
@property (nonatomic, strong) UIView *barsView;
@property (nonatomic, strong) UILabel *carrierLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL applied;
@property (nonatomic, assign) BOOL dumpedOnce;
@property (nonatomic, assign) BOOL loggedProfile;
@property (nonatomic, assign) BOOL loggedWindows;
@property (nonatomic, assign) NSInteger dumpBudget;
@property (nonatomic, weak) UIWindow *activeWindow;
@property (nonatomic, strong) NSMutableSet<NSString *> *loggedTexts;
- (void)start;
- (void)tick;
- (void)prefsChanged;
- (void)reloadPrefs;
- (void)restoreInWindow:(UIWindow *)window;
- (NSInteger)effectiveProfileForWindow:(UIWindow *)window;
- (void)walkView:(UIView *)view into:(NSMutableDictionary *)found depth:(NSInteger)depth;
- (void)setSubviewsAlpha:(UIView *)view alpha:(CGFloat)alpha;
- (void)dumpTree:(UIView *)view depth:(NSInteger)depth;
- (NSArray<UIWindow *> *)allWindows;
- (UIWindow *)bestStatusBarWindowWithFound:(NSMutableDictionary **)foundOut;
- (NSInteger)scoreForFound:(NSDictionary *)found;
- (NSString *)ancestorChainOfView:(UIView *)view;
- (UIFont *)statusBarFontFromStrings:(NSArray *)strings size:(CGFloat)size;
- (UIColor *)statusBarContentColorNearView:(UIView *)view fallbackWindow:(UIWindow *)window;
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
    self.loggedTexts = [NSMutableSet set];
    [self reloadPrefs];
    FG5Log(@"Fake5G 1.1.3 khoi dong — ban quyen: %@", FG5LicenseStatusText());
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
    gLayoutPref = FG5PrefString(FG5_KEY_LAYOUT_PROFILE, @"auto");
    gLicensed = FG5LicenseActive();
}

- (void)prefsChanged {
    [self reloadPrefs];
    FG5Log(@"prefs thay doi — enabled=%d licensed=%d nhan='%@' nha mang='%@' vach=%ld",
           gEnabled, gLicensed, FG5EffectiveLabel(), FG5EffectiveCarrier(),
           (long)FG5EffectiveBarsCount());
    [self tick];
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

- (NSInteger)scoreForFound:(NSDictionary *)found {
    NSInteger score = 0;
    if (found[@"wifi"]) score += 100;
    if (found[@"cellular"]) score += 40;
    score += (NSInteger)[(NSArray *)found[@"strings"] count];
    return score;
}

- (NSString *)ancestorChainOfView:(UIView *)view {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *v = view;
    NSInteger guard = 0;
    while (v && guard++ < 14) {
        [parts addObject:NSStringFromClass([v class])];
        if ([v isKindOfClass:[UIWindow class]]) break;
        v = v.superview;
    }
    return [parts componentsJoinedByString:@" > "];
}

// Font chuẩn của chính iPhone: mượn font của một view chữ thật trên thanh
// trạng thái (view giờ / nhà mạng — chúng dùng đúng SF của hệ thống) rồi
// chỉnh về cỡ cần thiết. Không đọc được thì dùng font hệ thống semibold.
- (UIFont *)statusBarFontFromStrings:(NSArray *)strings size:(CGFloat)size {
    for (UIView *sv in strings) {
        UIFont *f = nil;
        @try { f = [sv valueForKey:@"font"]; } @catch (NSException *e) {}
        if ([f isKindOfClass:[UIFont class]]) {
            return [f fontWithSize:size];
        }
    }
    return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

// Lịch sử chọn cửa sổ: 1.0.0 bắt nhầm SBStatusBarReusePoolWindow (kho chứa
// thanh trạng thái tái sử dụng, rỗng). 1.1.1 sửa bằng cách chỉ xét cửa sổ
// cao <= 70pt — NHƯNG log máy thật 26/11 chứng minh iOS 16 SpringBoard
// KHÔNG có cửa sổ trạng thái riêng nào thấp cả: cả 15 cửa sổ đều cao bằng
// màn hình (844) hoặc 340, nên 1.1.1 loại sạch mọi cửa sổ và không bám
// được vào đâu. Cách đúng từ 1.1.2: tìm theo VIEW NEO — quét mọi cửa sổ
// (bỏ cửa sổ đang ẩn), cửa sổ nào chứa icon Wi-Fi thật thì bám cửa sổ đó;
// kho ReusePool chỉ dùng khi không cửa sổ nào khác có view trạng thái.
- (UIWindow *)bestStatusBarWindowWithFound:(NSMutableDictionary **)foundOut {
    // Đường nhanh: cửa sổ đang bám mà còn icon Wi-Fi thì giữ nguyên
    if (self.activeWindow &&
        ![NSStringFromClass([self.activeWindow class]) containsString:@"ReusePool"] &&
        !self.activeWindow.hidden) {
        NSMutableDictionary *found = [NSMutableDictionary dictionary];
        found[@"strings"] = [NSMutableArray array];
        [self walkView:(UIView *)self.activeWindow into:found depth:0];
        if (found[@"wifi"]) {
            if (foundOut) *foundOut = found;
            return self.activeWindow;
        }
    }
    UIWindow *best = nil;
    NSMutableDictionary *bestFound = nil;
    NSInteger bestScore = 0;
    UIWindow *poolBest = nil;
    NSMutableDictionary *poolFound = nil;
    NSInteger poolScore = 0;
    for (UIWindow *w in [self allWindows]) {
        if (w.hidden || w.alpha < 0.01) continue;
        NSMutableDictionary *found = [NSMutableDictionary dictionary];
        found[@"strings"] = [NSMutableArray array];
        [self walkView:(UIView *)w into:found depth:0];
        NSInteger score = [self scoreForFound:found];
        if (score == 0) continue;
        if ([NSStringFromClass([w class]) containsString:@"ReusePool"]) {
            if (score > poolScore) {
                poolScore = score;
                poolBest = w;
                poolFound = found;
            }
            continue;
        }
        if (score > bestScore) {
            bestScore = score;
            best = w;
            bestFound = found;
        }
    }
    if (!best && poolBest) {
        best = poolBest;
        bestFound = poolFound;
    }
    if (foundOut) *foundOut = bestFound;
    return best;
}

- (NSInteger)effectiveProfileForWindow:(UIWindow *)window {
    if ([gLayoutPref isEqualToString:@"classic"]) return 0;
    if ([gLayoutPref isEqualToString:@"notch"]) return 1;
    if ([gLayoutPref isEqualToString:@"island"]) return 2;
    // Tự động: theo safeAreaInsets.top của cửa sổ (cổ điển 0→20, tai thỏ
    // 44–47, Island 59). KHÔNG dùng chiều cao cửa sổ: trên iOS 16 cửa sổ
    // chứa thanh trạng thái cao bằng cả màn hình (log 26/11).
    CGFloat h = window.safeAreaInsets.top;
    if (h <= 0) h = 20;
    if (h <= 24) return 0;
    if (h >= 52) return 2;
    return 1;
}

- (void)walkView:(UIView *)view into:(NSMutableDictionary *)found depth:(NSInteger)depth {
    if (!view || depth > 40) return;
    NSString *cls = NSStringFromClass([view class]);
    if ([cls containsString:@"WifiSignal"] || [cls containsString:@"WiFiSignal"]) {
        if (!found[@"wifi"]) found[@"wifi"] = view;
    } else if ([cls containsString:@"CellularSignal"] || [cls containsString:@"PhoneSignal"]) {
        if (!found[@"cellular"]) found[@"cellular"] = view;
    } else if ([cls isEqualToString:@"_UIStatusBarStringView"]) {
        [(NSMutableArray *)found[@"strings"] addObject:view];
    }
    for (UIView *sub in view.subviews) {
        [self walkView:sub into:found depth:depth + 1];
    }
}

- (void)setSubviewsAlpha:(UIView *)view alpha:(CGFloat)alpha {
    for (UIView *sub in view.subviews) {
        sub.alpha = alpha;
        [self setSubviewsAlpha:sub alpha:alpha];
    }
}

- (void)dumpTree:(UIView *)view depth:(NSInteger)depth {
    // Trần 220 dòng: từ 1.1.3 cửa sổ bám được có thể là cửa sổ toàn màn hình
    // (cây view rất lớn), không trần thì log ngập và máy chậm hẳn.
    if (!view || depth > 7 || self.dumpBudget <= 0) return;
    self.dumpBudget--;
    NSMutableString *pad = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) [pad appendString:@"  "];
    FG5Log(@"%@%@ frame=%@", pad, NSStringFromClass([view class]),
           NSStringFromCGRect(view.frame));
    for (UIView *sub in view.subviews) [self dumpTree:sub depth:depth + 1];
}

- (UIColor *)statusBarContentColorNearView:(UIView *)view fallbackWindow:(UIWindow *)window {
    // Ưu tiên mượn màu chữ của chính một StringView trên thanh trạng thái
    if (view) {
        @try {
            id c = [view valueForKey:@"textColor"];
            if ([c isKindOfClass:[UIColor class]]) return c;
        } @catch (NSException *e) {}
    }
    if (window.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        return [UIColor whiteColor];
    }
    return [UIColor blackColor];
}

- (void)restoreInWindow:(UIWindow *)window {
    if (!window) return;
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    found[@"strings"] = [NSMutableArray array];
    [self walkView:(UIView *)window into:found depth:0];
    if (found[@"wifi"]) {
        ((UIView *)found[@"wifi"]).alpha = 1.0;
        [self setSubviewsAlpha:found[@"wifi"] alpha:1.0];
    }
    if (found[@"cellular"]) {
        ((UIView *)found[@"cellular"]).alpha = 1.0;
        [self setSubviewsAlpha:found[@"cellular"] alpha:1.0];
    }
    for (UIView *sv in (NSArray *)found[@"strings"]) {
        sv.hidden = NO;
        NSString *orig = objc_getAssociatedObject(sv, kFG5OriginalTextKey);
        if (orig.length > 0) {
            @try { [sv setValue:orig forKey:@"text"]; } @catch (NSException *e) {}
        }
    }
    self.applied = NO;
}

- (void)tick {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
        return;
    }
    BOOL shouldApply = gEnabled && gLicensed;
    if (!shouldApply) {
        if (self.applied && self.activeWindow) [self restoreInWindow:self.activeWindow];
        self.wifiLabel.hidden = YES;
        self.barsView.hidden = YES;
        self.carrierLabel.hidden = YES;
        return;
    }
    NSMutableDictionary *found = nil;
    UIWindow *window = [self bestStatusBarWindowWithFound:&found];
    if (!window || !found) {
        if (!self.loggedWindows) {
            self.loggedWindows = YES;
            FG5Log(@"chua thay cua so thanh trang thai phu hop — tat ca cua so:");
            for (UIWindow *w in [self allWindows]) {
                FG5Log(@"  window %@ frame=%@", NSStringFromClass([w class]),
                       NSStringFromCGRect(w.frame));
            }
        }
        return;
    }
    self.activeWindow = window;
    // Lớp phủ phải nằm trong đúng cửa sổ đã chọn (cửa sổ có thể đổi giữa các lần)
    for (UIView *overlay in @[self.wifiLabel ?: [NSNull null],
                              self.barsView ?: [NSNull null],
                              self.carrierLabel ?: [NSNull null]]) {
        if ([overlay isKindOfClass:[UIView class]] && overlay.superview != window) {
            [overlay removeFromSuperview];
            [window addSubview:overlay];
        }
    }
    if (!self.dumpedOnce) {
        self.dumpedOnce = YES;
        FG5Log(@"bam vao cua so: %@ frame=%@", NSStringFromClass([window class]),
               NSStringFromCGRect(window.frame));
        if (found[@"wifi"]) {
            FG5Log(@"chuoi view cha cua icon Wi-Fi: %@",
                   [self ancestorChainOfView:found[@"wifi"]]);
        }
        FG5Log(@"— dump cay thanh trang thai (phuc vu chan doan) —");
        self.dumpBudget = 220;
        [self dumpTree:(UIView *)window depth:0];
    }

    UIView *wifi = found[@"wifi"];
    UIView *cellular = found[@"cellular"];
    NSArray *strings = found[@"strings"];

    // Chiều cao THANH TRẠNG THÁI thật + profile — tính trước vòng nhận diện
    // nhà mạng vì nhận diện theo vị trí cần sbH. Sửa ở 1.1.3: KHÔNG lấy
    // chiều cao cửa sổ nữa (cửa sổ chứa thanh cao bằng cả màn hình, 844,
    // làm dải dự phòng của 1.1.2 rơi xuống giữa màn hình — ảnh máy thật
    // 26/11). safeTop: tai thỏ 47, Island 59, cổ điển 0 → lấy 20.
    CGFloat sbH = window.safeAreaInsets.top;
    if (sbH <= 0) sbH = 20;
    NSInteger profile = [self effectiveProfileForWindow:window];
    CGFloat fontSize = 12, labelMaxW = 64, carrierMaxW = 120;
    FG5ParamsForProfile(profile, &fontSize, &labelMaxW, &carrierMaxW);
    if (!self.loggedProfile) {
        self.loggedProfile = YES;
        FG5Log(@"profile: %@ (pref='%@', cua so %@, safeTop=%.0f)",
               FG5ProfileName(profile), gLayoutPref,
               NSStringFromCGSize(window.bounds.size), window.safeAreaInsets.top);
    }

    // Nhận diện StringView của nhà mạng / "Không có SIM" + ghi log chữ lạ 1 lần
    UIView *serviceView = nil;
    UIColor *contentColor = nil;
    for (UIView *sv in strings) {
        NSString *text = nil;
        @try { text = [sv valueForKey:@"text"]; } @catch (NSException *e) {}
        if ([text isKindOfClass:[NSString class]] && text.length > 0 &&
            ![self.loggedTexts containsObject:text]) {
            [self.loggedTexts addObject:text];
            FG5Log(@"StringView text='%@' frame=%@", text, NSStringFromCGRect(sv.frame));
        }
        NSNumber *marked = objc_getAssociatedObject(sv, kFG5ServiceViewKey);
        BOOL claim = FG5IsNoSimText(text) || [marked boolValue];
        if (!claim && [text isKindOfClass:[NSString class]] && text.length > 0 &&
            ![text containsString:@":"]) {
            // Nhận diện theo VỊ TRÍ (1.1.3): máy có SIM thì view nhà mạng
            // mang tên nhà mạng thật (vd MobiFone) nên nhận diện theo chữ
            // "Không có SIM" không bắt được — log 1.1.2 đã chứng minh view
            // đó tồn tại mà không được nhận. View chữ nằm trong dải trạng
            // thái + ở nửa trái của thanh + chữ không phải giờ (giờ có
            // dấu :) → chính là view nhà mạng/dịch vụ.
            CGRect wr = [sv convertRect:sv.bounds toView:window];
            if (wr.origin.y < sbH &&
                CGRectGetMidX(wr) < window.bounds.size.width * 0.45) {
                claim = YES;
                objc_setAssociatedObject(sv, kFG5ServiceViewKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (objc_getAssociatedObject(sv, kFG5OriginalTextKey) == nil) {
                    objc_setAssociatedObject(sv, kFG5OriginalTextKey, text,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                FG5Log(@"nhan dien view nha mang theo vi tri: '%@' rect=%@",
                       text, NSStringFromCGRect(wr));
            }
        }
        if (claim) {
            serviceView = sv;
            if (text.length > 0 && !FG5IsNoSimText(text) &&
                objc_getAssociatedObject(sv, kFG5OriginalTextKey) == nil) {
                objc_setAssociatedObject(sv, kFG5OriginalTextKey, text,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (FG5IsNoSimText(text)) {
                objc_setAssociatedObject(sv, kFG5ServiceViewKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (objc_getAssociatedObject(sv, kFG5OriginalTextKey) == nil) {
                    objc_setAssociatedObject(sv, kFG5OriginalTextKey, text,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        if (!contentColor) {
            contentColor = [self statusBarContentColorNearView:sv fallbackWindow:window];
        }
    }
    if (!contentColor) contentColor = [self statusBarContentColorNearView:nil fallbackWindow:window];

    // Dải dọc dự phòng khi không có view neo: cổ điển dùng cả chiều cao 20pt,
    // tai thỏ/Island canh giữa vùng tai bằng dải 20pt giữa cửa sổ
    CGFloat bandY = (profile == 0) ? 0 : MAX(0, (sbH - 20) / 2.0);
    CGFloat bandH = (profile == 0) ? sbH : 20;

    // — Nhãn thay icon Wi-Fi —
    if (wifi) {
        // Ẩn cả CHÍNH view icon (1.1.3): chỉ ẩn view con như trước không đủ —
        // icon Wi-Fi tự vẽ một phần hình ở lớp của chính nó nên vẫn hằn mờ
        // sau nhãn (ảnh máy thật 26/11).
        wifi.alpha = 0.0;
        [self setSubviewsAlpha:wifi alpha:0.0];
        if (!self.wifiLabel) {
            self.wifiLabel = [[UILabel alloc] init];
            self.wifiLabel.textAlignment = NSTextAlignmentCenter;
            self.wifiLabel.adjustsFontSizeToFitWidth = YES;
            self.wifiLabel.minimumScaleFactor = 0.6;
            [window addSubview:self.wifiLabel];
        }
        self.wifiLabel.font = [self statusBarFontFromStrings:strings size:fontSize];
        NSString *label = FG5EffectiveLabel();
        self.wifiLabel.text = label;
        self.wifiLabel.textColor = contentColor;
        CGSize textSize = [label sizeWithAttributes:@{NSFontAttributeName: self.wifiLabel.font}];
        CGRect wr = [wifi convertRect:wifi.bounds toView:window];
        CGFloat w = MAX(wr.size.width, ceil(textSize.width) + 6);
        w = MIN(w, labelMaxW);
        // Canh theo đúng dải dọc của icon gốc (mọi đời máy đều đúng dải của nó)
        CGFloat ly = (wr.size.height >= 8) ? wr.origin.y : bandY;
        CGFloat lh = (wr.size.height >= 8) ? wr.size.height : bandH;
        self.wifiLabel.frame = CGRectMake(CGRectGetMidX(wr) - w / 2.0, ly, w, lh);
        self.wifiLabel.hidden = NO;
        [window bringSubviewToFront:self.wifiLabel];
    } else if (!gOnlyOnWifi) {
        // Tắt "chỉ khi có Wi-Fi": vẫn hiện nhãn ở cụm phải của thanh trạng thái
        if (!self.wifiLabel) {
            self.wifiLabel = [[UILabel alloc] init];
            self.wifiLabel.textAlignment = NSTextAlignmentCenter;
            self.wifiLabel.adjustsFontSizeToFitWidth = YES;
            self.wifiLabel.minimumScaleFactor = 0.6;
            [window addSubview:self.wifiLabel];
        }
        self.wifiLabel.font = [self statusBarFontFromStrings:strings size:fontSize];
        NSString *label = FG5EffectiveLabel();
        self.wifiLabel.text = label;
        self.wifiLabel.textColor = contentColor;
        CGSize textSize = [label sizeWithAttributes:@{NSFontAttributeName: self.wifiLabel.font}];
        CGFloat w = MIN(ceil(textSize.width) + 6, labelMaxW);
        CGFloat rightInset = (profile == 2) ? 38 : (profile == 1) ? 36 : 52;
        self.wifiLabel.frame = CGRectMake(window.bounds.size.width - rightInset - w,
                                          bandY, w, bandH);
        self.wifiLabel.hidden = NO;
        [window bringSubviewToFront:self.wifiLabel];
    } else {
        self.wifiLabel.hidden = YES;
        static BOOL loggedNoWifi = NO;
        if (!loggedNoWifi) {
            loggedNoWifi = YES;
            FG5Log(@"chua thay view icon Wi-Fi trong cay thanh trang thai (Wi-Fi tat?)");
        }
    }

    // — Vạch sóng giả —
    CGRect barsRect = CGRectZero;
    if (gFakeBars) {
        if (!self.barsView) {
            self.barsView = [[UIView alloc] init];
            for (NSInteger i = 0; i < 4; i++) {
                UIView *bar = [[UIView alloc] init];
                bar.tag = 100 + i;
                bar.layer.cornerRadius = 0.75;
                [self.barsView addSubview:bar];
            }
            [window addSubview:self.barsView];
        }
        if (cellular) {
            cellular.alpha = 0.0;
            [self setSubviewsAlpha:cellular alpha:0.0];
            barsRect = [cellular convertRect:cellular.bounds toView:window];
            if (barsRect.size.width < 14) barsRect.size.width = 18;
            if (barsRect.size.height < 8) {
                barsRect.origin.y = bandY;
                barsRect.size.height = bandH;
            }
        } else if (profile == 0) {
            barsRect = CGRectMake(7, bandY, 18, bandH);
        } else {
            // Tai thỏ/Island: cụm sóng nằm ở tai phải, ngay trước nhãn Wi-Fi
            CGFloat bx = window.bounds.size.width - ((profile == 2) ? 108 : 104);
            barsRect = CGRectMake(bx, bandY, 18, bandH);
        }
        self.barsView.frame = CGRectMake(barsRect.origin.x, barsRect.origin.y,
                                         18, barsRect.size.height);
        NSInteger active = FG5EffectiveBarsCount();
        CGFloat bh = barsRect.size.height;
        CGFloat scale = MIN(1.0, MAX(0.6, bh / 20.0));
        CGFloat heights[4] = {3, 5, 7, 9};
        CGFloat x = 0;
        for (NSInteger i = 0; i < 4; i++) {
            UIView *bar = [self.barsView viewWithTag:100 + i];
            CGFloat h = heights[i] * scale;
            bar.frame = CGRectMake(x, bh - 2 - h, 3, h);
            bar.backgroundColor = (i < active) ? contentColor
                                               : [contentColor colorWithAlphaComponent:0.3];
            x += 4.5;
        }
        self.barsView.hidden = NO;
        [window bringSubviewToFront:self.barsView];
    } else {
        self.barsView.hidden = YES;
        if (cellular) {
            cellular.alpha = 1.0;
            [self setSubviewsAlpha:cellular alpha:1.0];
        }
    }

    // — Tên nhà mạng —
    if (serviceView) {
        // Có view chữ của hệ thống: thay chữ ngay trên view đó (ổn định nhất)
        self.carrierLabel.hidden = YES;
        if (gFakeCarrier) {
            serviceView.hidden = NO;
            NSString *carrier = FG5EffectiveCarrier();
            NSString *cur = nil;
            @try { cur = [serviceView valueForKey:@"text"]; } @catch (NSException *e) {}
            if (![cur isEqualToString:carrier]) {
                @try { [serviceView setValue:carrier forKey:@"text"]; } @catch (NSException *e) {}
            }
        } else if (gHideNoSim) {
            serviceView.hidden = YES;
        } else {
            serviceView.hidden = NO;
        }
    } else if (gFakeCarrier) {
        // Không thấy view chữ: vẽ nhãn riêng theo profile
        if (!self.carrierLabel) {
            self.carrierLabel = [[UILabel alloc] init];
            self.carrierLabel.adjustsFontSizeToFitWidth = YES;
            self.carrierLabel.minimumScaleFactor = 0.6;
            [window addSubview:self.carrierLabel];
        }
        self.carrierLabel.font = [self statusBarFontFromStrings:strings size:fontSize];
        NSString *carrier = FG5EffectiveCarrier();
        self.carrierLabel.text = carrier;
        self.carrierLabel.textColor = contentColor;
        CGSize textSize = [carrier sizeWithAttributes:@{NSFontAttributeName: self.carrierLabel.font}];
        CGFloat cw = MIN(ceil(textSize.width) + 2, carrierMaxW);
        CGFloat x, cy, ch;
        if (profile == 0) {
            // Cổ điển: nhãn nằm ngay sau vạch sóng ở cụm trái
            x = gFakeBars ? CGRectGetMaxX(self.barsView.frame) + 4 : 8;
            cy = gFakeBars ? self.barsView.frame.origin.y : bandY;
            ch = gFakeBars ? self.barsView.frame.size.height : bandH;
        } else {
            // Tai thỏ/Island: nhãn nằm ở tai phải, ngay trước vạch sóng,
            // không lấn vào vùng giữa (tai thỏ/Island)
            CGFloat anchorX = gFakeBars ? self.barsView.frame.origin.x
                                        : CGRectGetMinX(self.wifiLabel.frame);
            x = anchorX - cw - 3;
            CGFloat minX = window.bounds.size.width * ((profile == 2) ? 0.64 : 0.63);
            if (x < minX) x = minX;
            cy = bandY;
            ch = bandH;
        }
        self.carrierLabel.frame = CGRectMake(x, cy, cw, ch);
        self.carrierLabel.hidden = NO;
        [window bringSubviewToFront:self.carrierLabel];
    } else {
        self.carrierLabel.hidden = YES;
    }

    self.applied = YES;
}

@end

#pragma mark - Hook StringView: chặn chữ nhà mạng ngay khi hệ thống gán

%hook _UIStatusBarStringView

- (void)setText:(NSString *)text {
    if (gEnabled && gLicensed && [text isKindOfClass:[NSString class]]) {
        BOOL isService = [objc_getAssociatedObject(self, kFG5ServiceViewKey) boolValue];
        if (FG5IsNoSimText(text) || isService) {
            objc_setAssociatedObject(self, kFG5ServiceViewKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (objc_getAssociatedObject(self, kFG5OriginalTextKey) == nil && text.length > 0) {
                objc_setAssociatedObject(self, kFG5OriginalTextKey, text,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (gFakeCarrier) {
                %orig(FG5EffectiveCarrier());
                return;
            }
            if (gHideNoSim && FG5IsNoSimText(text)) {
                %orig(@"");
                return;
            }
        }
    }
    %orig;
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
