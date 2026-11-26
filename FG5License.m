// FG5License.m — Fake5G 1.1.11
// Gồm: tiện ích prefs + log dùng chung (FG5Shared) và hệ bản quyền (FG5License).
#import "FG5Shared.h"
#import "FG5License.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

#pragma mark - Log + prefs dùng chung

void FG5Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[Fake5G] %@", msg);
    static NSObject *logLock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ logLock = [[NSObject alloc] init]; });
    @synchronized (logLock) {
        static NSDateFormatter *fmt = nil;
        if (!fmt) {
            fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        }
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:[NSDate date]], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:FG5_LOG_PATH];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:FG5_LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
}

id FG5PrefValue(NSString *key) {
    CFTypeRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                              (__bridge CFStringRef)FG5_PREFS_DOMAIN);
    return CFBridgingRelease(v);
}

BOOL FG5PrefBool(NSString *key, BOOL fallback) {
    id v = FG5PrefValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return fallback;
}

NSString *FG5PrefString(NSString *key, NSString *fallback) {
    id v = FG5PrefValue(key);
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return fallback;
}

void FG5PrefSet(NSString *key, id value) {
    if (value) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFTypeRef)value,
                                 (__bridge CFStringRef)FG5_PREFS_DOMAIN);
    } else {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL,
                                 (__bridge CFStringRef)FG5_PREFS_DOMAIN);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)FG5_PREFS_DOMAIN);
}

