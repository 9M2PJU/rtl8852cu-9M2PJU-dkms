#!/bin/sh

# Warning: Do not run this script in a terminal. It is designed to be
#          run from another script.

# SMEM needs to be set here if dkms build is not initiated by install-driver.sh
SMEM=$(LC_ALL=C free | awk '/Mem:/ { print $2 }')

# sproc needs to be set here if dkms build is not initiated by install-driver.sh
sproc=$(nproc)

# avoid Out of Memory condition in low-RAM systems by limiting core usage
if [ "$sproc" -gt 1 ]; then
	if [ "$SMEM" -lt 1400000 ]; then
		sproc=2
	fi
	if [ "$SMEM" -lt 700000 ]; then
		sproc=1
	fi
fi

kernelver=${kernelver:-$(uname -r)}
ksrc="/lib/modules/$kernelver/build"

# Auto-detect Clang/LLVM-built kernels (e.g. CachyOS)
llvm_flag=""
if [ -r "$ksrc/.config" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "$ksrc/.config"; then
	llvm_flag="LLVM=1"
elif [ -r "$ksrc/include/config/auto.conf" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "$ksrc/include/config/auto.conf"; then
	llvm_flag="LLVM=1"
fi

if [ -n "$llvm_flag" ]; then
	make "$llvm_flag" "-j$sproc" "KVER=$kernelver" "KSRC=$ksrc" "KBUILD_MODPOST_WARN=1"
else
	make "-j$sproc" "KVER=$kernelver" "KSRC=$ksrc" "KBUILD_MODPOST_WARN=1"
fi
