SHELL := /bin/bash

Pi3 Pi3+ Pi4 Pi400 PiZero2 PiCM3 PiCM3+ PiCM4 PiCM4S: prepare download_image64 download_kernel_src bcm2711-64_build install_kernel64

Pi5: prepare download_image64 download_kernel_src bcm2712-64_build install_kernel64

Pi2 Pi3-32 Pi3+-32 PiZero2-32 PiCM3-32 PiCM3+-32: prepare download_image32 download_kernel_src bcm2709-32_build install_kernel32

Pi4-32 Pi400-32 PiCM4-32 PiCM4S-32: prepare download_image32 download_kernel_src bcm2711-32_build install_kernel32

Pi1 PiCM1 PiZero: prepare download_image32 download_kernel_src bcmrpi-32_build install_kernel32

prepare:
	echo "Installing/updating required packages" && \
	apt-get -qq update && \
	apt-get -qq --yes install bc bison flex libssl-dev make libc6-dev libncurses5-dev crossbuild-essential-arm64 crossbuild-essential-armhf && \
	echo "Installation/update success"	

download_image64:
	export RASPIOS=raspios_lite_arm64 && \
	export DATE=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/ | sed -n "s:.*${RASPIOS}-\(.*\)/</a>.*:\1:p" | tail -1) && \
    export RASPIOS_IMAGE_NAME=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/ | sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | head -n 1) && \
    echo "Downloading ${RASPIOS_IMAGE_NAME}.xz" && \
    curl https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/${RASPIOS_IMAGE_NAME}.xz --output ${RASPIOS}.xz && \
    xz -d ${RASPIOS}.xz && \
	echo "${RASPIOS_IMAGE_NAME}.xz downloaded and extracted"

download_image32:
	export RASPIOS=raspios_lite_armhf
	export DATE=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/ | sed -n "s:.*${RASPIOS}-\(.*\)/</a>.*:\1:p" | tail -1) && \
    export RASPIOS_IMAGE_NAME=$(curl -s https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/ | sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | head -n 1) && \
    echo "Downloading ${RASPIOS_IMAGE_NAME}.xz" && \
    curl https://downloads.raspberrypi.org/${RASPIOS}/images/${RASPIOS}-${DATE}/${RASPIOS_IMAGE_NAME}.xz --output ${RASPIOS}.xz && \
    xz -d ${RASPIOS}.xz && \
	echo "${RASPIOS_IMAGE_NAME}.xz downloaded and extracted"

download_kernel_src:
	export RPI_KERNEL_VERSION=6.6 && \
	export RPI_KERNEL_BRANCH=stable_20240529 && \
	export LINUX_KERNEL_RT_PATCH=patch-6.6.31-rt31 && \
	echo "Downloading kernel source code" && \
	git clone --depth=1 --branch ${RPI_KERNEL_BRANCH} https://github.com/raspberrypi/linux && \
	echo "Kernel downloaded" && \
	echo "RT patch downloading" && \
	curl https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/${RPI_KERNEL_VERSION}/older/${LINUX_KERNEL_RT_PATCH}.patch.gz --output linux/rt.patch.gz && \
	echo "RT patch downloaded" && \
	echo "Applying patch" && \
	cd linux/ && \
    gzip -cd rt.patch.gz | patch -p1 --verbose && \
	echo "Patch applied" && \
	cd ..

bcm2711-64_build:
	cd linux && \
	export KERNEL=kernel8 && \
	make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig && \
	./scripts/config --disable CONFIG_VIRTUALIZATION && \
	./scripts/config --enable CONFIG_PREEMPT_RT && \
	./scripts/config --disable CONFIG_RCU_EXPERT && \
	./scripts/config --enable CONFIG_RCU_BOOST && \
	./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500 && \
	./scripts/config --enable CONFIG_PREEMPT_RT_FULL && \
	./scripts/config --enable CONFIG_HIGH_RES_TIMERS && \
	./scripts/config --set-val CONFIG_HZ 1000 && \
	./scripts/config --enable CONFIG_IRQ_FORCED_THREADING && \
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT" && \
	make -j$((`nproc`+1)) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules dtbs && \
	cd ..

bcm2712-64_build:
	cd linux && \
	export KERNEL=kernel_2712 && \
	make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig && \
	./scripts/config --disable CONFIG_VIRTUALIZATION && \
	./scripts/config --enable CONFIG_PREEMPT_RT && \
	./scripts/config --disable CONFIG_RCU_EXPERT && \
	./scripts/config --enable CONFIG_RCU_BOOST && \
	./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500 && \
	./scripts/config --enable CONFIG_PREEMPT_RT_FULL && \
	./scripts/config --enable CONFIG_HIGH_RES_TIMERS && \
	./scripts/config --set-val CONFIG_HZ 1000 && \
	./scripts/config --enable CONFIG_IRQ_FORCED_THREADING && \
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT" && \
	make -j$((`nproc`+1)) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules dtbs && \
	cd ..

