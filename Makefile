TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MaterialLoader

MaterialLoader_FILES = Tweak.x fishhook.c
MaterialLoader_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
