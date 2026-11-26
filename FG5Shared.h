// FG5Shared.h — Fake5G 1.1.5 (com.anhdang.fake5g)
// Khai báo dùng chung giữa tweak (SpringBoard) và prefs bundle (Cài đặt).
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

NS_ASSUME_NONNULL_BEGIN

#define FG5_PREFS_DOMAIN @"com.anhdang.fake5g"
#define FG5_PREFS_CHANGED_NOTIFICATION CFSTR("com.anhdang.fake5g/prefsChanged")
#define FG5_LOG_PATH @"/var/mobile/Documents/Fake5G.log"

// Khoá prefs (khớp 1-1 với Root.plist — rà chéo trước khi giao)
#define FG5_KEY_ENABLED       @"enabled"
#define FG5_KEY_LABEL_PRESET  @"labelPreset"
#define FG5_KEY_LABEL_CUSTOM  @"labelCustom"
#define FG5_KEY_ONLY_ON_WIFI  @"onlyOnWifi"
#define FG5_KEY_FAKE_BARS     @"fakeBars"
#define FG5_KEY_BARS_COUNT    @"barsCount"
#define FG5_KEY_FAKE_CARRIER  @"fakeCarrier"
#define FG5_KEY_CARRIER_PRESET @"carrierPreset"
#define FG5_KEY_CARRIER_CUSTOM @"carrierCustom"
#define FG5_KEY_HIDE_NOSIM    @"hideNoSim"
#define FG5_KEY_LAYOUT_PROFILE @"layoutProfile"
#define FG5_KEY_SHOW_IN_SWITCHER @"showInSwitcher"
// Khoá nội bộ của hệ bản quyền
#define FG5_KEY_LICENSE_KEY   @"licenseKey"
#define FG5_KEY_TRIAL_START   @"trialStart"
#define FG5_KEY_MAX_SEEN      @"maxSeen"
#define FG5_KEY_ACT_START     @"actStart"

void FG5Log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

id _Nullable FG5PrefValue(NSString *key);
BOOL FG5PrefBool(NSString *key, BOOL fallback);
NSString *FG5PrefString(NSString *key, NSString *fallback);
void FG5PrefSet(NSString *key, id _Nullable value);

// Nhãn hiệu lực: chữ tự nhập thắng chữ chọn sẵn
NSString *FG5EffectiveLabel(void);
// Tên nhà mạng hiệu lực: chữ tự nhập thắng tên chọn sẵn
NSString *FG5EffectiveCarrier(void);
NSInteger FG5EffectiveBarsCount(void);

NS_ASSUME_NONNULL_END
