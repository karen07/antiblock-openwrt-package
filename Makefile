include $(TOPDIR)/rules.mk

PKG_NAME:=antiblock
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/karen07/antiblock
PKG_SOURCE_VERSION:=2b8324bf624c27077c089327136ce34d1106c3d0

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/antiblock
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=libcurl
	TITLE:=DNS proxy add blocked domains ip address to route table.
	URL:=https://github.com/karen07/antiblock
endef

define Package/antiblock/description
	DNS proxy add blocked domains ip address to route table.
endef

define Package/antiblock/install
	$(CP) ./files/* $(1)/
	chmod +x $(1)/etc/init.d/antiblock

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/antiblock $(1)/usr/bin/
endef

$(eval $(call BuildPackage,antiblock))
