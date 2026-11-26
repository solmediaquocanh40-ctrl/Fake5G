// FG5RootListController.m — Fake5G 1.1.11
// Trang Cài đặt của Fake5G. Từ 1.1.4 theo yêu cầu của anh Quoc: CHƯA kích
// hoạt key thì không vào được phần điều chỉnh — mở trang lên là phủ mờ +
// hiện popup Active (OK = kiểm key, Huỷ = đóng; tự tắt sau 30 giây, đếm
// tạm dừng trong lúc đang gõ key) như mẫu ZUS. Dùng thử 3 ngày chỉ chạy
// phần hiển thị trên thanh trạng thái bằng cấu hình sẵn có, không mở
// trang điều chỉnh.
#import "FG5RootListController.h"
#import "../FG5Shared.h"
#import "../FG5License.h"
#import <spawn.h>

extern char **environ;

@implementation FG5RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        for (PSSpecifier *spec in _specifiers) {
            if ([[spec propertyForKey:@"id"] isEqualToString:@"licenseGroup"]) {
                [spec setProperty:FG5LicenseStatusText() forKey:@"footerText"];
            }
        }
    }
    return _specifiers;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (FG5LicenseHasActiveKey()) {
        [self removeExpiredOverlay];
        self.popupShownThisAppear = NO;
    } else {
        [self installExpiredOverlay];
        if (!self.popupShownThisAppear) {
            self.popupShownThisAppear = YES;
            [self showActivatePopup];
        }
    }
}

#pragma mark - Phủ mờ khi hết hạn

- (void)installExpiredOverlay {
    if ([self.view viewWithTag:9001]) return;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blur.tag = 9001;
    blur.frame = self.view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UILabel *label = [[UILabel alloc] initWithFrame:blur.contentView.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = (FG5LicenseCurrentState(NULL, NULL) == FG5LicStateTrial)
        ? @"Đang dùng thử — nhập key để mở khoá điều chỉnh\nChạm để nhập key kích hoạt"
        : @"Đã hết hạn dùng thử\nChạm để nhập key kích hoạt";
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [blur.contentView addSubview:label];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(expiredOverlayTapped)];
    [blur addGestureRecognizer:tap];
    [self.view addSubview:blur];
}

- (void)removeExpiredOverlay {
    [[self.view viewWithTag:9001] removeFromSuperview];
}

- (void)expiredOverlayTapped {
    [self showActivatePopup];
}

#pragma mark - Popup Active (mẫu ZUS: OK/Huỷ, tự tắt 30s, dừng đếm khi gõ)

- (void)activateTapped:(id)sender {
    [self showActivatePopup];
}

- (void)showActivatePopup {
    [self showActivatePopupWithMessage:FG5LicenseStatusText()];
}

- (void)showActivatePopupWithMessage:(NSString *)message {
    if (self.activeAlert) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Kích hoạt Fake5G"
                         message:[message stringByAppendingString:
                                  @"\nDán key vào ô dưới rồi bấm OK. Popup tự đóng sau 30 giây."]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"FG51-....";
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.delegate = self;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            [weakSelf stopPopupTimer];
            weakSelf.activeAlert = nil;
            NSString *key = alert.textFields.firstObject.text ?: @"";
            NSString *name = nil, *error = nil;
            if (FG5LicenseTryActivateKey(key, &name, &error)) {
                [weakSelf removeExpiredOverlay];
                weakSelf.popupShownThisAppear = NO;
                [weakSelf reloadSpecifiers];
                UIAlertController *ok = [UIAlertController
                    alertControllerWithTitle:@"Đã kích hoạt"
                                     message:[NSString stringWithFormat:@"Key của %@ đã được chấp nhận.", name ?: @""]
                              preferredStyle:UIAlertControllerStyleAlert];
                [ok addAction:[UIAlertAction actionWithTitle:@"Xong" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:ok animated:YES completion:nil];
            } else {
                [weakSelf showActivatePopupWithMessage:(error ?: @"Key chưa đúng.")];
            }
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *action) {
            [weakSelf stopPopupTimer];
            weakSelf.activeAlert = nil;
        }]];
    self.activeAlert = alert;
    self.popupSecondsLeft = 30;
    self.popupEditing = NO;
    [self presentViewController:alert animated:YES completion:nil];
    [self stopPopupTimer];
    self.popupTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(popupTimerFired)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)popupTimerFired {
    if (self.popupEditing) return; // đang gõ key thì dừng đếm, như ZUS
    self.popupSecondsLeft -= 1;
    if (self.popupSecondsLeft <= 0) {
        [self stopPopupTimer];
        [self.activeAlert dismissViewControllerAnimated:YES completion:nil];
        self.activeAlert = nil;
    }
}