# 32 bit
bcmrpi-32_build:
	cd linux && \
	export KERNEL=kernel && \
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcmrpi_defconfig && \
	./scripts/config --disable CONFIG_VIRTUALIZATION && \
	./scripts/config --enable CONFIG_PREEMPT_RT && \
	./scripts/config --disable CONFIG_RCU_EXPERT && \
	./scripts/config --enable CONFIG_RCU_BOOST && \
	./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500 && \
	./scripts/config --enable CONFIG_PREEMPT_RT_FULL && \
	./scripts/config --enable CONFIG_HIGH_RES_TIMERS && \
	./scripts/config --set-val CONFIG_HZ 1000 && \
	./scripts/config --enable CONFIG_IRQ_FORCED_THREADING && \
	./scripts/config --enable CONFIG_SMP && \
	./scripts/config --disable CONFIG_BROKEN_ON_SMP && \
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT" && \
	make -j$((`nproc`+1)) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs && \
	cd ..

bcm2709-32_build:
	cd linux && \
	export KERNEL=kernel7 && \
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2709_defconfig && \
	./scripts/config --disable CONFIG_VIRTUALIZATION && \
	./scripts/config --enable CONFIG_PREEMPT_RT && \
	./scripts/config --disable CONFIG_RCU_EXPERT && \
	./scripts/config --enable CONFIG_RCU_BOOST && \
	./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500 && \
	./scripts/config --enable CONFIG_PREEMPT_RT_FULL && \
	./scripts/config --enable CONFIG_HIGH_RES_TIMERS && \
	./scripts/config --set-val CONFIG_HZ 1000 && \
	./scripts/config --enable CONFIG_IRQ_FORCED_THREADING && \
	./scripts/config --enable CONFIG_SMP && \
	./scripts/config --disable CONFIG_BROKEN_ON_SMP && \
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT" && \
	make -j$((`nproc`+1)) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs && \
	cd ..

bcm2711-32_build:
	cd linux && \
	export KERNEL=kernel7l && \
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2711_defconfig && \
	./scripts/config --disable CONFIG_VIRTUALIZATION && \
	./scripts/config --enable CONFIG_PREEMPT_RT && \
	./scripts/config --disable CONFIG_RCU_EXPERT && \
	./scripts/config --enable CONFIG_RCU_BOOST && \
	./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500 && \
	./scripts/config --enable CONFIG_PREEMPT_RT_FULL && \
	./scripts/config --enable CONFIG_HIGH_RES_TIMERS && \
	./scripts/config --set-val CONFIG_HZ 1000 && \
	./scripts/config --enable CONFIG_IRQ_FORCED_THREADING && \
	./scripts/config --enable CONFIG_SMP && \
	./scripts/config --disable CONFIG_BROKEN_ON_SMP && \
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT" && \
	make -j$((`nproc`+1)) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs && \
	cd ..

install_kernel64:
	OUTPUT=$(sfdisk -lJ ${RASPIOS}) && \
	BOOT_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].start') && \
	BOOT_SIZE=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].size') && \
	EXT4_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[1].start') && \
	mkdir mnt && \
	mkdir mnt/boot && \
	mkdir mnt/root && \
	mount -t ext4 -o loop,offset=$(($EXT4_START*512)) ${RASPIOS} mnt/root && \
	mount -t vfat -o loop,offset=$(($BOOT_START*512)),sizelimit=$(($BOOT_SIZE*512)) ${RASPIOS} mnt/boot && \
	env PATH=${PATH} make -j$((`nproc`*1.5)) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=mnt/root modules_install && \
	cp mnt/boot/${KERNEL}.img mnt/boot/${KERNEL}-backup.img && \
	cp arch/arm64/boot/Image mnt/boot/${KERNEL}.img && \
	cp arch/arm64/boot/dts/broadcom/*.dtb mnt/boot/ && \
	cp arch/arm64/boot/dts/overlays/*.dtb* mnt/boot/overlays/ && \
	cp arch/arm64/boot/dts/overlays/README mnt/boot/overlays/ && \
	umount mnt/boot && \
	umount mnt/root && \
	mkdir build && \
	zip build/${RASPIOS}-${TARGET}.zip ${RASPIOS}

install_kernel32:
	OUTPUT=$(sfdisk -lJ ${RASPIOS}) && \
	BOOT_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].start') && \
	BOOT_SIZE=$(echo $OUTPUT | jq -r '.partitiontable.partitions[0].size') && \
	EXT4_START=$(echo $OUTPUT | jq -r '.partitiontable.partitions[1].start') && \
	mkdir mnt && \
	mkdir mnt/boot && \
	mkdir mnt/root && \
	mount -t ext4 -o loop,offset=$(($EXT4_START*512)) ${RASPIOS} mnt/root && \
	mount -t vfat -o loop,offset=$(($BOOT_START*512)),sizelimit=$(($BOOT_SIZE*512)) ${RASPIOS} mnt/boot && \
	sudo env PATH=$PATH make -j$((`nproc`*1.5)) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=mnt/root modules_install && \
	cp mnt/boot/$KERNEL.img mnt/boot/$KERNEL-backup.img && \
	cp arch/arm/boot/zImage mnt/boot/$KERNEL.img && \
	cp arch/arm/boot/dts/broadcom/*.dtb mnt/boot/ && \
	cp arch/arm/boot/dts/overlays/*.dtb* mnt/boot/overlays/ && \
	cp arch/arm/boot/dts/overlays/README mnt/boot/overlays/ && \
	umount mnt/boot && \
	umount mnt/root && \
	mkdir build && \
	zip build/${RASPIOS}-${TARGET}.zip ${RASPIOS}