TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Fake5G
Fake5G_FILES := Tweak.x FG5License.m
Fake5G_FRAMEWORKS := UIKit Security
Fake5G_CFLAGS := -fobjc-arc

SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# 1.1.13: tự loại 2 file icon tên chung ra khỏi gói ở khâu đóng gói.
# icon.png/icon@2x.png là file sót từ bản <=1.1.9 trong thư mục dùng
# chung PreferenceLoader/Preferences — nếu còn sót trên repo thì bản
# build bị dpkg từ chối vì va đường dẫn với package CallForward.
# Xoá ngay trong staging: gói xuất ra không bao giờ chứa chúng nữa,
# bất kể cây nguồn trên repo còn sót hay không.
after-stage::
	@rm -f "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/icon.png" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/icon@2x.png"
	@echo "Fake5G: da loai icon.png/icon@2x.png ten chung khoi goi (neu co)"
