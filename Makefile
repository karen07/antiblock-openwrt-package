include $(TOPDIR)/rules.mk

PKG_NAME:=antiblock
PKG_VERSION:=2.1.1
PKG_RELEASE:=1

ifeq ("$(wildcard ../antiblock)", "")
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/karen07/antiblock
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip
endif

PKG_MAINTAINER:=Khachatryan Karen <karen0734@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/antiblock
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=+libcurl +libpcap
  TITLE:=AntiBlock
  URL:=https://github.com/karen07/antiblock
endef

define Package/antiblock/description
  AntiBlock sniffer DNS requests. The IP addresses of the
  specified domains are added to the routing table for
  routing through the specified interfaces.
endef

define Package/antiblock/conffiles
/etc/config/antiblock
endef

ifneq ("$(wildcard ../antiblock)", "")
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ../antiblock/* $(PKG_BUILD_DIR)/
endef
endif

define Package/antiblock/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/antiblock $(1)/usr/bin/antiblock

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/antiblock $(1)/etc/init.d/antiblock

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/antiblock $(1)/etc/config/antiblock
endef

$(eval $(call BuildPackage,antiblock))
