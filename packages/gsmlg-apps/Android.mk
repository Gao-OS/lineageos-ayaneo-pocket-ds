LOCAL_PATH := $(call my-dir)

#
# gsmlg-apps — prebuilt APKs
#
# To add a new app:
#   1. Place the APK in prebuilt/<AppName>.apk
#   2. Add an include block below (copy the KernelSUManager template)
#   3. Add the package name to apps.mk PRODUCT_PACKAGES
#

# --- KernelSU Manager ---
include $(CLEAR_VARS)
LOCAL_MODULE := KernelSUManager
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_BUILT_MODULE_STEM := package.apk
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := prebuilt/KernelSUManager.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT_APPS)
LOCAL_PRODUCT_MODULE := true
LOCAL_DEX_PREOPT := false
include $(BUILD_PREBUILT)
