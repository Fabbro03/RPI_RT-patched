# Define shell for the Makefile
SHELL := /bin/bash

# Define variables for common settings
KERNEL_DIR := linux
IMAGE_OUTPUT := build
RASPIOS_64 := raspios_lite_arm64
RASPIOS_32 := raspios_lite_armhf

# Mapping build target configurations
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

# Alias variable mappings for RASPIOS versions based on Pi board
RASPIOS_TYPE_Pi3 := $(RASPIOS_64)
RASPIOS_TYPE_Pi3+ := $(RASPIOS_64)
RASPIOS_TYPE_Pi4 := $(RASPIOS_64)
RASPIOS_TYPE_Pi400 := $(RASPIOS_64)
RASPIOS_TYPE_PiZero2 := $(RASPIOS_64)
RASPIOS_TYPE_PiCM3 := $(RASPIOS_64)
RASPIOS_TYPE_PiCM3+ := $(RASPIOS_64)
RASPIOS_TYPE_PiCM4 := $(RASPIOS_64)
RASPIOS_TYPE_PiCM4S := $(RASPIOS_64)
RASPIOS_TYPE_Pi3-32 := $(RASPIOS_32)
RASPIOS_TYPE_Pi4-32 := $(RASPIOS_32)

# Define the common kernel configuration settings
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

download_image:
	@if [ "$(RASPIOS_TYPE_$(TARGET))" ]; then \
		export RASPIOS=$$(RASPIOS_TYPE_$(TARGET)); \
		$(call download_image_template,$(RASPIOS)); \
	else \
		echo "Error: Unknown TARGET '$(TARGET)'"; \
		exit 1; \
	fi

define download_image_template
export DATE=$(shell curl -s https://downloads.raspberrypi.org/$(1)/images/ | sed -n "s:.*$(1)-\(.*\)/</a>.*:\1:p" | tail -1) && \
export RASPIOS_IMAGE_NAME=$(shell curl -s https://downloads.raspberrypi.org/$(1)/images/$(1)-$(DATE)/ | sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | head -n 1) && \
echo "Downloading $(RASPIOS_IMAGE_NAME).xz" && \
curl https://downloads.raspberrypi.org/$(1)/images/$(1)-$(DATE)/$(RASPIOS_IMAGE_NAME).xz --output $(1).xz && \
xz -d $(1).xz && \
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

# Rule to build the kernel for a specified target
build:
	@if [ "$(TARGET)" ]; then \
		$(call kernel_build_template, $(TARGET)); \
	else \
		echo "Error: TARGET variable is not set. Use 'make build TARGET=<target_name>'"; \
		exit 1; \
	fi

define kernel_build_template
cd $(KERNEL_DIR) && \
export KERNEL=$$($(1)_kernel_img) && \
make ARCH=$$($(1)_arch) CROSS_COMPILE=$$($(1)_cross_compile) $$($(1)_config) && \
$(common_kernel_config) && \
make -j$$(nproc) ARCH=$$($(1)_arch) CROSS_COMPILE=$$($(1)_cross_compile) $$($(1)_kernel_img) modules dtbs && \
cd ..
endef