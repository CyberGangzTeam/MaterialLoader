TARGET := iphone:clang:latest:14.0
#THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MaterialLoader

MaterialLoader_FILES = Tweak.x
MaterialLoader_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
