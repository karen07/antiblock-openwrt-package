include $(TOPDIR)/rules.mk

PKG_NAME:=antiblock
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

ifeq ("$(wildcard ../antiblock)", "")
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/karen07/antiblock
PKG_SOURCE_VERSION:=f97a9790ae2310e0cb0fa97786974f0cecfda789
PKG_MIRROR_HASH:=51b37291f603a7f84e736ba0683ceccf79a8cd231788531824b1341b16cbb22a
endif

PKG_MAINTAINER:=Khachatryan Karen <karen0734@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/antiblock
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=+libcurl
  TITLE:=AntiBlock
  URL:=https://github.com/karen07/antiblock
endef

define Package/antiblock/description
  AntiBlock program proxies DNS requests.
  The IP addresses of the specified domains are added to
  the routing table for routing through the specified interface.
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
