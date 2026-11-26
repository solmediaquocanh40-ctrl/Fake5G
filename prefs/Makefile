TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := Fake5GPrefs
Fake5GPrefs_FILES := FG5RootListController.m ../FG5License.m
Fake5GPrefs_FRAMEWORKS := UIKit
Fake5GPrefs_INSTALL_PATH := /Library/PreferenceBundles
Fake5GPrefs_CFLAGS := -fobjc-arc -I..
Fake5GPrefs_LDFLAGS := -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
