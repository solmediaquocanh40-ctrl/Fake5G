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
