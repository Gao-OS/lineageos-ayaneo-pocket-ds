#
# gsmlg-apps integration
#
# Prebuilt APKs installed to /product partition
#

ifneq ($(wildcard packages/gsmlg-apps/apps.mk),)
$(call inherit-product, packages/gsmlg-apps/apps.mk)
else
$(warning gsmlg-apps not found. Run: scripts/fetch-gsmlg-apps.sh)
endif