- (void)stopPopupTimer {
    [self.popupTimer invalidate];
    self.popupTimer = nil;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.popupEditing = YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.popupEditing = NO;
}

#pragma mark - Reset về mặc định

- (void)resetTapped:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset về mặc định"
                         message:@"Toàn bộ cài đặt sẽ trở về mặc định và key đã kích hoạt sẽ bị xoá — phải nhập lại key mới dùng tiếp.\nThời gian kích hoạt của key vẫn tính từ lần nhập đầu tiên, dùng thử không chạy lại."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) { [weakSelf fg5PerformReset]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fg5PerformReset {
    // Ghi giá trị mặc định qua ĐÚNG đường ghi của PSListController cho từng
    // ô có key: trạng thái ô trên màn hình và dữ liệu khớp nhau ngay tại
    // chỗ. Cách cũ (xoá key trần rồi reloadSpecifiers) bị trang ghi ngược
    // giá trị ON của ô gạt đang hiện (Bật Fake5G) trở lại vào prefs — máy
    // thật 1.1.11 chứng minh: reset xong tweak vẫn đọc bat=1, chạy tiếp
    // bằng mặc định. Bảng mặc định này phải khớp Root.plist từng ô.
    NSDictionary<NSString *, id> *defaults = @{
        FG5_KEY_ENABLED: @NO,
        FG5_KEY_SHOW_IN_SWITCHER: @YES,
        FG5_KEY_SHOW_ON_LOCKSCREEN: @YES,
        FG5_KEY_EXCLUSIVE_MODE: @NO,
        FG5_KEY_LAYOUT_PROFILE: @"auto",
        FG5_KEY_SIDE_CLASSIC: @"left",
        FG5_KEY_SIDE_NOTCH: @"right",
        FG5_KEY_SIDE_ISLAND: @"right",
        FG5_KEY_OFFSET_X: @0,
        FG5_KEY_OFFSET_Y: @0,
        FG5_KEY_LABEL_PRESET: @"5G",
        FG5_KEY_LABEL_CUSTOM: @"",
        FG5_KEY_ONLY_ON_WIFI: @YES,
        FG5_KEY_FAKE_BARS: @YES,
        FG5_KEY_BARS_COUNT: @"4",
        FG5_KEY_FAKE_CARRIER: @YES,
        FG5_KEY_CARRIER_PRESET: @"Viettel",
        FG5_KEY_CARRIER_CUSTOM: @"",
        FG5_KEY_HIDE_NOSIM: @YES
    };
    for (PSSpecifier *spec in [self specifiers]) {
        NSString *k = [spec propertyForKey:@"key"];
        id v = k ? defaults[k] : nil;
        if (v) [self setPreferenceValue:v specifier:spec];
    }
    // Key đã nhập thì xoá thẳng (không phải ô trên trang nên không bị ghi
    // ngược). Các mốc thời gian bản quyền (trialStart / maxSeen / actStart
    // / actKeyHash ở prefs + Keychain + file ẩn) CỐ Ý GIỮ NGUYÊN: hạn key
    // tính từ lần kích hoạt đầu tiên.
    FG5PrefSet(FG5_KEY_LICENSE_KEY, nil);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         FG5_PREFS_CHANGED_NOTIFICATION, NULL, NULL, true);
    FG5Log(@"prefs: RESET ve mac dinh (ghi mac dinh qua trang, da xoa key, giu nguyen moc thoi gian)");
    [self reloadSpecifiers];
    // Hết key → trang khoá lại như lúc chưa kích hoạt (chạm để nhập lại key)
    if (!FG5LicenseHasActiveKey()) {
        [self installExpiredOverlay];
        self.popupShownThisAppear = YES;
    }
    UIAlertController *done = [UIAlertController
        alertControllerWithTitle:@"Đã reset"
                         message:@"Mọi cài đặt đã về mặc định và key đã bị xoá. Nhập lại key để dùng tiếp."
                  preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:done animated:YES completion:nil];
}

#pragma mark - Respring

- (void)respringTapped:(id)sender {
    NSArray<NSString *> *candidates = @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload"];
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            const char *argv[] = { [path fileSystemRepresentation], NULL };
            pid_t pid = 0;
            posix_spawn(&pid, [path fileSystemRepresentation], NULL, NULL,
                        (char *const *)argv, environ);
            return;
        }
    }
    FG5Log(@"respring: khong tim thay sbreload");
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Fake5G"
                         message:@"Không tìm thấy sbreload — hãy respring bằng công cụ jailbreak của anh."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
