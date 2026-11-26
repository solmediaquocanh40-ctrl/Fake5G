// Tweak.x — Fake5G 1.0.0 (com.anhdang.fake5g)
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
@property (nonatomic, strong) NSMutableSet<NSString *> *loggedTexts;
- (void)start;
- (void)tick;
- (void)prefsChanged;
- (void)reloadPrefs;
- (void)restoreInWindow:(UIWindow *)window;
- (void)walkView:(UIView *)view into:(NSMutableDictionary *)found depth:(NSInteger)depth;
- (void)setSubviewsAlpha:(UIView *)view alpha:(CGFloat)alpha;
- (void)dumpTree:(UIView *)view depth:(NSInteger)depth;
- (UIWindow *)statusBarWindow;
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
    FG5Log(@"Fake5G 1.0.0 khoi dong — ban quyen: %@", FG5LicenseStatusText());
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
    gLicensed = FG5LicenseActive();
}

- (void)prefsChanged {
    [self reloadPrefs];
    FG5Log(@"prefs thay doi — enabled=%d licensed=%d nhan='%@' nha mang='%@' vach=%ld",
           gEnabled, gLicensed, FG5EffectiveLabel(), FG5EffectiveCarrier(),
           (long)FG5EffectiveBarsCount());
    [self tick];
}

- (UIWindow *)statusBarWindow {
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
    UIWindow *best = nil;
    for (UIWindow *w in windows) {
        NSString *cls = NSStringFromClass([w class]);
        if ([cls containsString:@"StatusBar"]) return w;
        if (w.windowLevel >= UIWindowLevelStatusBar && !best) best = w;
    }
    return best;
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
    if (!view || depth > 7) return;
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
    if (found[@"wifi"]) [self setSubviewsAlpha:found[@"wifi"] alpha:1.0];
    if (found[@"cellular"]) [self setSubviewsAlpha:found[@"cellular"] alpha:1.0];
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
    UIWindow *window = [self statusBarWindow];
    BOOL shouldApply = gEnabled && gLicensed;
    if (!shouldApply) {
        if (self.applied && window) [self restoreInWindow:window];
        self.wifiLabel.hidden = YES;
        self.barsView.hidden = YES;
        self.carrierLabel.hidden = YES;
        return;
    }
    if (!window) return;
    if (!self.dumpedOnce) {
        self.dumpedOnce = YES;
        FG5Log(@"— dump cay thanh trang thai (phuc vu chan doan) —");
        [self dumpTree:(UIView *)window depth:0];
    }

    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    found[@"strings"] = [NSMutableArray array];
    [self walkView:(UIView *)window into:found depth:0];
    UIView *wifi = found[@"wifi"];
    UIView *cellular = found[@"cellular"];
    NSArray *strings = found[@"strings"];

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
        if (FG5IsNoSimText(text) || [marked boolValue]) {
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

    CGFloat sbH = window.bounds.size.height;

    // — Nhãn thay icon Wi-Fi —
    if (wifi) {
        [self setSubviewsAlpha:wifi alpha:0.0];
        if (!self.wifiLabel) {
            self.wifiLabel = [[UILabel alloc] init];
            self.wifiLabel.textAlignment = NSTextAlignmentCenter;
            self.wifiLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [window addSubview:self.wifiLabel];
        }
        NSString *label = FG5EffectiveLabel();
        self.wifiLabel.text = label;
        self.wifiLabel.textColor = contentColor;
        CGSize textSize = [label sizeWithAttributes:@{NSFontAttributeName: self.wifiLabel.font}];
        CGRect wr = [wifi convertRect:wifi.bounds toView:window];
        CGFloat w = MAX(wr.size.width, ceil(textSize.width) + 6);
        self.wifiLabel.frame = CGRectMake(CGRectGetMidX(wr) - w / 2.0, 0, w, sbH);
        self.wifiLabel.hidden = NO;
        [window bringSubviewToFront:self.wifiLabel];
    } else if (!gOnlyOnWifi) {
        // Tắt "chỉ khi có Wi-Fi": vẫn hiện nhãn ở cụm phải của thanh trạng thái
        if (!self.wifiLabel) {
            self.wifiLabel = [[UILabel alloc] init];
            self.wifiLabel.textAlignment = NSTextAlignmentCenter;
            self.wifiLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [window addSubview:self.wifiLabel];
        }
        NSString *label = FG5EffectiveLabel();
        self.wifiLabel.text = label;
        self.wifiLabel.textColor = contentColor;
        CGSize textSize = [label sizeWithAttributes:@{NSFontAttributeName: self.wifiLabel.font}];
        CGFloat w = ceil(textSize.width) + 6;
        self.wifiLabel.frame = CGRectMake(window.bounds.size.width - 52 - w, 0, w, sbH);
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
            [self setSubviewsAlpha:cellular alpha:0.0];
            barsRect = [cellular convertRect:cellular.bounds toView:window];
            if (barsRect.size.width < 14) barsRect.size.width = 18;
        } else {
            barsRect = CGRectMake(7, 0, 18, sbH);
        }
        self.barsView.frame = CGRectMake(barsRect.origin.x, 0, 18, sbH);
        NSInteger active = FG5EffectiveBarsCount();
        CGFloat heights[4] = {3, 5, 7, 9};
        CGFloat x = 0;
        for (NSInteger i = 0; i < 4; i++) {
            UIView *bar = [self.barsView viewWithTag:100 + i];
            CGFloat h = heights[i];
            bar.frame = CGRectMake(x, sbH - 4 - h, 3, h);
            bar.backgroundColor = (i < active) ? contentColor
                                               : [contentColor colorWithAlphaComponent:0.3];
            x += 4.5;
        }
        self.barsView.hidden = NO;
        [window bringSubviewToFront:self.barsView];
    } else {
        self.barsView.hidden = YES;
        if (cellular) [self setSubviewsAlpha:cellular alpha:1.0];
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
        // Không thấy view chữ: vẽ nhãn riêng ngay sau vạch sóng
        if (!self.carrierLabel) {
            self.carrierLabel = [[UILabel alloc] init];
            self.carrierLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [window addSubview:self.carrierLabel];
        }
        NSString *carrier = FG5EffectiveCarrier();
        self.carrierLabel.text = carrier;
        self.carrierLabel.textColor = contentColor;
        CGSize textSize = [carrier sizeWithAttributes:@{NSFontAttributeName: self.carrierLabel.font}];
        CGFloat x = gFakeBars ? CGRectGetMaxX(self.barsView.frame) + 4 : 8;
        self.carrierLabel.frame = CGRectMake(x, 0, ceil(textSize.width) + 2, sbH);
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
