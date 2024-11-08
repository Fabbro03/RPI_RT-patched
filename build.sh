#!/bin/bash
export TARGET=$1
case "$TARGET" in
    "Pi3" | "PiCM3" | "Pi3+" | "PiCM3+" | "PiZero2W" | "Pi4" | "Pi400" | "PiCM4" | "PiCM4S")
        export KERNEL=kernel8
        export ARCH=arm64
        export CROSS_COMPILE=aarch64-linux-gnu-
        export DEFCONFIG=bcm2711_defconfig
        ;;
    "Pi5")
        export KERNEL=kernel_2712
        export ARCH=arm64
        export CROSS_COMPILE=aarch64-linux-gnu-
        export DEFCONFIG=bcm2712_defconfig
        ;;
    "Pi1" | "PiCM1" | "PiZero" | "PiZeroW")
        export KERNEL=kernel
        export ARCH=arm
        export CROSS_COMPILE=arm-linux-gnueabihf-
        export DEFCONFIG=bcmrpi_defconfig
        ;;
    "Pi2" | "Pi3-32" | "PiCM3-32" | "Pi3+-32" | "PiCM3+-32" | "PiZero2W-32")
        export KERNEL=kernel7
        export ARCH=arm
        export CROSS_COMPILE=arm-linux-gnueabihf-
        export DEFCONFIG=bcm2709_defconfig
        ;;
    "Pi4-32" | "Pi400-32" | "PiCM4-32" | "PiCM4S-32")
        export KERNEL=kernel7l
        export ARCH=arm
        export CROSS_COMPILE=arm-linux-gnueabihf-
        export DEFCONFIG=bcm2711_defconfig
        ;;
    *)
        echo "Invalid platform. Supported list: Pi1, PiCM1, PiZero, PiZeroW, Pi2, Pi3, PiCM3, Pi3+, PiCM3+, PiZero2W, Pi4, Pi400, PiCM4, PiCM4S, Pi5"
esac

prepare_system(){
    echo "Installing/updating required packages"
	apt-get -qq update
    if [ $ARCH = "arm64" ]; then
        apt-get -qq --yes install git fdisk zip bc bison flex libssl-dev make libc6-dev libncurses5-dev crossbuild-essential-arm64
    else
        apt-get -qq --yes install git fdisk zip bc bison flex libssl-dev make libc6-dev libncurses5-dev crossbuild-essential-armhf
    fi
	echo "Packages installation/update success"
}

download_image(){
    if [ $ARCH = "arm64" ]; then
        export RASPIOS=raspios_lite_arm64
    else
        export RASPIOS=raspios_lite_armhf
    fi
	export DATE=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/ | sed -n "s:.*${RASPIOS}-\(.*\)/</a>.*:\1:p" | tail -1)
    export RASPIOS_IMAGE_NAME=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/ | sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | head -n 1)
    echo "Downloading ${RASPIOS_IMAGE_NAME}.xz"
    curl https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/${RASPIOS_IMAGE_NAME}.xz --output ${RASPIOS}.xz
    xz -d ${RASPIOS}.xz
	echo "${RASPIOS_IMAGE_NAME}.xz downloaded and extracted"
}

download_kernel_src(){
	echo "Downloading kernel source code"
	git clone --depth=1 --branch stable_20240529 https://github.com/raspberrypi/linux
	echo "Kernel downloaded"
	echo "RT patch downloading"
	curl https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/6.6/older/patch-6.6.31-rt31.patch.gz --output linux/rt.patch.gz
	echo "RT patch downloaded"
	echo "Applying patch"
	cd linux/
    gzip -cd rt.patch.gz | patch -p1
	echo "Patch applied"
	cd ..
}

build(){
	cd linux
    echo "Configuring kernel"
	make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE $DEFCONFIG
    configure_kernel
    echo "Building kernel: $KERNEL"
    if [ "$ARCH" = "arm64" ]; then
	    make -j$((`nproc`+1)) ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE Image modules dtbs
    else
        make -j$((`nproc`+1)) ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE zImage modules dtbs
    fi
}

install(){
    echo "Installing $KERNEL"
    export OUTPUT=$(sfdisk -lJ ../$RASPIOS)
    export BOOT_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].start')
    export BOOT_SIZE=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].size')
    export EXT4_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[1].start')
    mkdir -p mnt
    mkdir -p mnt/root
    mkdir -p mnt/boot
    mount -t ext4 -o loop,offset=$(($EXT4_START*512)) ../$RASPIOS mnt/root
    mount -t vfat -o loop,offset=$(($BOOT_START*512)),sizelimit=$(($BOOT_SIZE*512)) ../$RASPIOS mnt/boot
    env PATH=$PATH make -j$((`nproc`*1.5)) ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=mnt/root modules_install
    cp mnt/boot/$KERNEL.img mnt/boot/$KERNEL-backup.img
    if [ "$ARCH" = "arm64" ]; then
        cp arch/$ARCH/boot/Image mnt/boot/$KERNEL.img
    else
        cp arch/$ARCH/boot/zImage mnt/boot/$KERNEL.img
    fi
    cp arch/$ARCH/boot/dts/broadcom/*.dtb mnt/boot/
    cp arch/$ARCH/boot/dts/overlays/*.dtb* mnt/boot/overlays/
    cp arch/$ARCH/boot/dts/overlays/README mnt/boot/overlays/
    umount mnt/boot
    umount mnt/root
    cd ..
}

export_zip(){
    echo "Exporting image"
    mkdir build
    zip build/$RASPIOS-$TARGET.zip $RASPIOS
}

configure_kernel(){
    ./scripts/config --disable CONFIG_VIRTUALIZATION
	./scripts/config --enable CONFIG_PREEMPT_RT
	./scripts/config --disable CONFIG_RCU_EXPERT
	./scripts/config --enable CONFIG_RCU_BOOST
	./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500
	./scripts/config --enable CONFIG_PREEMPT_RT_FULL
	./scripts/config --enable CONFIG_HIGH_RES_TIMERS
	./scripts/config --set-val CONFIG_HZ 1000
	./scripts/config --enable CONFIG_IRQ_FORCED_THREADING
    if [ "$ARCH" = "arm" ]; then
        ./scripts/config --enable CONFIG_SMP
        ./scripts/config --disable CONFIG_BROKEN_ON_SMP
    fi
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT"
}

prepare_system
download_image
download_kernel_src
build
install
export_zip