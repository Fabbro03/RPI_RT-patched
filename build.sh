#!/bin/bash
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <arch>"
    echo "  arch = armhf | arm64"
    exit 1
fi

ARCH=$1

prepare_system(){
    echo "[*] Installing build dependencies..."
    apt-get -qq update
    apt-get -qq --yes upgrade
    apt-get -qq --yes install git fdisk zip bc bison flex libssl-dev make libc6-dev libncurses5-dev \
        crossbuild-essential-armhf crossbuild-essential-arm64 jq curl xz-utils
}

download_image(){
    case "$ARCH" in
        armhf) export RASPIOS=raspios_lite_armhf ;;
        arm64) export RASPIOS=raspios_lite_arm64 ;;
        *) echo "Unknown arch $ARCH"; exit 1 ;;
    esac

    export DATE=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/ | \
        sed -n "s:.*${RASPIOS}-\(.*\)/</a>.*:\1:p" | tail -1)
    export RASPIOS_IMAGE_NAME=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/ | \
        sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | head -n 1)

    echo "[*] Downloading ${RASPIOS_IMAGE_NAME}.xz"
    curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/${RASPIOS_IMAGE_NAME}.xz \
        --output ${RASPIOS}.xz
    xz -d -f ${RASPIOS}.xz
    mv "${RASPIOS_IMAGE_NAME%.xz}" ${RASPIOS}.img
}

download_kernel_src(){
    echo "[*] Downloading kernel source"
    rm -rf linux
    git clone --depth=1 --branch stable_20240529 https://github.com/raspberrypi/linux
    echo "[*] Downloading RT patch"
    curl -s https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/6.6/older/patch-6.6.31-rt31.patch.gz \
        --output linux/rt.patch.gz
    echo "[*] Applying RT patch"
    cd linux
    gzip -cd rt.patch.gz | patch -p1
    cd ..
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
    if [ "$ARCH" = "armhf" ]; then
        ./scripts/config --enable CONFIG_SMP
        ./scripts/config --disable CONFIG_BROKEN_ON_SMP
    fi
    ./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT"
}

mount_image(){
    IMG=${RASPIOS}.img

    export OUTPUT=$(sfdisk -lJ $IMG)
    export BOOT_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].start')
    export BOOT_SIZE=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].size')
    export EXT4_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[1].start')

    mkdir -p mnt/root mnt/boot
    mount -t ext4 -o loop,offset=$(($EXT4_START*512)) $IMG mnt/root
    mount -t vfat -o loop,offset=$(($BOOT_START*512)),sizelimit=$(($BOOT_SIZE*512)) $IMG mnt/boot
}

unmount_image(){
    umount mnt/boot
    umount mnt/root
}

build_armhf(){
    echo "[*] Building armhf kernels"
    export ARCH=arm
    export CROSS_COMPILE=arm-linux-gnueabihf-

    cd linux

    # kernel.img (Pi1/Zero)
    make bcmrpi_defconfig
    configure_kernel
    make -j$(nproc) zImage modules dtbs
    make INSTALL_MOD_PATH=../mnt/root modules_install
    cp arch/arm/boot/zImage ../mnt/boot/kernel.img
    cp arch/arm/boot/dts/broadcom/*.dtb ../mnt/boot/
    cp arch/arm/boot/dts/overlays/*.dtb* ../mnt/boot/overlays/
    cp arch/arm/boot/dts/overlays/README ../mnt/boot/overlays/

    # kernel7.img (Pi2/early Pi3)
    make bcm2709_defconfig
    configure_kernel
    make -j$(nproc) zImage modules dtbs
    make INSTALL_MOD_PATH=../mnt/root modules_install
    cp arch/arm/boot/zImage ../mnt/boot/kernel7.img

    # kernel7l.img (Pi3/4 in 32-bit mode)
    make bcm2711_defconfig
    configure_kernel
    make -j$(nproc) zImage modules dtbs
    make INSTALL_MOD_PATH=../mnt/root modules_install
    cp arch/arm/boot/zImage ../mnt/boot/kernel7l.img

    cd ..
}

build_arm64(){
    echo "[*] Building arm64 kernels"
    export ARCH=arm64
    export CROSS_COMPILE=aarch64-linux-gnu-

    cd linux

    # kernel8.img (Pi3/4/400/CM in 64-bit mode)
    make bcm2711_defconfig
    configure_kernel
    make -j$(nproc) Image modules dtbs
    make INSTALL_MOD_PATH=../mnt/root modules_install
    cp arch/arm64/boot/Image ../mnt/boot/kernel8.img
    cp arch/arm64/boot/dts/broadcom/*.dtb ../mnt/boot/
    cp arch/arm64/boot/dts/overlays/*.dtb* ../mnt/boot/overlays/
    cp arch/arm64/boot/dts/overlays/README ../mnt/boot/overlays/

    # kernel_2712.img (Pi5)
    make bcm2712_defconfig
    configure_kernel
    make -j$(nproc) Image modules dtbs
    make INSTALL_MOD_PATH=../mnt/root modules_install
    cp arch/arm64/boot/Image ../mnt/boot/kernel_2712.img

    cd ..
}

finalize_image(){
    unmount_image
    echo "[*] Compressing final ${ARCH} image"
    mkdir -p build
    xz -T0 -z ${RASPIOS}.img
    mv ${RASPIOS}.img.xz build/${RASPIOS}-fullrt-${ARCH}.img.xz
}

# ==============================
# Main
# ==============================
prepare_system
download_image
download_kernel_src
mount_image

if [ "$ARCH" = "armhf" ]; then
    build_armhf
elif [ "$ARCH" = "arm64" ]; then
    build_arm64
fi

finalize_image
echo "[*] Build complete for ${ARCH}"
ls -lh build