NSString *FG5EffectiveLabel(void) {
    // Chọn "none" thì ẩn hẳn — thắng cả ô tự nhập (yêu cầu của anh Quoc, 1.1.11)
    if ([FG5PrefString(FG5_KEY_LABEL_PRESET, @"5G") isEqualToString:@"none"]) return @"";
    NSString *custom = [FG5PrefString(FG5_KEY_LABEL_CUSTOM, @"")
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (custom.length > 0) return custom;
    return FG5PrefString(FG5_KEY_LABEL_PRESET, @"5G");
}

NSString *FG5EffectiveCarrier(void) {
    if ([FG5PrefString(FG5_KEY_CARRIER_PRESET, @"Viettel") isEqualToString:@"none"]) return @"";
    NSString *custom = [FG5PrefString(FG5_KEY_CARRIER_CUSTOM, @"")
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (custom.length > 0) return custom;
    return FG5PrefString(FG5_KEY_CARRIER_PRESET, @"Viettel");
}

NSInteger FG5EffectiveBarsCount(void) {
    if ([FG5PrefString(FG5_KEY_BARS_COUNT, @"4") isEqualToString:@"none"]) return 0;
    NSInteger n = [FG5PrefString(FG5_KEY_BARS_COUNT, @"4") integerValue];
    if (n < 1) n = 1;
    if (n > 4) n = 4;
    return n;
}

#pragma mark - Kho 3 nơi cho mốc bản quyền (prefs + Keychain + file)

// Dấu vân của một key (SHA-256 rút gọn) — để mốc kích hoạt GẮN với đúng key:
// reset xoá key nhưng mốc + dấu vân còn nguyên ở 3 nơi, nhập lại CÙNG key thì
// hạn vẫn tính từ lần kích hoạt đầu tiên của key đó (yêu cầu của anh, 1.1.11).
static NSString *FG5KeyHash(NSString *key) {
    NSData *d = [[key uppercaseString] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:16];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

// Chuỗi trạng thái dạng "start|maxSeen|actStart|actKeyHash" (giây unix, 0 = chưa có)
static NSString *FG5StateFilePath(void) {
    return @"/var/mobile/Documents/.fg5state";
}

static void FG5ParseStateString(NSString *s, NSTimeInterval *start, NSTimeInterval *maxSeen, NSTimeInterval *act, NSString **actHash) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return;
    NSArray<NSString *> *parts = [s componentsSeparatedByString:@"|"];
    // start lấy mốc SỚM nhất trong các nơi (chống xoá 1 nơi để reset dùng thử)
    if (parts.count >= 1 && [parts[0] doubleValue] > 0) {
        *start = (*start > 0) ? MIN(*start, [parts[0] doubleValue]) : [parts[0] doubleValue];
    }
    if (parts.count >= 2 && [parts[1] doubleValue] > 0) *maxSeen = MAX(*maxSeen, [parts[1] doubleValue]);
    // act và actHash là MỘT CẶP: nơi nào có act sớm nhất thì lấy cả cặp của nơi đó
    if (parts.count >= 3 && [parts[2] doubleValue] > 0) {
        if (*act <= 0 || [parts[2] doubleValue] < *act) {
            *act = [parts[2] doubleValue];
            if (actHash) *actHash = (parts.count >= 4) ? parts[3] : @"";
        }
    }
}

static NSString *FG5KeychainStateString(void) {
    NSDictionary *q = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.anhdang.fake5g.state",
        (__bridge id)kSecAttrAccount: @"state",
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st != errSecSuccess || !out) return nil;
    NSData *d = CFBridgingRelease(out);
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

static void FG5KeychainSetStateString(NSString *s) {
    NSDictionary *q = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.anhdang.fake5g.state",
        (__bridge id)kSecAttrAccount: @"state"
    };
    SecItemDelete((__bridge CFDictionaryRef)q);
    NSMutableDictionary *add = [q mutableCopy];
    add[(__bridge id)kSecValueData] = [s dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

static NSString *FG5FileStateString(void) {
    NSData *d = [NSData dataWithContentsOfFile:FG5StateFilePath()];
    if (!d || d.length == 0) return nil;
    NSMutableData *plain = [NSMutableData dataWithLength:d.length];
    const unsigned char *in = d.bytes;
    unsigned char *out = plain.mutableBytes;
    const char *mask = "FG5K";
    for (NSUInteger i = 0; i < d.length; i++) out[i] = in[i] ^ (unsigned char)mask[i % 4] ^ 0x5A;
    return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
}

static void FG5FileSetStateString(NSString *s) {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *obf = [NSMutableData dataWithLength:d.length];
    const unsigned char *in = d.bytes;
    unsigned char *out = obf.mutableBytes;
    const char *mask = "FG5K";
    for (NSUInteger i = 0; i < d.length; i++) out[i] = in[i] ^ (unsigned char)mask[i % 4] ^ 0x5A;
    [obf writeToFile:FG5StateFilePath() atomically:YES];
}

// Nạp + hợp nhất 3 nơi; persist=YES khi có thay đổi cần ghi lại khắp nơi.
static void FG5LoadState(NSTimeInterval *startOut, NSTimeInterval *maxSeenOut, NSTimeInterval *actOut, NSString **actHashOut, BOOL *dirtyOut) {
    NSTimeInterval start = 0, maxSeen = 0, act = 0;
    NSString *actHash = @"";
    // Nơi 1: prefs
    NSNumber *ps = FG5PrefValue(FG5_KEY_TRIAL_START);
    NSNumber *pm = FG5PrefValue(FG5_KEY_MAX_SEEN);
    NSNumber *pa = FG5PrefValue(FG5_KEY_ACT_START);
    NSString *ph = FG5PrefValue(FG5_KEY_ACT_KEYHASH);
    if ([ps isKindOfClass:[NSNumber class]] && [ps doubleValue] > 0) start = [ps doubleValue];
    if ([pm isKindOfClass:[NSNumber class]] && [pm doubleValue] > 0) maxSeen = [pm doubleValue];
    if ([pa isKindOfClass:[NSNumber class]] && [pa doubleValue] > 0) act = [pa doubleValue];
    if ([ph isKindOfClass:[NSString class]]) actHash = ph;
    // Nơi 2 + 3
    FG5ParseStateString(FG5KeychainStateString(), &start, &maxSeen, &act, &actHash);
    FG5ParseStateString(FG5FileStateString(), &start, &maxSeen, &act, &actHash);

    NSTimeInterval nowReal = [[NSDate date] timeIntervalSince1970];
    BOOL dirty = NO;
    if (start <= 0) { start = nowReal; dirty = YES; }
    NSTimeInterval effNow = MAX(nowReal, maxSeen);
    if (effNow > maxSeen + 60) { maxSeen = effNow; dirty = YES; }
    if (dirtyOut) *dirtyOut = dirty;
    if (startOut) *startOut = start;
    if (maxSeenOut) *maxSeenOut = effNow; // trả về "hiện tại hiệu dụng" đã chống vặn giờ
    if (actOut) *actOut = act;
    if (actHashOut) *actHashOut = actHash;
}

static void FG5PersistState(NSTimeInterval start, NSTimeInterval maxSeen, NSTimeInterval act, NSString *actHash) {
    FG5PrefSet(FG5_KEY_TRIAL_START, @((long long)start));
    FG5PrefSet(FG5_KEY_MAX_SEEN, @((long long)maxSeen));
    FG5PrefSet(FG5_KEY_ACT_START, @((long long)act));
    FG5PrefSet(FG5_KEY_ACT_KEYHASH, actHash ?: @"");
    NSString *s = [NSString stringWithFormat:@"%lld|%lld|%lld|%@",
                   (long long)start, (long long)maxSeen, (long long)act, actHash ?: @""];
    FG5KeychainSetStateString(s);
    FG5FileSetStateString(s);
}

#pragma mark - Kiểm key ECDSA P-256

// Khoá công khai (điểm chưa nén 65 byte, base64) — cặp với private_key.pem
// giữ riêng ở ~/workspace/Fake5G-license/, TUYỆT ĐỐI không đưa lên GitHub.
static NSString * const FG5PublicKeyB64 =
    @"BMMuFEH6bOFZ47iX9z4d3h1A0jDss2mMYf0uJPWRxhNDlvycMgII6dptzppefcTqGXj/f8RzHf9isjPlfoRxzbs=";

static NSData *FG5Base32Decode(NSString *s) {
    static const char *alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    NSMutableData *out = [NSMutableData data];
    int buffer = 0, bitsLeft = 0;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '=') break;
        const char *p = strchr(alpha, (char)c);
        if (!p) return nil;
        buffer = (buffer << 5) | (int)(p - alpha);
        bitsLeft += 5;
        if (bitsLeft >= 8) {
            bitsLeft -= 8;
            unsigned char byte = (unsigned char)((buffer >> bitsLeft) & 0xFF);
            [out appendBytes:&byte length:1];
        }
    }
    return out;
}

// Giải mã + kiểm chữ ký. Đúng: trả YES, kind/name lấy từ payload đã ký.
static BOOL FG5VerifyKey(NSString *key, NSInteger *kindOut, NSString **nameOut) {
    if (![key isKindOfClass:[NSString class]]) return NO;
    NSString *clean = [[key uppercaseString] stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    clean = [clean stringByReplacingOccurrencesOfString:@"-" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (![clean hasPrefix:@"FG51"]) return NO;
    NSData *blob = FG5Base32Decode([clean substringFromIndex:4]);
    if (!blob || blob.length < 8 + 40) return NO; // payload tối thiểu + chữ ký DER ~70 byte
    const unsigned char *b = blob.bytes;
    if (memcmp(b, "FG5K", 4) != 0 || b[4] != 1) return NO;
    NSInteger kind = b[5];
    if (kind != 1 && kind != 3) return NO;
    NSUInteger nameLen = b[6];
    NSUInteger payloadLen = 7 + nameLen;
    if (blob.length <= payloadLen) return NO;
    NSString *name = [[NSString alloc] initWithBytes:b + 7 length:nameLen encoding:NSUTF8StringEncoding];
    if (!name) return NO;
    NSData *payload = [blob subdataWithRange:NSMakeRange(0, payloadLen)];
    NSData *sigDER = [blob subdataWithRange:NSMakeRange(payloadLen, blob.length - payloadLen)];

    NSData *pubRaw = [[NSData alloc] initWithBase64EncodedString:FG5PublicKeyB64 options:0];
    if (!pubRaw || pubRaw.length != 65) return NO;
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };
    CFErrorRef err = NULL;
    SecKeyRef pub = SecKeyCreateWithData((__bridge CFDataRef)pubRaw,
                                           (__bridge CFDictionaryRef)attrs, &err);
    if (!pub) { if (err) CFRelease(err); return NO; }
    // Chữ ký trong key là DER — đúng định dạng X962 đòi (bài học ZUS 1.2.0/1.2.1)
    BOOL ok = SecKeyVerifySignature(pub, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                    (__bridge CFDataRef)payload, (__bridge CFDataRef)sigDER, &err);
    if (err) CFRelease(err);
    CFRelease(pub);
    if (!ok) return NO;
    if (kindOut) *kindOut = kind;
    if (nameOut) *nameOut = name;
    return YES;
}

#pragma mark - API bản quyền

FG5LicState FG5LicenseCurrentState(NSInteger *daysLeftOut, NSString **nameOut) {
    NSTimeInterval start = 0, effNow = 0, act = 0;
    NSString *actHash = @"";
    BOOL dirty = NO;
    FG5LoadState(&start, &effNow, &act, &actHash, &dirty);
    if (dirty) FG5PersistState(start, effNow, act, actHash);

    NSString *savedKey = FG5PrefString(FG5_KEY_LICENSE_KEY, @"");
    NSInteger kind = 0;
    NSString *name = nil;
    if (savedKey.length > 0 && FG5VerifyKey(savedKey, &kind, &name)) {
        if (nameOut) *nameOut = name;
        if (kind == 1) {
            if (daysLeftOut) *daysLeftOut = -1;
            return FG5LicStatePermanent;
        }
        // kind 3: 3 ngày từ lúc kích hoạt (act đã hợp nhất 3 nơi)
        if (act <= 0) {
            act = effNow;
            actHash = FG5KeyHash(savedKey);
            FG5PersistState(start, effNow, act, actHash);
        }
        NSTimeInterval remain = (act + 3 * 86400) - effNow;
        if (remain > 0) {
            if (daysLeftOut) *daysLeftOut = (NSInteger)ceil(remain / 86400.0);
            return FG5LicStateTimed;
        }
        if (daysLeftOut) *daysLeftOut = 0;
        return FG5LicStateTimedExpired;
    }

    NSTimeInterval remain = (start + 3 * 86400) - effNow;
    if (remain > 0) {
        if (daysLeftOut) *daysLeftOut = (NSInteger)ceil(remain / 86400.0);
        return FG5LicStateTrial;
    }
    if (daysLeftOut) *daysLeftOut = 0;
    return FG5LicStateTrialExpired;
}

BOOL FG5LicenseActive(void) {
    FG5LicState st = FG5LicenseCurrentState(NULL, NULL);
    return st == FG5LicStateTrial || st == FG5LicStatePermanent || st == FG5LicStateTimed;
}

BOOL FG5LicenseHasActiveKey(void) {
    FG5LicState st = FG5LicenseCurrentState(NULL, NULL);
    return st == FG5LicStatePermanent || st == FG5LicStateTimed;
}

NSString *FG5LicenseStatusText(void) {
    NSInteger days = 0;
    NSString *name = nil;
    FG5LicState st = FG5LicenseCurrentState(&days, &name);
    switch (st) {
        case FG5LicStateTrial:
            return [NSString stringWithFormat:@"Đang dùng thử — còn %ld ngày", (long)days];
        case FG5LicStateTrialExpired:
            return @"Đã hết hạn dùng thử — nhập key để kích hoạt";
        case FG5LicStatePermanent:
            return [NSString stringWithFormat:@"Đã kích hoạt — %@ (vĩnh viễn)", name ?: @""];
        case FG5LicStateTimed:
            return [NSString stringWithFormat:@"Đã kích hoạt — %@ (còn %ld ngày)", name ?: @"", (long)days];
        case FG5LicStateTimedExpired:
            return @"Key đã hết hạn 3 ngày — nhập key mới";
    }
    return @"";
}

BOOL FG5LicenseTryActivateKey(NSString *key, NSString **nameOut, NSString **errorOut) {
    NSInteger kind = 0;
    NSString *name = nil;
    NSString *clean = [key stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!FG5VerifyKey(clean, &kind, &name)) {
        if (errorOut) *errorOut = @"Key chưa đúng — kiểm tra lại key đã dán.";
        FG5Log(@"bản quyền: dán key SAI (dài %lu ký tự)", (unsigned long)clean.length);
        return NO;
    }
    NSTimeInterval start = 0, effNow = 0, act = 0;
    NSString *actHash = @"";
    BOOL dirty = NO;
    FG5LoadState(&start, &effNow, &act, &actHash, &dirty);
    NSString *oldKey = FG5PrefString(FG5_KEY_LICENSE_KEY, @"");
    if (kind == 3) {
        NSString *hash = FG5KeyHash(clean);
        if (act > 0 && [actHash isEqualToString:hash]) {
            // Chính key này đã từng kích hoạt: GIỮ mốc đầu tiên — reset xoá
            // key rồi nhập lại cũng không kéo dài được hạn (yêu cầu của anh).
        } else if (act > 0 && actHash.length == 0 && [oldKey isEqualToString:clean]) {
            actHash = hash; // mốc cũ của bản trước 1.1.11, gắn cho chính key đang lưu
        } else {
            act = effNow;   // key phụ mới: 3 ngày tính từ bây giờ
            actHash = hash;
        }
        if (act <= 0) { act = effNow; actHash = hash; }
    }
    FG5PrefSet(FG5_KEY_LICENSE_KEY, clean);
    FG5PersistState(start, effNow, act, actHash);
    if (nameOut) *nameOut = name;
    FG5Log(@"bản quyền: ĐÃ KÍCH HOẠT kind=%ld tên=%@", (long)kind, name);
    return YES;
}
