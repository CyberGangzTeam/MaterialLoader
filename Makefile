TARGET := iphone:clang:latest:14.0
ARCHS  := arm64
FOR_RELEASE := 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = libhynisloader

HL_NAME    := $(shell awk -F': *' '/^Name:/    {sub(/\r$$/,"",$$2); print $$2}' control)
HL_VERSION := $(shell awk -F': *' '/^Version:/ {sub(/\r$$/,"",$$2); print $$2}' control)
HL_AUTHOR  := $(shell awk -F': *' '/^Author:/  {sub(/\r$$/,"",$$2); print $$2}' control)

libhynisloader_FILES      = Tweak.x fishhook.c ZipHandler.m HyniSign/Tweak.x HyniSign/access_group.c
libhynisloader_FRAMEWORKS = Foundation UIKit
libhynisloader_CFLAGS     = -fobjc-arc \
    -DHL_NAME='"$(HL_NAME)"' \
    -DHL_VERSION='"$(HL_VERSION)"' \
    -DHL_AUTHOR='"$(HL_AUTHOR)"'

include $(THEOS_MAKE_PATH)/tweak.mk
