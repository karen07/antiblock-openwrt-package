#!/bin/sh
PACKET_SRC_FOLDER=package
PACKET=antiblock

PACKET_SRC_NAME=$(ls $PACKET_SRC_FOLDER | grep -i $PACKET | grep -i package)
PACKET_SRC_PATH=$PACKET_SRC_FOLDER/$PACKET_SRC_NAME

make $PACKET_SRC_PATH/clean

if make $PACKET_SRC_PATH/compile ; then

    PACKET_PATH=$(find bin | grep antiblock)
	PACKET_NAME=$(basename $PACKET_PATH)
	
	if [ -f "$PACKET_PATH" ]; then
		scp -O $PACKET_PATH router:~/
		ssh router opkg remove $PACKET
		ssh router opkg install $PACKET_NAME
		ssh router rm $PACKET_NAME
		echo "Command succeeded"
	fi
else
    make -j1 V=s $PACKET_SRC_PATH/compile
    echo "Command failed"
fi
