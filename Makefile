# Define shell for the Makefile
SHELL := /bin/bash

# Define variables for common settings
KERNEL_DIR := linux
IMAGE_OUTPUT := build
RASPIOS_64 := raspios_lite_arm64
RASPIOS_32 := raspios_lite_armhf

# Mapping targets to respective configs and compilers
define BUILD_TARGET
$(1)_config := $(2)
$(1)_cross_compile := $(3)
$(1)_arch := $(4)
$(1)_kernel_img := $(5)
endef

# Target-specific build configurations
$(eval $(call BUILD_TARGET, bcmrpi, bcmrpi_defconfig, arm-linux-gnueabihf-, arm, zImage))
$(eval $(call BUILD_TARGET, bcm2711-64, bcm2711_defconfig, aarch64-linux-gnu-, arm64, Image))
$(eval $(call BUILD_TARGET, bcm2712-64, bcm2712_defconfig, aarch64-linux-gnu-, arm64, Image))
$(eval $(call BUILD_TARGET, bcm2711-32, bcm2711_defconfig, arm-linux-gnueabihf-, arm, zImage))
$(eval $(call BUILD_TARGET, bcm2709-32, bcm2709_defconfig, arm-linux-gnueabihf-, arm, zImage))

# Target aliases for different Raspberry Pi boards
Pi3 Pi3+ Pi4 Pi400 PiZero2 PiCM3 PiCM3+ PiCM4 PiCM4S: RASPIOS = $(RASPIOS_64)
Pi2 Pi3-32 Pi3+-32 PiZero2-32 PiCM3-32 PiCM3+-32: RASPIOS = $(RASPIOS_32)
Pi4-32 Pi400-32 PiCM4-32 PiCM4S-32: RASPIOS = $(RASPIOS_32)

# Kernel configurations
common_kernel_config = \
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
	./scripts/config --set-str CONFIG_LOCALVERSION "-Fabbro03-FullRT"

prepare:
	echo "Installing/updating required packages" && \
	apt-get -qq update && \
	apt-get -qq --yes install bc bison flex libssl-dev make libc6-dev libncurses5-dev crossbuild-essential-arm64 crossbuild-essential-armhf && \
	echo "Installation/update success"

# Rules for downloading and extracting the image
download_image64:
	@$(call download_image_template, $(RASPIOS_64))

download_image32:
	@$(call download_image_template, $(RASPIOS_32))

define download_image_template
export RASPIOS=$1 && \
export DATE=$(shell curl -s https://downloads.raspberrypi.org/$(RASPIOS)/images/ | sed -n "s:.*$(RASPIOS)-\(.*\)/</a>.*:\1:p" | tail -1) && \
export RASPIOS_IMAGE_NAME=$(shell curl -s https://downloads.raspberrypi.org/$(RASPIOS)/images/$(RASPIOS)-$(DATE)/ | sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | head -n 1) && \
echo "Downloading $(RASPIOS_IMAGE_NAME).xz" && \
curl https://downloads.raspberrypi.org/$(RASPIOS)/images/$(RASPIOS)-$(DATE)/$(RASPIOS_IMAGE_NAME).xz --output $(RASPIOS).xz && \
xz -d $(RASPIOS).xz && \
echo "$(RASPIOS_IMAGE_NAME).xz downloaded and extracted"
endef

# Download and patch the kernel source
download_kernel_src:
	export RPI_KERNEL_VERSION=6.6 && \
	export RPI_KERNEL_BRANCH=stable_20240529 && \
	export LINUX_KERNEL_RT_PATCH=patch-6.6.31-rt31 && \
	echo "Downloading kernel source code" && \
	git clone --depth=1 --branch $(RPI_KERNEL_BRANCH) https://github.com/raspberrypi/linux $(KERNEL_DIR) && \
	echo "Kernel downloaded" && \
	echo "RT patch downloading" && \
	curl https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/$(RPI_KERNEL_VERSION)/older/$(LINUX_KERNEL_RT_PATCH).patch.gz --output $(KERNEL_DIR)/rt.patch.gz && \
	echo "RT patch downloaded" && \
	echo "Applying patch" && \
	cd $(KERNEL_DIR) && gzip -cd rt.patch.gz | patch -p1 --verbose && \
	echo "Patch applied" && cd ..

# Define the build rule for each target, applying the common configurations
define kernel_build_template
	cd $(KERNEL_DIR) && \
	export KERNEL=$(5) && \
	make ARCH=$(3) CROSS_COMPILE=$(2) $(1) && \
	$(common_kernel_config) && \
	make -j$$(nproc) ARCH=$(3) CROSS_COMPILE=$(2) $(4) modules dtbs && \
	cd ..
endef

bcmrpi-32_build:
	$(call kernel_build_template,$(bcmrpi_config),$(bcmrpi_cross_compile),$(bcmrpi_arch),zImage)

bcm2711-64_build:
	$(call kernel_build_template,$(bcm2711-64_config),$(bcm2711-64_cross_compile),$(bcm2711-64_arch),Image)

bcm2712-64_build:
	$(call kernel_build_template,$(bcm2712-64_config),$(bcm2712-64_cross_compile),$(bcm2712-64_arch),Image)

bcm2711-32_build:
	$(call kernel_build_template,$(bcm2711-32_config),$(bcm2711-32_cross_compile),$(bcm2711-32_arch),zImage)

bcm2709-32_build:
	$(call kernel_build_template,$(bcm2709-32_config),$(bcm2709-32_cross_compile),$(bcm2709-32_arch),zImage)

# Kernel installation rule for 64-bit and 32-bit images
install_kernel64 install_kernel32:
	@$(call install_kernel_template,$(TARGET))

define install_kernel_template
OUTPUT=$$(sfdisk -lJ $(RASPIOS)) && \
BOOT_START=$$(echo $$OUTPUT | jq -r '.partitiontable.partitions[0].start') && \
BOOT_SIZE=$$(echo $$OUTPUT | jq -r '.partitiontable.partitions[0].size') && \
EXT4_START=$$(echo $$OUTPUT | jq -r '.partitiontable.partitions[1].start') && \
mkdir -p mnt/boot mnt/root && \
mount -t ext4 -o loop,offset=$$(($$EXT4_START*512)) $(RASPIOS) mnt/root && \
mount -t vfat -o loop,offset=$$(($$BOOT_START*512)),sizelimit=$$(($$BOOT_SIZE*512)) $(RASPIOS) mnt/boot && \
env PATH=$$PATH make -j$$(($$(nproc)*1.5)) ARCH=$$(arch) CROSS_COMPILE=$$(cross_compile) INSTALL_MOD_PATH=mnt/root modules_install && \
cp mnt/boot/$$(kernel_img) mnt/boot/$$(kernel_img)-backup && \
cp arch/$$(arch)/boot/$$(kernel_img) mnt/boot/$$(kernel_img) && \
cp arch/$$(arch)/boot/dts/broadcom/*.dtb mnt/boot/ && \
cp arch/$$(arch)/boot/dts/overlays/*.dtb* mnt/boot/overlays/ && \
cp arch/$$(arch)/boot/dts/overlays/README mnt/boot/overlays/ && \
umount mnt/boot mnt/root && \
zip $(IMAGE_OUTPUT)/$(RASPIOS)-$1.zip $(RASPIOS)
endef
