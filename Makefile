TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

export DEBUG = 0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ActionGesture

ActionGesture_FILES = ActionGesture.xm ActionGestureSettings.xm ActionGestureHelper.m
ActionGesture_CFLAGS += -fobjc-arc -Wno-deprecated-declarations -fno-modules
ActionGesture_CCFLAGS += -fno-modules -fno-cxx-modules
ActionGesture_FRAMEWORKS += Foundation UIKit CoreMotion

ifeq ($(SCHEME),roothide)
    ActionGesture_LIBRARIES += roothide
endif

THEOS_DEVICE_IP = 192.168.31.108
THEOS_DEVICE_PORT = 22

include $(THEOS_MAKE_PATH)/tweak.mk
