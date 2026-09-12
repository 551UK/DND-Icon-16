ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SmartFinalCompatibility
SmartFinalCompatibility_FILES = Tweak.xm
SmartFinalCompatibility_FRAMEWORKS = UIKit Foundation
SmartFinalCompatibility_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter

include $(THEOS_MAKE_PATH)/tweak.mk
