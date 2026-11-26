// FG5RootListController.h — Fake5G 1.1.5
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface FG5RootListController : PSListController <UITextFieldDelegate>
@property (nonatomic, weak) UIAlertController *activeAlert;
@property (nonatomic, strong) NSTimer *popupTimer;
@property (nonatomic, assign) NSInteger popupSecondsLeft;
@property (nonatomic, assign) BOOL popupEditing;
@property (nonatomic, assign) BOOL popupShownThisAppear;
- (void)showActivatePopup;
- (void)showActivatePopupWithMessage:(NSString *)message;
- (void)activateTapped:(id)sender;
- (void)respringTapped:(id)sender;
- (void)popupTimerFired;
- (void)stopPopupTimer;
- (void)installExpiredOverlay;
- (void)removeExpiredOverlay;
- (void)expiredOverlayTapped;
@end
