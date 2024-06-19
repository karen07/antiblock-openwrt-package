#!/bin/sh

SDK="https://mirror-03.infra.openwrt.org/releases/23.05.3/targets/mediatek/filogic/openwrt-sdk-23.05.3-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
ARCHIVE=$(basename $SDK)

if [ ! -f "$ARCHIVE" ]; then
	wget $SDK
fi

FOLDER=$(echo $ARCHIVE | rev | cut -c 8- | rev)

if [ ! -f "$FOLDER" ]; then
	tar -xf $ARCHIVE
fi

cd $FOLDER/

./scripts/feeds update -a
./scripts/feeds install -a

if [ ! -f "package/antiblock" ]; then
	git clone --recursive git@github.com:karen07/antiblock.git package/antiblock
fi

if [ ! -f "package/antiblock-openwrt-package" ]; then
	git clone git@github.com:karen07/antiblock-openwrt-package.git package/antiblock-openwrt-package
	cp package/antiblock-openwrt-package/auto.sh auto.sh
fi

./auto.sh
